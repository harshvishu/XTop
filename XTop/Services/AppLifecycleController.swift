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
        _ = try await launch(
            bundleIdentifier: bundleIdentifier,
            on: udid,
            childEnvironment: [:]
        )
    }

    /// Launches a simulator app, forwarding `childEnvironment` as
    /// `SIMCTL_CHILD_*` env vars so they reach the launched app process.
    ///
    /// `DYLD_INSERT_LIBRARIES` is the primary use case — it must be passed via
    /// `SIMCTL_CHILD_DYLD_INSERT_LIBRARIES=…` to take effect inside the
    /// simulator process.
    ///
    /// Returns the PID parsed from `simctl launch` stdout (format
    /// `<bundle-id>: <pid>`) when available, or `nil` if it could not be
    /// parsed.
    @discardableResult
    func launch(
        bundleIdentifier: String,
        on udid: String,
        childEnvironment: [String: String]
    ) async throws -> Int32? {
        let result = await simctl.launch(
            udid: udid,
            bundleIdentifier: bundleIdentifier,
            childEnvironment: childEnvironment
        )
        guard result.exitStatus == 0 else {
            throw LifecycleError.launchFailed(
                stderr: result.stderr,
                exitStatus: result.exitStatus
            )
        }
        return Self.parsePID(fromLaunchStdout: result.stdout)
    }

    /// Parses the PID emitted by `simctl launch`. Output looks like
    /// `com.example.app: 12345\n`. Returns `nil` if no integer suffix is
    /// present (e.g. older Xcode versions or unexpected output).
    static func parsePID(fromLaunchStdout stdout: String) -> Int32? {
        let trimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let lastSpace = trimmed.lastIndex(of: " ") else { return nil }
        let suffix = trimmed[trimmed.index(after: lastSpace)...]
        return Int32(suffix)
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
