import Foundation
import os

/// Orchestrates a single camera-injection session end-to-end:
///   1. Start the localhost transport server with a per-launch token.
///   2. Terminate the target app (best-effort).
///   3. Launch it with `DYLD_INSERT_LIBRARIES`, port, and token env vars.
///   4. Start the chosen frame source and forward frames to the transport.
///   5. On `stop()`, tear everything down in reverse.
actor CameraInjectionCoordinator {
    enum CoordinatorError: Error, LocalizedError, Sendable {
        case shimMissing(String)
        case launchFailed(String)

        var errorDescription: String? {
            switch self {
            case let .shimMissing(reason): return "Camera shim unavailable: \(reason)"
            case let .launchFailed(reason): return "Launch failed: \(reason)"
            }
        }
    }

    private let lifecycle: any SimulatorAppLauncher
    private let transport: CameraTransportServer
    private let log = Logger(subsystem: "com.vishwakarma.XTop", category: "CameraCoordinator")

    private var currentSource: (any CameraFrameSource)?
    private(set) var activeBundleID: String?
    private(set) var activeUDID: String?
    private(set) var activePort: UInt16?
    private(set) var activePID: Int32?

    init(
        lifecycle: any SimulatorAppLauncher,
        transport: CameraTransportServer = CameraTransportServer()
    ) {
        self.lifecycle = lifecycle
        self.transport = transport
    }

    /// Exposes the transport state stream so view models can subscribe.
    func transportStateStream() async -> AsyncStream<CameraTransportState> {
        await transport.stateStream()
    }

    /// Starts a new injection session. Caller supplies the chosen source.
    func injectAndLaunch(
        bundleIdentifier: String,
        on udid: String,
        source: any CameraFrameSource
    ) async throws {
        await stop()

        let shimURL: URL
        do {
            shimURL = try CameraShimBundle.resolvedURL()
        } catch {
            throw CoordinatorError.shimMissing(error.localizedDescription)
        }

        let token = CameraWireFormat.makeToken()
        let port: UInt16
        do {
            port = try await transport.start(token: token)
        } catch {
            throw CoordinatorError.launchFailed(error.localizedDescription)
        }
        activePort = port

        // Best-effort terminate.
        try? await lifecycle.terminate(bundleIdentifier: bundleIdentifier, on: udid)

        let env: [String: String] = [
            "DYLD_INSERT_LIBRARIES": shimURL.path,
            "XTOP_CAMERA_PORT": String(port),
            "XTOP_CAMERA_TOKEN": token.map { String(format: "%02x", $0) }.joined()
        ]

        do {
            let pid = try await lifecycle.launch(
                bundleIdentifier: bundleIdentifier,
                on: udid,
                childEnvironment: env
            )
            activePID = pid
        } catch {
            await transport.stop()
            activePort = nil
            throw CoordinatorError.launchFailed(error.localizedDescription)
        }

        activeBundleID = bundleIdentifier
        activeUDID = udid
        currentSource = source

        // Begin streaming. Frames flow into the transport actor.
        let transport = self.transport
        try await source.start { frame in
            Task { await transport.send(frame: frame) }
        }
        log.info("Camera injection running for \(bundleIdentifier, privacy: .public) on port \(port, privacy: .public)")
    }

    func stop() async {
        if let currentSource {
            await currentSource.stop()
        }
        currentSource = nil
        await transport.stop()
        activeBundleID = nil
        activeUDID = nil
        activePort = nil
        activePID = nil
    }
}
