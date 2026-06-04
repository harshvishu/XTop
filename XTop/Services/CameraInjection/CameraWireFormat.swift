import Foundation
import Security

/// On-the-wire framing shared between `CameraTransportServer` (macOS) and the
/// shim dylib client (simulator-side).
///
/// Frame layout:
///   - 4-byte magic `XTCM` (ASCII)
///   - 4-byte little-endian payload length (UInt32)
///   - <length> payload bytes
///
/// The first message after `connect` must be the 32-byte authentication token.
/// Subsequent messages are JPEG-encoded video frames.
enum CameraWireFormat {
    static let magic: [UInt8] = [0x58, 0x54, 0x43, 0x4D] // "XTCM"
    static let headerSize = 8
    static let tokenSize = 32
    /// Hard cap on a single payload to avoid runaway memory. 8 MiB is well
    /// above any reasonable JPEG frame.
    static let maxPayloadBytes = 8 * 1024 * 1024

    /// Builds a framed message: magic + length + payload.
    static func encode(payload: Data) -> Data {
        var buffer = Data(capacity: headerSize + payload.count)
        buffer.append(contentsOf: magic)
        var len = UInt32(payload.count).littleEndian
        withUnsafeBytes(of: &len) { buffer.append(contentsOf: $0) }
        buffer.append(payload)
        return buffer
    }

    /// Generates a fresh per-launch 32-byte authentication token.
    static func makeToken() -> Data {
        var bytes = [UInt8](repeating: 0, count: tokenSize)
        let status = SecRandomCopyBytes(kSecRandomDefault, tokenSize, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed")
        return Data(bytes)
    }

    /// Parses a header buffer and returns the declared payload length if the
    /// magic matches. Returns nil for malformed headers.
    static func parseHeader(_ header: Data) -> Int? {
        guard header.count == headerSize else { return nil }
        for (i, byte) in magic.enumerated() where header[header.startIndex + i] != byte {
            return nil
        }
        var len: UInt32 = 0
        let lenStart = header.startIndex + 4
        for i in 0..<4 {
            len |= UInt32(header[lenStart + i]) << (8 * i)
        }
        let intLen = Int(len)
        guard intLen >= 0, intLen <= maxPayloadBytes else { return nil }
        return intLen
    }
}
