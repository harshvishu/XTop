import Foundation
import Observation

@MainActor
@Observable
final class DeveloperDiagnosticsStore {
    private(set) var toolAvailability: ToolAvailability = .unknown
    private(set) var lastDeveloperScan: Date?
    private(set) var recentMaintenanceLogs: [MaintenanceActionResult] = []

    func updateToolAvailability(
        _ availability: ToolAvailability
    ) {
        toolAvailability = availability
    }

    func recordDeveloperScan(
        toolAvailability: ToolAvailability
    ) {
        self.toolAvailability = toolAvailability
        lastDeveloperScan = .now
    }

    func recordMaintenance(
        _ result: MaintenanceActionResult
    ) {
        recentMaintenanceLogs.insert(
            result,
            at: 0
        )
        recentMaintenanceLogs = Array(
            recentMaintenanceLogs.prefix(8)
        )
    }
}
