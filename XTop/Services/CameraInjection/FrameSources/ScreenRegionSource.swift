import CoreGraphics
import CoreImage
import Foundation
import ScreenCaptureKit

/// Captures a host-side display or window region using `ScreenCaptureKit`.
///
/// Requires Screen Recording permission (granted via TCC on first run).
@available(macOS 13.0, *)
final class ScreenRegionSource: NSObject, CameraFrameSource, @unchecked Sendable {
    enum ScreenError: Error, LocalizedError {
        case noDisplay
        case streamFailed(String)

        var errorDescription: String? {
            switch self {
            case .noDisplay: return "No displays were found for capture."
            case let .streamFailed(reason): return "Screen capture failed: \(reason)"
            }
        }
    }

    /// What to capture. `display(nil)` means "main display".
    enum Target: Sendable {
        case display(displayID: CGDirectDisplayID?)
        case window(windowID: CGWindowID)
    }

    let target: Target
    private let encoder = CameraEncoder(quality: 0.7)
    private let ciContext = CIContext()
    private var stream: SCStream?
    private var sink: (@Sendable (CameraFrame) -> Void)?
    private var sequence: UInt64 = 0
    private let startedAt = Date.now
    private let outputHandler = ScreenStreamOutput()

    init(target: Target = .display(displayID: nil)) {
        self.target = target
    }

    func start(sink: @escaping @Sendable (CameraFrame) -> Void) async throws {
        await stop()
        self.sink = sink
        outputHandler.bind { [weak self] sample in
            self?.handleSample(sample)
        }

        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        let filter: SCContentFilter
        switch target {
        case let .display(displayID):
            let display: SCDisplay
            if let displayID, let match = content.displays.first(where: { $0.displayID == displayID }) {
                display = match
            } else if let main = content.displays.first {
                display = main
            } else {
                throw ScreenError.noDisplay
            }
            filter = SCContentFilter(display: display, excludingWindows: [])
        case let .window(windowID):
            guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
                throw ScreenError.noDisplay
            }
            filter = SCContentFilter(desktopIndependentWindow: window)
        }

        let config = SCStreamConfiguration()
        config.width = 1280
        config.height = 720
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.queueDepth = 5

        let stream = SCStream(filter: filter, configuration: config, delegate: outputHandler)
        try stream.addStreamOutput(
            outputHandler,
            type: .screen,
            sampleHandlerQueue: DispatchQueue(label: "xtop.camera.screen")
        )
        try await stream.startCapture()
        self.stream = stream
    }

    func stop() async {
        if let stream {
            try? await stream.stopCapture()
        }
        stream = nil
        sink = nil
        outputHandler.bind(nil)
    }

    private func handleSample(_ sampleBuffer: CMSampleBuffer) {
        guard CMSampleBufferIsValid(sampleBuffer), let sink else { return }
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

/// Bridges SCStream's `SCStreamOutput`/`SCStreamDelegate` callbacks into a
/// simple sample-buffer closure. Kept as a separate class so we can hand it to
/// both `SCStream.delegate` and `addStreamOutput`.
@available(macOS 13.0, *)
private final class ScreenStreamOutput: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private var handler: ((CMSampleBuffer) -> Void)?
    private let lock = NSLock()

    func bind(_ handler: ((CMSampleBuffer) -> Void)?) {
        lock.lock(); defer { lock.unlock() }
        self.handler = handler
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        lock.lock(); let h = handler; lock.unlock()
        h?(sampleBuffer)
    }
}
