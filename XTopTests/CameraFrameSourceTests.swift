import CoreGraphics
import Foundation
import Testing
@testable import XTop

@Suite("Camera frame sources")
struct CameraFrameSourceTests {
    @Test func testPatternRendersValidJPEGAtFrameZero() throws {
        let cgImage = try #require(TestPatternSource.renderFrame(
            width: 320, height: 240, sequence: 0, elapsed: 0
        ))
        let encoder = CameraEncoder(quality: 0.6)
        let jpeg = try #require(encoder.encode(cgImage: cgImage))
        // JPEG magic: FF D8 FF
        #expect(jpeg.count > 100)
        #expect(jpeg[0] == 0xFF && jpeg[1] == 0xD8 && jpeg[2] == 0xFF)
    }

    @Test func testPatternProducesFramesIntoSink() async throws {
        let source = TestPatternSource()
        let received = ReceivedFrames()
        try await source.start { frame in
            Task { await received.append(frame) }
        }
        try await Task.sleep(for: .milliseconds(250))
        await source.stop()
        let count = await received.count
        #expect(count >= 1, "Expected at least one frame, got \(count)")
    }

    @Test func encoderQualityIsClampedToValidRange() {
        let low = CameraEncoder(quality: -1)
        let high = CameraEncoder(quality: 5)
        #expect(low.quality >= 0.05)
        #expect(high.quality <= 1.0)
    }

    @Test func testPatternRendersDeterministicallyAtSameInputs() throws {
        let a = try #require(TestPatternSource.renderFrame(
            width: 160, height: 120, sequence: 0, elapsed: 0
        ))
        let b = try #require(TestPatternSource.renderFrame(
            width: 160, height: 120, sequence: 0, elapsed: 0
        ))
        // Same inputs MUST produce byte-identical pixel data.
        #expect(a.dataProvider?.data == b.dataProvider?.data)
    }

    @Test func testPatternFirstBarIsWhiteAtTimeZero() throws {
        let image = try #require(TestPatternSource.renderFrame(
            width: 160, height: 120, sequence: 0, elapsed: 0
        ))
        // SMPTE bar 0 is white (1,1,1). Sample mid-height, mid-of-first-bar
        // (x=10, y=60) which is below the frame-counter overlay.
        let pixel = try #require(samplePixel(image, x: 10, y: 60))
        #expect(pixel.r > 240)
        #expect(pixel.g > 240)
        #expect(pixel.b > 240)
    }

    @Test func testPatternFrameCounterChangesBetweenSequences() throws {
        // We sweep elapsed (not just sequence) because the seq label may be
        // rendered with a fallback font in the test bundle, and the bars are
        // the dominant deterministic signal. Different elapsed values shift
        // the diagonal sweep band and the bar offset, which MUST change the
        // raw pixel buffer.
        let a = try #require(TestPatternSource.renderFrame(
            width: 160, height: 120, sequence: 0, elapsed: 0
        ))
        let b = try #require(TestPatternSource.renderFrame(
            width: 160, height: 120, sequence: 1, elapsed: 0.6
        ))
        #expect(a.dataProvider?.data != b.dataProvider?.data)
    }

    // MARK: - Helpers

    private struct Pixel { let r: UInt8; let g: UInt8; let b: UInt8 }

    private func samplePixel(_ image: CGImage, x: Int, y: Int) -> Pixel? {
        guard let data = image.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else { return nil }
        let bpr = image.bytesPerRow
        let offset = y * bpr + x * 4
        return Pixel(r: bytes[offset], g: bytes[offset + 1], b: bytes[offset + 2])
    }
}

actor ReceivedFrames {
    private var frames: [CameraFrame] = []
    func append(_ f: CameraFrame) { frames.append(f) }
    var count: Int { frames.count }
}
