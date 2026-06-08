import Foundation
import Testing
@testable import XTop

@Suite("GitMonitorRegistryLifecycle")
struct GitMonitorRegistryLifecycleTests {

    @Test("First inserted repository is auto-primary")
    func firstRepositoryBecomesPrimary() async throws {
        let store = GitRepositoryRegistryStore(defaults: try makeDefaults())
        let repo = await store.upsertRepository(path: "/tmp/a", displayName: "A")
        let registry = await store.load()
        #expect(repo.isPrimary)
        #expect(registry.repositories.count == 1)
        #expect(registry.repositories[0].isPrimary)
    }

    @Test("Removing primary promotes another active repository")
    func removingPrimaryPromotesNext() async throws {
        let store = GitRepositoryRegistryStore(defaults: try makeDefaults())
        let primary = await store.upsertRepository(path: "/tmp/a", displayName: "A")
        _ = await store.upsertRepository(path: "/tmp/b", displayName: "B")

        await store.removeRepository(id: primary.id)
        let registry = await store.load()

        #expect(registry.repositories.count == 1)
        #expect(registry.repositories[0].isPrimary)
        #expect(registry.repositories[0].canonicalPath.hasSuffix("/tmp/b/"))
    }

    @Test("Set primary clears prior primary flag")
    func setPrimaryClearsPrevious() async throws {
        let store = GitRepositoryRegistryStore(defaults: try makeDefaults())
        let first = await store.upsertRepository(path: "/tmp/a", displayName: "A")
        let second = await store.upsertRepository(path: "/tmp/b", displayName: "B")

        await store.setPrimaryRepository(second.id)
        let registry = await store.load()

        let firstStored = registry.repositories.first(where: { $0.id == first.id })
        let secondStored = registry.repositories.first(where: { $0.id == second.id })
        #expect(firstStored?.isPrimary == false)
        #expect(secondStored?.isPrimary == true)
    }

    @Test("Mark inactive transitions repo and reassigns primary")
    func markInactiveReassignsPrimary() async throws {
        let store = GitRepositoryRegistryStore(defaults: try makeDefaults())
        let first = await store.upsertRepository(path: "/tmp/a", displayName: "A")
        _ = await store.upsertRepository(path: "/tmp/b", displayName: "B")

        await store.markInactive(repositoryID: first.id)
        let registry = await store.load()

        let firstStored = registry.repositories.first(where: { $0.id == first.id })
        let activePrimary = registry.repositories.first(where: { $0.isPrimary })
        #expect(firstStored?.isActive == false)
        #expect(firstStored?.isPrimary == false)
        #expect(activePrimary?.canonicalPath.hasSuffix("/tmp/b/") == true)
    }

    @Test("Reconcile reactivates and deactivates based on reachability")
    func reconcileReactivatesAndDeactivates() async throws {
        let store = GitRepositoryRegistryStore(defaults: try makeDefaults())
        let first = await store.upsertRepository(path: "/tmp/a", displayName: "A")
        _ = await store.upsertRepository(path: "/tmp/b", displayName: "B")
        await store.markInactive(repositoryID: first.id)

        let canonicalA = await store.repositories().first(where: { $0.id == first.id })!.canonicalPath
        await store.reconcileActiveRepositories(reachableCanonicalPaths: [canonicalA])

        let registry = await store.load()
        let firstStored = registry.repositories.first(where: { $0.id == first.id })
        let secondStored = registry.repositories.first(where: { $0.canonicalPath.hasSuffix("/tmp/b/") })
        #expect(firstStored?.isActive == true)
        #expect(secondStored?.isActive == false)
        #expect(registry.repositories.contains(where: { $0.isPrimary && $0.isActive }))
    }

    @Test("Bind repository sets bound account profile id")
    func bindRepositoryAssignsProfile() async throws {
        let store = GitRepositoryRegistryStore(defaults: try makeDefaults())
        let repo = await store.upsertRepository(path: "/tmp/a", displayName: "A")
        let profileID = UUID()

        await store.bindRepository(repo.id, accountProfileID: profileID)
        let registry = await store.load()

        #expect(registry.repositories[0].boundAccountProfileID == profileID)

        await store.bindRepository(repo.id, accountProfileID: nil)
        let cleared = await store.load()
        #expect(cleared.repositories[0].boundAccountProfileID == nil)
    }

    @Test("Repository metadata updates persist project type")
    func repositoryMetadataPersists() async throws {
        let store = GitRepositoryRegistryStore(defaults: try makeDefaults())
        let repo = await store.upsertRepository(path: "/tmp/a", displayName: "A")

        await store.updateRepositoryMetadata(
            id: repo.id,
            xcodeProjectType: .xcodeproj,
            detectedProjectFilePath: "/tmp/a/App.xcodeproj"
        )

        let registry = await store.load()
        let stored = registry.repositories.first(where: { $0.id == repo.id })
        #expect(stored?.xcodeProjectType == .xcodeproj)
        #expect(stored?.detectedProjectFilePath == "/tmp/a/App.xcodeproj")
    }

    private func makeDefaults() throws -> UserDefaults {
        let suite = "GitMonitorRegistryLifecycleTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            throw NSError(domain: "GitMonitorRegistryLifecycleTests", code: 1)
        }
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
