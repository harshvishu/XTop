import Foundation

actor GitAccountCredentialManager {
    private let profileStore: GitAccountProfileStore
    private let secureStore: GitCredentialSecureStore

    nonisolated init(
        profileStore: GitAccountProfileStore,
        secureStore: GitCredentialSecureStore
    ) {
        self.profileStore = profileStore
        self.secureStore = secureStore
    }

    @discardableResult
    func createHTTPSProfile(
        displayName: String,
        host: String,
        username: String,
        token: String
    ) async throws -> GitMonitorAccountProfile {
        var profile = GitMonitorAccountProfile(
            displayName: displayName,
            host: host,
            username: username,
            authMode: .httpsToken
        )
        profile.updatedAt = .now

        let stored = await profileStore.upsertProfile(profile)
        let key = GitCredentialSecretKey(profileID: stored.id, kind: .httpsToken)
        try await secureStore.saveSecret(token, for: key)
        return stored
    }

    @discardableResult
    func createSSHProfile(
        displayName: String,
        host: String,
        username: String,
        privateKeyPath: String,
        publicKeyFingerprint: String,
        passphrase: String?
    ) async throws -> GitMonitorAccountProfile {
        var profile = GitMonitorAccountProfile(
            displayName: displayName,
            host: host,
            username: username,
            authMode: .sshKey,
            sshPrivateKeyPath: privateKeyPath,
            sshPublicKeyFingerprint: publicKeyFingerprint
        )
        profile.updatedAt = .now

        let stored = await profileStore.upsertProfile(profile)
        if let passphrase, !passphrase.isEmpty {
            let key = GitCredentialSecretKey(profileID: stored.id, kind: .sshPassphrase)
            try await secureStore.saveSecret(passphrase, for: key)
        }

        return stored
    }

    func secret(
        profileID: UUID,
        kind: GitCredentialSecretKind
    ) async throws -> String? {
        try await secureStore.readSecret(
            for: GitCredentialSecretKey(
                profileID: profileID,
                kind: kind
            )
        )
    }

    func logout(profileID: UUID) async throws {
        try await secureStore.deleteSecrets(for: profileID)
    }
}
