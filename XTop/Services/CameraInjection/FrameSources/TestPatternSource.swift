import CoreGraphics
import CoreText
import Foundation

/// A no-permission-required animated test pattern: rotating SMPTE-ish color
/// bars plus a frame counter overlay. Useful for verifying the wire stays
/// alive before exercising webcam / screen capture.
final class TestPatternSource: CameraFrameSource, @unchecked Sendable {
    private let encoder = CameraEncoder(quality: 0.7)
    private let width = 640
    private let height = 480
    private let fps: Double = 30

    private var task: Task<Void, Never>?

    func start(sink: @escaping @Sendable (CameraFrame) -> Void) async throws {
        await stop()
        let width = self.width
        let height = self.height
        let fps = self.fps
        let encoder = self.encoder
        task = Task.detached(priority: .userInitiated) {
            let frameInterval = Duration.nanoseconds(Int(1_000_000_000.0 / fps))
            var sequence: UInt64 = 0
            let startedAt = Date.now
            while !Task.isCancelled {
                let elapsed = Date.now.timeIntervalSince(startedAt)
                if let cgImage = Self.renderFrame(
                    width: width,
                    height: height,
                    sequence: sequence,
                    elapsed: elapsed
                ), let jpeg = encoder.encode(cgImage: cgImage) {
                    sink(CameraFrame(
                        jpegData: jpeg,
                        pixelSize: CGSize(width: width, height: height),
                        presentationSeconds: elapsed,
                        sequence: sequence
                    ))
                }
                sequence &+= 1
                try? await Task.sleep(for: frameInterval)
            }
        }
    }

    func stop() async {
        task?.cancel()
        task = nil
    }

    // MARK: - Render

    static func renderFrame(
        width: Int,
        height: Int,
        sequence: UInt64,
        elapsed: TimeInterval
    ) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Rotating color bars (8 SMPTE-style bars, hue shifted by time).
        let bars: [(r: CGFloat, g: CGFloat, b: CGFloat)] = [
            (1, 1, 1), (1, 1, 0), (0, 1, 1), (0, 1, 0),
            (1, 0, 1), (1, 0, 0), (0, 0, 1), (0, 0, 0)
        ]
        let barWidth = CGFloat(width) / CGFloat(bars.count)
        let offset = Int(elapsed * 2) % bars.count
        for index in 0..<bars.count {
            let color = bars[(index + offset) % bars.count]
            context.setFillColor(red: color.r, green: color.g, blue: color.b, alpha: 1)
            context.fill(CGRect(
                x: CGFloat(index) * barWidth,
                y: 0,
                width: barWidth,
                height: CGFloat(height)
            ))
        }

        // Diagonal sweep band — easy to visually confirm motion.
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 0.25)
        let sweepX = CGFloat((Int(elapsed * 200) % (width + 200)) - 100)
        context.fill(CGRect(x: sweepX, y: 0, width: 60, height: CGFloat(height)))

        // Frame counter overlay (top-left).
        let label = "XTop seq \(sequence)"
        let font = CTFontCreateWithName("Menlo-Bold" as CFString, 28, nil)
        let foreground = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        let attrString = CFAttributedStringCreateMutable(kCFAllocatorDefault, 0)!
        CFAttributedStringReplaceString(attrString, CFRange(location: 0, length: 0), label as CFString)
        let range = CFRange(location: 0, length: (label as NSString).length)
        CFAttributedStringSetAttribute(attrString, range, kCTFontAttributeName, font)
        CFAttributedStringSetAttribute(attrString, range, kCTForegroundColorAttributeName, foreground)
        let line = CTLineCreateWithAttributedString(attrString)
        context.textPosition = CGPoint(x: 16, y: CGFloat(height) - 40)
        CTLineDraw(line, context)

        return context.makeImage()
    }
}
