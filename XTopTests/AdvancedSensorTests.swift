import Foundation
import Testing
@testable import XTop

// MARK: - Test fixtures

private struct StubAdvancedSensorClient: AdvancedSensorClient {
    let status: AdvancedSensorHelperStatus
    let sample: Result<AdvancedSensorSample, AdvancedSensorClientError>
    let setupOutcome: AdvancedSensorSetupOutcome
    let accessTest: AdvancedSensorAccessTestResult
    let sampleDelay: Duration

    init(
        status: AdvancedSensorHelperStatus = .unavailable,
        sample: Result<AdvancedSensorSample, AdvancedSensorClientError> =
            .failure(.notInstalled(reason: "stub: no helper")),
        setupOutcome: AdvancedSensorSetupOutcome =
            .unsupported(message: "stub"),
        accessTest: AdvancedSensorAccessTestResult = .neverRun,
        sampleDelay: Duration = .zero
    ) {
        self.status = status
        self.sample = sample
        self.setupOutcome = setupOutcome
        self.accessTest = accessTest
        self.sampleDelay = sampleDelay
    }

    func fetchStatus() async -> AdvancedSensorHelperStatus { status }
    func startSetup() async -> AdvancedSensorSetupOutcome { setupOutcome }
    func removeConfiguration() async {}
    func performAccessTest() async -> AdvancedSensorAccessTestResult { accessTest }

    func sampleAdvancedMetrics() async throws -> AdvancedSensorSample {
        if sampleDelay > .zero {
            try await Task.sleep(for: sampleDelay)
        }
        switch sample {
        case .success(let value): return value
        case .failure(let error): throw error
        }
    }
}

private func readyStatus(
    gpu: Bool = true,
    temp: Bool = true,
    fan: Bool = true
) -> AdvancedSensorHelperStatus {
    AdvancedSensorHelperStatus(
        installation: .ready,
        connectivity: .connected,
        supportsGPU: gpu,
        supportsTemperature: temp,
        supportsFan: fan
    )
}

// MARK: - Task 5.1: setup state resolution

struct AdvancedSensorSetupStateResolutionTests {

    @Test func resolvesUnsupportedWhenInstallationUnsupported() {
        let state = AdvancedSensorSetupState.resolve(
            isEnabled: true,
            helperStatus: .unsupportedHost,
            accessTestFailed: false
        )
        #expect(state == .unsupported)
    }

    @Test func resolvesDisabledWhenUserDisabledIt() {
        let state = AdvancedSensorSetupState.resolve(
            isEnabled: false,
            helperStatus: readyStatus(),
            accessTestFailed: false
        )
        #expect(state == .disabled)
    }

    @Test func resolvesNotInstalledFromObservedStatus() {
        let state = AdvancedSensorSetupState.resolve(
            isEnabled: true,
            helperStatus: .unavailable,
            accessTestFailed: false
        )
        #expect(state == .notInstalled)
    }

    @Test func resolvesApprovalRequiredFromObservedStatus() {
        let status = AdvancedSensorHelperStatus(
            installation: .awaitingApproval,
            connectivity: .unknown,
            supportsGPU: true, supportsTemperature: true, supportsFan: true
        )
        let state = AdvancedSensorSetupState.resolve(
            isEnabled: true,
            helperStatus: status,
            accessTestFailed: false
        )
        #expect(state == .approvalRequired)
    }

    @Test func resolvesConnectedWhenReadyAndNoFailures() {
        let state = AdvancedSensorSetupState.resolve(
            isEnabled: true,
            helperStatus: readyStatus(),
            accessTestFailed: false
        )
        #expect(state == .connected)
    }

    @Test func resolvesFailedWhenAccessTestFailed() {
        let state = AdvancedSensorSetupState.resolve(
            isEnabled: true,
            helperStatus: readyStatus(),
            accessTestFailed: true
        )
        #expect(state == .failed)
    }

    @Test func resolvesFailedWhenConnectivityFailed() {
        let status = AdvancedSensorHelperStatus(
            installation: .ready,
            connectivity: .failed(reason: "no response"),
            supportsGPU: true, supportsTemperature: true, supportsFan: true
        )
        let state = AdvancedSensorSetupState.resolve(
            isEnabled: true,
            helperStatus: status,
            accessTestFailed: false
        )
        #expect(state == .failed)
    }

    @Test func resolvesUnsupportedWhenReadyButNoMetricsExposed() {
        let state = AdvancedSensorSetupState.resolve(
            isEnabled: true,
            helperStatus: readyStatus(gpu: false, temp: false, fan: false),
            accessTestFailed: false
        )
        #expect(state == .unsupported)
    }
}

// MARK: - Task 5.2 + 5.3: telemetry service behavior

struct DefaultSystemTelemetryServiceAdvancedSensorTests {

    @Test func connectedHelperReturnsAvailableMetrics() async {
        let client = StubAdvancedSensorClient(
            status: readyStatus(),
            sample: .success(AdvancedSensorSample(
                gpuPercent: 42,
                temperatureC: 55.3,
                fanRPM: 1800,
                unavailableReasons: [:]
            ))
        )
        let service = DefaultSystemTelemetryService(advancedSensorClient: client)
        let metrics = await service.collectAdvancedMetrics()

        #expect(metrics.gpu.isAvailable)
        #expect(metrics.gpu.value == 42)
        #expect(metrics.temp.isAvailable)
        #expect(metrics.temp.value == 55.3)
        #expect(metrics.fan.isAvailable)
        #expect(metrics.fan.value == 1800)
    }

    @Test func partialHelperSampleMarksMissingMetricsUnavailable() async {
        let client = StubAdvancedSensorClient(
            status: readyStatus(gpu: false),
            sample: .success(AdvancedSensorSample(
                gpuPercent: nil,
                temperatureC: 60,
                fanRPM: 2000,
                unavailableReasons: [
                    AdvancedSensorMetric.gpu.rawValue: "GPU sensor unavailable on this Mac."
                ]
            ))
        )
        let service = DefaultSystemTelemetryService(advancedSensorClient: client)
        let metrics = await service.collectAdvancedMetrics()

        #expect(!metrics.gpu.isAvailable)
        #expect(metrics.gpu.unavailableReason == "GPU sensor unavailable on this Mac.")
        #expect(metrics.temp.isAvailable && metrics.temp.value == 60)
        #expect(metrics.fan.isAvailable && metrics.fan.value == 2000)
    }

    @Test func helperFailureMarksAllAdvancedMetricsUnavailable() async {
        let client = StubAdvancedSensorClient(
            sample: .failure(.communicationFailed(reason: "XPC down"))
        )
        let service = DefaultSystemTelemetryService(advancedSensorClient: client)
        let metrics = await service.collectAdvancedMetrics()

        #expect(!metrics.gpu.isAvailable)
        #expect(!metrics.temp.isAvailable)
        #expect(!metrics.fan.isAvailable)
        #expect(metrics.gpu.unavailableReason?.contains("XPC down") == true)
    }

    @Test func disabledAdvancedSensorsReturnDisabledReason() async {
        let client = StubAdvancedSensorClient(
            sample: .success(AdvancedSensorSample(
                gpuPercent: 50, temperatureC: 50, fanRPM: 1000,
                unavailableReasons: [:]
            ))
        )
        let service = DefaultSystemTelemetryService(advancedSensorClient: client)
        await service.setAdvancedSensorsEnabled(false)
        let metrics = await service.collectAdvancedMetrics()

        #expect(!metrics.gpu.isAvailable)
        #expect(!metrics.temp.isAvailable)
        #expect(!metrics.fan.isAvailable)
        let reason = metrics.gpu.unavailableReason ?? ""
        #expect(reason.contains("disabled"))
    }

    @Test func slowHelperTimesOutWithoutBlockingTelemetry() async {
        let client = StubAdvancedSensorClient(
            sample: .success(AdvancedSensorSample(
                gpuPercent: 1, temperatureC: 1, fanRPM: 1,
                unavailableReasons: [:]
            )),
            sampleDelay: .seconds(5)
        )
        let service = DefaultSystemTelemetryService(
            advancedSensorClient: client,
            advancedSampleTimeout: .milliseconds(50)
        )
        let metrics = await service.collectAdvancedMetrics()

        #expect(!metrics.gpu.isAvailable)
        let reason = metrics.gpu.unavailableReason ?? ""
        #expect(reason.contains("did not respond") || reason.contains("sampling budget"))
    }

    // Task 5.3: baseline telemetry survives even when advanced sensors fail.
    @Test func baselineTelemetryAvailableWhenAdvancedSensorsFail() async {
        let client = StubAdvancedSensorClient(
            sample: .failure(.notInstalled(reason: "no helper"))
        )
        let service = DefaultSystemTelemetryService(advancedSensorClient: client)
        let snapshot = await service.collectBaseSnapshot(previous: nil)

        // CPU and memory must be sampled regardless. We can't guarantee a
        // specific value (depends on the test host), but they must not carry
        // the advanced-sensor failure reason.
        #expect(snapshot.cpuPercent.label == "CPU")
        #expect(snapshot.memoryUsedPercent.label == "Memory")
        #expect(snapshot.storageUsedPercent.label == "Storage")

        // Advanced metrics are unavailable, baseline metrics are independent.
        #expect(!snapshot.gpuPercent.isAvailable)
        #expect(!snapshot.temperatureC.isAvailable)
        #expect(!snapshot.fanRPM.isAvailable)
    }
}

// MARK: - Task 5.4: settings diagnostics + access test

@MainActor
struct SensorSettingsModelDiagnosticsTests {

    @Test func startSetupRecordsOutcomeAndRefreshesStatus() async {
        let client = StubAdvancedSensorClient(
            status: AdvancedSensorHelperStatus(
                installation: .awaitingApproval,
                connectivity: .unknown,
                supportsGPU: true, supportsTemperature: true, supportsFan: true
            ),
            setupOutcome: .awaitingApproval(message: "Please approve in System Settings.")
        )
        let model = SensorSettingsModel(
            client: client,
            defaults: makeIsolatedDefaults()
        )
        await model.startSetup()

        #expect(model.lastSetupOutcome?.message.contains("approve") == true)
        #expect(model.setupState == .approvalRequired)
    }

    @Test func testAccessRecordsSuccessSummary() async {
        let success = AdvancedSensorAccessTestResult(
            succeeded: true,
            summary: "Sensor access test passed.",
            performedAt: .now
        )
        let client = StubAdvancedSensorClient(
            status: readyStatus(),
            accessTest: success
        )
        let model = SensorSettingsModel(
            client: client,
            defaults: makeIsolatedDefaults()
        )
        await model.testAccess()

        #expect(model.lastAccessTestSummary == "Sensor access test passed.")
        #expect(model.setupState == .connected)
    }

    @Test func testAccessFailurePropagatesToSetupState() async {
        let failure = AdvancedSensorAccessTestResult(
            succeeded: false,
            summary: "Helper unreachable.",
            performedAt: .now
        )
        let client = StubAdvancedSensorClient(
            status: readyStatus(),
            accessTest: failure
        )
        let model = SensorSettingsModel(
            client: client,
            defaults: makeIsolatedDefaults()
        )
        await model.testAccess()

        #expect(model.lastAccessTestSummary == "Helper unreachable.")
        #expect(model.setupState == .failed)
    }

    @Test func disableUpdatesPreferenceAndSummary() async {
        let client = StubAdvancedSensorClient(status: readyStatus())
        let model = SensorSettingsModel(
            client: client,
            defaults: makeIsolatedDefaults()
        )
        await model.disable()

        #expect(model.isEnabled == false)
        #expect(model.setupState == .disabled)
        #expect(model.lastAccessTestSummary.contains("disabled"))
    }

    // Helpers

    private func makeIsolatedDefaults() -> UserDefaults {
        let suite = "xtop.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
