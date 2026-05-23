import Foundation
import Observation

@MainActor
@Observable
final class SensorSettingsModel {
    private(set) var helperEnabled: Bool
    private(set) var helperInstalled: Bool
    private(set) var approvalGranted: Bool
    private(set) var accessTestFailed: Bool
    private(set) var lastAccessTestSummary: String

    @ObservationIgnored
    private let defaults: UserDefaults

    @ObservationIgnored
    private let hostSupported: Bool

    init(
        defaults: UserDefaults = .standard,
        hostSupported: Bool = true
    ) {
        self.defaults = defaults
        self.hostSupported = hostSupported

        self.helperEnabled =
            defaults.object(
                forKey: Keys.helperEnabled
            ) as? Bool ?? true

        self.helperInstalled =
            defaults.bool(
                forKey: Keys.helperInstalled
            )

        self.approvalGranted =
            defaults.bool(
                forKey: Keys.approvalGranted
            )

        self.accessTestFailed =
            defaults.bool(
                forKey: Keys.accessTestFailed
            )

        self.lastAccessTestSummary =
            defaults.string(
                forKey: Keys.lastAccessTestSummary
            ) ?? "No sensor access test has run."
    }

    var capabilities: [AdvancedSensorCapability] {
        AdvancedSensorMetric.allCases.map { metric in
            AdvancedSensorCapability(
                metric: metric,
                state: setupState
            )
        }
    }

    var setupState: AdvancedSensorSetupState {
        AdvancedSensorSetupState.resolve(
            isEnabled: helperEnabled,
            helperInstalled: helperInstalled,
            approvalGranted: approvalGranted,
            hostSupported: hostSupported,
            accessTestFailed: accessTestFailed
        )
    }

    func startSetup() {
        helperEnabled = true
        accessTestFailed = false
        lastAccessTestSummary =
            "Setup is ready for a supported helper installation."
        persist()
    }

    func recordHelperInstallation() {
        helperEnabled = true
        helperInstalled = true
        approvalGranted = false
        accessTestFailed = false
        lastAccessTestSummary =
            "Helper presence recorded. Approval is still required."
        persist()
    }

    func recordApproval() {
        helperEnabled = true
        helperInstalled = true
        approvalGranted = true
        accessTestFailed = false
        lastAccessTestSummary =
            "Helper approval recorded. Test access to verify metrics."
        persist()
    }

    func testAccess() {
        accessTestFailed = setupState != .connected
        lastAccessTestSummary =
            accessTestFailed
            ? "Sensor test failed because helper setup is incomplete."
            : "Sensor access test completed. Waiting for live helper metric feed."
        persist()
    }

    func disable() {
        helperEnabled = false
        accessTestFailed = false
        lastAccessTestSummary =
            "Advanced sensors disabled. Baseline telemetry remains active."
        persist()
    }

    func removeConfiguration() {
        helperEnabled = true
        helperInstalled = false
        approvalGranted = false
        accessTestFailed = false
        lastAccessTestSummary =
            "Sensor helper configuration removed."
        persist()
    }

    private func persist() {
        defaults.set(
            helperEnabled,
            forKey: Keys.helperEnabled
        )
        defaults.set(
            helperInstalled,
            forKey: Keys.helperInstalled
        )
        defaults.set(
            approvalGranted,
            forKey: Keys.approvalGranted
        )
        defaults.set(
            accessTestFailed,
            forKey: Keys.accessTestFailed
        )
        defaults.set(
            lastAccessTestSummary,
            forKey: Keys.lastAccessTestSummary
        )
    }

    private enum Keys {
        static let helperEnabled =
            "sensor.helperEnabled"
        static let helperInstalled =
            "sensor.helperInstalled"
        static let approvalGranted =
            "sensor.approvalGranted"
        static let accessTestFailed =
            "sensor.accessTestFailed"
        static let lastAccessTestSummary =
            "sensor.lastAccessTestSummary"
    }
}
