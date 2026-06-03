import Foundation
import Observation
import SwiftUI

/// Drives the Simulator Inspector window. Owns refresh state for booted
/// simulators, installed apps, `UserDefaults` entries, and lifecycle actions.
@MainActor
@Observable
final class SimulatorInspectorViewModel {
    // MARK: - Published state

    private(set) var simulators: [SimulatorDevice] = []
    private(set) var installedApps: [InstalledApp] = []
    private(set) var entries: [UserDefaultsEntry] = []

    private(set) var isRefreshingSimulators = false
    private(set) var isRefreshingApps = false
    private(set) var isRefreshingEntries = false

    private(set) var lastError: String?
    private(set) var lastInfo: String?
    private(set) var pendingRelaunchSuggestion = false
    private(set) var isTargetAppRunning = false

    var selectedSimulatorID: String? {
        didSet {
            guard oldValue != selectedSimulatorID else { return }
            selectedBundleIdentifier = nil
            installedApps = []
            entries = []
            Task { await refreshInstalledApps() }
        }
    }

    var selectedBundleIdentifier: String? {
        didSet {
            guard oldValue != selectedBundleIdentifier else { return }
            currentScope = selectedBundleIdentifier.map { .app(bundleIdentifier: $0) }
            entries = []
            Task {
                await refreshEntries()
                await refreshRunningState()
            }
        }
    }

    var currentScope: UserDefaultsScope?

    var selectedSimulator: SimulatorDevice? {
        simulators.first { $0.id == selectedSimulatorID }
    }

    var selectedApp: InstalledApp? {
        installedApps.first { $0.bundleIdentifier == selectedBundleIdentifier }
    }

    // MARK: - Collaborators

    @ObservationIgnored let bookmarkStore: SimulatorAccessBookmarkStore
    @ObservationIgnored private let discovery: SimulatorDiscoveryService
    @ObservationIgnored private let catalog: InstalledAppCatalog
    @ObservationIgnored private let defaultsStore: UserDefaultsStore
    @ObservationIgnored private let keychainClearer: KeychainClearer
    @ObservationIgnored private let lifecycle: AppLifecycleController

    @ObservationIgnored private var simulatorRefreshTask: Task<Void, Never>?

    private static let simulatorRefreshInterval: Duration = .seconds(8)

    // MARK: - Init

    init(
        bookmarkStore: SimulatorAccessBookmarkStore,
        discovery: SimulatorDiscoveryService,
        catalog: InstalledAppCatalog,
        defaultsStore: UserDefaultsStore,
        keychainClearer: KeychainClearer,
        lifecycle: AppLifecycleController
    ) {
        self.bookmarkStore = bookmarkStore
        self.discovery = discovery
        self.catalog = catalog
        self.defaultsStore = defaultsStore
        self.keychainClearer = keychainClearer
        self.lifecycle = lifecycle
    }

    deinit {
        simulatorRefreshTask?.cancel()
    }

    // MARK: - Refresh

    func startPeriodicRefresh() {
        stopPeriodicRefresh()
        simulatorRefreshTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshSimulators()
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: Self.simulatorRefreshInterval)
                } catch {
                    break
                }
                if Task.isCancelled { break }
                await self.refreshSimulators()
            }
        }
    }

    func stopPeriodicRefresh() {
        simulatorRefreshTask?.cancel()
        simulatorRefreshTask = nil
    }

    func refreshSimulators() async {
        isRefreshingSimulators = true
        defer { isRefreshingSimulators = false }
        let booted: [SimulatorDevice]
        do {
            booted = try await discovery.bootedSimulators()
            lastError = nil
        } catch {
            booted = []
            lastError = "Failed to list simulators: \(error.localizedDescription)"
        }
        simulators = booted
        if let selected = selectedSimulatorID, !booted.contains(where: { $0.id == selected }) {
            selectedSimulatorID = booted.first?.id
        } else if selectedSimulatorID == nil {
            selectedSimulatorID = booted.first?.id
        }
    }

    func refreshInstalledApps() async {
        guard let udid = selectedSimulatorID else {
            installedApps = []
            return
        }
        isRefreshingApps = true
        defer { isRefreshingApps = false }
        installedApps = await catalog.installedApps(for: udid)
        if let selected = selectedBundleIdentifier,
           !installedApps.contains(where: { $0.bundleIdentifier == selected }) {
            selectedBundleIdentifier = installedApps.first?.bundleIdentifier
        }
    }

    func refreshEntries() async {
        guard let scope = currentScope, let app = selectedApp else {
            entries = []
            return
        }
        guard let url = UserDefaultsStore.plistURL(for: scope, in: app) else {
            entries = []
            lastError = "Could not resolve UserDefaults plist path."
            return
        }
        isRefreshingEntries = true
        defer { isRefreshingEntries = false }
        do {
            entries = try await defaultsStore.loadEntries(at: url)
            lastError = nil
        } catch {
            entries = []
            lastError = error.localizedDescription
        }
    }

    func refreshRunningState() async {
        guard let udid = selectedSimulatorID, let bundle = selectedBundleIdentifier else {
            isTargetAppRunning = false
            return
        }
        isTargetAppRunning = await lifecycle.isRunning(
            bundleIdentifier: bundle,
            on: udid
        )
    }

    // MARK: - UserDefaults mutation

    func updateEntry(key: String, value: Any) async {
        guard let scope = currentScope, let app = selectedApp,
              let url = UserDefaultsStore.plistURL(for: scope, in: app) else { return }
        await refreshRunningState()
        do {
            try await defaultsStore.update(key: key, to: value, at: url)
            await refreshEntries()
            pendingRelaunchSuggestion = true
            lastInfo = "Updated \(key). Relaunch the app for the change to take effect."
        } catch {
            lastError = error.localizedDescription
        }
    }

    func addEntry(key: String, value: Any) async {
        guard let scope = currentScope, let app = selectedApp,
              let url = UserDefaultsStore.plistURL(for: scope, in: app) else { return }
        await refreshRunningState()
        do {
            try await defaultsStore.add(key: key, value: value, at: url)
            await refreshEntries()
            pendingRelaunchSuggestion = true
            lastInfo = "Added \(key)."
        } catch {
            lastError = error.localizedDescription
        }
    }

    func deleteEntry(key: String) async {
        guard let scope = currentScope, let app = selectedApp,
              let url = UserDefaultsStore.plistURL(for: scope, in: app) else { return }
        await refreshRunningState()
        do {
            try await defaultsStore.delete(key: key, at: url)
            await refreshEntries()
            pendingRelaunchSuggestion = true
            lastInfo = "Deleted \(key)."
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Lifecycle

    func relaunchSelectedApp() async {
        guard let udid = selectedSimulatorID, let bundle = selectedBundleIdentifier else { return }
        do {
            try await lifecycle.relaunch(bundleIdentifier: bundle, on: udid)
            pendingRelaunchSuggestion = false
            lastInfo = "Relaunched \(bundle)."
            await refreshRunningState()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func terminateSelectedApp() async {
        guard let udid = selectedSimulatorID, let bundle = selectedBundleIdentifier else { return }
        do {
            try await lifecycle.terminate(bundleIdentifier: bundle, on: udid)
            await refreshRunningState()
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Keychain

    func clearSelectedKeychain() async {
        guard let udid = selectedSimulatorID else { return }
        guard let bundle = selectedBundleIdentifier else {
            // No selected app means we don't need to terminate anything first.
            await performKeychainClear(udid: udid)
            return
        }
        do {
            try await lifecycle.terminate(bundleIdentifier: bundle, on: udid)
        } catch {
            lastError = "Refusing to clear keychain — could not terminate \(bundle): \(error.localizedDescription)"
            return
        }
        await performKeychainClear(udid: udid)
    }

    private func performKeychainClear(udid: String) async {
        do {
            try await keychainClearer.clear(forSimulator: udid)
            lastInfo = "Keychain cleared. Relaunch the simulator if subsequent keychain reads fail."
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Scope selection

    func selectScope(_ scope: UserDefaultsScope) {
        currentScope = scope
        Task { await refreshEntries() }
    }

    // MARK: - Banner clears

    func dismissError() { lastError = nil }
    func dismissInfo() { lastInfo = nil }
    func dismissRelaunchSuggestion() { pendingRelaunchSuggestion = false }
}
