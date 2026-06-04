import Foundation
import Testing
@testable import XTop

@Suite("CameraSourcePreferenceStore")
struct CameraSourcePreferenceStoreTests {
    private func makeIsolatedDefaults() -> UserDefaults {
        let suiteName = "XTopTests.CameraSourcePreferenceStore.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @Test func roundTripsPreferencePerAppAndSimulator() throws {
        let defaults = makeIsolatedDefaults()
        let store = CameraSourcePreferenceStore(defaults: defaults)

        let pref = CameraSourcePreference(
            kind: .webcam,
            videoFileBookmark: nil,
            screenWindowID: nil,
            jpegQuality: 0.42
        )
        store.save(pref, udid: "UDID-A", bundleID: "com.example.alpha")

        let loaded = store.preference(udid: "UDID-A", bundleID: "com.example.alpha")
        #expect(loaded == pref)
    }

    @Test func returnsNilForUnknownKey() throws {
        let defaults = makeIsolatedDefaults()
        let store = CameraSourcePreferenceStore(defaults: defaults)
        #expect(store.preference(udid: "missing", bundleID: "com.example") == nil)
    }

    @Test func preferencesAreNamespacedPerUDIDAndBundle() throws {
        let defaults = makeIsolatedDefaults()
        let store = CameraSourcePreferenceStore(defaults: defaults)

        let a = CameraSourcePreference(kind: .testPattern, videoFileBookmark: nil, screenWindowID: nil, jpegQuality: 0.5)
        let b = CameraSourcePreference(kind: .videoFile, videoFileBookmark: nil, screenWindowID: nil, jpegQuality: 0.9)
        store.save(a, udid: "UDID-1", bundleID: "com.example.app")
        store.save(b, udid: "UDID-2", bundleID: "com.example.app")

        #expect(store.preference(udid: "UDID-1", bundleID: "com.example.app")?.kind == .testPattern)
        #expect(store.preference(udid: "UDID-2", bundleID: "com.example.app")?.kind == .videoFile)
    }
}
