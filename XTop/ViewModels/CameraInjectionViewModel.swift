import Foundation
import Observation
import SwiftUI

/// View model for the Simulator Inspector's Camera tab.
///
/// Owns the chosen frame source, the coordinator, and the live transport
/// state for UI binding.
@MainActor
@Observable
final class CameraInjectionViewModel {
    // MARK: - Published state

    var selectedKind: CameraSourceKind = .testPattern
    var jpegQuality: Double = 0.7
    var videoFileURL: URL?

    private(set) var transportState: CameraTransportState = .stopped
    private(set) var phase: CameraInjectionPhase = .idle
    private(set) var lastError: String?
    private(set) var activePID: Int32?

    // MARK: - Collaborators

    @ObservationIgnored private let coordinator: CameraInjectionCoordinator
    @ObservationIgnored private let preferences: CameraSourcePreferenceStore
    @ObservationIgnored private var stateObserverTask: Task<Void, Never>?

    // MARK: - Init

    init(
        coordinator: CameraInjectionCoordinator,
        preferences: CameraSourcePreferenceStore = CameraSourcePreferenceStore()
    ) {
        self.coordinator = coordinator
        self.preferences = preferences
    }

    deinit {
        stateObserverTask?.cancel()
    }

    // MARK: - Observation

    func startObservingTransport() {
        stateObserverTask?.cancel()
        stateObserverTask = Task { [weak self, coordinator] in
            let stream = await coordinator.transportStateStream()
            for await state in stream {
                guard let self else { return }
                self.transportState = state
            }
        }
    }

    func stopObservingTransport() {
        stateObserverTask?.cancel()
        stateObserverTask = nil
    }

    // MARK: - Actions

    func injectAndLaunch(bundleID: String, udid: String) async {
        lastError = nil
        phase = .preparing
        savePreference(udid: udid, bundleID: bundleID)
        let source: any CameraFrameSource
        switch selectedKind {
        case .testPattern:
            source = TestPatternSource()
        case .webcam:
            source = WebcamSource()
        case .videoFile:
            guard let url = videoFileURL else {
                lastError = "Pick a video file first."
                phase = .error(lastError ?? "")
                return
            }
            source = VideoFileSource(url: url)
        case .screenRegion:
            if #available(macOS 13.0, *) {
                source = ScreenRegionSource(target: .display(displayID: nil))
            } else {
                lastError = "Screen Region source requires macOS 13+."
                phase = .error(lastError ?? "")
                return
            }
        }
        do {
            try await coordinator.injectAndLaunch(
                bundleIdentifier: bundleID,
                on: udid,
                source: source
            )
            let pid = await coordinator.activePID
            activePID = pid
            phase = .running(port: transportState.port ?? 0, pid: pid)
        } catch {
            lastError = error.localizedDescription
            phase = .error(error.localizedDescription)
            await coordinator.stop()
        }
    }

    func stop() async {
        phase = .stopping
        await coordinator.stop()
        activePID = nil
        phase = .idle
    }

    // MARK: - Preferences

    /// Loads the persisted preference (if any) for this app on this simulator
    /// and applies it to the UI-facing fields. Call from `.onAppear` once the
    /// inspector has a selected bundle ID + UDID.
    func loadPreference(udid: String, bundleID: String) {
        guard let pref = preferences.preference(udid: udid, bundleID: bundleID) else {
            return
        }
        selectedKind = pref.kind
        jpegQuality = pref.jpegQuality
        if let bookmark = pref.videoFileBookmark,
           let url = resolveBookmark(bookmark) {
            videoFileURL = url
        }
    }

    private func savePreference(udid: String, bundleID: String) {
        let bookmark: Data? = {
            guard selectedKind == .videoFile, let url = videoFileURL else { return nil }
            return try? url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }()
        let pref = CameraSourcePreference(
            kind: selectedKind,
            videoFileBookmark: bookmark,
            screenWindowID: nil,
            jpegQuality: jpegQuality
        )
        preferences.save(pref, udid: udid, bundleID: bundleID)
    }

    private func resolveBookmark(_ data: Data) -> URL? {
        var isStale = false
        return try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
    }

    /// Builds an Xcode scheme env-var snippet for developers who Cmd-R from
    /// Xcode rather than going through XTop's launch button.
    func xcodeSchemeSnippet() async -> String {
        let port = transportState.port ?? 0
        let shimPath = (try? CameraShimBundle.resolvedURL().path) ?? "<missing-shim>"
        return """
        DYLD_INSERT_LIBRARIES = \(shimPath)
        XTOP_CAMERA_PORT = \(port)
        XTOP_CAMERA_TOKEN = <token printed at launch>
        """
    }
}
