import Foundation
import CoreGraphics
import Network
import Testing
@testable import XTop

@Suite("Camera transport")
struct CameraTransportTests {

    @Test func wireFormatEncodesAndDecodesRoundTrip() {
        let payload = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let encoded = CameraWireFormat.encode(payload: payload)
        #expect(encoded.count == CameraWireFormat.headerSize + payload.count)
        let header = encoded.prefix(CameraWireFormat.headerSize)
        let length = CameraWireFormat.parseHeader(Data(header))
        #expect(length == payload.count)
    }

    @Test func wireFormatRejectsBadMagic() {
        var bytes: [UInt8] = [0, 0, 0, 0, 4, 0, 0, 0]
        let parsed = CameraWireFormat.parseHeader(Data(bytes))
        #expect(parsed == nil)
        bytes = [0x58, 0x54, 0x43, 0x4D, 0xFF, 0xFF, 0xFF, 0x7F]
        #expect(CameraWireFormat.parseHeader(Data(bytes)) == nil) // > max
    }

    @Test func wireFormatTokenIsRandomAndCorrectSize() {
        let a = CameraWireFormat.makeToken()
        let b = CameraWireFormat.makeToken()
        #expect(a.count == CameraWireFormat.tokenSize)
        #expect(b.count == CameraWireFormat.tokenSize)
        #expect(a != b)
    }

    @Test func serverAcceptsAuthenticatedClientAndRoundTripsFrame() async throws {
        let server = CameraTransportServer()
        let token = CameraWireFormat.makeToken()
        let port = try await server.start(token: token)
        #expect(port > 0)

        // Build a tiny client.
        let client = TestTransportClient(port: port)
        try await client.connectAndAuthenticate(token: token)

        // Give the server a moment to flip to authenticated.
        try await Task.sleep(for: .milliseconds(250))

        let payload = Data(repeating: 0xAB, count: 1024)
        let frame = CameraFrame(
            jpegData: payload,
            pixelSize: .init(width: 64, height: 64),
            presentationSeconds: 0,
            sequence: 0
        )
        await server.send(frame: frame)
        let received = try await client.receiveOneFrame()
        #expect(received == payload)

        await server.stop()
        client.disconnect()
    }
}

/// Minimal Network.framework client used only by these tests.
private final class TestTransportClient: @unchecked Sendable {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "test-transport-client")

    init(port: UInt16) {
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host("127.0.0.1"),
            port: NWEndpoint.Port(rawValue: port)!
        )
        self.connection = NWConnection(to: endpoint, using: .tcp)
    }

    func connectAndAuthenticate(token: Data) async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: c.resume()
                case let .failed(error): c.resume(throwing: error)
                default: break
                }
            }
            connection.start(queue: queue)
        }
        try await sendRaw(token)
    }

    func sendRaw(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { c.resume(throwing: error) } else { c.resume() }
            })
        }
    }

    /// Receives one framed message and returns the payload.
    func receiveOneFrame() async throws -> Data {
        let header = try await receiveExact(count: CameraWireFormat.headerSize)
        guard let len = CameraWireFormat.parseHeader(header) else {
            throw NSError(domain: "test", code: 1)
        }
        return try await receiveExact(count: len)
    }

    private func receiveExact(count: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Data, Error>) in
            connection.receive(minimumIncompleteLength: count, maximumLength: count) { data, _, _, error in
                if let error { c.resume(throwing: error); return }
                guard let data, data.count == count else {
                    c.resume(throwing: NSError(domain: "short-read", code: 1))
                    return
                }
                c.resume(returning: data)
            }
        }
    }

    func disconnect() {
        connection.cancel()
    }
}
