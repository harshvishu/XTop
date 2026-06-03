import Foundation
import Testing
@testable import XTop

@Suite("UserDefaultsStore")
struct UserDefaultsStoreTests {
    private func makeTempPlistURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "xtop-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "test.plist", directoryHint: .notDirectory)
    }

    @Test func roundTripsAllSupportedScalarTypes() async throws {
        let url = makeTempPlistURL()
        let store = UserDefaultsStore()

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let blob = Data([0x01, 0x02, 0x03])

        try await store.add(key: "bool", value: NSNumber(value: true), at: url)
        try await store.add(key: "int", value: NSNumber(value: 42), at: url)
        try await store.add(key: "double", value: NSNumber(value: 3.5), at: url)
        try await store.add(key: "string", value: "hello", at: url)
        try await store.add(key: "date", value: now, at: url)
        try await store.add(key: "data", value: blob, at: url)

        let entries = try await store.loadEntries(at: url)
        let byKey = Dictionary(uniqueKeysWithValues: entries.map { ($0.key, $0) })
        #expect(byKey["bool"]?.type == .bool)
        #expect(byKey["int"]?.type == .integer)
        #expect(byKey["double"]?.type == .double)
        #expect(byKey["string"]?.type == .string)
        #expect(byKey["date"]?.type == .date)
        #expect(byKey["data"]?.type == .data)

        let raw = try await store.rawValue(forKey: "string", at: url)
        #expect(raw as? String == "hello")
    }

    @Test func roundTripsNestedArrayAndDictionary() async throws {
        let url = makeTempPlistURL()
        let store = UserDefaultsStore()

        let array: [Any] = ["a", NSNumber(value: 1), NSNumber(value: true)]
        let dict: [String: Any] = ["nested": NSNumber(value: 7), "label": "x"]

        try await store.add(key: "array", value: array, at: url)
        try await store.add(key: "dict", value: dict, at: url)

        let entries = try await store.loadEntries(at: url)
        let byKey = Dictionary(uniqueKeysWithValues: entries.map { ($0.key, $0) })
        #expect(byKey["array"]?.type == .array)
        #expect(byKey["dict"]?.type == .dictionary)

        let readArray = try await store.rawValue(forKey: "array", at: url) as? [Any]
        #expect(readArray?.count == 3)
        let readDict = try await store.rawValue(forKey: "dict", at: url) as? [String: Any]
        #expect(readDict?["nested"] as? Int == 7)
    }

    @Test func updatePreservesValueAndDeleteRemovesIt() async throws {
        let url = makeTempPlistURL()
        let store = UserDefaultsStore()

        try await store.add(key: "k", value: NSNumber(value: 1), at: url)
        try await store.update(key: "k", to: NSNumber(value: 99), at: url)
        let value = try await store.rawValue(forKey: "k", at: url) as? Int
        #expect(value == 99)

        try await store.delete(key: "k", at: url)
        let after = try await store.rawValue(forKey: "k", at: url)
        #expect(after == nil)
    }

    @Test func addingDuplicateKeyThrows() async throws {
        let url = makeTempPlistURL()
        let store = UserDefaultsStore()
        try await store.add(key: "k", value: "v1", at: url)
        await #expect(throws: UserDefaultsStore.StoreError.self) {
            try await store.add(key: "k", value: "v2", at: url)
        }
    }
}
