import SwiftUI

@MainActor
struct XTopAppState {
    let services: XTopAppServices
    let preferences: MacbarPreferences
    let sensorSettings: SensorSettingsModel
    let diagnostics: DeveloperDiagnosticsStore
    let viewModel: MacbarViewModel
    let simulatorInspector: SimulatorInspectorViewModel
    let cameraInjection: CameraInjectionViewModel
    let gridOverlayController: GridOverlayController
    let gridOverlayConfigStore: GridOverlayConfigStore
    let axPermissionMonitor: AXPermissionMonitor

    init() {
        let services = XTopAppServices()
        let preferences = MacbarPreferences()
        let sensorSettings = SensorSettingsModel(
            client: services.advancedSensorClient,
            telemetryService: services.telemetryService
        )
        let diagnostics = DeveloperDiagnosticsStore()

        self.services = services
        self.preferences = preferences
        self.sensorSettings = sensorSettings
        self.diagnostics = diagnostics
        self.viewModel = MacbarViewModel(
            telemetryService: services.telemetryService,
            xcodeService: services.xcodeService,
            resolver: services.resolver,
            gitService: services.gitService,
            gitMonitorService: services.gitMonitorService,
            maintenanceService: services.maintenanceService,
            preferences: preferences,
            sensorSettings: sensorSettings,
            diagnostics: diagnostics
        )
        self.simulatorInspector = SimulatorInspectorViewModel(
            bookmarkStore: services.simulatorBookmarkStore,
            discovery: services.simulatorDiscovery,
            catalog: services.installedAppCatalog,
            defaultsStore: services.simulatorUserDefaultsStore,
            keychainClearer: services.simulatorKeychainClearer,
            lifecycle: services.appLifecycleController
        )
        self.cameraInjection = CameraInjectionViewModel(
            coordinator: services.cameraInjectionCoordinator
        )
        self.gridOverlayController = GridOverlayController()
        self.gridOverlayConfigStore = GridOverlayConfigStore()
        self.axPermissionMonitor = AXPermissionMonitor()
    }
}

struct XTopAppServices {
    let runner: CommandRunner
    let resolver: FocusedProjectResolving
    let advancedSensorClient: AdvancedSensorClient
    let telemetryService: SystemTelemetryService
    let xcodeService: XcodeEnvironmentService
    let gitService: GitContextService
    let gitMonitorService: GitMonitorService
    let maintenanceService: MaintenanceService

    let simulatorBookmarkStore: SimulatorAccessBookmarkStore
    let simctlClient: SimctlClient
    let simulatorDiscovery: SimulatorDiscoveryService
    let installedAppCatalog: InstalledAppCatalog
    let simulatorUserDefaultsStore: UserDefaultsStore
    let simulatorKeychainClearer: KeychainClearer
    let appLifecycleController: AppLifecycleController
    let cameraInjectionCoordinator: CameraInjectionCoordinator

    init(
        runner: CommandRunner = CommandRunner(),
        advancedSensorClient: AdvancedSensorClient = LocalAdvancedSensorClient()
    ) {
        let resolver = DefaultFocusedProjectResolver(runner: runner)

        self.runner = runner
        self.resolver = resolver
        self.advancedSensorClient = advancedSensorClient
        self.telemetryService = DefaultSystemTelemetryService(
            runner: runner,
            advancedSensorClient: advancedSensorClient
        )
        self.xcodeService = DefaultXcodeEnvironmentService(runner: runner)
        self.gitService = DefaultGitContextService(runner: runner)
        self.gitMonitorService = DefaultGitMonitorService(runner: runner)
        self.maintenanceService = DefaultMaintenanceService(
            runner: runner,
            resolver: resolver
        )

        let simctl = SimctlClient(runner: runner)
        self.simctlClient = simctl
        self.simulatorBookmarkStore = SimulatorAccessBookmarkStore()
        self.simulatorDiscovery = SimulatorDiscoveryService(simctl: simctl)
        self.installedAppCatalog = InstalledAppCatalog(simctl: simctl)
        self.simulatorUserDefaultsStore = UserDefaultsStore()
        self.simulatorKeychainClearer = KeychainClearer()
        let lifecycle = AppLifecycleController(simctl: simctl)
        self.appLifecycleController = lifecycle
        self.cameraInjectionCoordinator = CameraInjectionCoordinator(lifecycle: lifecycle)
    }
}

extension View {
    @MainActor
    func xtopEnvironment(_ state: XTopAppState) -> some View {
        self
            .environment(state.preferences)
            .environment(state.sensorSettings)
            .environment(state.diagnostics)
            .environment(state.viewModel)
            .environment(state.simulatorInspector)
            .environment(state.cameraInjection)
            .environment(state.gridOverlayController)
            .environment(state.axPermissionMonitor)
    }
}
