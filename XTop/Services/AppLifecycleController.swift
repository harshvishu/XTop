import Foundation

/// Terminates and launches simulator apps via `simctl`.
actor AppLifecycleController {
    enum LifecycleError: Error, LocalizedError, Sendable {
        case terminateFailed(stderr: String, exitStatus: Int32)
        case launchFailed(stderr: String, exitStatus: Int32)

        var errorDescription: String? {
            switch self {
            case let .terminateFailed(stderr, status):
                return "Failed to terminate app (exit \(status)): \(stderr)"
            case let .launchFailed(stderr, status):
                return "Failed to launch app (exit \(status)): \(stderr)"
            }
        }
    }

    private let simctl: SimctlClient

    init(simctl: SimctlClient) {
        self.simctl = simctl
    }

    func terminate(bundleIdentifier: String, on udid: String) async throws {
        let result = await simctl.terminate(udid: udid, bundleIdentifier: bundleIdentifier)
        // `simctl terminate` exits non-zero when the app is not running. That
        // is not an error for our use case.
        guard result.exitStatus == 0
            || result.stderr.localizedCaseInsensitiveContains("not currently running")
            || result.stderr.localizedCaseInsensitiveContains("found nothing to terminate")
        else {
            throw LifecycleError.terminateFailed(
                stderr: result.stderr,
                exitStatus: result.exitStatus
            )
        }
    }

    func launch(bundleIdentifier: String, on udid: String) async throws {
        let result = await simctl.launch(udid: udid, bundleIdentifier: bundleIdentifier)
        guard result.exitStatus == 0 else {
            throw LifecycleError.launchFailed(
                stderr: result.stderr,
                exitStatus: result.exitStatus
            )
        }
    }

    func relaunch(bundleIdentifier: String, on udid: String) async throws {
        try await terminate(bundleIdentifier: bundleIdentifier, on: udid)
        try await launch(bundleIdentifier: bundleIdentifier, on: udid)
    }

    /// Returns `true` if the app is currently running on the simulator. This is
    /// a best-effort, read-only probe via `simctl spawn <udid> launchctl list`,
    /// which lists labeled jobs whose label contains the bundle identifier when
    /// the app is running.
    func isRunning(bundleIdentifier: String, on udid: String) async -> Bool {
        let listing = await simctl.launchctlList(udid: udid)
        return listing.localizedCaseInsensitiveContains(bundleIdentifier)
    }
}
