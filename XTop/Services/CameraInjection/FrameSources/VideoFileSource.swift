import AVFoundation
import CoreGraphics
import CoreImage
import Foundation

/// Streams frames from a video file on disk, looping at EOF.
///
/// Backed by `AVAssetReader`. Tries to honor the file's native frame rate but
/// caps at ~30 fps to keep encode cost bounded.
final class VideoFileSource: CameraFrameSource, @unchecked Sendable {
    enum VideoError: Error, LocalizedError {
        case noVideoTrack
        case readerFailed(String)

        var errorDescription: String? {
            switch self {
            case .noVideoTrack: return "Selected file has no video track."
            case let .readerFailed(reason): return "Video reader failed: \(reason)"
            }
        }
    }

    let url: URL
    private let encoder = CameraEncoder(quality: 0.7)
    private let ciContext = CIContext()
    private var task: Task<Void, Never>?

    init(url: URL) {
        self.url = url
    }

    func start(sink: @escaping @Sendable (CameraFrame) -> Void) async throws {
        await stop()
        let url = self.url
        let encoder = self.encoder
        let ciContext = self.ciContext
        task = Task.detached(priority: .userInitiated) {
            let startedAt = Date.now
            var sequence: UInt64 = 0
            while !Task.isCancelled {
                do {
                    try await Self.playOnce(
                        url: url,
                        encoder: encoder,
                        ciContext: ciContext,
                        startedAt: startedAt,
                        sequence: &sequence,
                        sink: sink
                    )
                } catch {
                    // Reader failed; back off and retry once a second.
                    try? await Task.sleep(for: .seconds(1))
                }
            }
        }
    }

    func stop() async {
        task?.cancel()
        task = nil
    }

    private static func playOnce(
        url: URL,
        encoder: CameraEncoder,
        ciContext: CIContext,
        startedAt: Date,
        sequence: inout UInt64,
        sink: @escaping @Sendable (CameraFrame) -> Void
    ) async throws {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else { throw VideoError.noVideoTrack }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
            ]
        )
        reader.add(output)
        guard reader.startReading() else {
            throw VideoError.readerFailed(reader.error?.localizedDescription ?? "unknown")
        }
        let frameInterval = Duration.nanoseconds(Int(1_000_000_000.0 / 30.0))
        while !Task.isCancelled {
            guard let sample = output.copyNextSampleBuffer() else { break }
            defer { CMSampleBufferInvalidate(sample) }
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { continue }
            guard let jpeg = encoder.encode(cgImage: cgImage) else { continue }
            let elapsed = Date.now.timeIntervalSince(startedAt)
            let seq = sequence
            sequence &+= 1
            sink(CameraFrame(
                jpegData: jpeg,
                pixelSize: CGSize(width: cgImage.width, height: cgImage.height),
                presentationSeconds: elapsed,
                sequence: seq
            ))
            try await Task.sleep(for: frameInterval)
        }
    }
}
