import Foundation

actor DefaultMaintenanceService: MaintenanceService {
    private let runner: CommandRunner
    private let resolver: FocusedProjectResolving

    init(
        runner: CommandRunner = CommandRunner(),
        resolver: FocusedProjectResolving
    ) {
        self.runner = runner
        self.resolver = resolver
    }

    func checkToolAvailability() async -> ToolAvailability {
        async let git = runner.isCommandAvailable("git")
        async let xcodebuild = runner.isCommandAvailable("xcodebuild")
        async let pod = runner.isCommandAvailable("pod")

        return await ToolAvailability(
            git: git,
            xcodebuild: xcodebuild,
            pod: pod
        )
    }

    func cleanDerivedData(targetPath: String?) async -> MaintenanceActionResult {
        let path = targetPath ?? (NSHomeDirectory() as NSString)
            .appendingPathComponent("Library/Developer/Xcode/DerivedData")
        let before = directorySize(atPath: path)
        let result = await safeRun(
            command: "rm",
            arguments: ["-rf", path],
            cwd: "/"
        )
        let after = directorySize(atPath: path)
        let reclaimed = before > after ? before - after : 0

        return MaintenanceActionResult(
            action: "Clean DerivedData",
            summary: result.exitStatus == 0 ? "DerivedData cleaned." : "Failed to clean DerivedData.",
            reclaimedBytes: reclaimed,
            commandResults: [result]
        )
    }

    func cleanDeveloperCaches() async -> MaintenanceActionResult {
        let caches = [
            (NSHomeDirectory() as NSString)
                .appendingPathComponent("Library/Caches/org.swift.swiftpm"),
            (NSHomeDirectory() as NSString)
                .appendingPathComponent("Library/Caches/CocoaPods")
        ]

        var results: [CommandResult] = []
        var reclaimed: UInt64 = 0

        for path in caches {
            let before = directorySize(atPath: path)
            let result = await safeRun(
                command: "rm",
                arguments: ["-rf", path],
                cwd: "/"
            )
            let after = directorySize(atPath: path)
            reclaimed += before > after ? before - after : 0
            results.append(result)
        }

        return MaintenanceActionResult(
            action: "Clean Developer Caches",
            summary: results.allSatisfy { $0.exitStatus == 0 }
                ? "Developer caches cleaned."
                : "One or more cache cleanup steps failed.",
            reclaimedBytes: reclaimed,
            commandResults: results
        )
    }

    func resetSwiftPM(projectPath: String) async -> MaintenanceActionResult {
        let folder = (projectPath as NSString).deletingLastPathComponent
        let result = await safeRun(
            command: "xcodebuild",
            arguments: ["-resolvePackageDependencies", "-disableAutomaticPackageResolution"],
            cwd: folder
        )

        return MaintenanceActionResult(
            action: "Reset SwiftPM",
            summary: result.exitStatus == 0 ? "SwiftPM reset command completed." : "SwiftPM reset failed.",
            reclaimedBytes: nil,
            commandResults: [result]
        )
    }

    func refetchSwiftPM(projectPath: String) async -> MaintenanceActionResult {
        let folder = (projectPath as NSString).deletingLastPathComponent
        let result = await safeRun(
            command: "xcodebuild",
            arguments: ["-resolvePackageDependencies"],
            cwd: folder
        )

        return MaintenanceActionResult(
            action: "Refetch SwiftPM",
            summary: result.exitStatus == 0 ? "SwiftPM dependency fetch completed." : "SwiftPM dependency fetch failed.",
            reclaimedBytes: nil,
            commandResults: [result]
        )
    }

    func listPods(projectPath: String) async -> MaintenanceActionResult {
        let folder = (projectPath as NSString).deletingLastPathComponent
        let podfilePath = (folder as NSString).appendingPathComponent("Podfile")

        guard FileManager.default.fileExists(atPath: podfilePath) else {
            return MaintenanceActionResult(
                action: "List Pods",
                summary: "No Podfile found in project folder.",
                reclaimedBytes: nil,
                commandResults: []
            )
        }

        let read = await safeRun(
            command: "sh",
            arguments: ["-c", "grep -E '^\\s*pod\\s+' Podfile || true"],
            cwd: folder
        )
        return MaintenanceActionResult(
            action: "List Pods",
            summary: read.exitStatus == 0 ? "Pod entries listed from Podfile." : "Failed to list Podfile pods.",
            reclaimedBytes: nil,
            commandResults: [read]
        )
    }

    func installPods(projectPath: String) async -> MaintenanceActionResult {
        let folder = (projectPath as NSString).deletingLastPathComponent
        let result = await safeRun(
            command: "pod",
            arguments: ["install"],
            cwd: folder
        )

        return MaintenanceActionResult(
            action: "Install Pods",
            summary: result.exitStatus == 0 ? "pod install completed." : "pod install failed.",
            reclaimedBytes: nil,
            commandResults: [result]
        )
    }

    func updateSinglePod(
        projectPath: String,
        podName: String
    ) async -> MaintenanceActionResult {
        let folder = (projectPath as NSString).deletingLastPathComponent
        let result = await safeRun(
            command: "pod",
            arguments: ["update", podName],
            cwd: folder
        )

        return MaintenanceActionResult(
            action: "Update Pod",
            summary: result.exitStatus == 0 ? "Pod \(podName) updated." : "Pod update failed.",
            reclaimedBytes: nil,
            commandResults: [result]
        )
    }

    func cleanPodCache(podName: String?) async -> MaintenanceActionResult {
        let args: [String]
        if let podName, !podName.isEmpty {
            args = ["cache", "clean", podName]
        } else {
            args = ["cache", "clean", "--all"]
        }

        let result = await safeRun(
            command: "pod",
            arguments: args,
            cwd: NSHomeDirectory()
        )

        return MaintenanceActionResult(
            action: "Clean Pod Cache",
            summary: result.exitStatus == 0 ? "CocoaPods cache clean completed." : "CocoaPods cache clean failed.",
            reclaimedBytes: nil,
            commandResults: [result]
        )
    }

    func deintegratePods(projectPath: String) async -> MaintenanceActionResult {
        let folder = (projectPath as NSString).deletingLastPathComponent
        let result = await safeRun(
            command: "pod",
            arguments: ["deintegrate"],
            cwd: folder
        )

        return MaintenanceActionResult(
            action: "Deintegrate Pods",
            summary: result.exitStatus == 0 ? "pod deintegrate completed." : "pod deintegrate failed.",
            reclaimedBytes: nil,
            commandResults: [result]
        )
    }

    private func safeRun(
        command: String,
        arguments: [String],
        cwd: String
    ) async -> CommandResult {
        await runner.run(
            command: command,
            arguments: arguments,
            workingDirectory: cwd
        ) { cmd, args, _ in
            if cmd == "rm" {
                return args.contains { arg in
                    arg.contains("DerivedData")
                        || arg.contains("Caches")
                        || arg.contains("swiftpm")
                        || arg.contains("CocoaPods")
                }
            }
            return true
        }
    }

    private func directorySize(atPath path: String) -> UInt64 {
        let fileManager = FileManager.default
        var total: UInt64 = 0

        guard let enumerator = fileManager.enumerator(atPath: path) else {
            return 0
        }

        for case let element as String in enumerator {
            let fullPath = (path as NSString).appendingPathComponent(element)
            guard
                let attrs = try? fileManager.attributesOfItem(atPath: fullPath),
                let fileSize = attrs[.size] as? NSNumber
            else {
                continue
            }
            total += fileSize.uint64Value
        }

        return total
    }
}
