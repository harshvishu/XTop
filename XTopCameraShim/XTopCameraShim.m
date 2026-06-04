// XTopCameraShim — DYLD-inserted into a simulator-launched iOS app.
//
// Reads XTOP_CAMERA_PORT and XTOP_CAMERA_TOKEN from the environment at +load
// time, opens a localhost TCP connection back to the macOS host, sends the
// token, and dispatches received JPEG frames to swizzled AVFoundation outputs.
//
// Hard rules:
// - If env vars are missing or malformed, this dylib is a complete no-op.
// - Every swizzle is wrapped so a single failure cannot crash the app.
// - All logging is via os_log; never NSLog at scale.

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <ImageIO/ImageIO.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <os/log.h>
#import <Network/Network.h>

// MARK: - Logging

static os_log_t XTCSLog(void) {
    static os_log_t log;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        log = os_log_create("com.vishwakarma.XTop.shim", "shim");
    });
    return log;
}

// MARK: - Wire format

static const uint8_t kXTCMMagic[4] = { 'X', 'T', 'C', 'M' };
static const size_t kXTCMHeaderSize = 8;
static const size_t kXTCMTokenSize = 32;
static const size_t kXTCMMaxPayload = 8 * 1024 * 1024;

// MARK: - State

@interface XTopCameraShim : NSObject
@property (nonatomic, assign) BOOL active;
@property (nonatomic, assign) uint16_t port;
@property (nonatomic, strong) NSData *token;
@property (nonatomic, strong) nw_connection_t connection;
@property (nonatomic, strong) NSMutableArray<AVCaptureSession *> *trackedSessions;
@property (nonatomic, strong) NSMutableArray<AVCaptureVideoDataOutput *> *videoOutputs;
@property (nonatomic, strong) NSMutableData *receiveBuffer;
+ (instancetype)shared;
- (void)deliverJPEG:(NSData *)jpeg;
@end

@implementation XTopCameraShim
+ (instancetype)shared {
    static XTopCameraShim *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[XTopCameraShim alloc] init];
        instance.trackedSessions = [NSMutableArray array];
        instance.videoOutputs = [NSMutableArray array];
        instance.receiveBuffer = [NSMutableData data];
    });
    return instance;
}

- (void)deliverJPEG:(NSData *)jpeg {
    if (jpeg.length < 4) { return; }
    if (self.videoOutputs.count == 0) {
        os_log_debug(XTCSLog(), "frame %lu bytes but no tracked outputs", (unsigned long)jpeg.length);
        return;
    }

    // 1) JPEG -> CGImage via ImageIO.
    CGImageSourceRef src = CGImageSourceCreateWithData((__bridge CFDataRef)jpeg, NULL);
    if (!src) { return; }
    CGImageRef image = CGImageSourceCreateImageAtIndex(src, 0, NULL);
    CFRelease(src);
    if (!image) { return; }

    const size_t width = CGImageGetWidth(image);
    const size_t height = CGImageGetHeight(image);

    // 2) CGImage -> CVPixelBuffer (BGRA, IOSurface-backed so downstream
    //    consumers can hand it to Metal / preview layers without an extra copy).
    NSDictionary *attrs = @{
        (id)kCVPixelBufferIOSurfacePropertiesKey: @{},
        (id)kCVPixelBufferCGImageCompatibilityKey: @YES,
        (id)kCVPixelBufferCGBitmapContextCompatibilityKey: @YES,
    };
    CVPixelBufferRef pixelBuffer = NULL;
    CVReturn pbStatus = CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                                            kCVPixelFormatType_32BGRA,
                                            (__bridge CFDictionaryRef)attrs,
                                            &pixelBuffer);
    if (pbStatus != kCVReturnSuccess || !pixelBuffer) {
        CGImageRelease(image);
        return;
    }
    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    void *base = CVPixelBufferGetBaseAddress(pixelBuffer);
    const size_t bpr = CVPixelBufferGetBytesPerRow(pixelBuffer);
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(base, width, height, 8, bpr, cs,
        kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Little);
    CGColorSpaceRelease(cs);
    if (ctx) {
        CGContextDrawImage(ctx, CGRectMake(0, 0, width, height), image);
        CGContextRelease(ctx);
    }
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
    CGImageRelease(image);

    // 3) Wrap in CMSampleBuffer with a sane presentation timestamp.
    CMVideoFormatDescriptionRef fmt = NULL;
    if (CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, pixelBuffer, &fmt) != noErr || !fmt) {
        CVPixelBufferRelease(pixelBuffer);
        return;
    }
    static int64_t s_frameIndex = 0;
    int64_t idx = __sync_add_and_fetch(&s_frameIndex, 1);
    CMTime pts = CMTimeMake(idx, 30);
    CMSampleTimingInfo timing = {
        .duration = CMTimeMake(1, 30),
        .presentationTimeStamp = pts,
        .decodeTimeStamp = kCMTimeInvalid,
    };
    CMSampleBufferRef sample = NULL;
    OSStatus sbStatus = CMSampleBufferCreateReadyWithImageBuffer(kCFAllocatorDefault,
                                                                  pixelBuffer, fmt, &timing, &sample);
    CFRelease(fmt);
    CVPixelBufferRelease(pixelBuffer);
    if (sbStatus != noErr || !sample) { return; }

    // 4) Snapshot outputs under @synchronized and dispatch to each delegate on
    //    its configured queue (or a sensible default).
    NSArray<AVCaptureVideoDataOutput *> *outputsSnapshot;
    @synchronized (self.videoOutputs) {
        outputsSnapshot = [self.videoOutputs copy];
    }
    for (AVCaptureVideoDataOutput *output in outputsSnapshot) {
        id<AVCaptureVideoDataOutputSampleBufferDelegate> delegate = output.sampleBufferDelegate;
        if (!delegate) { continue; }
        if (![delegate respondsToSelector:@selector(captureOutput:didOutputSampleBuffer:fromConnection:)]) {
            continue;
        }
        dispatch_queue_t queue = output.sampleBufferCallbackQueue
            ?: dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);
        AVCaptureConnection *connection = output.connections.firstObject;
        CFRetain(sample);
        dispatch_async(queue, ^{
            @try {
                [delegate captureOutput:output didOutputSampleBuffer:sample fromConnection:connection];
            } @catch (NSException *e) {
                os_log_error(XTCSLog(), "delegate threw: %{public}@", e.reason);
            }
            CFRelease(sample);
        });
    }
    CFRelease(sample);
}
@end

// MARK: - Swizzle helpers

static BOOL XTCSSwizzleClassMethod(Class cls, SEL original, SEL replacement) {
    Method origMethod = class_getClassMethod(cls, original);
    Method replMethod = class_getClassMethod(cls, replacement);
    if (!origMethod || !replMethod) return NO;
    Class metaCls = object_getClass((id)cls);
    if (class_addMethod(metaCls, original,
                        method_getImplementation(replMethod),
                        method_getTypeEncoding(replMethod))) {
        class_replaceMethod(metaCls, replacement,
                            method_getImplementation(origMethod),
                            method_getTypeEncoding(origMethod));
    } else {
        method_exchangeImplementations(origMethod, replMethod);
    }
    return YES;
}

static BOOL XTCSSwizzleInstanceMethod(Class cls, SEL original, SEL replacement) {
    Method origMethod = class_getInstanceMethod(cls, original);
    Method replMethod = class_getInstanceMethod(cls, replacement);
    if (!origMethod || !replMethod) return NO;
    if (class_addMethod(cls, original,
                        method_getImplementation(replMethod),
                        method_getTypeEncoding(replMethod))) {
        class_replaceMethod(cls, replacement,
                            method_getImplementation(origMethod),
                            method_getTypeEncoding(origMethod));
    } else {
        method_exchangeImplementations(origMethod, replMethod);
    }
    return YES;
}

// MARK: - AVCaptureDevice swizzles

@interface AVCaptureDevice (XTopCameraShim)
@end
@implementation AVCaptureDevice (XTopCameraShim)
+ (AVAuthorizationStatus)xtcs_authorizationStatusForMediaType:(AVMediaType)mediaType {
    if ([mediaType isEqualToString:AVMediaTypeVideo]) {
        return AVAuthorizationStatusAuthorized;
    }
    return [self xtcs_authorizationStatusForMediaType:mediaType];
}

+ (void)xtcs_requestAccessForMediaType:(AVMediaType)mediaType
                     completionHandler:(void (^)(BOOL granted))handler {
    if ([mediaType isEqualToString:AVMediaTypeVideo]) {
        // Resemble OS behavior: small async hop, then yes.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)),
                       dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
            if (handler) handler(YES);
        });
        return;
    }
    [self xtcs_requestAccessForMediaType:mediaType completionHandler:handler];
}
@end

// MARK: - AVCaptureSession swizzles

@interface AVCaptureSession (XTopCameraShim)
@end
@implementation AVCaptureSession (XTopCameraShim)
- (void)xtcs_startRunning {
    @try {
        XTopCameraShim *shim = [XTopCameraShim shared];
        if (shim.active && ![shim.trackedSessions containsObject:self]) {
            [shim.trackedSessions addObject:self];
        }
    } @catch (NSException *e) {
        os_log_error(XTCSLog(), "startRunning swizzle threw: %{public}@", e.reason);
    }
    [self xtcs_startRunning];
}

- (void)xtcs_stopRunning {
    @try {
        XTopCameraShim *shim = [XTopCameraShim shared];
        [shim.trackedSessions removeObject:self];
    } @catch (NSException *e) {
        os_log_error(XTCSLog(), "stopRunning swizzle threw: %{public}@", e.reason);
    }
    [self xtcs_stopRunning];
}

- (void)xtcs_addOutput:(AVCaptureOutput *)output {
    @try {
        XTopCameraShim *shim = [XTopCameraShim shared];
        if (shim.active && [output isKindOfClass:[AVCaptureVideoDataOutput class]]) {
            [shim.videoOutputs addObject:(AVCaptureVideoDataOutput *)output];
        }
    } @catch (NSException *e) {
        os_log_error(XTCSLog(), "addOutput swizzle threw: %{public}@", e.reason);
    }
    [self xtcs_addOutput:output];
}
@end

// MARK: - Networking

static void XTCSReceiveNext(nw_connection_t connection);

static void XTCSHandleReceivedPayload(NSData *payload) {
    [[XTopCameraShim shared] deliverJPEG:payload];
}

static void XTCSReceiveNext(nw_connection_t connection) {
    nw_connection_receive(connection, (uint32_t)kXTCMHeaderSize, (uint32_t)kXTCMHeaderSize,
        ^(dispatch_data_t content, nw_content_context_t context, bool is_complete, nw_error_t error) {
        if (error || !content) {
            os_log_error(XTCSLog(), "receive header failed");
            return;
        }
        __block NSMutableData *header = [NSMutableData data];
        dispatch_data_apply(content, ^bool(dispatch_data_t region, size_t offset, const void *buffer, size_t size) {
            [header appendBytes:buffer length:size];
            return true;
        });
        if (header.length != kXTCMHeaderSize) return;
        const uint8_t *bytes = header.bytes;
        if (memcmp(bytes, kXTCMMagic, 4) != 0) {
            os_log_error(XTCSLog(), "bad magic on inbound frame");
            return;
        }
        uint32_t len = 0;
        memcpy(&len, bytes + 4, 4);
        len = CFSwapInt32LittleToHost(len);
        if (len == 0 || len > kXTCMMaxPayload) {
            os_log_error(XTCSLog(), "payload length out of range: %u", len);
            return;
        }
        nw_connection_receive(connection, len, len,
            ^(dispatch_data_t payload, nw_content_context_t pctx, bool pcomplete, nw_error_t perror) {
            if (perror || !payload) return;
            __block NSMutableData *buf = [NSMutableData dataWithCapacity:len];
            dispatch_data_apply(payload, ^bool(dispatch_data_t region, size_t offset, const void *buffer, size_t size) {
                [buf appendBytes:buffer length:size];
                return true;
            });
            XTCSHandleReceivedPayload(buf);
            XTCSReceiveNext(connection);
        });
    });
}

static void XTCSOpenConnection(uint16_t port, NSData *token) {
    nw_endpoint_t endpoint = nw_endpoint_create_host("127.0.0.1",
        [[NSString stringWithFormat:@"%u", port] UTF8String]);
    nw_parameters_t params = nw_parameters_create_secure_tcp(
        NW_PARAMETERS_DISABLE_PROTOCOL, NW_PARAMETERS_DEFAULT_CONFIGURATION);
    nw_connection_t connection = nw_connection_create(endpoint, params);
    [XTopCameraShim shared].connection = connection;

    nw_connection_set_queue(connection, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0));
    nw_connection_set_state_changed_handler(connection, ^(nw_connection_state_t state, nw_error_t error) {
        if (state == nw_connection_state_ready) {
            // Send the token first.
            dispatch_data_t data = dispatch_data_create(token.bytes, token.length,
                dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), DISPATCH_DATA_DESTRUCTOR_DEFAULT);
            nw_connection_send(connection, data, NW_CONNECTION_DEFAULT_MESSAGE_CONTEXT, true,
                ^(nw_error_t sendError) {
                if (sendError) {
                    os_log_error(XTCSLog(), "token send failed");
                    return;
                }
                XTCSReceiveNext(connection);
            });
        } else if (state == nw_connection_state_failed || state == nw_connection_state_cancelled) {
            os_log_error(XTCSLog(), "connection failed/cancelled");
        }
    });
    nw_connection_start(connection);
}

// MARK: - Bootstrap

static NSData *XTCSDecodeHexToken(NSString *hex) {
    if (hex.length != kXTCMTokenSize * 2) return nil;
    NSMutableData *data = [NSMutableData dataWithCapacity:kXTCMTokenSize];
    char buffer[3] = {0};
    for (NSUInteger i = 0; i < kXTCMTokenSize; i++) {
        buffer[0] = [hex characterAtIndex:i * 2];
        buffer[1] = [hex characterAtIndex:i * 2 + 1];
        char *end = NULL;
        unsigned long byte = strtoul(buffer, &end, 16);
        if (end != buffer + 2) return nil;
        uint8_t b = (uint8_t)byte;
        [data appendBytes:&b length:1];
    }
    return data;
}

static void XTCSInstallSwizzles(void) {
    Class deviceCls = [AVCaptureDevice class];
    XTCSSwizzleClassMethod(deviceCls,
        @selector(authorizationStatusForMediaType:),
        @selector(xtcs_authorizationStatusForMediaType:));
    XTCSSwizzleClassMethod(deviceCls,
        @selector(requestAccessForMediaType:completionHandler:),
        @selector(xtcs_requestAccessForMediaType:completionHandler:));

    Class sessionCls = [AVCaptureSession class];
    XTCSSwizzleInstanceMethod(sessionCls,
        @selector(startRunning), @selector(xtcs_startRunning));
    XTCSSwizzleInstanceMethod(sessionCls,
        @selector(stopRunning), @selector(xtcs_stopRunning));
    XTCSSwizzleInstanceMethod(sessionCls,
        @selector(addOutput:), @selector(xtcs_addOutput:));
}

__attribute__((constructor))
static void XTopCameraShim_Initialize(void) {
    @autoreleasepool {
        const char *portStr = getenv("XTOP_CAMERA_PORT");
        const char *tokenStr = getenv("XTOP_CAMERA_TOKEN");
        if (!portStr || !tokenStr) {
            os_log_info(XTCSLog(), "no env vars; shim is a no-op");
            return;
        }
        int port = atoi(portStr);
        if (port <= 0 || port > UINT16_MAX) {
            os_log_error(XTCSLog(), "bad XTOP_CAMERA_PORT");
            return;
        }
        NSData *token = XTCSDecodeHexToken([NSString stringWithUTF8String:tokenStr]);
        if (!token) {
            os_log_error(XTCSLog(), "bad XTOP_CAMERA_TOKEN");
            return;
        }

        [XTopCameraShim shared].active = YES;
        [XTopCameraShim shared].port = (uint16_t)port;
        [XTopCameraShim shared].token = token;

        @try {
            XTCSInstallSwizzles();
        } @catch (NSException *e) {
            os_log_error(XTCSLog(), "swizzle install threw: %{public}@", e.reason);
            return;
        }

        XTCSOpenConnection((uint16_t)port, token);
        os_log(XTCSLog(), "XTopCameraShim active on port %d, pid=%d", port, getpid());
    }
}
