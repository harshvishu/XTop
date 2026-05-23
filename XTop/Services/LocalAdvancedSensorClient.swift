import Foundation

// MARK: - LocalAdvancedSensorClient

/// In-process implementation of ``AdvancedSensorClient``.
///
/// Sensor sourcing on Apple Silicon (macOS 13+):
/// - GPU utilization: IOKit `IOAccelerator.PerformanceStatistics` via
///   ``GPUStatsReader``.
/// - Temperature: private `IOHIDEventSystemClient` thermal sensors via
///   ``IOHIDSensorReader``. The public `AppleSMC` user-client interface
///   no longer exposes key reads to unprivileged user processes on Apple
///   Silicon (every `kSMCReadKey` call returns `kIOReturnNotPrivileged`).
/// - Fans: same IOHID source; Macs without fan hardware (MacBook Air,
///   Mac mini M-series) report fan as unavailable with a "no fan hardware"
///   reason, which is the correct state, not a malfunction.
///
/// The "install/approve" parts of the protocol are no-ops that report
/// success immediately: there is nothing to install for an in-process
/// reader. `performAccessTest` and `sampleAdvancedMetrics` are the only
/// methods that touch hardware.
final class LocalAdvancedSensorClient: AdvancedSensorClient, @unchecked Sendable {

    private let hid: IOHIDSensorReader
    private let gpu: GPUStatsReader

    init(
        hid: IOHIDSensorReader = IOHIDSensorReader(),
        gpu: GPUStatsReader = GPUStatsReader()
    ) {
        self.hid = hid
        self.gpu = gpu
    }

    // MARK: AdvancedSensorClient

    func fetchStatus() async -> AdvancedSensorHelperStatus {
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
        let status = await fetchStatus()
        switch status.installation {
        case .ready:
            return .ready(message: "Advanced sensors are available on this Mac.")
        case .unsupported:
            return .unsupported(message: "This Mac does not expose the advanced sensors XTop reads.")
        case .notInstalled, .awaitingApproval:
            return .failed(message: "Unexpected reader state.")
        }
    }

    func removeConfiguration() async {
        // Nothing persisted, nothing to remove.
    }

    func sampleAdvancedMetrics() async throws -> AdvancedSensorSample {
        let result = collectSample()

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
        let tempOK = ((try? hid.readAverageDieTemperature()) ?? nil) != nil
        let fanOK = hid.hostHasFanHardware()
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

        // Temperature
        do {
            if let temp = try hid.readAverageDieTemperature() {
                temperatureC = temp
            } else {
                reasons[AdvancedSensorMetric.temperature.rawValue] =
                    "No temperature sensor returned a usable reading."
            }
        } catch IOHIDSensorReaderError.clientUnavailable {
            reasons[AdvancedSensorMetric.temperature.rawValue] =
                "Thermal sensor SPI is unavailable on this host."
        } catch {
            reasons[AdvancedSensorMetric.temperature.rawValue] =
                "Temperature read failed: \(error)."
        }

        // Fan
        do {
            if let fan = try hid.readAverageFanRPM() {
                fanRPM = fan
            } else {
                reasons[AdvancedSensorMetric.fan.rawValue] =
                    "No fan hardware detected on this Mac."
            }
        } catch IOHIDSensorReaderError.clientUnavailable {
            reasons[AdvancedSensorMetric.fan.rawValue] =
                "Thermal sensor SPI is unavailable on this host."
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
