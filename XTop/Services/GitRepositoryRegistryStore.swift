import Foundation

actor GitRepositoryRegistryStore {
    private enum Keys {
        static let registry = "gitMonitor.registry"
    }

    private let defaults: UserDefaults
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    nonisolated init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    func load() -> GitMonitorRegistry {
        guard let data = defaults.data(forKey: Keys.registry) else {
            return GitMonitorRegistry()
        }

        return (try? decoder.decode(GitMonitorRegistry.self, from: data)) ?? GitMonitorRegistry()
    }

    func repositories() -> [GitMonitoredRepository] {
        load().repositories
    }

    func setBaseFolders(_ folders: [String]) {
        var registry = load()
        registry.baseFolders = canonicalizeUniquePaths(folders)
        persist(registry)
    }

    @discardableResult
    func upsertRepository(
        path: String,
        displayName: String? = nil,
        boundAccountProfileID: UUID? = nil
    ) -> GitMonitoredRepository {
        var registry = load()
        let canonicalPath = canonicalPath(for: path)
        let fallbackName = URL(filePath: canonicalPath).lastPathComponent

        if let index = registry.repositories.firstIndex(where: { $0.canonicalPath == canonicalPath }) {
            registry.repositories[index].path = path
            registry.repositories[index].displayName = displayName ?? registry.repositories[index].displayName
            registry.repositories[index].boundAccountProfileID = boundAccountProfileID ?? registry.repositories[index].boundAccountProfileID
            registry.repositories[index].isActive = true
            registry.repositories[index].lastSeenAt = .now
            registry.repositories[index].updatedAt = .now
            let updated = registry.repositories[index]
            persist(registry)
            return updated
        }

        let isPrimary = registry.repositories.isEmpty
        let repository = GitMonitoredRepository(
            displayName: displayName ?? fallbackName,
            path: path,
            canonicalPath: canonicalPath,
            isPrimary: isPrimary,
            isActive: true,
            boundAccountProfileID: boundAccountProfileID
        )

        registry.repositories.append(repository)
        persist(registry)
        return repository
    }

    func removeRepository(id: UUID) {
        var registry = load()
        let removedWasPrimary = registry.repositories.first(where: { $0.id == id })?.isPrimary ?? false
        registry.repositories.removeAll { $0.id == id }

        if removedWasPrimary,
           let firstActiveIndex = registry.repositories.firstIndex(where: { $0.isActive }) {
            clearPrimary(&registry.repositories)
            registry.repositories[firstActiveIndex].isPrimary = true
        }

        persist(registry)
    }

    func setPrimaryRepository(_ repositoryID: UUID) {
        var registry = load()
        guard let selectedIndex = registry.repositories.firstIndex(where: { $0.id == repositoryID }) else {
            return
        }

        clearPrimary(&registry.repositories)
        registry.repositories[selectedIndex].isPrimary = true
        registry.repositories[selectedIndex].updatedAt = .now
        persist(registry)
    }

    /// Clears the primary flag from the given repository without auto-promoting
    /// another repository to take its place. The registry can be left in a
    /// "no primary" state until the user explicitly designates one again.
    func clearPrimaryRepository(_ repositoryID: UUID) {
        var registry = load()
        guard let index = registry.repositories.firstIndex(where: { $0.id == repositoryID }),
              registry.repositories[index].isPrimary else {
            return
        }
        registry.repositories[index].isPrimary = false
        registry.repositories[index].updatedAt = .now
        persist(registry)
    }

    func bindRepository(_ repositoryID: UUID, accountProfileID: UUID?) {
        var registry = load()
        guard let index = registry.repositories.firstIndex(where: { $0.id == repositoryID }) else {
            return
        }

        registry.repositories[index].boundAccountProfileID = accountProfileID
        registry.repositories[index].updatedAt = .now
        persist(registry)
    }

    func markInactive(repositoryID: UUID) {
        var registry = load()
        guard let index = registry.repositories.firstIndex(where: { $0.id == repositoryID }) else {
            return
        }

        registry.repositories[index].isActive = false
        registry.repositories[index].updatedAt = .now
        registry.repositories[index].isPrimary = false

        if let firstActiveIndex = registry.repositories.firstIndex(where: { $0.isActive }) {
            registry.repositories[firstActiveIndex].isPrimary = true
        }

        persist(registry)
    }

    func reconcileActiveRepositories(reachableCanonicalPaths: Set<String>) {
        var registry = load()

        for index in registry.repositories.indices {
            let isReachable = reachableCanonicalPaths.contains(registry.repositories[index].canonicalPath)
            if isReachable {
                registry.repositories[index].isActive = true
                registry.repositories[index].lastSeenAt = .now
            } else {
                registry.repositories[index].isActive = false
                registry.repositories[index].isPrimary = false
            }
            registry.repositories[index].updatedAt = .now
        }

        if !registry.repositories.contains(where: { $0.isPrimary && $0.isActive }),
           let firstActiveIndex = registry.repositories.firstIndex(where: { $0.isActive }) {
            registry.repositories[firstActiveIndex].isPrimary = true
        }

        persist(registry)
    }

    private func persist(_ registry: GitMonitorRegistry) {
        guard let data = try? encoder.encode(registry) else {
            return
        }

        defaults.set(data, forKey: Keys.registry)
    }

    private func clearPrimary(_ repositories: inout [GitMonitoredRepository]) {
        for index in repositories.indices {
            repositories[index].isPrimary = false
        }
    }

    private func canonicalizeUniquePaths(_ paths: [String]) -> [String] {
        var seen = Set<String>()
        var output: [String] = []

        for path in paths {
            let canonical = canonicalPath(for: path)
            if seen.insert(canonical).inserted {
                output.append(canonical)
            }
        }

        return output
    }

    private func canonicalPath(for path: String) -> String {
        URL(filePath: path)
            .standardized
            .resolvingSymlinksInPath()
            .path()
    }
}
