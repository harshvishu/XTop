import Foundation
import Testing
@testable import XTop

@Suite("GitMonitorStorage")
struct GitMonitorStorageTests {

    @Test("Repository store deduplicates canonical paths")
    func repositoryStoreCanonicalDeduplication() async throws {
        let defaults = try makeDefaultsSuite()
        let store = GitRepositoryRegistryStore(defaults: defaults)

        let first = await store.upsertRepository(path: "/tmp/repo", displayName: "Repo")
        let second = await store.upsertRepository(path: "/tmp/./repo", displayName: "Repo Again")

        let registry = await store.load()
        #expect(first.id == second.id)
        #expect(registry.repositories.count == 1)
    }

    @Test("Account profile store persists metadata without secrets")
    func accountProfileStorePersistsMetadata() async throws {
        let defaults = try makeDefaultsSuite()
        let store = GitAccountProfileStore(defaults: defaults)

        let profile = GitMonitorAccountProfile(
            displayName: "Work",
            host: "github.com",
            username: "harsh",
            authMode: .httpsToken
        )

        _ = await store.upsertProfile(profile)
        let loaded = await store.loadProfiles()

        #expect(loaded.count == 1)
        #expect(loaded[0].displayName == "Work")
        #expect(loaded[0].authMode == .httpsToken)
    }

    @Test("Credential manager create read delete lifecycle")
    func credentialManagerLifecycle() async throws {
        let defaults = try makeDefaultsSuite()
        let profileStore = GitAccountProfileStore(defaults: defaults)
        let secureStore = InMemoryGitCredentialSecureStore()
        let manager = GitAccountCredentialManager(
            profileStore: profileStore,
            secureStore: secureStore
        )

        let profile = try await manager.createHTTPSProfile(
            displayName: "Primary",
            host: "github.com",
            username: "harsh",
            token: "token-123"
        )

        let storedSecret = try await manager.secret(
            profileID: profile.id,
            kind: .httpsToken
        )
        #expect(storedSecret == "token-123")

        try await manager.logout(profileID: profile.id)

        let removedSecret = try await manager.secret(
            profileID: profile.id,
            kind: .httpsToken
        )
        #expect(removedSecret == nil)
    }

    @Test("GitMonitoredRepository decodes when new metadata fields are missing")
    func monitoredRepositoryBackwardDecodeCompatibility() throws {
        let json = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "displayName": "Repo",
          "path": "/tmp/repo",
          "canonicalPath": "/tmp/repo",
          "isPrimary": true,
          "isActive": true,
          "boundAccountProfileID": null,
          "createdAt": "2026-01-01T00:00:00Z",
          "updatedAt": "2026-01-01T00:00:00Z",
          "lastSeenAt": "2026-01-01T00:00:00Z"
        }
        """

        let decoder = JSONDecoder()
        let data = try #require(json.data(using: .utf8))
        let decoded = try decoder.decode(GitMonitoredRepository.self, from: data)

        #expect(decoded.xcodeProjectType == nil)
        #expect(decoded.detectedProjectFilePath == nil)
    }

    private func makeDefaultsSuite() throws -> UserDefaults {
        let suite = "GitMonitorStorageTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            throw NSError(domain: "GitMonitorStorageTests", code: 1)
        }
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
