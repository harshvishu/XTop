import Foundation

actor DefaultXcodeEnvironmentService: XcodeEnvironmentService {
    private let runner: CommandRunner
    private let homeDirectory: String

    init(
        runner: CommandRunner = CommandRunner(),
        homeDirectory: String = NSHomeDirectory()
    ) {
        self.runner = runner
        self.homeDirectory = homeDirectory
    }

    func collectXcodeEnvironment() async -> XcodeEnvironmentSnapshot {
        var errors: [String] = []

        let derivedDataLocations = await resolveDerivedDataLocations()
        let totalDerivedData = derivedDataLocations.reduce(UInt64(0)) { $0 + $1.sizeBytes }
        let openProjects = await detectOpenProjects()

        let profilesResult = await collectProvisioningProfiles()
        if !profilesResult.errors.isEmpty {
            errors.append(contentsOf: profilesResult.errors)
        }

        let certificatesResult = await collectCertificates()
        if !certificatesResult.errors.isEmpty {
            errors.append(contentsOf: certificatesResult.errors)
        }

        return XcodeEnvironmentSnapshot(
            derivedDataLocations: derivedDataLocations,
            totalDerivedDataBytes: totalDerivedData,
            openProjects: openProjects,
            provisioningProfiles: profilesResult.items,
            certificates: certificatesResult.items,
            errors: errors,
            lastUpdated: .now
        )
    }

    private func resolveDerivedDataLocations() async -> [DerivedDataLocation] {
        let defaultPath = (homeDirectory as NSString)
            .appendingPathComponent("Library/Developer/Xcode/DerivedData")
        var paths = [defaultPath]

        let customDefaults = await runner.run(
            command: "defaults",
            arguments: ["read", "com.apple.dt.Xcode", "IDECustomDerivedDataLocation"],
            workingDirectory: homeDirectory
        )

        if customDefaults.exitStatus == 0 {
            let customPath = customDefaults.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if !customPath.isEmpty {
                paths.append(customPath)
            }
        }

        return Array(Set(paths)).map { path in
            DerivedDataLocation(
                path: path,
                sizeBytes: directorySize(atPath: path)
            )
        }
    }

    private func detectOpenProjects() async -> [XcodeProjectUsage] {
        let appleScript = "tell application \"Xcode\" to get path of documents"
        let result = await runner.run(
            command: "osascript",
            arguments: ["-e", appleScript],
            workingDirectory: homeDirectory
        )

        var projectPaths: [String] = []
        if result.exitStatus == 0 {
            projectPaths = result.stdout
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        if projectPaths.isEmpty {
            let cwd = FileManager.default.currentDirectoryPath
            if let fallback = nearestXcodeProjectPath(from: cwd) {
                projectPaths = [fallback]
            }
        }

        return projectPaths.map { path in
            let folder = (path as NSString).deletingLastPathComponent
            return XcodeProjectUsage(
                projectPath: path,
                sizeBytes: directorySize(atPath: folder)
            )
        }
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

    private func collectProvisioningProfiles() async -> (items: [ProvisioningProfileSummary], errors: [String]) {
        let profilesPath = (homeDirectory as NSString)
            .appendingPathComponent("Library/MobileDevice/Provisioning Profiles")
        let fm = FileManager.default

        guard let files = try? fm.contentsOfDirectory(atPath: profilesPath) else {
            return ([], ["Provisioning profiles directory not found."])
        }

        var summaries: [ProvisioningProfileSummary] = []
        var errors: [String] = []

        for file in files where file.hasSuffix(".mobileprovision") {
            let fullPath = (profilesPath as NSString).appendingPathComponent(file)
            let decode = await runner.run(
                command: "security",
                arguments: ["cms", "-D", "-i", fullPath],
                workingDirectory: homeDirectory
            )

            if decode.exitStatus != 0 {
                errors.append("Failed to decode profile: \(file)")
                continue
            }

            let name = extract(xml: decode.stdout, key: "Name") ?? file
            let expiration = extract(xml: decode.stdout, key: "ExpirationDate") ?? "Unknown"
            let team = extractTeamIdentifier(xml: decode.stdout) ?? "Unknown"

            summaries.append(
                ProvisioningProfileSummary(
                    name: name,
                    teamIdentifier: team,
                    expirationDate: expiration,
                    path: fullPath
                )
            )
        }

        return (summaries, errors)
    }

    private func collectCertificates() async -> (items: [CertificateSummary], errors: [String]) {
        let result = await runner.run(
            command: "security",
            arguments: ["find-identity", "-v", "-p", "codesigning"],
            workingDirectory: homeDirectory
        )

        guard result.exitStatus == 0 else {
            return ([], ["Unable to query code-signing certificates."])
        }

        let certs = result.stdout
            .split(separator: "\n")
            .compactMap { line -> CertificateSummary? in
                let text = String(line)
                guard text.contains("\"") else { return nil }
                guard
                    let firstQuote = text.firstIndex(of: "\""),
                    let lastQuote = text.lastIndex(of: "\"")
                else {
                    return nil
                }

                let name = String(text[text.index(after: firstQuote)..<lastQuote])
                let teamHint = name
                    .components(separatedBy: "(")
                    .last?
                    .replacingOccurrences(of: ")", with: "") ?? "Unknown"

                return CertificateSummary(
                    commonName: name,
                    teamHint: teamHint,
                    expirationDate: "Check Keychain"
                )
            }

        return (certs, [])
    }

    private func extract(xml: String, key: String) -> String? {
        let pattern = "<key>\\Q\(key)\\E</key>\\s*<(?:string|date)>([^<]+)</(?:string|date)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        guard
            let match = regex.firstMatch(in: xml, options: [], range: range),
            let valueRange = Range(match.range(at: 1), in: xml)
        else {
            return nil
        }
        return String(xml[valueRange])
    }

    private func extractTeamIdentifier(xml: String) -> String? {
        let pattern = "<key>TeamIdentifier</key>\\s*<array>\\s*<string>([^<]+)</string>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        guard
            let match = regex.firstMatch(in: xml, options: [], range: range),
            let valueRange = Range(match.range(at: 1), in: xml)
        else {
            return nil
        }
        return String(xml[valueRange])
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
