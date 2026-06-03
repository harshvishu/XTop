import Foundation

actor DefaultGitMonitorService: GitMonitorService {
    private let syncConcurrencyLimit = 4
    private let syncTimeout: Duration = .seconds(20)

    private let fileManager: FileManager
    private let repositoryStore: GitRepositoryRegistryStore
    private let profileStore: GitAccountProfileStore
    private let credentialManager: GitAccountCredentialManager
    private let remoteGateway: GitRemoteCommandGateway

    nonisolated init(
        runner: CommandRunner = CommandRunner(),
        repositoryStore: GitRepositoryRegistryStore = GitRepositoryRegistryStore(),
        profileStore: GitAccountProfileStore = GitAccountProfileStore(),
        secureStore: GitCredentialSecureStore = KeychainGitCredentialSecureStore(),
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.repositoryStore = repositoryStore
        self.profileStore = profileStore
        self.credentialManager = GitAccountCredentialManager(
            profileStore: profileStore,
            secureStore: secureStore
        )
        self.remoteGateway = GitRemoteCommandGateway(runner: runner)
    }

    func loadRegistry() async -> GitMonitorRegistry {
        await repositoryStore.load()
    }

    func loadProfiles() async -> [GitMonitorAccountProfile] {
        await profileStore.loadProfiles()
    }

    func setBaseFolders(_ folders: [String]) async {
        await repositoryStore.setBaseFolders(folders)
    }

    func upsertRepository(
        path: String,
        displayName: String?,
        boundAccountProfileID: UUID?
    ) async -> GitMonitoredRepository {
        await repositoryStore.upsertRepository(
            path: path,
            displayName: displayName,
            boundAccountProfileID: boundAccountProfileID
        )
    }

    func removeRepository(id: UUID) async {
        await repositoryStore.removeRepository(id: id)
    }

    func bindRepository(id: UUID, accountProfileID: UUID?) async {
        await repositoryStore.bindRepository(id, accountProfileID: accountProfileID)
    }

    func setPrimaryRepository(id: UUID) async {
        await repositoryStore.setPrimaryRepository(id)
    }

    func clearPrimaryRepository(id: UUID) async {
        await repositoryStore.clearPrimaryRepository(id)
    }

    func createHTTPSProfile(
        displayName: String,
        host: String,
        username: String,
        token: String
    ) async throws -> GitMonitorAccountProfile {
        try await credentialManager.createHTTPSProfile(
            displayName: displayName,
            host: host,
            username: username,
            token: token
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
        try await credentialManager.createSSHProfile(
            displayName: displayName,
            host: host,
            username: username,
            privateKeyPath: privateKeyPath,
            publicKeyFingerprint: publicKeyFingerprint,
            passphrase: passphrase
        )
    }

    func logoutProfile(id: UUID) async throws {
        try await credentialManager.logout(profileID: id)
    }

    func runDeepDiscovery() async -> [GitMonitoredRepository] {
        let registry = await repositoryStore.load()
        guard !registry.baseFolders.isEmpty else {
            return registry.repositories
        }

        var discoveredCanonicalPaths = Set<String>()

        for baseFolder in registry.baseFolders {
            let discovered = discoverRepositories(in: baseFolder)
            for repositoryPath in discovered {
                let repository = await repositoryStore.upsertRepository(path: repositoryPath)
                discoveredCanonicalPaths.insert(repository.canonicalPath)
            }
        }

        await repositoryStore.reconcileActiveRepositories(reachableCanonicalPaths: discoveredCanonicalPaths)
        return await repositoryStore.repositories()
    }

    func refreshAllActiveRepositories() async -> [GitRepositorySnapshot] {
        let repositories = await repositoryStore.repositories().filter { $0.isActive }
        guard !repositories.isEmpty else {
            return []
        }

        var snapshots: [GitRepositorySnapshot] = []
        snapshots.reserveCapacity(repositories.count)

        var iterator = repositories.makeIterator()
        let initialWorkers = min(syncConcurrencyLimit, repositories.count)

        await withTaskGroup(of: GitRepositorySnapshot.self) { group in
            for _ in 0..<initialWorkers {
                guard let repository = iterator.next() else { break }
                group.addTask { [self] in
                    await refreshSnapshotWithTimeout(for: repository)
                }
            }

            while let snapshot = await group.next() {
                snapshots.append(snapshot)

                if let nextRepository = iterator.next() {
                    group.addTask { [self] in
                        await refreshSnapshotWithTimeout(for: nextRepository)
                    }
                }
            }
        }

        return snapshots
    }

    private func refreshSnapshotWithTimeout(
        for repository: GitMonitoredRepository
    ) async -> GitRepositorySnapshot {
        return await withTaskGroup(of: GitRepositorySnapshot.self) { group in
            group.addTask { [self] in
                await refreshSnapshot(for: repository)
            }

            group.addTask {
                try? await Task.sleep(for: self.syncTimeout)
                return GitRepositorySnapshot(
                    repositoryID: repository.id,
                    syncState: .timeout,
                    lastErrorMessage: "Sync operation timed out."
                )
            }

            let first = await group.next() ?? GitRepositorySnapshot(
                repositoryID: repository.id,
                syncState: .failed,
                lastErrorMessage: "Sync operation cancelled before producing a result."
            )
            group.cancelAll()
            return first
        }
    }

    private func refreshSnapshot(
        for repository: GitMonitoredRepository
    ) async -> GitRepositorySnapshot {
        let local = await collectLocalSnapshot(for: repository)

        let fetchResult = await remoteGateway.runGitCommand(
            repositoryPath: repository.path,
            arguments: ["fetch", "--quiet"],
            accountProfile: nil
        )

        guard fetchResult.succeeded else {
            return GitRepositorySnapshot(
                repositoryID: repository.id,
                branch: local.branch,
                stagedCount: local.stagedCount,
                unstagedCount: local.unstagedCount,
                untrackedCount: local.untrackedCount,
                aheadBy: nil,
                behindBy: nil,
                headCommitDate: local.headCommitDate,
                lastLocalSyncAt: .now,
                lastRemoteSyncAt: nil,
                syncState: classifyRemoteFailure(fetchResult.stderr),
                lastErrorMessage: fetchResult.stderr.trimmingCharacters(in: .whitespacesAndNewlines),
                configuredUserName: local.userName,
                configuredUserEmail: local.userEmail,
                remoteURL: local.remoteURL
            )
        }

        let aheadBehind = await remoteGateway.runGitCommand(
            repositoryPath: repository.path,
            arguments: ["rev-list", "--left-right", "--count", "@{upstream}...HEAD"],
            accountProfile: nil
        )

        let (behind, ahead) = parseAheadBehind(aheadBehind.stdout)

        return GitRepositorySnapshot(
            repositoryID: repository.id,
            branch: local.branch,
            stagedCount: local.stagedCount,
            unstagedCount: local.unstagedCount,
            untrackedCount: local.untrackedCount,
            aheadBy: ahead,
            behindBy: behind,
            headCommitDate: local.headCommitDate,
            lastLocalSyncAt: .now,
            lastRemoteSyncAt: .now,
            syncState: .healthy,
            lastErrorMessage: nil,
            configuredUserName: local.userName,
            configuredUserEmail: local.userEmail,
            remoteURL: local.remoteURL
        )
    }

    private func collectLocalSnapshot(
        for repository: GitMonitoredRepository
    ) async -> (branch: String?, stagedCount: Int, unstagedCount: Int, untrackedCount: Int, headCommitDate: Date?, userName: String?, userEmail: String?, remoteURL: String?) {
        let branchResult = await remoteGateway.runGitCommand(
            repositoryPath: repository.path,
            arguments: ["branch", "--show-current"],
            accountProfile: nil
        )
        let branch = branchResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)

        let statusResult = await remoteGateway.runGitCommand(
            repositoryPath: repository.path,
            arguments: ["status", "--porcelain"],
            accountProfile: nil
        )
        let counts = parseStatusCounts(statusResult.stdout)

        let commitDateResult = await remoteGateway.runGitCommand(
            repositoryPath: repository.path,
            arguments: ["log", "-1", "--format=%cI"],
            accountProfile: nil
        )
        let commitDate = parseCommitDate(commitDateResult.stdout)

        let userNameResult = await remoteGateway.runGitCommand(
            repositoryPath: repository.path,
            arguments: ["config", "user.name"],
            accountProfile: nil
        )
        let userEmailResult = await remoteGateway.runGitCommand(
            repositoryPath: repository.path,
            arguments: ["config", "user.email"],
            accountProfile: nil
        )
        let remoteURLResult = await remoteGateway.runGitCommand(
            repositoryPath: repository.path,
            arguments: ["config", "--get", "remote.origin.url"],
            accountProfile: nil
        )

        return (
            branch.isEmpty ? nil : branch,
            counts.staged,
            counts.unstaged,
            counts.untracked,
            commitDate,
            nonEmpty(userNameResult.stdout),
            nonEmpty(userEmailResult.stdout),
            nonEmpty(remoteURLResult.stdout)
        )
    }

    private func nonEmpty(_ stdout: String) -> String? {
        let trimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func discoverRepositories(in basePath: String) -> [String] {
        guard let enumerator = fileManager.enumerator(
            at: URL(filePath: basePath),
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsPackageDescendants, .skipsHiddenFiles]
        ) else {
            return []
        }

        let ignoredNames = Set([
            ".build", "DerivedData", "node_modules", "Pods", ".swiftpm", ".git"
        ])

        var discovered: Set<String> = []

        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            if ignoredNames.contains(name) {
                enumerator.skipDescendants()
                continue
            }

            let gitPath = url.appending(path: ".git").path()
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: gitPath, isDirectory: &isDirectory) {
                let canonical = url.standardized.resolvingSymlinksInPath().path()
                discovered.insert(canonical)
                enumerator.skipDescendants()
            }
        }

        return discovered.sorted()
    }

    private func parseStatusCounts(_ stdout: String) -> (staged: Int, unstaged: Int, untracked: Int) {
        var staged = 0
        var unstaged = 0
        var untracked = 0

        for line in stdout.split(separator: "\n") {
            guard line.count >= 2 else { continue }
            let chars = Array(line)
            let x = chars[0]
            let y = chars[1]

            if x == "?" && y == "?" {
                untracked += 1
                continue
            }

            if x != " " {
                staged += 1
            }

            if y != " " {
                unstaged += 1
            }
        }

        return (staged, unstaged, untracked)
    }

    private func parseCommitDate(_ stdout: String) -> Date? {
        let text = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return try? Date(text, strategy: .iso8601)
    }

    private func parseAheadBehind(_ stdout: String) -> (behind: Int?, ahead: Int?) {
        let fields = stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })
        guard fields.count == 2 else {
            return (nil, nil)
        }

        return (Int(fields[0]), Int(fields[1]))
    }

    private func classifyRemoteFailure(_ stderr: String) -> GitMonitorSyncState {
        Self.classifyRemoteFailure(stderr)
    }

    nonisolated static func classifyRemoteFailure(_ stderr: String) -> GitMonitorSyncState {
        let normalized = stderr.lowercased()
        if normalized.contains("timed out") || normalized.contains("timeout") {
            return .timeout
        }
        if normalized.contains("permission denied") || normalized.contains("authentication") || normalized.contains("could not read from remote repository") {
            return .authRequired
        }

        return .failed
    }
}
