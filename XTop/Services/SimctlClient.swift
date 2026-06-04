import Foundation

/// Thin wrapper around `xcrun simctl` invocations. All operations route through
/// `CommandRunner` so they inherit the project's command allowlist and sandbox
/// posture.
actor SimctlClient {
    private let runner: CommandRunner

    init(runner: CommandRunner) {
        self.runner = runner
    }

    // MARK: - Devices

    struct DevicesPayload: Decodable {
        let devices: [String: [Device]]

        struct Device: Decodable {
            let udid: String
            let name: String
            let state: String
            let deviceTypeIdentifier: String?
        }
    }

    /// Returns the JSON-decoded payload from `simctl list devices booted -j`.
    func bootedDevices() async throws -> DevicesPayload {
        let result = await runner.run(
            command: "xcrun",
            arguments: ["simctl", "list", "devices", "booted", "-j"],
            workingDirectory: NSHomeDirectory()
        )
        return try SimctlClient.decodeOrFail(result, as: DevicesPayload.self)
    }

    // MARK: - Apps

    struct InstalledAppsPayload {
        let apps: [String: AppInfo]

        struct AppInfo: Decodable {
            let CFBundleIdentifier: String?
            let CFBundleDisplayName: String?
            let CFBundleName: String?
            let Bundle: String?
            let Path: String?
            let ApplicationType: String?
        }
    }

    /// Returns installed apps for the given simulator. `simctl listapps` emits
    /// an old-style property list, not JSON, so we decode it via
    /// `PropertyListSerialization` rather than `JSONDecoder`.
    func installedApps(udid: String) async throws -> [String: InstalledAppsPayload.AppInfo] {
        let result = await runner.run(
            command: "xcrun",
            arguments: ["simctl", "listapps", udid],
            workingDirectory: NSHomeDirectory()
        )
        guard result.exitStatus == 0 else {
            throw SimctlError.commandFailed(
                command: "simctl listapps",
                exitStatus: result.exitStatus,
                stderr: result.stderr
            )
        }
        guard let data = result.stdout.data(using: .utf8) else {
            throw SimctlError.decodeFailed("stdout was not UTF-8")
        }
        let plist = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        )
        let decoder = PropertyListDecoder()
        let reencoded = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .binary,
            options: 0
        )
        return try decoder.decode(
            [String: InstalledAppsPayload.AppInfo].self,
            from: reencoded
        )
    }

    enum ContainerKind: String, Sendable {
        case app
        case data
        case groups
    }

    /// Returns the container path for the given app and container kind.
    func appContainerPath(
        udid: String,
        bundleIdentifier: String,
        kind: ContainerKind
    ) async -> String? {
        let result = await runner.run(
            command: "xcrun",
            arguments: ["simctl", "get_app_container", udid, bundleIdentifier, kind.rawValue],
            workingDirectory: NSHomeDirectory()
        )
        guard result.exitStatus == 0 else { return nil }
        let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Returns all App Group container paths for the given app, one per line.
    func appGroupContainerPaths(
        udid: String,
        bundleIdentifier: String
    ) async -> [String] {
        let result = await runner.run(
            command: "xcrun",
            arguments: ["simctl", "get_app_container", udid, bundleIdentifier, "groups"],
            workingDirectory: NSHomeDirectory()
        )
        guard result.exitStatus == 0 else { return [] }
        // Output format is "<group-id> <path>" per line; we keep only paths.
        return result.stdout
            .split(separator: "\n")
            .compactMap { line -> String? in
                let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
                guard parts.count == 2 else { return nil }
                let path = String(parts[1]).trimmingCharacters(in: .whitespaces)
                return path.isEmpty ? nil : path
            }
    }

    // MARK: - Lifecycle

    @discardableResult
    func terminate(udid: String, bundleIdentifier: String) async -> CommandResult {
        await runner.run(
            command: "xcrun",
            arguments: ["simctl", "terminate", udid, bundleIdentifier],
            workingDirectory: NSHomeDirectory()
        )
    }

    @discardableResult
    func launch(udid: String, bundleIdentifier: String) async -> CommandResult {
        await launch(
            udid: udid,
            bundleIdentifier: bundleIdentifier,
            childEnvironment: [:]
        )
    }

    /// Launches `bundleIdentifier` and forwards `childEnvironment` as
    /// `SIMCTL_CHILD_*` env vars to `xcrun simctl`. Empty environment behaves
    /// identically to the no-arg overload.
    @discardableResult
    func launch(
        udid: String,
        bundleIdentifier: String,
        childEnvironment: [String: String]
    ) async -> CommandResult {
        var env = ProcessInfo.processInfo.environment
        for (key, value) in childEnvironment {
            env["SIMCTL_CHILD_\(key)"] = value
        }
        return await runner.run(
            command: "xcrun",
            arguments: ["simctl", "launch", udid, bundleIdentifier],
            workingDirectory: NSHomeDirectory(),
            environment: env
        )
    }

    /// Returns the stdout of `simctl spawn <udid> launchctl list`. Used as a
    /// read-only probe to detect whether a bundle id is currently running.
    func launchctlList(udid: String) async -> String {
        let result = await runner.run(
            command: "xcrun",
            arguments: ["simctl", "spawn", udid, "launchctl", "list"],
            workingDirectory: NSHomeDirectory()
        )
        guard result.exitStatus == 0 else { return "" }
        return result.stdout
    }

    // MARK: - Decoding helpers

    /// Decodes the command's stdout into `T` after asserting exit status `0`.
    /// Exposed for tests that want to reuse the same decode pipeline on fixtures.
    static func decode<T: Decodable>(
        _ stdout: String,
        as type: T.Type
    ) throws -> T {
        guard let data = stdout.data(using: .utf8) else {
            throw SimctlError.decodeFailed("stdout was not UTF-8")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func decodeOrFail<T: Decodable>(
        _ result: CommandResult,
        as type: T.Type
    ) throws -> T {
        guard result.exitStatus == 0 else {
            throw SimctlError.commandFailed(
                command: "\(result.command) \(result.arguments.joined(separator: " "))",
                exitStatus: result.exitStatus,
                stderr: result.stderr
            )
        }
        return try decode(result.stdout, as: type)
    }
}

enum SimctlError: Error, LocalizedError, Sendable {
    case commandFailed(command: String, exitStatus: Int32, stderr: String)
    case decodeFailed(String)

    var errorDescription: String? {
        switch self {
        case let .commandFailed(command, exitStatus, stderr):
            return "`\(command)` failed (exit \(exitStatus)): \(stderr)"
        case let .decodeFailed(reason):
            return "Failed to decode simctl output: \(reason)"
        }
    }
}
