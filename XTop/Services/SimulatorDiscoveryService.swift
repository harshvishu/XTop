import Foundation

/// Lists booted iOS Simulators and their installed apps using `simctl`.
actor SimulatorDiscoveryService {
    private let simctl: SimctlClient

    init(simctl: SimctlClient) {
        self.simctl = simctl
    }

    /// Returns the currently booted iOS Simulators, sorted by name.
    func bootedSimulators() async throws -> [SimulatorDevice] {
        let payload = try await simctl.bootedDevices()
        var devices: [SimulatorDevice] = []
        for (runtimeIdentifier, runtimeDevices) in payload.devices {
            for raw in runtimeDevices where raw.state.caseInsensitiveCompare("booted") == .orderedSame {
                devices.append(
                    SimulatorDevice(
                        id: raw.udid,
                        name: raw.name,
                        runtimeIdentifier: runtimeIdentifier,
                        runtimeDisplayName: SimulatorDiscoveryService.displayName(
                            forRuntime: runtimeIdentifier
                        ),
                        deviceTypeIdentifier: raw.deviceTypeIdentifier
                    )
                )
            }
        }
        return devices.sorted { lhs, rhs in
            lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    /// Derives a human-readable label from a runtime identifier such as
    /// `com.apple.CoreSimulator.SimRuntime.iOS-26-0` → `iOS 26.0`.
    static func displayName(forRuntime identifier: String) -> String {
        guard let lastDot = identifier.lastIndex(of: ".") else { return identifier }
        let suffix = identifier[identifier.index(after: lastDot)...]
        let parts = suffix.split(separator: "-")
        guard let platform = parts.first else { return String(suffix) }
        let version = parts.dropFirst().joined(separator: ".")
        return version.isEmpty ? String(platform) : "\(platform) \(version)"
    }
}
