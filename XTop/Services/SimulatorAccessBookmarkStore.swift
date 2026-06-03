import Foundation
import Observation

/// Persists a security-scoped bookmark granting the app read/write access to
/// the user's `~/Library/Developer/CoreSimulator/Devices/` folder. This is
/// required because XTop runs sandboxed and cannot read that location without
/// the user explicitly granting access once.
@MainActor
@Observable
final class SimulatorAccessBookmarkStore {
    @ObservationIgnored
    private static let defaultsKey = "simulatorInspector.coreSimulatorBookmark.v1"

    private(set) var resolvedURL: URL?
    @ObservationIgnored
    private var isAccessing = false

    init() {
        resolveExistingBookmark()
    }

    /// Returns the canonical absolute path the user should grant access to.
    static var requiredFolderPath: String {
        URL(fileURLWithPath: NSHomeDirectory())
            .appending(path: "Library/Developer/CoreSimulator/Devices", directoryHint: .isDirectory)
            .path(percentEncoded: false)
    }

    /// `true` if a valid security-scoped bookmark is currently active. When the
    /// app runs without the sandbox there is no bookmark to acquire, so we
    /// always report access as available — the developer's normal filesystem
    /// permissions are sufficient to reach `~/Library/Developer/CoreSimulator/`.
    var hasAccess: Bool { true }

    /// Stores a fresh bookmark for the given URL (which the user picked through
    /// `NSOpenPanel`). The URL must point at the canonical CoreSimulator
    /// `Devices` folder for the inspector to work.
    func storeBookmark(for url: URL) throws {
        let data = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        stopAccessingIfNeeded()
        resolvedURL = url
        startAccessingIfNeeded()
    }

    /// Drops the stored bookmark (used for "Reset access" controls in settings).
    func forgetBookmark() {
        stopAccessingIfNeeded()
        UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
        resolvedURL = nil
    }

    private func resolveExistingBookmark() {
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey) else { return }
        var stale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
            resolvedURL = url
            startAccessingIfNeeded()
            if stale {
                try? storeBookmark(for: url)
            }
        } catch {
            resolvedURL = nil
        }
    }

    private func startAccessingIfNeeded() {
        guard let url = resolvedURL, !isAccessing else { return }
        isAccessing = url.startAccessingSecurityScopedResource()
    }

    private func stopAccessingIfNeeded() {
        guard let url = resolvedURL, isAccessing else { return }
        url.stopAccessingSecurityScopedResource()
        isAccessing = false
    }
}
