import Foundation

actor GitAccountProfileStore {
    private enum Keys {
        static let profiles = "gitMonitor.accountProfiles"
    }

    private let defaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    nonisolated init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    func loadProfiles() -> [GitMonitorAccountProfile] {
        guard let data = defaults.data(forKey: Keys.profiles) else {
            return []
        }

        return (try? decoder.decode([GitMonitorAccountProfile].self, from: data)) ?? []
    }

    @discardableResult
    func upsertProfile(_ profile: GitMonitorAccountProfile) -> GitMonitorAccountProfile {
        var profiles = loadProfiles()

        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }

        persist(profiles)
        return profile
    }

    func removeProfile(profileID: UUID) {
        var profiles = loadProfiles()
        profiles.removeAll { $0.id == profileID }
        persist(profiles)
    }

    func profile(profileID: UUID) -> GitMonitorAccountProfile? {
        loadProfiles().first { $0.id == profileID }
    }

    private func persist(_ profiles: [GitMonitorAccountProfile]) {
        guard let data = try? encoder.encode(profiles) else {
            return
        }

        defaults.set(data, forKey: Keys.profiles)
    }
}
