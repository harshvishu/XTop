import CoreGraphics
import Foundation

/// A single video frame to be sent to an injected simulator app.
///
/// Frames are encoded once on the macOS side (typically as JPEG) and forwarded
/// over the localhost transport. The shim dylib decodes and dispatches them as
/// `CMSampleBuffer`s to swizzled AVFoundation outputs.
struct CameraFrame: Sendable, Equatable {
    /// JPEG-encoded payload.
    let jpegData: Data
    /// Original frame dimensions, in pixels.
    let pixelSize: CGSize
    /// Capture timestamp in seconds since stream start.
    let presentationSeconds: Double
    /// Monotonically increasing index, starting at zero per source.
    let sequence: UInt64

    init(
        jpegData: Data,
        pixelSize: CGSize,
        presentationSeconds: Double,
        sequence: UInt64
    ) {
        self.jpegData = jpegData
        self.pixelSize = pixelSize
        self.presentationSeconds = presentationSeconds
        self.sequence = sequence
    }
}
