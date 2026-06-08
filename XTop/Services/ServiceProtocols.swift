import Foundation

protocol SystemTelemetryService: Sendable {
    func collectBaseSnapshot(previous: SystemTelemetrySnapshot?) async -> SystemTelemetrySnapshot
    func collectAdvancedMetrics() async -> (gpu: MetricValue, temp: MetricValue, fan: MetricValue, diskCache: MetricValue)
    func setAdvancedSensorsEnabled(_ enabled: Bool) async
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

protocol GitMonitorService: Sendable {
    func loadRegistry() async -> GitMonitorRegistry
    func loadProfiles() async -> [GitMonitorAccountProfile]
    func setBaseFolders(_ folders: [String]) async
    func upsertRepository(path: String, displayName: String?, boundAccountProfileID: UUID?) async -> GitMonitoredRepository
    func updateRepositoryMetadata(id: UUID, xcodeProjectType: XcodeProjectType?, detectedProjectFilePath: String?) async
    func removeRepository(id: UUID) async
    func bindRepository(id: UUID, accountProfileID: UUID?) async
    func setPrimaryRepository(id: UUID) async
    func clearPrimaryRepository(id: UUID) async
    func createHTTPSProfile(displayName: String, host: String, username: String, token: String) async throws -> GitMonitorAccountProfile
    func createSSHProfile(displayName: String, host: String, username: String, privateKeyPath: String, publicKeyFingerprint: String, passphrase: String?) async throws -> GitMonitorAccountProfile
    func logoutProfile(id: UUID) async throws
    func runDeepDiscovery() async -> [GitMonitoredRepository]
    func refreshAllActiveRepositories() async -> [GitRepositorySnapshot]
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

protocol XcodeProjectDetecting: Sendable {
    func detectProjectType(at repositoryPath: String) async -> (type: XcodeProjectType, projectFilePath: String)?
}

protocol ExcludedArchsManaging: Sendable {
    func dryRun(mode: ExcludedArchsMode, projectFilePath: String) async throws -> ExcludedArchsResult
    func apply(mode: ExcludedArchsMode, projectFilePath: String) async throws -> ExcludedArchsResult
}
