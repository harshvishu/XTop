import Foundation

/// Persists `GridOverlayConfig` per simulator UDID using `UserDefaults`.
///
/// The store keeps an in-memory dictionary mirror so callers can fetch a
/// config without an async hop, and writes through to disk immediately on
/// each update. Concurrent access is mediated by an internal queue.
final class GridOverlayConfigStore: @unchecked Sendable {
    static let defaultsKey = "SimulatorInspector.GridOverlay.configs"

    private let defaults: UserDefaults
    private let key: String
    private let queue = DispatchQueue(label: "xtop.gridOverlay.configStore")
    private var cache: [String: GridOverlayConfig]

    init(defaults: UserDefaults = .standard, key: String = GridOverlayConfigStore.defaultsKey) {
        self.defaults = defaults
        self.key = key
        self.cache = GridOverlayConfigStore.load(defaults: defaults, key: key)
    }

    /// Returns the persisted configuration for the UDID, or
    /// `GridOverlayConfig.default` if none is stored yet.
    func config(forUDID udid: String) -> GridOverlayConfig {
        queue.sync {
            cache[udid] ?? .default
        }
    }

    /// Stores a configuration for the UDID and writes through to defaults.
    func setConfig(_ config: GridOverlayConfig, forUDID udid: String) {
        queue.sync {
            cache[udid] = config
            persistLocked()
        }
    }

    /// Removes the stored configuration for a UDID (resets to defaults).
    func clearConfig(forUDID udid: String) {
        queue.sync {
            cache.removeValue(forKey: udid)
            persistLocked()
        }
    }

    private func persistLocked() {
        do {
            let data = try JSONEncoder().encode(cache)
            defaults.set(data, forKey: key)
        } catch {
            // Encoding a [String: GridOverlayConfig] should never fail.
            assertionFailure("Failed to encode GridOverlayConfig store: \(error)")
        }
    }

    private static func load(defaults: UserDefaults, key: String) -> [String: GridOverlayConfig] {
        guard let data = defaults.data(forKey: key) else { return [:] }
        do {
            return try JSONDecoder().decode([String: GridOverlayConfig].self, from: data)
        } catch {
            return [:]
        }
    }
}
