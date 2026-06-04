import Foundation
import Testing
@testable import XTop

/// In-memory fake `SimulatorAppLauncher` that records every call without
/// shelling out to `simctl`. Used to verify the ordering, environment, and
/// teardown behavior of `CameraInjectionCoordinator`.
actor FakeSimulatorAppLauncher: SimulatorAppLauncher {
    struct LaunchCall: Equatable, Sendable {
        let bundleIdentifier: String
        let udid: String
        let environment: [String: String]
    }

    private(set) var terminateCalls: [(bundleIdentifier: String, udid: String)] = []
    private(set) var launchCalls: [LaunchCall] = []
    var launchPID: Int32? = 4242
    var launchError: Error?
    var terminateError: Error?

    func terminate(bundleIdentifier: String, on udid: String) async throws {
        terminateCalls.append((bundleIdentifier, udid))
        if let terminateError { throw terminateError }
    }

    @discardableResult
    func launch(
        bundleIdentifier: String,
        on udid: String,
        childEnvironment: [String: String]
    ) async throws -> Int32? {
        launchCalls.append(LaunchCall(
            bundleIdentifier: bundleIdentifier,
            udid: udid,
            environment: childEnvironment
        ))
        if let launchError { throw launchError }
        return launchPID
    }

    func setLaunchError(_ error: Error?) { launchError = error }
}

/// A trivial frame source that records start/stop and never emits frames.
actor RecordingFrameSource: CameraFrameSource {
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start(sink: @escaping @Sendable (CameraFrame) -> Void) async throws {
        startCount += 1
    }

    func stop() async {
        stopCount += 1
    }
}

@Suite("CameraInjectionCoordinator")
struct CameraInjectionCoordinatorTests {
    @Test func injectAndLaunchTerminatesThenLaunchesWithRequiredEnvVars() async throws {
        let launcher = FakeSimulatorAppLauncher()
        let coordinator = CameraInjectionCoordinator(lifecycle: launcher)
        let source = RecordingFrameSource()

        try await coordinator.injectAndLaunch(
            bundleIdentifier: "com.example.app",
            on: "UDID-1",
            source: source
        )

        let terminates = await launcher.terminateCalls
        let launches = await launcher.launchCalls
        #expect(terminates.count == 1)
        #expect(terminates[0].bundleIdentifier == "com.example.app")
        #expect(launches.count == 1)
        let call = try #require(launches.first)
        #expect(call.bundleIdentifier == "com.example.app")
        #expect(call.udid == "UDID-1")
        #expect(call.environment["DYLD_INSERT_LIBRARIES"]?.hasSuffix("XTopCameraShim.bin") == true)
        let portString = try #require(call.environment["XTOP_CAMERA_PORT"])
        #expect(Int(portString) ?? 0 > 0)
        let token = try #require(call.environment["XTOP_CAMERA_TOKEN"])
        // 32 bytes hex-encoded → 64 chars.
        #expect(token.count == 64)
        #expect(token.allSatisfy { $0.isHexDigit })

        let startCount = await source.startCount
        #expect(startCount == 1)

        let activeBundle = await coordinator.activeBundleID
        let activeUDID = await coordinator.activeUDID
        let activePID = await coordinator.activePID
        let activePort = await coordinator.activePort
        #expect(activeBundle == "com.example.app")
        #expect(activeUDID == "UDID-1")
        #expect(activePID == 4242)
        #expect((activePort ?? 0) > 0)

        await coordinator.stop()
    }

    @Test func stopTearsDownSourceAndClearsActiveState() async throws {
        let launcher = FakeSimulatorAppLauncher()
        let coordinator = CameraInjectionCoordinator(lifecycle: launcher)
        let source = RecordingFrameSource()
        try await coordinator.injectAndLaunch(
            bundleIdentifier: "com.example.app",
            on: "UDID-1",
            source: source
        )

        await coordinator.stop()

        let stopCount = await source.stopCount
        #expect(stopCount == 1)
        let active = await (
            coordinator.activeBundleID,
            coordinator.activeUDID,
            coordinator.activePort,
            coordinator.activePID
        )
        #expect(active.0 == nil)
        #expect(active.1 == nil)
        #expect(active.2 == nil)
        #expect(active.3 == nil)
    }

    @Test func launchFailureRollsBackTransportAndPropagatesError() async throws {
        let launcher = FakeSimulatorAppLauncher()
        await launcher.setLaunchError(
            AppLifecycleController.LifecycleError.launchFailed(stderr: "boom", exitStatus: 1)
        )
        let coordinator = CameraInjectionCoordinator(lifecycle: launcher)
        let source = RecordingFrameSource()

        await #expect(throws: CameraInjectionCoordinator.CoordinatorError.self) {
            try await coordinator.injectAndLaunch(
                bundleIdentifier: "com.example.app",
                on: "UDID-1",
                source: source
            )
        }

        // Active state must be cleared after a failed launch.
        let activePort = await coordinator.activePort
        let activeBundle = await coordinator.activeBundleID
        #expect(activePort == nil)
        #expect(activeBundle == nil)
        // Source must NOT have been started.
        let startCount = await source.startCount
        #expect(startCount == 0)
    }

    @Test func secondInjectStopsPreviousSession() async throws {
        let launcher = FakeSimulatorAppLauncher()
        let coordinator = CameraInjectionCoordinator(lifecycle: launcher)
        let first = RecordingFrameSource()
        let second = RecordingFrameSource()

        try await coordinator.injectAndLaunch(
            bundleIdentifier: "com.example.app",
            on: "UDID-1",
            source: first
        )
        try await coordinator.injectAndLaunch(
            bundleIdentifier: "com.example.app",
            on: "UDID-1",
            source: second
        )

        let firstStops = await first.stopCount
        let secondStarts = await second.startCount
        #expect(firstStops >= 1)
        #expect(secondStarts == 1)

        await coordinator.stop()
    }
}
