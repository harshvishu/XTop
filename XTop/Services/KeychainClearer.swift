import Foundation

/// Deletes a simulator's keychain database files. v1 clear-all only; per-item
/// inspection is intentionally out of scope.
actor KeychainClearer {
    enum ClearError: Error, LocalizedError, Sendable {
        case missingDataContainer
        case removalFailed(path: String, underlying: Error)

        var errorDescription: String? {
            switch self {
            case .missingDataContainer:
                return "Simulator data container not found."
            case let .removalFailed(path, error):
                return "Failed to remove \(path): \(error.localizedDescription)"
            }
        }
    }

    /// Returns the keychain database file URL and its SQLite sidecar URLs for
    /// the given simulator UDID.
    static func keychainFileURLs(for udid: String) -> [URL] {
        let base = URL(fileURLWithPath: NSHomeDirectory())
            .appending(path: "Library/Developer/CoreSimulator/Devices", directoryHint: .isDirectory)
            .appending(path: udid, directoryHint: .isDirectory)
            .appending(path: "data/Library/Keychains", directoryHint: .isDirectory)

        return [
            base.appending(path: "keychain-2-debug.db", directoryHint: .notDirectory),
            base.appending(path: "keychain-2-debug.db-shm", directoryHint: .notDirectory),
            base.appending(path: "keychain-2-debug.db-wal", directoryHint: .notDirectory)
        ]
    }

    /// Clears the keychain by removing the main database and its SQLite
    /// sidecars. Missing files are treated as success.
    func clear(forSimulator udid: String) async throws {
        let fileManager = FileManager.default
        for url in Self.keychainFileURLs(for: udid) {
            do {
                if fileManager.fileExists(atPath: url.path(percentEncoded: false)) {
                    try fileManager.removeItem(at: url)
                }
            } catch {
                throw ClearError.removalFailed(
                    path: url.path(percentEncoded: false),
                    underlying: error
                )
            }
        }
    }
}
