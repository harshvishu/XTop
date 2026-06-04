import Foundation
import Observation

@MainActor
@Observable
final class MacbarViewModel {
    private(set) var telemetry: SystemTelemetrySnapshot
    private(set) var xcodeSnapshot: XcodeEnvironmentSnapshot
    private(set) var focusedProject: FocusedProjectResolution
    private(set) var gitSnapshot: GitContextSnapshot
    private(set) var maintenanceLogs: [MaintenanceActionResult]
    private(set) var toolAvailability: ToolAvailability
    private(set) var gitMonitorRegistry: GitMonitorRegistry
    private(set) var gitMonitorProfiles: [GitMonitorAccountProfile]
    private(set) var gitMonitorSnapshots: [UUID: GitRepositorySnapshot]

    let preferences: MacbarPreferences
    let sensorSettings: SensorSettingsModel

    @ObservationIgnored
    private let telemetryService: SystemTelemetryService

    @ObservationIgnored
    private let maintenanceService: MaintenanceService

    @ObservationIgnored
    private let gitMonitorService: GitMonitorService

    @ObservationIgnored
    private let developerContextCollector: DeveloperContextCollector

    @ObservationIgnored
    private let diagnostics: DeveloperDiagnosticsStore

    @ObservationIgnored
    private var samplingTask: Task<Void, Never>?

    @ObservationIgnored
    private var developerContextTask: Task<Void, Never>?

    @ObservationIgnored
    private var gitMonitorRefreshTask: Task<Void, Never>?

    @ObservationIgnored
    private var lastDeveloperRefresh = Date.distantPast

    @ObservationIgnored
    private let developerRefreshInterval: TimeInterval = 30

    init(
        telemetryService: SystemTelemetryService,
        xcodeService: XcodeEnvironmentService,
        resolver: FocusedProjectResolving,
        gitService: GitContextService,
        gitMonitorService: GitMonitorService,
        maintenanceService: MaintenanceService,
        preferences: MacbarPreferences,
        sensorSettings: SensorSettingsModel,
        diagnostics: DeveloperDiagnosticsStore
    ) {
        self.telemetryService = telemetryService
        self.maintenanceService = maintenanceService
        self.gitMonitorService = gitMonitorService
        self.preferences = preferences
        self.sensorSettings = sensorSettings
        self.diagnostics = diagnostics

        self.developerContextCollector = DeveloperContextCollector(
            xcodeService: xcodeService,
            resolver: resolver,
            gitService: gitService,
            maintenanceService: maintenanceService
        )

        self.maintenanceLogs = []
        self.toolAvailability = .unknown
        self.gitMonitorRegistry = GitMonitorRegistry()
        self.gitMonitorProfiles = []
        self.gitMonitorSnapshots = [:]
        self.telemetry = .empty
        self.xcodeSnapshot = .empty
        self.focusedProject = .unresolved
        self.gitSnapshot = .empty

        diagnostics.updateToolAvailability(toolAvailability)
    }

    deinit {
        samplingTask?.cancel()
        developerContextTask?.cancel()
        gitMonitorRefreshTask?.cancel()
    }

    func startSampling() {
        stopSampling()

        samplingTask = Task { [weak self] in
            guard let self else { return }

            await self.refresh()

            while !Task.isCancelled {
                do {
                    try await Task.sleep(
                        for: .seconds(
                            self.preferences.refreshInterval.seconds
                        )
                    )
                    await self.refreshWithBudget()
                } catch {
                    break
                }
            }
        }
    }

    func stopSampling() {
        samplingTask?.cancel()
        samplingTask = nil
    }

    func refresh() async {
        await refreshTelemetry()
        await refreshDeveloperContextIfNeeded(force: true)
        await refreshGitMonitor(force: true)
    }

    /// Refreshes only the developer-context snapshot (tool availability, Xcode
    /// project, Git, focused project). Useful for Settings views that need
    /// fresh `toolAvailability` without paying the cost of a full `refresh()`.
    func refreshDeveloperContext() async {
        await refreshDeveloperContextIfNeeded(force: true)
    }

    func refreshWithBudget() async {
        let started = Date.now
        let previousTelemetry = telemetry

        await refreshTelemetry()

        if shouldRefreshDeveloperContext {
            await refreshDeveloperContextIfNeeded()
        }

        if shouldRefreshDeveloperContext {
            await refreshGitMonitor()
        }

        let elapsed = Date.now
            .timeIntervalSince(started)

        guard elapsed <= 1 else {
            telemetry = delayedTelemetry(
                from: previousTelemetry
            )
            return
        }
    }

    private func refreshTelemetry() async {
        telemetry = await telemetryService.collectBaseSnapshot(
            previous: telemetry
        )
    }

    private func refreshDeveloperContextIfNeeded(
        force: Bool = false
    ) async {
        if force {
            developerContextTask?.cancel()
            developerContextTask = nil
        }

        guard developerContextTask == nil else {
            return
        }

        lastDeveloperRefresh = .now

        developerContextTask = Task { [weak self] in
            guard let self else { return }

            let snapshot = await self.developerContextCollector.collect()

            guard !Task.isCancelled else {
                return
            }

            self.xcodeSnapshot = snapshot.xcode
            self.focusedProject = snapshot.focusedProject
            self.gitSnapshot = snapshot.git
            self.toolAvailability = snapshot.toolAvailability

            self.diagnostics.recordDeveloperScan(
                toolAvailability: snapshot.toolAvailability
            )

            self.developerContextTask = nil
        }

        await developerContextTask?.value
    }

    private func refreshGitMonitor(force: Bool = false) async {
        if force {
            gitMonitorRefreshTask?.cancel()
            gitMonitorRefreshTask = nil
        }

        guard gitMonitorRefreshTask == nil else {
            return
        }

        gitMonitorRefreshTask = Task { [weak self] in
            guard let self else { return }

            _ = await self.gitMonitorService.runDeepDiscovery()
            let registry = await self.gitMonitorService.loadRegistry()
            let profiles = await self.gitMonitorService.loadProfiles()
            let snapshots = await self.gitMonitorService.refreshAllActiveRepositories()

            guard !Task.isCancelled else {
                return
            }

            self.gitMonitorRegistry = registry
            self.gitMonitorProfiles = profiles
            self.gitMonitorSnapshots = Dictionary(
                uniqueKeysWithValues: snapshots.map { ($0.repositoryID, $0) }
            )
            self.gitMonitorRefreshTask = nil
        }

        await gitMonitorRefreshTask?.value
    }

    var primaryMonitoredRepository: GitMonitoredRepository? {
        gitMonitorRegistry.repositories.first {
            $0.isPrimary && $0.isActive
        } ?? gitMonitorRegistry.repositories.first { $0.isActive }
    }

    var secondaryMonitoredRepositories: [GitMonitoredRepository] {
        guard let primaryID = primaryMonitoredRepository?.id else {
            return gitMonitorRegistry.repositories.filter { $0.isActive }
        }

        return gitMonitorRegistry.repositories.filter {
            $0.isActive && $0.id != primaryID
        }
    }

    var inactiveMonitoredRepositories: [GitMonitoredRepository] {
        gitMonitorRegistry.repositories.filter { !$0.isActive }
    }

    func gitSnapshot(for repositoryID: UUID) -> GitRepositorySnapshot? {
        gitMonitorSnapshots[repositoryID]
    }

    func setGitMonitorBaseFolders(_ folders: [String]) {
        Task { [weak self] in
            guard let self else { return }
            await self.gitMonitorService.setBaseFolders(folders)
            await self.refreshGitMonitor(force: true)
        }
    }

    func addMonitoredRepository(path: String, displayName: String?) {
        Task { [weak self] in
            guard let self else { return }
            _ = await self.gitMonitorService.upsertRepository(
                path: path,
                displayName: displayName,
                boundAccountProfileID: nil
            )
            await self.refreshGitMonitor(force: true)
        }
    }

    func removeMonitoredRepository(id: UUID) {
        Task { [weak self] in
            guard let self else { return }
            await self.gitMonitorService.removeRepository(id: id)
            await self.reloadGitRegistry()
            await self.refreshGitMonitor(force: true)
        }
    }

    func setPrimaryMonitoredRepository(id: UUID) {
        Task { [weak self] in
            guard let self else { return }
            await self.gitMonitorService.setPrimaryRepository(id: id)
            await self.reloadGitRegistry()
            await self.refreshGitMonitor(force: true)
        }
    }

    /// Toggle the primary flag for a repository: if it is currently primary,
    /// clear it; otherwise promote it to primary.
    func togglePrimaryMonitoredRepository(id: UUID) {
        let isPrimary = gitMonitorRegistry.repositories.first(where: { $0.id == id })?.isPrimary ?? false
        Task { [weak self] in
            guard let self else { return }
            if isPrimary {
                await self.gitMonitorService.clearPrimaryRepository(id: id)
            } else {
                await self.gitMonitorService.setPrimaryRepository(id: id)
            }
            await self.reloadGitRegistry()
            await self.refreshGitMonitor(force: true)
        }
    }

    /// Reload just the persisted registry/profiles into local state without
    /// running the (slow) deep discovery or remote snapshot refresh. Used to
    /// reflect quick local mutations (set primary, remove, etc.) in the UI
    /// immediately instead of waiting on `git fetch`.
    private func reloadGitRegistry() async {
        let registry = await gitMonitorService.loadRegistry()
        let profiles = await gitMonitorService.loadProfiles()
        gitMonitorRegistry = registry
        gitMonitorProfiles = profiles
    }

    func bindRepository(id: UUID, accountProfileID: UUID?) {
        Task { [weak self] in
            guard let self else { return }
            await self.gitMonitorService.bindRepository(id: id, accountProfileID: accountProfileID)
            await self.refreshGitMonitor(force: true)
        }
    }

    func loginHTTPSProfile(
        displayName: String,
        host: String,
        username: String,
        token: String
    ) {
        Task { [weak self] in
            guard let self else { return }
            _ = try? await self.gitMonitorService.createHTTPSProfile(
                displayName: displayName,
                host: host,
                username: username,
                token: token
            )
            await self.refreshGitMonitor(force: true)
        }
    }

    func loginSSHProfile(
        displayName: String,
        host: String,
        username: String,
        privateKeyPath: String,
        publicKeyFingerprint: String,
        passphrase: String?
    ) {
        Task { [weak self] in
            guard let self else { return }
            _ = try? await self.gitMonitorService.createSSHProfile(
                displayName: displayName,
                host: host,
                username: username,
                privateKeyPath: privateKeyPath,
                publicKeyFingerprint: publicKeyFingerprint,
                passphrase: passphrase
            )
            await self.refreshGitMonitor(force: true)
        }
    }

    func logoutProfile(id: UUID) {
        Task { [weak self] in
            guard let self else { return }
            try? await self.gitMonitorService.logoutProfile(id: id)
            await self.refreshGitMonitor(force: true)
        }
    }

    func performMaintenanceAction(
        _ action: MaintenanceAction
    ) async {
        let projectPath = focusedProject.projectPath ?? ""

        let result: MaintenanceActionResult = switch action {
        case .cleanDerivedData:
            await maintenanceService.cleanDerivedData(
                targetPath: nil
            )
        case .cleanCaches:
            await maintenanceService.cleanDeveloperCaches()
        case .resetSwiftPM:
            await maintenanceService.resetSwiftPM(
                projectPath: projectPath
            )
        case .refetchSwiftPM:
            await maintenanceService.refetchSwiftPM(
                projectPath: projectPath
            )
        case .listPods:
            await maintenanceService.listPods(
                projectPath: projectPath
            )
        case .installPods:
            await maintenanceService.installPods(
                projectPath: projectPath
            )
        case .updateSinglePod(let podName):
            await maintenanceService.updateSinglePod(
                projectPath: projectPath,
                podName: podName
            )
        case .cleanPodCache(let podName):
            await maintenanceService.cleanPodCache(
                podName: podName
            )
        case .deintegratePods:
            await maintenanceService.deintegratePods(
                projectPath: projectPath
            )
        }

        maintenanceLogs.insert(result, at: 0)
        diagnostics.recordMaintenance(result)

        await refreshTelemetry()
        await refreshDeveloperContextIfNeeded(force: true)
    }

    func setManualProjectOverride(
        path: String?
    ) {
        Task { [weak self] in
            guard let self else { return }

            await self.developerContextCollector
                .setManualProjectOverride(path: path)

            await self.refreshDeveloperContextIfNeeded(
                force: true
            )
        }
    }

    private var shouldRefreshDeveloperContext: Bool {
        Date.now.timeIntervalSince(
            lastDeveloperRefresh
        ) >= developerRefreshInterval
    }

    private func delayedTelemetry(
        from snapshot: SystemTelemetrySnapshot
    ) -> SystemTelemetrySnapshot {
        SystemTelemetrySnapshot(
            cpuPercent: snapshot.cpuPercent,
            perCoreCpuPercent: snapshot.perCoreCpuPercent,
            memoryUsedPercent: snapshot.memoryUsedPercent,
            gpuPercent: snapshot.gpuPercent,
            temperatureC: snapshot.temperatureC,
            fanRPM: snapshot.fanRPM,
            diskCacheMB: snapshot.diskCacheMB,
            storageUsedPercent: snapshot.storageUsedPercent,
            developerToolUsage: snapshot.developerToolUsage,
            lastUpdated: snapshot.lastUpdated,
            severity: snapshot.severity,
            sampleDelayed: true
        )
    }
}

enum MaintenanceAction {
    case cleanDerivedData
    case cleanCaches
    case resetSwiftPM
    case refetchSwiftPM
    case listPods
    case installPods
    case updateSinglePod(String)
    case cleanPodCache(String?)
    case deintegratePods
}

private struct DeveloperContextSnapshot: Sendable {
    let xcode: XcodeEnvironmentSnapshot
    let focusedProject: FocusedProjectResolution
    let git: GitContextSnapshot
    let toolAvailability: ToolAvailability
}

private actor DeveloperContextCollector {
    private let xcodeService: XcodeEnvironmentService
    private let resolver: FocusedProjectResolving
    private let gitService: GitContextService
    private let maintenanceService: MaintenanceService

    init(
        xcodeService: XcodeEnvironmentService,
        resolver: FocusedProjectResolving,
        gitService: GitContextService,
        maintenanceService: MaintenanceService
    ) {
        self.xcodeService = xcodeService
        self.resolver = resolver
        self.gitService = gitService
        self.maintenanceService = maintenanceService
    }

    func collect() async -> DeveloperContextSnapshot {
        let xcode = await xcodeService.collectXcodeEnvironment()
        let focusedProject = await resolver.resolveFocusedProject()
        let git = await gitService.collectGitContext(
            for: focusedProject
        )
        let toolAvailability = await maintenanceService.checkToolAvailability()

        return DeveloperContextSnapshot(
            xcode: xcode,
            focusedProject: focusedProject,
            git: git,
            toolAvailability: toolAvailability
        )
    }

    func setManualProjectOverride(
        path: String?
    ) async {
        await resolver.setManualOverride(
            path: path
        )
    }
}
