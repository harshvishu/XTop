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
#import <QuartzCore/QuartzCore.h>
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

// Associated-object key used to attach an overlay CALayer to each tracked
// AVCaptureVideoPreviewLayer. Its address is the unique key.
static char kXTCSOverlayKey;

// MARK: - State

@interface XTopCameraShim : NSObject
@property (nonatomic, assign) BOOL active;
@property (nonatomic, assign) uint16_t port;
@property (nonatomic, strong) NSData *token;
@property (nonatomic, strong) nw_connection_t connection;
@property (nonatomic, strong) NSMutableArray<AVCaptureSession *> *trackedSessions;
@property (nonatomic, strong) NSMutableArray<AVCaptureVideoDataOutput *> *videoOutputs;
@property (nonatomic, strong) NSHashTable<CALayer *> *previewLayers;
@property (nonatomic, strong) NSMutableData *receiveBuffer;
@property (nonatomic, assign) uint64_t framesReceived;
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
        instance.previewLayers = [NSHashTable weakObjectsHashTable];
        instance.receiveBuffer = [NSMutableData data];
    });
    return instance;
}

- (void)deliverJPEG:(NSData *)jpeg {
    if (jpeg.length < 4) { return; }
    self.framesReceived += 1;
    if (self.framesReceived == 1) {
        os_log(XTCSLog(), "first frame received: %lu bytes", (unsigned long)jpeg.length);
    }

    // 1) JPEG -> CGImage via ImageIO.
    CGImageSourceRef src = CGImageSourceCreateWithData((__bridge CFDataRef)jpeg, NULL);
    if (!src) { return; }
    CGImageRef image = CGImageSourceCreateImageAtIndex(src, 0, NULL);
    CFRelease(src);
    if (!image) { return; }

    // Snapshot preview layers; for each, ensure a child overlay CALayer
    // exists (AVCaptureVideoPreviewLayer's own .contents is ignored by its
    // private internal renderer, so we cannot just set it directly), then
    // push the CGImage into the overlay's contents on the main thread.
    NSArray<CALayer *> *previewSnapshot;
    @synchronized (self.previewLayers) {
        previewSnapshot = self.previewLayers.allObjects;
    }
    if (previewSnapshot.count > 0) {
        CGImageRef retained = CGImageRetain(image);
        dispatch_async(dispatch_get_main_queue(), ^{
            for (CALayer *parent in previewSnapshot) {
                @try {
                    CALayer *overlay = objc_getAssociatedObject(parent, &kXTCSOverlayKey);
                    if (!overlay) {
                        overlay = [CALayer layer];
                        overlay.contentsGravity = kCAGravityResizeAspectFill;
                        overlay.masksToBounds = YES;
                        overlay.zPosition = CGFLOAT_MAX;
                        objc_setAssociatedObject(parent, &kXTCSOverlayKey, overlay,
                                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                        [parent addSublayer:overlay];
                    }
                    [CATransaction begin];
                    [CATransaction setDisableActions:YES];
                    overlay.frame = parent.bounds;
                    overlay.contents = (__bridge id)retained;
                    [CATransaction commit];
                } @catch (NSException *e) {
                    os_log_error(XTCSLog(), "preview overlay push threw: %{public}@", e.reason);
                }
            }
            CGImageRelease(retained);
        });
    }

    if (self.videoOutputs.count == 0 && previewSnapshot.count == 0) {
        // Sampled log to avoid spam; once per ~30 frames is plenty.
        if (self.framesReceived % 30 == 1) {
            os_log_info(XTCSLog(),
                        "frame %llu received but no tracked outputs and no preview layers",
                        (unsigned long long)self.framesReceived);
        }
        CGImageRelease(image);
        return;
    }

    if (self.videoOutputs.count == 0) {
        CGImageRelease(image);
        return;
    }

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

// MARK: - Fake AVCaptureDevice / AVCaptureDeviceInput
//
// AVCaptureDevice has no public initializer. We subclass it and allocate via
// class_createInstance(_, 0) to bypass +alloc validation. We then override
// every property a typical camera consumer might query so the host app does
// not crash when it inspects the placeholder.
//
// Caveats:
// - AVCaptureDeviceFormat has no public initializer either, so -formats and
//   -activeFormat return empty array / nil. Apps that gate on a specific
//   format will reject the device. There is no clean way around this without
//   reaching into private AVFoundation symbols.
// - We do not implement KVO observation lists, so apps that addObserver on
//   our device for keys like "adjustingFocus" will see no notifications.
// - lockForConfiguration:/unlockForConfiguration are no-ops that always
//   report success.

static NSString * const XTCSFakeDeviceUniqueID = @"com.vishwakarma.XTop.fakeCamera.back";

@interface XTCSFakeCaptureDevice : AVCaptureDevice
@end

@implementation XTCSFakeCaptureDevice {
    AVMediaType _mediaType;
}

+ (instancetype)sharedVideoDevice {
    static XTCSFakeCaptureDevice *device;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        device = (XTCSFakeCaptureDevice *)class_createInstance([XTCSFakeCaptureDevice class], 0);
        device->_mediaType = AVMediaTypeVideo;
    });
    return device;
}

- (NSString *)uniqueID { return XTCSFakeDeviceUniqueID; }
- (NSString *)modelID { return @"XTopFakeCamera1,1"; }
- (NSString *)localizedName { return @"XTop Virtual Camera"; }
- (NSString *)manufacturer { return @"XTop"; }
- (AVCaptureDevicePosition)position { return AVCaptureDevicePositionBack; }
- (AVCaptureDeviceType)deviceType { return AVCaptureDeviceTypeBuiltInWideAngleCamera; }
- (BOOL)hasMediaType:(AVMediaType)mediaType { return [mediaType isEqualToString:AVMediaTypeVideo]; }
- (BOOL)supportsAVCaptureSessionPreset:(AVCaptureSessionPreset)preset { return YES; }
- (NSArray *)formats { return @[]; }
- (id)activeFormat { return nil; }
- (BOOL)isConnected { return YES; }
- (BOOL)isSuspended { return NO; }
- (BOOL)lockForConfiguration:(NSError **)outError {
    if (outError) *outError = nil;
    return YES;
}
- (void)unlockForConfiguration { }
- (BOOL)hasTorch { return NO; }
- (BOOL)hasFlash { return NO; }
- (BOOL)isFocusModeSupported:(AVCaptureFocusMode)mode { return NO; }
- (BOOL)isExposureModeSupported:(AVCaptureExposureMode)mode { return NO; }
- (BOOL)isWhiteBalanceModeSupported:(AVCaptureWhiteBalanceMode)mode { return NO; }

// AVCaptureDevice overrides NSObject -class to return the class via runtime
// inspection; ensure our subclass advertises itself correctly to isKindOfClass: checks.
- (Class)class { return [XTCSFakeCaptureDevice class]; }
@end

// We mark sessions/inputs that interact with our fake device so addInput:
// can swallow the real call without throwing.
static char kXTCSFakeMarkerKey;

static BOOL XTCSIsFakeMarked(id obj) {
    return objc_getAssociatedObject(obj, &kXTCSFakeMarkerKey) != nil;
}
static void XTCSMarkFake(id obj) {
    objc_setAssociatedObject(obj, &kXTCSFakeMarkerKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@interface XTCSFakeCaptureDeviceInput : AVCaptureDeviceInput
@end

@implementation XTCSFakeCaptureDeviceInput {
    AVCaptureDevice *_fakeDevice;
}

+ (instancetype)inputWithDevice:(AVCaptureDevice *)device {
    XTCSFakeCaptureDeviceInput *input = (XTCSFakeCaptureDeviceInput *)class_createInstance([XTCSFakeCaptureDeviceInput class], 0);
    input->_fakeDevice = device;
    XTCSMarkFake(input);
    return input;
}

- (AVCaptureDevice *)device { return _fakeDevice; }
- (NSArray *)ports { return @[]; }
- (Class)class { return [XTCSFakeCaptureDeviceInput class]; }
@end

// MARK: - AVCaptureDevice swizzles

@interface AVCaptureDevice (XTopCameraShim)
@end
@implementation AVCaptureDevice (XTopCameraShim)
+ (AVAuthorizationStatus)xtcs_authorizationStatusForMediaType:(AVMediaType)mediaType {
    os_log(XTCSLog(), "hook: +authorizationStatusForMediaType:%{public}@", mediaType);
    if ([mediaType isEqualToString:AVMediaTypeVideo]) {
        return AVAuthorizationStatusAuthorized;
    }
    return [self xtcs_authorizationStatusForMediaType:mediaType];
}

+ (void)xtcs_requestAccessForMediaType:(AVMediaType)mediaType
                     completionHandler:(void (^)(BOOL granted))handler {
    os_log(XTCSLog(), "hook: +requestAccessForMediaType:%{public}@", mediaType);
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

+ (AVCaptureDevice *)xtcs_defaultDeviceWithMediaType:(AVMediaType)mediaType {
    AVCaptureDevice *device = [self xtcs_defaultDeviceWithMediaType:mediaType];
    if (!device && [mediaType isEqualToString:AVMediaTypeVideo]) {
        device = [XTCSFakeCaptureDevice sharedVideoDevice];
        os_log(XTCSLog(), "hook: +defaultDeviceWithMediaType:video -> FAKE %p", device);
    } else {
        os_log(XTCSLog(), "hook: +defaultDeviceWithMediaType:%{public}@ -> %p", mediaType, device);
    }
    return device;
}

+ (NSArray<AVCaptureDevice *> *)xtcs_devicesWithMediaType:(AVMediaType)mediaType {
    NSArray *devices = [self xtcs_devicesWithMediaType:mediaType];
    if ((!devices || devices.count == 0) && [mediaType isEqualToString:AVMediaTypeVideo]) {
        devices = @[[XTCSFakeCaptureDevice sharedVideoDevice]];
        os_log(XTCSLog(), "hook: +devicesWithMediaType:video -> FAKE count=1");
    } else {
        os_log(XTCSLog(), "hook: +devicesWithMediaType:%{public}@ -> count=%lu",
               mediaType, (unsigned long)devices.count);
    }
    return devices;
}

+ (AVCaptureDevice *)xtcs_deviceWithUniqueID:(NSString *)uniqueID {
    if ([uniqueID isEqualToString:XTCSFakeDeviceUniqueID]) {
        return [XTCSFakeCaptureDevice sharedVideoDevice];
    }
    AVCaptureDevice *device = [self xtcs_deviceWithUniqueID:uniqueID];
    os_log(XTCSLog(), "hook: +deviceWithUniqueID:%{public}@ -> %p", uniqueID, device);
    return device;
}
@end

// MARK: - AVCaptureDeviceDiscoverySession diagnostic hook

@interface AVCaptureDeviceDiscoverySession (XTopCameraShim)
@end
@implementation AVCaptureDeviceDiscoverySession (XTopCameraShim)
+ (instancetype)xtcs_discoverySessionWithDeviceTypes:(NSArray<AVCaptureDeviceType> *)deviceTypes
                                           mediaType:(AVMediaType)mediaType
                                            position:(AVCaptureDevicePosition)position {
    AVCaptureDeviceDiscoverySession *s = [self xtcs_discoverySessionWithDeviceTypes:deviceTypes
                                                                          mediaType:mediaType
                                                                           position:position];
    os_log(XTCSLog(), "hook: +discoverySession types=%{public}@ media=%{public}@ pos=%ld -> devices.count=%lu",
           deviceTypes, mediaType, (long)position, (unsigned long)s.devices.count);
    return s;
}
@end

// MARK: - AVCaptureDeviceInput diagnostic hook

@interface AVCaptureDeviceInput (XTopCameraShim)
@end
@implementation AVCaptureDeviceInput (XTopCameraShim)
+ (instancetype)xtcs_deviceInputWithDevice:(AVCaptureDevice *)device
                                     error:(NSError * _Nullable __autoreleasing *)outError {
    AVCaptureDeviceInput *input = [self xtcs_deviceInputWithDevice:device error:outError];
    os_log(XTCSLog(), "hook: +deviceInputWithDevice:%p -> input=%p err=%{public}@",
           device, input, (outError && *outError) ? *outError : nil);
    return input;
}
@end

// MARK: - AVCaptureSession swizzles

@interface AVCaptureSession (XTopCameraShim)
@end
@implementation AVCaptureSession (XTopCameraShim)
- (void)xtcs_startRunning {
    os_log(XTCSLog(), "hook: -[AVCaptureSession startRunning] session=%p", self);
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
    os_log(XTCSLog(), "hook: -[AVCaptureSession stopRunning] session=%p", self);
    @try {
        XTopCameraShim *shim = [XTopCameraShim shared];
        [shim.trackedSessions removeObject:self];
    } @catch (NSException *e) {
        os_log_error(XTCSLog(), "stopRunning swizzle threw: %{public}@", e.reason);
    }
    [self xtcs_stopRunning];
}

- (void)xtcs_addOutput:(AVCaptureOutput *)output {
    os_log(XTCSLog(), "hook: -[AVCaptureSession addOutput:] session=%p output=%{public}@",
           self, NSStringFromClass([output class]));
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

// MARK: - AVCaptureVideoPreviewLayer swizzles
//
// Most camera UIs render the live preview through AVCaptureVideoPreviewLayer.
// In the iOS simulator there is no real AVCaptureDevice, so the layer has
// nothing to draw and stays grey. We hook setSession: (covers both
// -initWithSession: and -layerWithSession: which go through the setter) to
// track every preview layer instance; on each frame the shim sets the
// layer.contents to the inbound CGImage, which makes the layer render as
// if it were receiving real frames.

@interface AVCaptureVideoPreviewLayer (XTopCameraShim)
@end
@implementation AVCaptureVideoPreviewLayer (XTopCameraShim)
- (void)xtcs_setSession:(AVCaptureSession *)session {
    os_log(XTCSLog(), "hook: -[AVCaptureVideoPreviewLayer setSession:] layer=%p session=%p",
           self, session);
    @try {
        XTopCameraShim *shim = [XTopCameraShim shared];
        if (shim.active) {
            @synchronized (shim.previewLayers) {
                [shim.previewLayers addObject:self];
            }
        }
    } @catch (NSException *e) {
        os_log_error(XTCSLog(), "preview setSession swizzle threw: %{public}@", e.reason);
    }
    [self xtcs_setSession:session];
}

- (instancetype)xtcs_initWithSession:(AVCaptureSession *)session {
    AVCaptureVideoPreviewLayer *layer = [self xtcs_initWithSession:session];
    os_log(XTCSLog(), "hook: -[AVCaptureVideoPreviewLayer initWithSession:] layer=%p session=%p",
           layer, session);
    @try {
        XTopCameraShim *shim = [XTopCameraShim shared];
        if (layer && shim.active) {
            @synchronized (shim.previewLayers) {
                [shim.previewLayers addObject:layer];
            }
        }
    } @catch (NSException *e) {
        os_log_error(XTCSLog(), "preview initWithSession swizzle threw: %{public}@", e.reason);
    }
    return layer;
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
    XTCSSwizzleClassMethod(deviceCls,
        @selector(defaultDeviceWithMediaType:),
        @selector(xtcs_defaultDeviceWithMediaType:));
    XTCSSwizzleClassMethod(deviceCls,
        @selector(devicesWithMediaType:),
        @selector(xtcs_devicesWithMediaType:));
    XTCSSwizzleClassMethod(deviceCls,
        @selector(deviceWithUniqueID:),
        @selector(xtcs_deviceWithUniqueID:));

    Class discoveryCls = [AVCaptureDeviceDiscoverySession class];
    XTCSSwizzleClassMethod(discoveryCls,
        @selector(discoverySessionWithDeviceTypes:mediaType:position:),
        @selector(xtcs_discoverySessionWithDeviceTypes:mediaType:position:));

    Class inputCls = [AVCaptureDeviceInput class];
    XTCSSwizzleClassMethod(inputCls,
        @selector(deviceInputWithDevice:error:),
        @selector(xtcs_deviceInputWithDevice:error:));

    Class sessionCls = [AVCaptureSession class];
    XTCSSwizzleInstanceMethod(sessionCls,
        @selector(startRunning), @selector(xtcs_startRunning));
    XTCSSwizzleInstanceMethod(sessionCls,
        @selector(stopRunning), @selector(xtcs_stopRunning));
    XTCSSwizzleInstanceMethod(sessionCls,
        @selector(addOutput:), @selector(xtcs_addOutput:));

    Class previewCls = [AVCaptureVideoPreviewLayer class];
    XTCSSwizzleInstanceMethod(previewCls,
        @selector(setSession:), @selector(xtcs_setSession:));
    XTCSSwizzleInstanceMethod(previewCls,
        @selector(initWithSession:), @selector(xtcs_initWithSession:));
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
