import AVFoundation
import CoreGraphics
import CoreImage
import Foundation

/// Captures from the host Mac's default video device (FaceTime HD, Continuity
/// Camera, etc.) and forwards encoded frames to the sink.
///
/// Requires `NSCameraUsageDescription` and `com.apple.security.device.camera`
/// in the host app. Permission is requested lazily on `start()`.
final class WebcamSource: NSObject, CameraFrameSource, @unchecked Sendable {
    enum WebcamError: Error, LocalizedError {
        case permissionDenied
        case noCamera
        case sessionFailed(String)

        var errorDescription: String? {
            switch self {
            case .permissionDenied: return "Mac camera permission was denied."
            case .noCamera: return "No camera found on this Mac."
            case let .sessionFailed(reason): return "Camera session failed: \(reason)"
            }
        }
    }

    private let encoder = CameraEncoder(quality: 0.7)
    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "xtop.camera.webcam")
    private var sink: (@Sendable (CameraFrame) -> Void)?
    private var sequence: UInt64 = 0
    private let startedAt = Date.now
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    func start(sink: @escaping @Sendable (CameraFrame) -> Void) async throws {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            break
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if !granted { throw WebcamError.permissionDenied }
        case .denied, .restricted:
            throw WebcamError.permissionDenied
        @unknown default:
            throw WebcamError.permissionDenied
        }

        guard let device = AVCaptureDevice.default(for: .video) else {
            throw WebcamError.noCamera
        }

        self.sink = sink
        session.beginConfiguration()
        session.sessionPreset = .vga640x480
        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) { session.addInput(input) }
            output.alwaysDiscardsLateVideoFrames = true
            output.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
            ]
            output.setSampleBufferDelegate(self, queue: queue)
            if session.canAddOutput(output) { session.addOutput(output) }
        } catch {
            session.commitConfiguration()
            throw WebcamError.sessionFailed(error.localizedDescription)
        }
        session.commitConfiguration()
        session.startRunning()
    }

    func stop() async {
        session.stopRunning()
        for input in session.inputs { session.removeInput(input) }
        for output in session.outputs { session.removeOutput(output) }
        sink = nil
    }
}

extension WebcamSource: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let sink else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }
        guard let jpeg = encoder.encode(cgImage: cgImage) else { return }
        let elapsed = Date.now.timeIntervalSince(startedAt)
        let seq = sequence
        sequence &+= 1
        sink(CameraFrame(
            jpegData: jpeg,
            pixelSize: CGSize(width: cgImage.width, height: cgImage.height),
            presentationSeconds: elapsed,
            sequence: seq
        ))
    }
}
