import Foundation

actor DefaultFocusedProjectResolver: FocusedProjectResolving {
    private let runner: CommandRunner
    private let homeDirectory: String
    private let overrideKey = "xtop.manualProjectPath"

    init(
        runner: CommandRunner = CommandRunner(),
        homeDirectory: String = NSHomeDirectory()
    ) {
        self.runner = runner
        self.homeDirectory = homeDirectory
    }

    func resolveFocusedProject() async -> FocusedProjectResolution {
        if let override = manualOverridePath() {
            return FocusedProjectResolution(
                projectPath: override,
                confidence: 1.0,
                source: "manual-override",
                isManualOverride: true
            )
        }

        if let appleScriptPath = await xcodeFrontDocumentPath() {
            return FocusedProjectResolution(
                projectPath: appleScriptPath,
                confidence: 0.9,
                source: "xcode-front-document",
                isManualOverride: false
            )
        }

        let cwd = FileManager.default.currentDirectoryPath
        if let discovered = nearestXcodeProjectPath(from: cwd) {
            return FocusedProjectResolution(
                projectPath: discovered,
                confidence: 0.5,
                source: "cwd-scan",
                isManualOverride: false
            )
        }

        return FocusedProjectResolution(
            projectPath: nil,
            confidence: 0.0,
            source: "none",
            isManualOverride: false
        )
    }

    func setManualOverride(path: String?) async {
        if let path, !path.isEmpty {
            UserDefaults.standard.set(path, forKey: overrideKey)
        } else {
            UserDefaults.standard.removeObject(forKey: overrideKey)
        }
    }

    private func manualOverridePath() -> String? {
        UserDefaults.standard.string(forKey: overrideKey)
    }

    private func xcodeFrontDocumentPath() async -> String? {
        let script = "tell application \"Xcode\" to if (count of documents) > 0 then return path of front document"
        let result = await runner.run(
            command: "osascript",
            arguments: ["-e", script],
            workingDirectory: homeDirectory
        )

        guard result.exitStatus == 0 else { return nil }
        let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }

    private func nearestXcodeProjectPath(from directory: String) -> String? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: directory) else { return nil }

        for case let element as String in enumerator {
            if element.hasSuffix(".xcodeproj") || element.hasSuffix(".xcworkspace") {
                return (directory as NSString).appendingPathComponent(element)
            }
        }

        return nil
    }
}
