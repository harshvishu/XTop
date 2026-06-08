import Foundation
import Testing
@testable import XTop

@Suite("MacbarViewModel Repository Actions")
struct MacbarViewModelRepositoryActionsTests {

    @Test("scanProjectType updates repository metadata from detector")
    @MainActor
    func scanProjectTypeUpdatesRepositoryMetadata() async throws {
        let repository = GitMonitoredRepository(
            displayName: "App",
            path: "/tmp/repo",
            canonicalPath: "/tmp/repo"
        )
        let gitMonitor = StubGitMonitorService(registry: GitMonitorRegistry(repositories: [repository]))
        let detector = StubXcodeProjectDetector(result: (.xcodeproj, "/tmp/repo/App.xcodeproj"))
        let archManager = StubExcludedArchsManager()

        let viewModel = makeViewModel(
            gitMonitorService: gitMonitor,
            detector: detector,
            archManager: archManager
        )

        await viewModel.scanProjectType(for: repository.id)

        let updated = viewModel.gitMonitorRegistry.repositories.first(where: { $0.id == repository.id })
        #expect(updated?.xcodeProjectType == .xcodeproj)
        #expect(updated?.detectedProjectFilePath == "/tmp/repo/App.xcodeproj")
    }

    @Test("applyArchsAction delegates to manager with resolved pbxproj path")
    @MainActor
    func applyArchsActionDelegatesToManager() async throws {
        let repository = GitMonitoredRepository(
            displayName: "App",
            path: "/tmp/repo",
            canonicalPath: "/tmp/repo",
            xcodeProjectType: .xcodeproj,
            detectedProjectFilePath: "/tmp/repo/App.xcodeproj"
        )
        let gitMonitor = StubGitMonitorService(registry: GitMonitorRegistry(repositories: [repository]))
        let detector = StubXcodeProjectDetector(result: nil)
        let archManager = StubExcludedArchsManager()

        let viewModel = makeViewModel(
            gitMonitorService: gitMonitor,
            detector: detector,
            archManager: archManager
        )

        _ = try await viewModel.applyArchsAction(
            mode: .setDebugArm64,
            repositoryID: repository.id
        )

        let call = await archManager.lastApply
        #expect(call?.mode == .setDebugArm64)
        #expect(call?.projectFilePath == "/tmp/repo/App.xcodeproj/project.pbxproj")
    }

    @MainActor
    private func makeViewModel(
        gitMonitorService: GitMonitorService,
        detector: XcodeProjectDetecting,
        archManager: ExcludedArchsManaging
    ) -> MacbarViewModel {
        MacbarViewModel(
            telemetryService: StubSystemTelemetryService(),
            xcodeService: StubXcodeEnvironmentService(),
            resolver: StubFocusedProjectResolver(),
            gitService: StubGitContextService(),
            gitMonitorService: gitMonitorService,
            maintenanceService: StubMaintenanceService(),
            xcodeProjectDetector: detector,
            excludedArchsManager: archManager,
            preferences: MacbarPreferences(),
            sensorSettings: SensorSettingsModel(),
            diagnostics: DeveloperDiagnosticsStore()
        )
    }
}

private actor StubGitMonitorService: GitMonitorService {
    private var registry: GitMonitorRegistry

    init(registry: GitMonitorRegistry) {
        self.registry = registry
    }

    func loadRegistry() async -> GitMonitorRegistry { registry }
    func loadProfiles() async -> [GitMonitorAccountProfile] { [] }
    func setBaseFolders(_ folders: [String]) async { registry.baseFolders = folders }

    func upsertRepository(
        path: String,
        displayName: String?,
        boundAccountProfileID: UUID?
    ) async -> GitMonitoredRepository {
        let repository = GitMonitoredRepository(
            displayName: displayName ?? URL(filePath: path).lastPathComponent,
            path: path,
            canonicalPath: path,
            boundAccountProfileID: boundAccountProfileID
        )
        registry.repositories.append(repository)
        return repository
    }

    func updateRepositoryMetadata(
        id: UUID,
        xcodeProjectType: XcodeProjectType?,
        detectedProjectFilePath: String?
    ) async {
        guard let index = registry.repositories.firstIndex(where: { $0.id == id }) else {
            return
        }
        registry.repositories[index].xcodeProjectType = xcodeProjectType
        registry.repositories[index].detectedProjectFilePath = detectedProjectFilePath
    }

    func removeRepository(id: UUID) async {
        registry.repositories.removeAll(where: { $0.id == id })
    }

    func bindRepository(id: UUID, accountProfileID: UUID?) async {}
    func setPrimaryRepository(id: UUID) async {}
    func clearPrimaryRepository(id: UUID) async {}

    func createHTTPSProfile(
        displayName: String,
        host: String,
        username: String,
        token: String
    ) async throws -> GitMonitorAccountProfile {
        GitMonitorAccountProfile(
            displayName: displayName,
            host: host,
            username: username,
            authMode: .httpsToken
        )
    }

    func createSSHProfile(
        displayName: String,
        host: String,
        username: String,
        privateKeyPath: String,
        publicKeyFingerprint: String,
        passphrase: String?
    ) async throws -> GitMonitorAccountProfile {
        GitMonitorAccountProfile(
            displayName: displayName,
            host: host,
            username: username,
            authMode: .sshKey,
            sshPrivateKeyPath: privateKeyPath,
            sshPublicKeyFingerprint: publicKeyFingerprint
        )
    }

    func logoutProfile(id: UUID) async throws {}
    func runDeepDiscovery() async -> [GitMonitoredRepository] { registry.repositories }
    func refreshAllActiveRepositories() async -> [GitRepositorySnapshot] { [] }
}

private actor StubXcodeProjectDetector: XcodeProjectDetecting {
    let result: (type: XcodeProjectType, projectFilePath: String)?

    init(result: (type: XcodeProjectType, projectFilePath: String)?) {
        self.result = result
    }

    func detectProjectType(at repositoryPath: String) async -> (type: XcodeProjectType, projectFilePath: String)? {
        result
    }
}

private actor StubExcludedArchsManager: ExcludedArchsManaging {
    private(set) var lastDryRun: (mode: ExcludedArchsMode, projectFilePath: String)?
    private(set) var lastApply: (mode: ExcludedArchsMode, projectFilePath: String)?

    func dryRun(mode: ExcludedArchsMode, projectFilePath: String) async throws -> ExcludedArchsResult {
        lastDryRun = (mode, projectFilePath)
        return ExcludedArchsResult(
            changedBlocks: 1,
            changedLines: 1,
            debugBlocksChanged: 1,
            nonDebugBlocksChanged: 0,
            message: "Dry run"
        )
    }

    func apply(mode: ExcludedArchsMode, projectFilePath: String) async throws -> ExcludedArchsResult {
        lastApply = (mode, projectFilePath)
        return ExcludedArchsResult(
            changedBlocks: 1,
            changedLines: 1,
            debugBlocksChanged: 1,
            nonDebugBlocksChanged: 0,
            backupPath: "/tmp/project.pbxproj.backup",
            message: "Applied"
        )
    }
}

private struct StubSystemTelemetryService: SystemTelemetryService {
    func collectBaseSnapshot(previous: SystemTelemetrySnapshot?) async -> SystemTelemetrySnapshot { .empty }
    func collectAdvancedMetrics() async -> (gpu: MetricValue, temp: MetricValue, fan: MetricValue, diskCache: MetricValue) {
        (
            .unavailable(label: "GPU", unit: "%", reason: "n/a"),
            .unavailable(label: "Temp", unit: "C", reason: "n/a"),
            .unavailable(label: "Fan", unit: "RPM", reason: "n/a"),
            .unavailable(label: "Disk", unit: "MB", reason: "n/a")
        )
    }
    func setAdvancedSensorsEnabled(_ enabled: Bool) async {}
}

private struct StubXcodeEnvironmentService: XcodeEnvironmentService {
    func collectXcodeEnvironment() async -> XcodeEnvironmentSnapshot { .empty }
}

private struct StubFocusedProjectResolver: FocusedProjectResolving {
    func resolveFocusedProject() async -> FocusedProjectResolution { .unresolved }
    func setManualOverride(path: String?) async {}
}

private struct StubGitContextService: GitContextService {
    func collectGitContext(for projectResolution: FocusedProjectResolution) async -> GitContextSnapshot { .empty }
}

private struct StubMaintenanceService: MaintenanceService {
    func checkToolAvailability() async -> ToolAvailability { .unknown }
    func cleanDerivedData(targetPath: String?) async -> MaintenanceActionResult { .init(action: "", summary: "", reclaimedBytes: nil, commandResults: []) }
    func cleanDeveloperCaches() async -> MaintenanceActionResult { .init(action: "", summary: "", reclaimedBytes: nil, commandResults: []) }
    func resetSwiftPM(projectPath: String) async -> MaintenanceActionResult { .init(action: "", summary: "", reclaimedBytes: nil, commandResults: []) }
    func refetchSwiftPM(projectPath: String) async -> MaintenanceActionResult { .init(action: "", summary: "", reclaimedBytes: nil, commandResults: []) }
    func listPods(projectPath: String) async -> MaintenanceActionResult { .init(action: "", summary: "", reclaimedBytes: nil, commandResults: []) }
    func installPods(projectPath: String) async -> MaintenanceActionResult { .init(action: "", summary: "", reclaimedBytes: nil, commandResults: []) }
    func updateSinglePod(projectPath: String, podName: String) async -> MaintenanceActionResult { .init(action: "", summary: "", reclaimedBytes: nil, commandResults: []) }
    func cleanPodCache(podName: String?) async -> MaintenanceActionResult { .init(action: "", summary: "", reclaimedBytes: nil, commandResults: []) }
    func deintegratePods(projectPath: String) async -> MaintenanceActionResult { .init(action: "", summary: "", reclaimedBytes: nil, commandResults: []) }
}
