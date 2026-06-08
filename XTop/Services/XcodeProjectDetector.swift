import Foundation

actor XcodeProjectDetector: XcodeProjectDetecting {
    private let fileManager: FileManager

    nonisolated init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func detectProjectType(at repositoryPath: String) async -> (type: XcodeProjectType, projectFilePath: String)? {
        let rootURL = URL(filePath: repositoryPath)
            .standardized
            .resolvingSymlinksInPath()

        let xcodeproj = findPackagePath(in: rootURL, suffix: ".xcodeproj")
        if let xcodeproj {
            return (.xcodeproj, xcodeproj)
        }

        let workspace = findPackagePath(in: rootURL, suffix: ".xcworkspace")
        if let workspace {
            return (.xcworkspace, workspace)
        }

        let packagePath = rootURL.appending(path: "Package.swift").path()
        if fileManager.fileExists(atPath: packagePath) {
            return (.swiftPackage, packagePath)
        }

        return nil
    }

    private func findPackagePath(in rootURL: URL, suffix: String) -> String? {
        guard let names = try? fileManager.contentsOfDirectory(atPath: rootURL.path()) else {
            return nil
        }

        let matched = names
            .filter { $0.hasSuffix(suffix) }
            .sorted { lhs, rhs in
                lhs.localizedStandardCompare(rhs) == .orderedAscending
            }
            .first

        guard let matched else {
            return nil
        }

        return rootURL.appending(path: matched).path()
    }
}
