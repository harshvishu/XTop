import Foundation

protocol SystemTelemetryService: Sendable {
    func collectBaseSnapshot(previous: SystemTelemetrySnapshot?) async -> SystemTelemetrySnapshot
    func collectAdvancedMetrics() async -> (gpu: MetricValue, temp: MetricValue, fan: MetricValue, diskCache: MetricValue)
}

protocol XcodeEnvironmentService: Sendable {
    func collectXcodeEnvironment() async -> XcodeEnvironmentSnapshot
}

protocol FocusedProjectResolving: Sendable {
    func resolveFocusedProject() async -> FocusedProjectResolution
    func setManualOverride(path: String?) async
}

protocol GitContextService: Sendable {
    func collectGitContext(for projectResolution: FocusedProjectResolution) async -> GitContextSnapshot
}

protocol MaintenanceService: Sendable {
    func checkToolAvailability() async -> ToolAvailability
    func cleanDerivedData(targetPath: String?) async -> MaintenanceActionResult
    func cleanDeveloperCaches() async -> MaintenanceActionResult
    func resetSwiftPM(projectPath: String) async -> MaintenanceActionResult
    func refetchSwiftPM(projectPath: String) async -> MaintenanceActionResult
    func listPods(projectPath: String) async -> MaintenanceActionResult
    func installPods(projectPath: String) async -> MaintenanceActionResult
    func updateSinglePod(projectPath: String, podName: String) async -> MaintenanceActionResult
    func cleanPodCache(podName: String?) async -> MaintenanceActionResult
    func deintegratePods(projectPath: String) async -> MaintenanceActionResult
}
