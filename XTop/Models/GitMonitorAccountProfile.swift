import Foundation

struct GitMonitorAccountProfile: Codable, Identifiable, Sendable {
    let id: UUID
    var displayName: String
    var host: String
    var username: String
    var authMode: GitMonitorAuthMode
    var sshPrivateKeyPath: String?
    var sshPublicKeyFingerprint: String?
    var createdAt: Date
    var updatedAt: Date

    nonisolated init(
        id: UUID = UUID(),
        displayName: String,
        host: String,
        username: String,
        authMode: GitMonitorAuthMode,
        sshPrivateKeyPath: String? = nil,
        sshPublicKeyFingerprint: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.displayName = displayName
        self.host = host
        self.username = username
        self.authMode = authMode
        self.sshPrivateKeyPath = sshPrivateKeyPath
        self.sshPublicKeyFingerprint = sshPublicKeyFingerprint
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
