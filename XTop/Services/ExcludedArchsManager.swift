import Foundation

actor ExcludedArchsManager: ExcludedArchsManaging {
    private struct EditStats: Sendable {
        var changedBlocks = 0
        var changedLines = 0
        var debugBlocksChanged = 0
        var nonDebugBlocksChanged = 0
    }

    enum Error: Swift.Error, LocalizedError {
        case fileNotFound(String)
        case xcBuildConfigurationSectionNotFound
        case unexpectedEndOfBuildConfigurationBlock
        case buildSettingsBlockNotFound
        case buildSettingsClosingBraceNotFound

        var errorDescription: String? {
            switch self {
            case .fileNotFound(let path):
                return "Project file not found: \(path)"
            case .xcBuildConfigurationSectionNotFound:
                return "XCBuildConfiguration section not found in project file"
            case .unexpectedEndOfBuildConfigurationBlock:
                return "Unexpected end of XCBuildConfiguration block while parsing project file"
            case .buildSettingsBlockNotFound:
                return "buildSettings block not found while processing Debug configuration"
            case .buildSettingsClosingBraceNotFound:
                return "buildSettings closing brace not found while processing Debug configuration"
            }
        }
    }

    private let fileManager: FileManager

    nonisolated init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func dryRun(mode: ExcludedArchsMode, projectFilePath: String) async throws -> ExcludedArchsResult {
        try process(mode: mode, projectFilePath: projectFilePath, dryRun: true)
    }

    func apply(mode: ExcludedArchsMode, projectFilePath: String) async throws -> ExcludedArchsResult {
        try process(mode: mode, projectFilePath: projectFilePath, dryRun: false)
    }

    private func process(
        mode: ExcludedArchsMode,
        projectFilePath: String,
        dryRun: Bool
    ) throws -> ExcludedArchsResult {
        guard fileManager.fileExists(atPath: projectFilePath) else {
            throw Error.fileNotFound(projectFilePath)
        }

        let content = try String(contentsOf: URL(filePath: projectFilePath), encoding: .utf8)
        guard let sectionRange = sectionRange(in: content) else {
            throw Error.xcBuildConfigurationSectionNotFound
        }

        let sectionHeader = "/* Begin XCBuildConfiguration section */\n"
        let sectionFooter = "/* End XCBuildConfiguration section */"
        let sectionBody = String(content[sectionRange])

        let transformed = try transformSectionBody(sectionBody, mode: mode)
        let stats = transformed.stats

        if stats.changedBlocks == 0 {
            return ExcludedArchsResult(
                changedBlocks: 0,
                changedLines: 0,
                debugBlocksChanged: 0,
                nonDebugBlocksChanged: 0,
                backupPath: nil,
                message: "No changes required for mode '\(modeLabel(mode))'."
            )
        }

        let updatedSection = sectionHeader + transformed.sectionBody + sectionFooter
        let updatedContent = content.replacing(
            sectionHeader + sectionBody + sectionFooter,
            with: updatedSection,
            maxReplacements: 1
        )

        var backupPath: String?

        if !dryRun {
            let backupURL = try makeBackupURL(for: URL(filePath: projectFilePath))
            try content.write(to: backupURL, atomically: true, encoding: .utf8)
            try updatedContent.write(to: URL(filePath: projectFilePath), atomically: true, encoding: .utf8)
            backupPath = backupURL.path()
        }

        let message = buildSummary(
            mode: mode,
            projectFilePath: projectFilePath,
            stats: stats,
            dryRun: dryRun
        )

        return ExcludedArchsResult(
            changedBlocks: stats.changedBlocks,
            changedLines: stats.changedLines,
            debugBlocksChanged: stats.debugBlocksChanged,
            nonDebugBlocksChanged: stats.nonDebugBlocksChanged,
            backupPath: backupPath,
            message: message
        )
    }

    private func sectionRange(in content: String) -> Range<String.Index>? {
        guard let start = content.range(of: "/* Begin XCBuildConfiguration section */\n")?.upperBound,
              let end = content.range(of: "/* End XCBuildConfiguration section */")?.lowerBound,
              start <= end else {
            return nil
        }

        return start..<end
    }

    private func transformSectionBody(
        _ sectionBody: String,
        mode: ExcludedArchsMode
    ) throws -> (sectionBody: String, stats: EditStats) {
        let lines = sectionBody.split(separator: "\n", omittingEmptySubsequences: false).map { String($0) }

        var rebuilt: [String] = []
        var block: [String] = []
        var insideBlock = false
        var braceDepth = 0
        var stats = EditStats()

        for line in lines {
            if insideBlock {
                block.append(line)
                braceDepth += line.filter { $0 == "{" }.count
                braceDepth -= line.filter { $0 == "}" }.count

                if braceDepth == 0 {
                    let transformed = try transformBlock(block, mode: mode, stats: &stats)
                    rebuilt.append(contentsOf: transformed)
                    block.removeAll(keepingCapacity: true)
                    insideBlock = false
                }
                continue
            }

            if isBuildConfigurationBlockStart(line) {
                insideBlock = true
                block = [line]
                braceDepth = line.filter { $0 == "{" }.count - line.filter { $0 == "}" }.count

                if braceDepth == 0 {
                    let transformed = try transformBlock(block, mode: mode, stats: &stats)
                    rebuilt.append(contentsOf: transformed)
                    block.removeAll(keepingCapacity: true)
                    insideBlock = false
                }
            } else {
                rebuilt.append(line)
            }
        }

        if insideBlock {
            throw Error.unexpectedEndOfBuildConfigurationBlock
        }

        return (rebuilt.joined(separator: "\n"), stats)
    }

    private func isBuildConfigurationBlockStart(_ line: String) -> Bool {
        let pattern = #"^\s*[A-F0-9]+\s/\* .* \*/ = \{$"#
        return line.range(of: pattern, options: .regularExpression) != nil
    }

    private func transformBlock(
        _ blockLines: [String],
        mode: ExcludedArchsMode,
        stats: inout EditStats
    ) throws -> [String] {
        let configName = configurationName(for: blockLines)
        var updated = blockLines
        var changed = false
        var changedLines = 0

        switch mode {
        case .clearArm64:
            for index in updated.indices {
                if let match = updated[index].firstMatch(of: /^(\s*)EXCLUDED_ARCHS = arm64;$/) {
                    changed = true
                    changedLines += 1
                    updated[index] = "\(match.1)EXCLUDED_ARCHS = \"\";"
                }
            }

        case .setDebugArm64:
            guard configName == "Debug" else {
                return blockLines
            }

            var foundUnscoped = false

            for index in updated.indices {
                if let match = updated[index].firstMatch(of: /^(\s*)EXCLUDED_ARCHS = (.*);$/) {
                    foundUnscoped = true
                    let currentValue = String(match.2)
                    if currentValue != "arm64" {
                        changed = true
                        changedLines += 1
                        updated[index] = "\(match.1)EXCLUDED_ARCHS = arm64;"
                    }
                }
            }

            if !foundUnscoped {
                guard let settingsStart = updated.firstIndex(where: { $0.contains("buildSettings = {") }) else {
                    throw Error.buildSettingsBlockNotFound
                }

                var closingIndex: Int?
                for index in updated.indices where index > settingsStart {
                    if updated[index].firstMatch(of: /^\s*};$/) != nil {
                        closingIndex = index
                        break
                    }
                }

                guard let closingIndex else {
                    throw Error.buildSettingsClosingBraceNotFound
                }

                let indent = String(updated[settingsStart].prefix { $0 == " " || $0 == "\t" }) + "\t"
                updated.insert("\(indent)EXCLUDED_ARCHS = arm64;", at: closingIndex)
                changed = true
                changedLines += 1
            }
        }

        if changed {
            stats.changedBlocks += 1
            stats.changedLines += changedLines
            if configName == "Debug" {
                stats.debugBlocksChanged += 1
            } else {
                stats.nonDebugBlocksChanged += 1
            }
        }

        return updated
    }

    private func configurationName(for blockLines: [String]) -> String? {
        guard let line = blockLines.first(where: {
            $0.range(of: #"^\s*name = "#, options: .regularExpression) != nil
        }) else {
            return nil
        }

        if let quoted = line.range(of: #"^\s*name = "([^"]+)";"#, options: .regularExpression) {
            let text = String(line[quoted])
            return text
                .replacing(#"^\s*name = ""#, with: "", options: .regularExpression)
                .replacing(#"";$"#, with: "", options: .regularExpression)
        }

        if let unquoted = line.range(of: #"^\s*name = ([^;]+);"#, options: .regularExpression) {
            let text = String(line[unquoted])
            return text
                .replacing(#"^\s*name = "#, with: "", options: .regularExpression)
                .replacing(#";$"#, with: "", options: .regularExpression)
        }

        return nil
    }

    private func makeBackupURL(for projectFileURL: URL) throws -> URL {
        let timestamp = Date.now.formatted(
            Date.FormatStyle()
                .year(.defaultDigits)
                .month(.twoDigits)
                .day(.twoDigits)
                .hour(.twoDigits(amPM: .omitted))
                .minute(.twoDigits)
                .second(.twoDigits)
        )

        let basePath = projectFileURL.path() + ".backup." + timestamp
        var candidate = URL(filePath: basePath)
        var suffix = 0

        while fileManager.fileExists(atPath: candidate.path()) {
            suffix += 1
            candidate = URL(filePath: basePath + ".\(suffix)")
        }

        return candidate
    }

    private func buildSummary(
        mode: ExcludedArchsMode,
        projectFilePath: String,
        stats: EditStats,
        dryRun: Bool
    ) -> String {
        var lines: [String] = []
        lines.append("Mode: \(modeLabel(mode))")
        lines.append("Project file: \(projectFilePath)")
        lines.append("Changed blocks: \(stats.changedBlocks)")
        lines.append("Changed lines: \(stats.changedLines)")
        lines.append("Debug blocks changed: \(stats.debugBlocksChanged)")
        lines.append("Non-Debug blocks changed: \(stats.nonDebugBlocksChanged)")

        if dryRun {
            lines.append("Dry run only. No file changes written.")
        }

        return lines.joined(separator: "\n")
    }

    private func modeLabel(_ mode: ExcludedArchsMode) -> String {
        switch mode {
        case .clearArm64:
            return "clear"
        case .setDebugArm64:
            return "set-debug-arm64"
        }
    }
}
