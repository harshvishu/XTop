import Foundation

/// Default ``AdvancedSensorClient`` for builds without a privileged helper.
///
/// This honestly reports that no helper is installed. Every method returns
/// or throws the appropriate "unavailable" value — the rest of the app
/// can treat this identically to a missing/uninstalled helper and the
/// settings UI will guide the user accordingly.
///
/// When the real helper ships, swap this in `XTopAppServices` for the
/// helper-backed implementation; no other code needs to change.
struct UnavailableAdvancedSensorClient: AdvancedSensorClient {

    private let installation: AdvancedSensorHelperInstallation

    init(installation: AdvancedSensorHelperInstallation = .notInstalled) {
        self.installation = installation
    }

    func fetchStatus() async -> AdvancedSensorHelperStatus {
        AdvancedSensorHelperStatus(
            installation: installation,
            connectivity: .unknown,
            supportsGPU: false,
            supportsTemperature: false,
            supportsFan: false
        )
    }

    func startSetup() async -> AdvancedSensorSetupOutcome {
        .unsupported(
            message:
                "A signed privileged helper is not bundled with this build. Advanced sensors will remain unavailable."
        )
    }

    func removeConfiguration() async {
        // No-op: there is nothing installed to remove.
    }

    func sampleAdvancedMetrics() async throws -> AdvancedSensorSample {
        throw AdvancedSensorClientError.notInstalled(
            reason: "Advanced sensor helper is not installed."
        )
    }

    func performAccessTest() async -> AdvancedSensorAccessTestResult {
        AdvancedSensorAccessTestResult(
            succeeded: false,
            summary:
                "Sensor access test failed: helper is not installed on this host.",
            performedAt: .now
        )
    }
}
