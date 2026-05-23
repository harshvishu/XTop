import Foundation
import Observation

@MainActor
@Observable
final class SensorSettingsModel {

    // MARK: - Persisted user preference

    /// User's stated intent: do they want advanced sensors active at all?
    /// This is the only piece of sensor settings state that persists across
    /// launches. Everything else is observed from the helper at runtime.
    private(set) var isEnabled: Bool

    // MARK: - Observed runtime state

    /// Most recent helper status snapshot from `client.fetchStatus()`.
    private(set) var helperStatus: AdvancedSensorHelperStatus

    /// Most recent end-to-end access test result.
    private(set) var lastAccessTestResult: AdvancedSensorAccessTestResult

    /// Most recent outcome of a setup attempt, surfaced to settings.
    private(set) var lastSetupOutcome: AdvancedSensorSetupOutcome?

    /// True while an async action (status fetch, setup, test) is in flight.
    private(set) var isPerformingAction: Bool = false

    // MARK: - Dependencies

    @ObservationIgnored
    private let defaults: UserDefaults

    @ObservationIgnored
    private let client: AdvancedSensorClient

    @ObservationIgnored
    private let telemetryService: SystemTelemetryService?

    // MARK: - Init

    init(
        client: AdvancedSensorClient = UnavailableAdvancedSensorClient(),
        telemetryService: SystemTelemetryService? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.client = client
        self.telemetryService = telemetryService
        self.defaults = defaults

        if defaults.object(forKey: Keys.isEnabled) != nil {
            self.isEnabled = defaults.bool(forKey: Keys.isEnabled)
        } else {
            self.isEnabled = true
        }

        self.helperStatus = .unavailable
        self.lastAccessTestResult = .neverRun
        self.lastSetupOutcome = nil

        // Probe real helper state immediately, and propagate the user's
        // enabled preference to the telemetry service.
        Task { [weak self] in
            guard let self else { return }
            await self.propagateEnabledPreference()
            await self.refreshStatus()
        }
    }

    // MARK: - Derived state

    /// Resolved sensor setup state from real observed inputs + user preference.
    var setupState: AdvancedSensorSetupState {
        AdvancedSensorSetupState.resolve(
            isEnabled: isEnabled,
            helperStatus: helperStatus,
            accessTestFailed: lastAccessTestResult.performedAt != .distantPast
                && !lastAccessTestResult.succeeded
        )
    }

    var capabilities: [AdvancedSensorCapability] {
        AdvancedSensorMetric.allCases.map { metric in
            AdvancedSensorCapability(
                metric: metric,
                state: setupState
            )
        }
    }

    /// Single sentence describing the most recent diagnostics outcome.
    /// Used directly by ``SettingsRootView`` — no string formatting needed.
    var lastAccessTestSummary: String {
        lastAccessTestResult.summary
    }

    // MARK: - Real actions (replace the old placeholder toggles)

    /// Refresh the observed helper status. Safe to call repeatedly.
    func refreshStatus() async {
        helperStatus = await client.fetchStatus()
    }

    /// Attempt a real setup of the privileged helper.
    /// Equivalent of the old "Start Setup" / "Record Helper" / "Record
    /// Approval" buttons collapsed into one honest action.
    func startSetup() async {
        await performing {
            self.lastSetupOutcome = await self.client.startSetup()
            await self.refreshStatus()
        }
    }

    /// Run an end-to-end access test and record the result.
    func testAccess() async {
        await performing {
            self.lastAccessTestResult = await self.client.performAccessTest()
            await self.refreshStatus()
        }
    }

    /// Disable advanced sensors without removing the helper.
    /// Updates the persisted user preference and propagates to telemetry.
    func disable() async {
        isEnabled = false
        persistEnabledPreference()
        await propagateEnabledPreference()
        lastAccessTestResult = AdvancedSensorAccessTestResult(
            succeeded: false,
            summary: "Advanced sensors disabled. Baseline telemetry remains active.",
            performedAt: .now
        )
    }

    /// Re-enable advanced sensors after a previous disable.
    func enable() async {
        isEnabled = true
        persistEnabledPreference()
        await propagateEnabledPreference()
        await refreshStatus()
    }

    /// Drop the local helper configuration.
    func removeConfiguration() async {
        await performing {
            await self.client.removeConfiguration()
            self.lastAccessTestResult = AdvancedSensorAccessTestResult(
                succeeded: false,
                summary: "Sensor helper configuration removed.",
                performedAt: .now
            )
            self.lastSetupOutcome = nil
            await self.refreshStatus()
        }
    }

    // MARK: - Private helpers

    private func performing(_ work: @MainActor () async -> Void) async {
        isPerformingAction = true
        await work()
        isPerformingAction = false
    }

    private func propagateEnabledPreference() async {
        await telemetryService?.setAdvancedSensorsEnabled(isEnabled)
    }

    private func persistEnabledPreference() {
        defaults.set(isEnabled, forKey: Keys.isEnabled)
    }

    private enum Keys {
        static let isEnabled = "sensor.isEnabled"
    }
}
