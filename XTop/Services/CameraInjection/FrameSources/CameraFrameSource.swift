import CoreGraphics
import Foundation

/// Pull-style frame producer protocol shared by every macOS-side source.
///
/// Sources push frames into the provided sink at their own cadence (usually
/// ~30 fps). Implementations must be cancellation-safe and idempotent on
/// `stop()`. Hosts call `start` exactly once, then `stop` exactly once.
protocol CameraFrameSource: AnyObject, Sendable {
    /// Begins emitting frames into `sink` until `stop()` is called.
    func start(sink: @escaping @Sendable (CameraFrame) -> Void) async throws

    /// Stops the source and releases any underlying capture resources.
    func stop() async
}
