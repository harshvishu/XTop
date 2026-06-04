import Foundation
import Network
import os

/// Localhost TCP server that the shim dylib connects to once at app launch.
///
/// Lifecycle:
/// 1. `start(token:)` binds to `127.0.0.1` on an ephemeral port and returns
///    the chosen port.
/// 2. The first inbound connection's first message must equal `token`.
/// 3. After the token is validated, callers may send frames via `send(frame:)`.
/// 4. `stop()` cancels everything and frees the port.
///
/// Only one connection is accepted per `start` cycle. Any additional inbound
/// connections are rejected immediately.
actor CameraTransportServer {
    enum TransportError: Error, LocalizedError, Sendable {
        case alreadyRunning
        case bindFailed(String)
        case notConnected
        case tokenMismatch

        var errorDescription: String? {
            switch self {
            case .alreadyRunning: return "Transport server is already running."
            case let .bindFailed(reason): return "Failed to bind localhost listener: \(reason)"
            case .notConnected: return "No simulator client is connected."
            case .tokenMismatch: return "Shim client presented an invalid token."
            }
        }
    }

    private let log = Logger(subsystem: "com.vishwakarma.XTop", category: "CameraTransport")

    private var listener: NWListener?
    private var connection: NWConnection?
    private var expectedToken: Data?
    private var isAuthenticated = false
    private var inflightSend = false
    private(set) var droppedFrames: UInt64 = 0
    private(set) var sentFrames: UInt64 = 0

    private var stateContinuation: AsyncStream<CameraTransportState>.Continuation?
    nonisolated(unsafe) private var _stateStream: AsyncStream<CameraTransportState>?

    init() {}

    /// A stream of transport state changes for UI consumption.
    func stateStream() -> AsyncStream<CameraTransportState> {
        if let existing = _stateStream { return existing }
        let stream = AsyncStream<CameraTransportState> { [weak self] continuation in
            Task { await self?.attach(continuation: continuation) }
        }
        _stateStream = stream
        return stream
    }

    private func attach(continuation: AsyncStream<CameraTransportState>.Continuation) {
        self.stateContinuation = continuation
        continuation.yield(.stopped)
    }

    /// Binds the listener and waits for the shim to connect with `token`.
    /// Returns the chosen ephemeral port.
    @discardableResult
    func start(token: Data) async throws -> UInt16 {
        guard listener == nil else { throw TransportError.alreadyRunning }
        precondition(token.count == CameraWireFormat.tokenSize, "Token must be 32 bytes")

        self.expectedToken = token
        self.isAuthenticated = false
        self.droppedFrames = 0
        self.sentFrames = 0

        let parameters = NWParameters.tcp
        parameters.acceptLocalOnly = true

        let listener: NWListener
        do {
            // Bind to an ephemeral local port; NWListener picks a free port
            // and reports it back via `listener.port` after `start()`.
            listener = try NWListener(using: parameters)
        } catch {
            throw TransportError.bindFailed(error.localizedDescription)
        }

        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            Task { await self?.acceptConnection(connection) }
        }

        listener.start(queue: .global(qos: .userInitiated))

        // Wait until the listener actually has a port assigned.
        let port = try await awaitListenerPort(listener)
        log.info("Camera transport listening on 127.0.0.1:\(port, privacy: .public)")
        stateContinuation?.yield(.listening(port: port))
        return port
    }

    /// Sends a JPEG frame to the connected client. No-op when not yet
    /// authenticated. Drops the frame if a previous send is still in flight.
    func send(frame: CameraFrame) async {
        guard let connection, isAuthenticated else { return }
        guard !inflightSend else {
            droppedFrames &+= 1
            return
        }
        inflightSend = true
        let message = CameraWireFormat.encode(payload: frame.jpegData)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            connection.send(content: message, completion: .contentProcessed { [weak self] error in
                Task { await self?.completeSend(error: error) }
                continuation.resume()
            })
        }
    }

    private func completeSend(error: NWError?) {
        inflightSend = false
        if let error {
            log.error("Frame send failed: \(error.localizedDescription, privacy: .public)")
        } else {
            sentFrames &+= 1
        }
    }

    /// Tears down the listener and connection, frees the port.
    func stop() {
        connection?.cancel()
        connection = nil
        listener?.cancel()
        listener = nil
        isAuthenticated = false
        expectedToken = nil
        stateContinuation?.yield(.stopped)
    }

    // MARK: - Private

    private func awaitListenerPort(_ listener: NWListener) async throws -> UInt16 {
        // Poll the listener's port — it becomes available on the first ready state.
        for _ in 0..<200 {
            if let p = listener.port?.rawValue, p != 0 { return p }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw TransportError.bindFailed("Listener did not report a port")
    }

    private func acceptConnection(_ newConnection: NWConnection) async {
        if connection != nil {
            // Already have one — reject extras.
            newConnection.cancel()
            return
        }
        self.connection = newConnection
        newConnection.stateUpdateHandler = { [weak self] state in
            Task { await self?.handleConnectionState(state) }
        }
        newConnection.start(queue: .global(qos: .userInitiated))
    }

    private func handleConnectionState(_ state: NWConnection.State) async {
        switch state {
        case .ready:
            await readToken()
        case let .failed(error):
            log.error("Camera transport connection failed: \(error.localizedDescription, privacy: .public)")
            stateContinuation?.yield(.failed(error.localizedDescription))
            connection?.cancel()
            connection = nil
            isAuthenticated = false
        case .cancelled:
            isAuthenticated = false
            connection = nil
            if listener != nil, let port = listener?.port?.rawValue {
                stateContinuation?.yield(.listening(port: port))
            } else {
                stateContinuation?.yield(.stopped)
            }
        default:
            break
        }
    }

    private func readToken() async {
        guard let connection else { return }
        connection.receive(
            minimumIncompleteLength: CameraWireFormat.tokenSize,
            maximumLength: CameraWireFormat.tokenSize
        ) { [weak self] data, _, _, error in
            Task { await self?.handleToken(data: data, error: error) }
        }
    }

    private func handleToken(data: Data?, error: NWError?) async {
        guard error == nil, let data, data == expectedToken else {
            log.error("Camera transport token mismatch; closing connection")
            stateContinuation?.yield(.failed("token mismatch"))
            connection?.cancel()
            connection = nil
            return
        }
        isAuthenticated = true
        let port = listener?.port?.rawValue ?? 0
        let peer = "shim"
        stateContinuation?.yield(.connected(port: port, peer: peer))
        log.info("Camera transport authenticated on port \(port, privacy: .public)")
    }
}
