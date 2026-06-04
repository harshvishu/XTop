import Foundation

/// Persists the user's last-used `CameraSourcePreference` keyed by
/// `<UDID>|<bundleID>`. Stored as a `[String: Data]` JSON blob under a
/// single UserDefaults key so we don't pollute the defaults namespace.
struct CameraSourcePreferenceStore: Sendable {
    static let defaultsKey = "SimulatorInspector.cameraSourcePreferences"

    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    static func makeKey(udid: String, bundleID: String) -> String {
        "\(udid)|\(bundleID)"
    }

    func preference(udid: String, bundleID: String) -> CameraSourcePreference? {
        guard let blob = defaults.dictionary(forKey: Self.defaultsKey) as? [String: Data] else {
            return nil
        }
        guard let data = blob[Self.makeKey(udid: udid, bundleID: bundleID)] else {
            return nil
        }
        return try? JSONDecoder().decode(CameraSourcePreference.self, from: data)
    }

    func save(_ preference: CameraSourcePreference, udid: String, bundleID: String) {
        guard let data = try? JSONEncoder().encode(preference) else { return }
        var blob = (defaults.dictionary(forKey: Self.defaultsKey) as? [String: Data]) ?? [:]
        blob[Self.makeKey(udid: udid, bundleID: bundleID)] = data
        defaults.set(blob, forKey: Self.defaultsKey)
    }
}
