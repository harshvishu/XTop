import Foundation

enum SeverityLevel: String, Codable, Sendable {
    case healthy
    case warning
    case critical
    case unknown
}

struct MetricValue: Codable, Sendable {
    let label: String
    let value: Double?
    let unit: String
    let isAvailable: Bool
    let unavailableReason: String?

    nonisolated static func unavailable(label: String, unit: String, reason: String) -> MetricValue {
        MetricValue(label: label, value: nil, unit: unit, isAvailable: false, unavailableReason: reason)
    }
}

struct ProcessUsage: Codable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let cpuPercent: Double
    let memoryMB: Double

    nonisolated init(id: UUID = UUID(), name: String, cpuPercent: Double, memoryMB: Double) {
        self.id = id
        self.name = name
        self.cpuPercent = cpuPercent
        self.memoryMB = memoryMB
    }
}

struct SystemTelemetrySnapshot: Codable, Sendable {
    let cpuPercent: MetricValue
    let perCoreCpuPercent: [Double]
    let memoryUsedPercent: MetricValue
    let gpuPercent: MetricValue
    let temperatureC: MetricValue
    let fanRPM: MetricValue
    let diskCacheMB: MetricValue
    let storageUsedPercent: MetricValue
    let developerToolUsage: [ProcessUsage]
    let lastUpdated: Date
    let severity: SeverityLevel
    let sampleDelayed: Bool

    static var empty: SystemTelemetrySnapshot {
        SystemTelemetrySnapshot(
            cpuPercent: .unavailable(label: "CPU", unit: "%", reason: "Telemetry has not been sampled yet."),
            perCoreCpuPercent: [],
            memoryUsedPercent: .unavailable(label: "Memory", unit: "%", reason: "Telemetry has not been sampled yet."),
            gpuPercent: .unavailable(label: "GPU", unit: "%", reason: "Telemetry has not been sampled yet."),
            temperatureC: .unavailable(label: "Temperature", unit: "C", reason: "Telemetry has not been sampled yet."),
            fanRPM: .unavailable(label: "Fan", unit: "RPM", reason: "Telemetry has not been sampled yet."),
            diskCacheMB: .unavailable(label: "Disk Cache", unit: "MB", reason: "Telemetry has not been sampled yet."),
            storageUsedPercent: .unavailable(label: "Storage", unit: "%", reason: "Telemetry has not been sampled yet."),
            developerToolUsage: [],
            lastUpdated: .distantPast,
            severity: .unknown,
            sampleDelayed: false
        )
    }
}

struct DerivedDataLocation: Codable, Identifiable, Sendable {
    let id: UUID
    let path: String
    let sizeBytes: UInt64

    nonisolated init(id: UUID = UUID(), path: String, sizeBytes: UInt64) {
        self.id = id
        self.path = path
        self.sizeBytes = sizeBytes
    }
}

struct XcodeProjectUsage: Codable, Identifiable, Sendable {
    let id: UUID
    let projectPath: String
    let sizeBytes: UInt64

    nonisolated init(id: UUID = UUID(), projectPath: String, sizeBytes: UInt64) {
        self.id = id
        self.projectPath = projectPath
        self.sizeBytes = sizeBytes
    }
}

struct ProvisioningProfileSummary: Codable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let teamIdentifier: String
    let expirationDate: String
    let path: String

    nonisolated init(id: UUID = UUID(), name: String, teamIdentifier: String, expirationDate: String, path: String) {
        self.id = id
        self.name = name
        self.teamIdentifier = teamIdentifier
        self.expirationDate = expirationDate
        self.path = path
    }
}

struct CertificateSummary: Codable, Identifiable, Sendable {
    let id: UUID
    let commonName: String
    let teamHint: String
    let expirationDate: String

    nonisolated init(id: UUID = UUID(), commonName: String, teamHint: String, expirationDate: String) {
        self.id = id
        self.commonName = commonName
        self.teamHint = teamHint
        self.expirationDate = expirationDate
    }
}

struct XcodeEnvironmentSnapshot: Codable, Sendable {
    let derivedDataLocations: [DerivedDataLocation]
    let totalDerivedDataBytes: UInt64
    let openProjects: [XcodeProjectUsage]
    let provisioningProfiles: [ProvisioningProfileSummary]
    let certificates: [CertificateSummary]
    let errors: [String]
    let lastUpdated: Date

    static var empty: XcodeEnvironmentSnapshot {
        XcodeEnvironmentSnapshot(
            derivedDataLocations: [],
            totalDerivedDataBytes: 0,
            openProjects: [],
            provisioningProfiles: [],
            certificates: [],
            errors: [],
            lastUpdated: .distantPast
        )
    }
}

struct FocusedProjectResolution: Codable, Sendable {
    let projectPath: String?
    let confidence: Double
    let source: String
    let isManualOverride: Bool

    static var unresolved: FocusedProjectResolution {
        FocusedProjectResolution(
            projectPath: nil,
            confidence: 0,
            source: "pending",
            isManualOverride: false
        )
    }
}

struct GitWorktreeSummary: Codable, Identifiable, Sendable {
    let id: UUID
    let path: String
    let branch: String
    let isCurrent: Bool

    nonisolated init(id: UUID = UUID(), path: String, branch: String, isCurrent: Bool) {
        self.id = id
        self.path = path
        self.branch = branch
        self.isCurrent = isCurrent
    }
}

struct GitContextSnapshot: Codable, Sendable {
    let projectPath: String?
    let repositoryRoot: String?
    let branch: String?
    let worktreePath: String?
    let worktrees: [GitWorktreeSummary]
    let note: String

    static var empty: GitContextSnapshot {
        GitContextSnapshot(
            projectPath: nil,
            repositoryRoot: nil,
            branch: nil,
            worktreePath: nil,
            worktrees: [],
            note: "Project context has not been scanned yet."
        )
    }
}

struct CommandResult: Codable, Sendable {
    let command: String
    let arguments: [String]
    let workingDirectory: String
    let exitStatus: Int32
    let stdout: String
    let stderr: String
    let startedAt: Date
    let endedAt: Date

    var succeeded: Bool {
        exitStatus == 0
    }
}

struct MaintenanceActionResult: Codable, Identifiable, Sendable {
    let id: UUID
    let action: String
    let summary: String
    let reclaimedBytes: UInt64?
    let commandResults: [CommandResult]
    let completedAt: Date

    nonisolated init(
        id: UUID = UUID(),
        action: String,
        summary: String,
        reclaimedBytes: UInt64?,
        commandResults: [CommandResult],
        completedAt: Date = Date()
    ) {
        self.id = id
        self.action = action
        self.summary = summary
        self.reclaimedBytes = reclaimedBytes
        self.commandResults = commandResults
        self.completedAt = completedAt
    }
}

struct ToolAvailability: Sendable {
    let git: Bool
    let xcodebuild: Bool
    let pod: Bool

    static var unknown: ToolAvailability {
        ToolAvailability(git: false, xcodebuild: false, pod: false)
    }
}

enum CoreMeterSegment: Equatable {
    case empty
    case filled
    case partial(Double)

    var fillFraction: Double {
        switch self {
        case .empty:
            return 0
        case .filled:
            return 1
        case .partial(let fraction):
            return min(max(fraction, 0), 1)
        }
    }
}

struct CoreMeterMapper {
    static let stepCount = 10

    static func segments(for percentage: Double) -> [CoreMeterSegment] {
        let normalized = min(max(percentage, 0), 100) / 10
        let fullSteps = Int(normalized.rounded(.down))
        let remainder = normalized - Double(fullSteps)

        return (0..<stepCount).map { index in
            if index < fullSteps {
                return .filled
            }
            if index == fullSteps, remainder > 0 {
                return .partial(remainder)
            }
            return .empty
        }
    }
}

enum CoreMeterUsageBand: Equatable {
    case low
    case moderate
    case elevated
    case high

    static func band(for percentage: Double) -> Self {
        switch min(max(percentage, 0), 100) {
        case ..<30:
            return .low
        case ...60:
            return .moderate
        case ...85:
            return .elevated
        default:
            return .high
        }
    }
}

struct CoreMeterGeometry {
    static let blockSide: Double = 10
    static let maximumBlockSide: Double = 22
    static let blockSpacing: Double = 2
    static let columnSpacing: Double = 4
    static let labelWidth: Double = 12
    static let compactDashboardMinimumWidth: Double = 250
    static let dashboardChartChromeWidth: Double = 48
    static let meterLabelGap: Double = 5
    static let meterLabelHeight: Double = 14

    static var columnWidth: Double {
        max(blockSide, labelWidth)
    }

    static var maximumMeterHeight: Double {
        (maximumBlockSide * Double(CoreMeterMapper.stepCount))
            + (blockSpacing * Double(CoreMeterMapper.stepCount - 1))
            + meterLabelGap
            + meterLabelHeight
            + 4
    }

    static func chartWidth(for coreCount: Int) -> Double {
        chartWidth(for: coreCount, blockSide: blockSide)
    }

    static func chartWidth(for coreCount: Int, blockSide: Double) -> Double {
        guard coreCount > 0 else { return 0 }
        let columnWidth = max(blockSide, labelWidth)
        return (Double(coreCount) * columnWidth) + (Double(coreCount - 1) * columnSpacing)
    }

    static func expandedBlockSide(for coreCount: Int, availableWidth: Double) -> Double {
        guard coreCount > 0 else { return blockSide }
        let availableColumnsWidth = availableWidth - (Double(coreCount - 1) * columnSpacing)
        let blockSideForWidth = availableColumnsWidth / Double(coreCount)
        return min(maximumBlockSide, max(blockSide, blockSideForWidth))
    }

    static func expandedChartWidth(for coreCount: Int, availableWidth: Double) -> Double {
        chartWidth(for: coreCount, blockSide: expandedBlockSide(for: coreCount, availableWidth: availableWidth))
    }

    static func dashboardWidth(for coreCount: Int, maximumWidth: Double) -> Double {
        let coreWidth = chartWidth(for: coreCount) + dashboardChartChromeWidth
        return min(maximumWidth, max(compactDashboardMinimumWidth, coreWidth))
    }
}

enum AdvancedSensorMetric: String, CaseIterable, Identifiable {
    case gpu = "GPU"
    case temperature = "Temperature"
    case fan = "Fan"

    var id: String { rawValue }

    var shortName: String {
        switch self {
        case .gpu:
            return "GPU"
        case .temperature:
            return "Temp"
        case .fan:
            return "Fan"
        }
    }
}

enum AdvancedSensorSetupState: String, CaseIterable {
    case notInstalled
    case approvalRequired
    case connected
    case unsupported
    case disabled
    case failed

    var title: String {
        switch self {
        case .notInstalled:
            return "Setup Required"
        case .approvalRequired:
            return "Approval Required"
        case .connected:
            return "Connected"
        case .unsupported:
            return "Unsupported"
        case .disabled:
            return "Disabled"
        case .failed:
            return "Access Failed"
        }
    }

    var nextAction: String {
        switch self {
        case .notInstalled:
            return "Configure a supported sensor helper."
        case .approvalRequired:
            return "Approve helper access before testing sensors."
        case .connected:
            return "Advanced sensor access is ready."
        case .unsupported:
            return "Use baseline telemetry on this host."
        case .disabled:
            return "Enable advanced sensor setup to continue."
        case .failed:
            return "Review helper diagnostics and test access again."
        }
    }

    static func resolve(
        isEnabled: Bool,
        helperInstalled: Bool,
        approvalGranted: Bool,
        hostSupported: Bool,
        accessTestFailed: Bool
    ) -> AdvancedSensorSetupState {
        guard hostSupported else { return .unsupported }
        guard isEnabled else { return .disabled }
        guard helperInstalled else { return .notInstalled }
        guard approvalGranted else { return .approvalRequired }
        guard !accessTestFailed else { return .failed }
        return .connected
    }
}

struct AdvancedSensorCapability: Identifiable {
    let metric: AdvancedSensorMetric
    let state: AdvancedSensorSetupState

    var id: String { metric.id }

    var dashboardStatus: String {
        switch state {
        case .connected:
            return "Waiting for sensor feed"
        case .notInstalled, .approvalRequired:
            return "Set up in Settings"
        case .failed:
            return "Check Settings"
        case .unsupported:
            return "Unsupported"
        case .disabled:
            return "Disabled"
        }
    }
}
