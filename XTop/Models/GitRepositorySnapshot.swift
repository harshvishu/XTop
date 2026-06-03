import Foundation

struct GitRepositorySnapshot: Codable, Sendable {
    let repositoryID: UUID
    let branch: String?
    let stagedCount: Int
    let unstagedCount: Int
    let untrackedCount: Int
    let aheadBy: Int?
    let behindBy: Int?
    let headCommitDate: Date?
    let lastLocalSyncAt: Date?
    let lastRemoteSyncAt: Date?
    let syncState: GitMonitorSyncState
    let lastErrorMessage: String?
    let configuredUserName: String?
    let configuredUserEmail: String?
    let remoteURL: String?

    nonisolated init(
        repositoryID: UUID,
        branch: String? = nil,
        stagedCount: Int = 0,
        unstagedCount: Int = 0,
        untrackedCount: Int = 0,
        aheadBy: Int? = nil,
        behindBy: Int? = nil,
        headCommitDate: Date? = nil,
        lastLocalSyncAt: Date? = nil,
        lastRemoteSyncAt: Date? = nil,
        syncState: GitMonitorSyncState = .idle,
        lastErrorMessage: String? = nil,
        configuredUserName: String? = nil,
        configuredUserEmail: String? = nil,
        remoteURL: String? = nil
    ) {
        self.repositoryID = repositoryID
        self.branch = branch
        self.stagedCount = stagedCount
        self.unstagedCount = unstagedCount
        self.untrackedCount = untrackedCount
        self.aheadBy = aheadBy
        self.behindBy = behindBy
        self.headCommitDate = headCommitDate
        self.lastLocalSyncAt = lastLocalSyncAt
        self.lastRemoteSyncAt = lastRemoteSyncAt
        self.syncState = syncState
        self.lastErrorMessage = lastErrorMessage
        self.configuredUserName = configuredUserName
        self.configuredUserEmail = configuredUserEmail
        self.remoteURL = remoteURL
    }
}
