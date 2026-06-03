import Foundation

/// Lists installed apps for a given simulator and resolves their container paths.
actor InstalledAppCatalog {
    private let simctl: SimctlClient

    init(simctl: SimctlClient) {
        self.simctl = simctl
    }

    /// Returns the user-installed third-party apps for the given simulator,
    /// sorted by display name. System apps (`ApplicationType == "System"`) are
    /// excluded.
    func installedApps(for udid: String) async -> [InstalledApp] {
        let payload: [String: SimctlClient.InstalledAppsPayload.AppInfo]
        do {
            payload = try await simctl.installedApps(udid: udid)
        } catch {
            return []
        }

        var apps: [InstalledApp] = []
        for (_, info) in payload {
            guard let bundleID = info.CFBundleIdentifier, !bundleID.isEmpty else { continue }
            let type = info.ApplicationType?.lowercased() ?? "user"
            guard type != "system" else { continue }
            let bundlePath = info.Bundle ?? info.Path ?? ""
            guard !bundlePath.isEmpty else { continue }

            let dataPath = await simctl.appContainerPath(
                udid: udid,
                bundleIdentifier: bundleID,
                kind: .data
            )
            let groups = await simctl.appGroupContainerPaths(
                udid: udid,
                bundleIdentifier: bundleID
            )

            apps.append(
                InstalledApp(
                    bundleIdentifier: bundleID,
                    displayName: info.CFBundleDisplayName
                        ?? info.CFBundleName
                        ?? bundleID,
                    bundlePath: bundlePath,
                    dataContainerPath: dataPath,
                    appGroupContainerPaths: groups
                )
            )
        }

        return apps.sorted { lhs, rhs in
            lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
        }
    }
}
