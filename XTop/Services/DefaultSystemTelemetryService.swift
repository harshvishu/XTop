import Darwin
import Foundation

actor DefaultSystemTelemetryService: SystemTelemetryService {
    private let runner: CommandRunner
    private let advancedSensorClient: AdvancedSensorClient
    private let advancedSampleTimeout: Duration
    private var priorProcessorTicks: [ProcessorTicks] = []
    private var advancedSensorsEnabled: Bool = true

    init(
        runner: CommandRunner = CommandRunner(),
        advancedSensorClient: AdvancedSensorClient = UnavailableAdvancedSensorClient(),
        advancedSampleTimeout: Duration = .milliseconds(750)
    ) {
        self.runner = runner
        self.advancedSensorClient = advancedSensorClient
        self.advancedSampleTimeout = advancedSampleTimeout
    }

    func setAdvancedSensorsEnabled(_ enabled: Bool) async {
        advancedSensorsEnabled = enabled
    }

    func collectBaseSnapshot(
        previous: SystemTelemetrySnapshot?
    ) async -> SystemTelemetrySnapshot {
        let processorUsage = processorUsage()
        let cpu = processorUsage.overall
        let memory = await memoryMetric()
        let storage = storageMetric()
        let processes = await developerProcesses()
        let advanced = await collectAdvancedMetrics()
        let severity = calculateSeverity(cpu: cpu.value, memory: memory.value)

        return SystemTelemetrySnapshot(
            cpuPercent: cpu,
            perCoreCpuPercent: processorUsage.perCore,
            memoryUsedPercent: memory,
            gpuPercent: advanced.gpu,
            temperatureC: advanced.temp,
            fanRPM: advanced.fan,
            diskCacheMB: advanced.diskCache,
            storageUsedPercent: storage,
            developerToolUsage: processes,
            lastUpdated: .now,
            severity: severity,
            sampleDelayed: false
        )
    }

    func collectAdvancedMetrics() async -> (
        gpu: MetricValue,
        temp: MetricValue,
        fan: MetricValue,
        diskCache: MetricValue
    ) {
        // Disk cache is derived from vm_stat — independent of the helper.
        let vmStat = await runner.run(
            command: "vm_stat",
            arguments: [],
            workingDirectory: "/"
        )
        let diskCache = parseDiskCacheFromVMStat(vmStat.stdout)

        // Advanced sensors require the privileged helper. Failure here must
        // never block baseline telemetry — we always produce a complete
        // (gpu, temp, fan) triple of MetricValues.
        let advancedTriple = await sampleAdvancedTriple()

        return (advancedTriple.gpu, advancedTriple.temp, advancedTriple.fan, diskCache)
    }

    private func sampleAdvancedTriple() async -> (gpu: MetricValue, temp: MetricValue, fan: MetricValue) {
        guard advancedSensorsEnabled else {
            return makeUnavailableTriple(
                reason: "Advanced sensors are disabled in settings."
            )
        }

        let sample: AdvancedSensorSample
        do {
            sample = try await withAdvancedSensorTimeout {
                try await self.advancedSensorClient.sampleAdvancedMetrics()
            }
        } catch let error as AdvancedSensorClientError {
            return makeUnavailableTriple(reason: error.reason)
        } catch is CancellationError {
            return makeUnavailableTriple(reason: "Advanced sensor sample was cancelled.")
        } catch {
            return makeUnavailableTriple(
                reason: "Advanced sensor sample failed: \(error.localizedDescription)"
            )
        }

        return (
            gpu: metricValue(
                label: "GPU",
                unit: "%",
                value: sample.gpuPercent,
                metric: .gpu,
                reasons: sample.unavailableReasons
            ),
            temp: metricValue(
                label: "Temperature",
                unit: "C",
                value: sample.temperatureC,
                metric: .temperature,
                reasons: sample.unavailableReasons
            ),
            fan: metricValue(
                label: "Fan",
                unit: "RPM",
                value: sample.fanRPM,
                metric: .fan,
                reasons: sample.unavailableReasons
            )
        )
    }

    private func metricValue(
        label: String,
        unit: String,
        value: Double?,
        metric: AdvancedSensorMetric,
        reasons: [String: String]
    ) -> MetricValue {
        if let value {
            return MetricValue(
                label: label,
                value: value,
                unit: unit,
                isAvailable: true,
                unavailableReason: nil
            )
        }
        let reason = reasons[metric.rawValue]
            ?? "Helper did not return a value for \(label)."
        return MetricValue.unavailable(label: label, unit: unit, reason: reason)
    }

    private func makeUnavailableTriple(reason: String) -> (gpu: MetricValue, temp: MetricValue, fan: MetricValue) {
        (
            gpu: MetricValue.unavailable(label: "GPU", unit: "%", reason: reason),
            temp: MetricValue.unavailable(label: "Temperature", unit: "C", reason: reason),
            fan: MetricValue.unavailable(label: "Fan", unit: "RPM", reason: reason)
        )
    }

    private func withAdvancedSensorTimeout<T: Sendable>(
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let timeout = advancedSampleTimeout
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw AdvancedSensorClientError.timedOut(
                    reason: "Helper did not respond within the sampling budget."
                )
            }
            guard let result = try await group.next() else {
                throw AdvancedSensorClientError.communicationFailed(
                    reason: "Helper task ended without a result."
                )
            }
            group.cancelAll()
            return result
        }
    }

    private func processorUsage() -> (overall: MetricValue, perCore: [Double]) {
        var cpuInfo: processor_info_array_t?
        var cpuInfoCount = mach_msg_type_number_t(0)
        var processorCount = natural_t(0)

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &processorCount,
            &cpuInfo,
            &cpuInfoCount
        )

        guard result == KERN_SUCCESS, let cpuInfo else {
            let overall = MetricValue.unavailable(
                label: "CPU",
                unit: "%",
                reason: "Unable to query processor usage"
            )
            return (overall, [])
        }

        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(bitPattern: cpuInfo),
                vm_size_t(cpuInfoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            )
        }

        let values = UnsafeBufferPointer(start: cpuInfo, count: Int(cpuInfoCount))
        let ticks = (0..<Int(processorCount)).map { index in
            let offset = index * Int(CPU_STATE_MAX)
            return ProcessorTicks(
                user: UInt64(values[offset + Int(CPU_STATE_USER)]),
                system: UInt64(values[offset + Int(CPU_STATE_SYSTEM)]),
                idle: UInt64(values[offset + Int(CPU_STATE_IDLE)]),
                nice: UInt64(values[offset + Int(CPU_STATE_NICE)])
            )
        }

        let perCore = ticks.enumerated().map { index, current in
            if priorProcessorTicks.indices.contains(index) {
                return current.usagePercent(since: priorProcessorTicks[index])
            }
            return current.usagePercentSinceBoot()
        }
        priorProcessorTicks = ticks

        guard !perCore.isEmpty else {
            let overall = MetricValue.unavailable(
                label: "CPU",
                unit: "%",
                reason: "Unable to compute processor usage"
            )
            return (overall, [])
        }

        let average = perCore.reduce(0, +) / Double(perCore.count)
        return (
            MetricValue(
                label: "CPU",
                value: average,
                unit: "%",
                isAvailable: true,
                unavailableReason: nil
            ),
            perCore
        )
    }

    private func memoryMetric() async -> MetricValue {
        let result = await runner.run(
            command: "sh",
            arguments: ["-c", "vm_stat"],
            workingDirectory: "/"
        )
        guard result.exitStatus == 0 else {
            return MetricValue.unavailable(label: "Memory", unit: "%", reason: "Unable to query vm_stat")
        }

        let stats = parseVMStats(vmStatOutput: result.stdout)
        let active = (stats["Pages active"] ?? 0)
            + (stats["Pages wired down"] ?? 0)
            + (stats["Pages occupied by compressor"] ?? 0)
        let free = (stats["Pages free"] ?? 0)
            + (stats["Pages speculative"] ?? 0)
        let total = active + free

        guard total > 0 else {
            return MetricValue.unavailable(label: "Memory", unit: "%", reason: "Unable to compute total pages")
        }

        let usedPercent = (Double(active) / Double(total)) * 100.0
        return MetricValue(
            label: "Memory",
            value: usedPercent,
            unit: "%",
            isAvailable: true,
            unavailableReason: nil
        )
    }

    private func storageMetric() -> MetricValue {
        do {
            let attrs = try FileManager.default.attributesOfFileSystem(forPath: "/")
            guard
                let total = attrs[.systemSize] as? NSNumber,
                let free = attrs[.systemFreeSize] as? NSNumber
            else {
                return MetricValue.unavailable(label: "Storage", unit: "%", reason: "Unable to read storage stats")
            }

            let used = Double(total.uint64Value - free.uint64Value)
            let usedPercent = (used / Double(total.uint64Value)) * 100.0
            return MetricValue(
                label: "Storage",
                value: usedPercent,
                unit: "%",
                isAvailable: true,
                unavailableReason: nil
            )
        } catch {
            return MetricValue.unavailable(label: "Storage", unit: "%", reason: error.localizedDescription)
        }
    }

    private func developerProcesses() async -> [ProcessUsage] {
        let result = await runner.run(
            command: "sh",
            arguments: ["-c", "ps -axo comm,%cpu,rss | grep -E '(Xcode|Simulator|sourcekit|swift-frontend|swiftc|clang|git|pod)' || true"],
            workingDirectory: "/"
        )

        guard result.exitStatus == 0 || !result.stdout.isEmpty else {
            return []
        }

        return result.stdout
            .split(separator: "\n")
            .compactMap { line in
                let comps = line
                    .split { $0 == " " || $0 == "\t" }
                    .map(String.init)
                guard comps.count >= 3 else { return nil }
                let command = comps[0]
                let cpu = Double(comps[1]) ?? 0
                let rssKB = Double(comps[2]) ?? 0
                return ProcessUsage(
                    name: command,
                    cpuPercent: cpu,
                    memoryMB: rssKB / 1024.0
                )
            }
            .sorted { $0.cpuPercent > $1.cpuPercent }
            .prefix(8)
            .map { $0 }
    }

    private func parsePageSize(vmStatOutput: String) -> Double {
        guard let range = vmStatOutput.range(of: "page size of ") else { return 4096 }
        let tail = vmStatOutput[range.upperBound...]
        let page = tail.split(whereSeparator: { !$0.isNumber }).first
        return Double(page ?? "4096") ?? 4096
    }

    private func parseVMStats(vmStatOutput: String) -> [String: UInt64] {
        var values: [String: UInt64] = [:]
        for line in vmStatOutput.split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = String(parts[0])
            let digits = parts[1].filter { $0.isNumber }
            values[key] = UInt64(digits) ?? 0
        }
        return values
    }

    private func parseDiskCacheFromVMStat(_ output: String) -> MetricValue {
        let stats = parseVMStats(vmStatOutput: output)
        let pageSize = parsePageSize(vmStatOutput: output)
        let fileBackedPages = stats["File-backed pages"] ?? 0
        let mb = (Double(fileBackedPages) * pageSize) / (1024 * 1024)
        return MetricValue(
            label: "Disk Cache",
            value: mb,
            unit: "MB",
            isAvailable: true,
            unavailableReason: nil
        )
    }

    private func calculateSeverity(cpu: Double?, memory: Double?) -> SeverityLevel {
        guard let cpu, let memory else { return .unknown }
        if cpu > 85 || memory > 85 {
            return .critical
        }
        if cpu > 65 || memory > 70 {
            return .warning
        }
        return .healthy
    }
}

private struct ProcessorTicks {
    let user: UInt64
    let system: UInt64
    let idle: UInt64
    let nice: UInt64

    private nonisolated func busyValue() -> UInt64 {
        user + system + nice
    }

    private nonisolated func totalValue() -> UInt64 {
        busyValue() + idle
    }

    nonisolated func usagePercentSinceBoot() -> Double {
        percent(busy: busyValue(), total: totalValue())
    }

    nonisolated func usagePercent(since previous: ProcessorTicks) -> Double {
        let busy = busyValue()
        let previousBusy = previous.busyValue()
        let total = totalValue()
        let previousTotal = previous.totalValue()
        let busyDelta = busy >= previousBusy ? busy - previousBusy : busy
        let totalDelta = total >= previousTotal ? total - previousTotal : total
        return percent(busy: busyDelta, total: totalDelta)
    }

    private nonisolated func percent(busy: UInt64, total: UInt64) -> Double {
        guard total > 0 else { return 0 }
        return min(100, max(0, (Double(busy) / Double(total)) * 100.0))
    }
}
