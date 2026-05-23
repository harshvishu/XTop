import Foundation

// MARK: - LocalAdvancedSensorClient

/// In-process implementation of ``AdvancedSensorClient``.
///
/// Uses ``SMCReader`` for temperature/fan and ``GPUStatsReader`` for GPU
/// utilization. No privileged helper, no XPC, no install step — all reads
/// happen inside the main app on macOS 13+.
///
/// The "install/approve" parts of the protocol are no-ops that report
/// success immediately: there is nothing to install for an in-process
/// reader. ``performAccessTest`` and ``sampleAdvancedMetrics`` are the
/// only methods that touch real hardware.
///
/// `final class` (rather than struct) because the SMC reader holds an
/// IOKit connection we want to share across calls without copying.
final class LocalAdvancedSensorClient: AdvancedSensorClient, @unchecked Sendable {

    private let smc: SMCReader
    private let gpu: GPUStatsReader

    /// Symbolic SMC key groups. CPU temperature uses the first probe that
    /// returns a value (Mac model differences); GPU temperature does the
    /// same; fans walk a small list of sensors.
    private static let cpuTemperatureKeys: [SMCKey] = [
        .cpuProximityTemp, .cpuDieTemp, .cpuPackageTemp
    ]
    private static let gpuTemperatureKeys: [SMCKey] = [
        .gpuProximityTemp, .gpuDieTemp
    ]
    private static let fanCurrentKeys: [SMCKey] = [.fan0Current, .fan1Current]

    init(
        smc: SMCReader = SMCReader(),
        gpu: GPUStatsReader = GPUStatsReader()
    ) {
        self.smc = smc
        self.gpu = gpu
    }

    // MARK: AdvancedSensorClient

    func fetchStatus() async -> AdvancedSensorHelperStatus {
        // Probe each source once to determine host support. We use a short
        // synchronous probe rather than a full sample because callers want
        // status quickly (settings UI refresh, app launch).
        let probe = probeCapabilities()

        guard probe.anySupported else {
            return AdvancedSensorHelperStatus(
                installation: .unsupported,
                connectivity: .failed(reason: "No advanced sensor sources available on this host."),
                supportsGPU: false,
                supportsTemperature: false,
                supportsFan: false
            )
        }

        return AdvancedSensorHelperStatus(
            installation: .ready,
            connectivity: .connected,
            supportsGPU: probe.gpu,
            supportsTemperature: probe.temperature,
            supportsFan: probe.fan
        )
    }

    func startSetup() async -> AdvancedSensorSetupOutcome {
        // In-process readers have nothing to install. Treat setup as a
        // capability probe and surface the result as the outcome.
        let status = await fetchStatus()
        switch status.installation {
        case .ready:
            return .ready(message: "Advanced sensors are available on this Mac.")
        case .unsupported:
            return .unsupported(message: "This Mac does not expose the advanced sensors XTop reads.")
        case .notInstalled, .awaitingApproval:
            // Not reachable for the local client, but keep the contract honest.
            return .failed(message: "Unexpected reader state.")
        }
    }

    func removeConfiguration() async {
        // Nothing persisted, nothing to remove.
    }

    func sampleAdvancedMetrics() async throws -> AdvancedSensorSample {
        let result = collectSample()

        // If literally every metric failed, throw — the telemetry service
        // turns this into a uniform unavailable sample. Partial samples
        // are returned as-is so per-metric reasons survive.
        if result.gpuPercent == nil,
           result.temperatureC == nil,
           result.fanRPM == nil {
            throw AdvancedSensorClientError.unsupported(
                reason: "No advanced sensors returned data on this host."
            )
        }
        return result
    }

    func performAccessTest() async -> AdvancedSensorAccessTestResult {
        let sample = collectSample()

        var parts: [String] = []
        if let gpu = sample.gpuPercent {
            parts.append("GPU \(formatPercent(gpu))")
        }
        if let temp = sample.temperatureC {
            parts.append("Temp \(formatTemp(temp))")
        }
        if let fan = sample.fanRPM {
            parts.append("Fan \(formatFan(fan))")
        }

        if parts.isEmpty {
            return AdvancedSensorAccessTestResult(
                succeeded: false,
                summary: "Access test failed: no advanced sensors returned data.",
                performedAt: .now
            )
        }
        return AdvancedSensorAccessTestResult(
            succeeded: true,
            summary: "Access test succeeded: \(parts.joined(separator: ", ")).",
            performedAt: .now
        )
    }

    // MARK: Sampling

    private struct CapabilityProbe {
        let gpu: Bool
        let temperature: Bool
        let fan: Bool
        var anySupported: Bool { gpu || temperature || fan }
    }

    private func probeCapabilities() -> CapabilityProbe {
        let gpuOK = (try? gpu.readUtilizationPercent()) != nil
        let tempOK = (try? smc.firstAvailable(of: Self.cpuTemperatureKeys)) != nil
        let fanOK = (try? smc.firstAvailable(of: Self.fanCurrentKeys)) != nil
        return CapabilityProbe(gpu: gpuOK, temperature: tempOK, fan: fanOK)
    }

    private func collectSample() -> AdvancedSensorSample {
        var gpuPercent: Double?
        var temperatureC: Double?
        var fanRPM: Double?
        var reasons: [String: String] = [:]

        // GPU
        do {
            gpuPercent = try gpu.readUtilizationPercent()
        } catch {
            reasons[AdvancedSensorMetric.gpu.rawValue] =
                "GPU performance statistics are not published on this host."
        }

        // Temperature: prefer CPU package, fall back to GPU temp if CPU is missing.
        do {
            if let cpuTemp = try smc.firstAvailable(of: Self.cpuTemperatureKeys) {
                temperatureC = cpuTemp
            } else if let gpuTemp = try smc.firstAvailable(of: Self.gpuTemperatureKeys) {
                temperatureC = gpuTemp
            } else {
                reasons[AdvancedSensorMetric.temperature.rawValue] =
                    "No temperature SMC key returned a reading."
            }
        } catch SMCReaderError.serviceUnavailable {
            reasons[AdvancedSensorMetric.temperature.rawValue] =
                "AppleSMC service is unavailable on this host."
        } catch {
            reasons[AdvancedSensorMetric.temperature.rawValue] =
                "Temperature read failed: \(error)."
        }

        // Fan
        do {
            if let fan = try smc.firstAvailable(of: Self.fanCurrentKeys) {
                fanRPM = fan
            } else {
                reasons[AdvancedSensorMetric.fan.rawValue] =
                    "No fan SMC key returned a reading."
            }
        } catch SMCReaderError.serviceUnavailable {
            reasons[AdvancedSensorMetric.fan.rawValue] =
                "AppleSMC service is unavailable on this host."
        } catch {
            reasons[AdvancedSensorMetric.fan.rawValue] =
                "Fan read failed: \(error)."
        }

        return AdvancedSensorSample(
            gpuPercent: gpuPercent,
            temperatureC: temperatureC,
            fanRPM: fanRPM,
            unavailableReasons: reasons
        )
    }

    // MARK: Formatting (diagnostics only)

    private func formatPercent(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0))) + "%"
    }

    private func formatTemp(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1))) + "°C"
    }

    private func formatFan(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0))) + " RPM"
    }
}
