import Foundation

/// Reads and writes a simulator app's `UserDefaults` plist directly on disk,
/// preserving plist value types. All filesystem and serialization work happens
/// off the main actor so callers can publish snapshots back to a `@MainActor`
/// view model.
actor UserDefaultsStore {
    enum StoreError: Error, LocalizedError, Sendable {
        case missingContainer
        case invalidPlistRoot
        case readFailed(underlying: Error)
        case writeFailed(underlying: Error)
        case unsupportedType
        case keyAlreadyExists

        var errorDescription: String? {
            switch self {
            case .missingContainer:
                return "App data container not found. The app may need to be launched once."
            case .invalidPlistRoot:
                return "UserDefaults plist root is not a dictionary."
            case .readFailed(let error):
                return "Failed to read UserDefaults plist: \(error.localizedDescription)"
            case .writeFailed(let error):
                return "Failed to write UserDefaults plist: \(error.localizedDescription)"
            case .unsupportedType:
                return "Value type is not supported by the inspector."
            case .keyAlreadyExists:
                return "A key with that name already exists."
            }
        }
    }

    // MARK: - Path resolution

    /// Resolves the on-disk plist URL for the given scope.
    static func plistURL(for scope: UserDefaultsScope, in app: InstalledApp) -> URL? {
        switch scope {
        case .app:
            guard let data = app.dataContainerPath else { return nil }
            return URL(fileURLWithPath: data)
                .appending(path: "Library", directoryHint: .isDirectory)
                .appending(path: "Preferences", directoryHint: .isDirectory)
                .appending(path: "\(app.bundleIdentifier).plist", directoryHint: .notDirectory)
        case .appGroup(let containerPath):
            // App Group UserDefaults are named after the group identifier, which
            // is typically derivable from the trailing path component, but the
            // canonical location is `<group>/Library/Preferences/<group-id>.plist`.
            // We discover the group ID from the metadata plist when available.
            let groupURL = URL(fileURLWithPath: containerPath)
            let metadataURL = groupURL.appending(
                path: ".com.apple.mobile_container_manager.metadata.plist",
                directoryHint: .notDirectory
            )
            let groupID = (try? PropertyListSerialization.propertyList(
                from: Data(contentsOf: metadataURL),
                options: [],
                format: nil
            ))
            .flatMap { $0 as? [String: Any] }
            .flatMap { $0["MCMMetadataIdentifier"] as? String }
            ?? groupURL.lastPathComponent

            return groupURL
                .appending(path: "Library", directoryHint: .isDirectory)
                .appending(path: "Preferences", directoryHint: .isDirectory)
                .appending(path: "\(groupID).plist", directoryHint: .notDirectory)
        }
    }

    // MARK: - Read

    /// Loads all entries from the resolved plist URL, returning them sorted by key.
    func loadEntries(at url: URL) throws -> [UserDefaultsEntry] {
        let dict = try readDictionary(at: url)
        return dict
            .map { key, value in
                UserDefaultsEntry(
                    key: key,
                    type: PlistValueType(value: value) ?? .string,
                    displayValue: Self.preview(for: value)
                )
            }
            .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
    }

    /// Returns the raw value for a key. Useful for the edit sheet.
    func rawValue(forKey key: String, at url: URL) throws -> Any? {
        let dict = try readDictionary(at: url)
        return dict[key]
    }

    // MARK: - Write

    /// Updates an existing entry, preserving the original type.
    func update(key: String, to newValue: Any, at url: URL) throws {
        var dict = (try? readDictionary(at: url)) ?? [:]
        dict[key] = newValue
        try writeDictionary(dict, to: url)
    }

    /// Adds a new entry with an explicit type. Fails if the key already exists.
    func add(key: String, value: Any, at url: URL) throws {
        var dict = (try? readDictionary(at: url)) ?? [:]
        guard dict[key] == nil else { throw StoreError.keyAlreadyExists }
        dict[key] = value
        try writeDictionary(dict, to: url)
    }

    /// Removes an entry.
    func delete(key: String, at url: URL) throws {
        var dict = (try? readDictionary(at: url)) ?? [:]
        dict.removeValue(forKey: key)
        try writeDictionary(dict, to: url)
    }

    // MARK: - Internals

    private func readDictionary(at url: URL) throws -> [String: Any] {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch CocoaError.fileReadNoSuchFile {
            return [:]
        } catch {
            throw StoreError.readFailed(underlying: error)
        }
        if data.isEmpty { return [:] }
        let raw: Any
        do {
            raw = try PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            )
        } catch {
            throw StoreError.readFailed(underlying: error)
        }
        guard let dict = raw as? [String: Any] else {
            throw StoreError.invalidPlistRoot
        }
        return dict
    }

    private func writeDictionary(_ dict: [String: Any], to url: URL) throws {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try PropertyListSerialization.data(
                fromPropertyList: dict,
                format: .binary,
                options: 0
            )
            try data.write(to: url, options: .atomic)
        } catch {
            throw StoreError.writeFailed(underlying: error)
        }
    }

    /// Renders a stable, human-readable preview string for a plist value.
    nonisolated static func preview(for value: Any) -> String {
        switch value {
        case let bool as Bool:
            return bool ? "true" : "false"
        case let number as NSNumber:
            // Distinguish Bool vs numeric — Bool is also NSNumber bridged.
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "true" : "false"
            }
            return number.stringValue
        case let string as String:
            return string
        case let date as Date:
            return date.formatted(date: .abbreviated, time: .standard)
        case let data as Data:
            return "\(data.count) bytes"
        case let array as [Any]:
            return "Array (\(array.count))"
        case let dict as [String: Any]:
            return "Dictionary (\(dict.count))"
        default:
            return String(describing: value)
        }
    }
}

extension PlistValueType {
    /// Best-effort classification of an existing plist value into one of the
    /// supported inspector types. Returns `nil` for unsupported values.
    init?(value: Any) {
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool
                return
            }
            // Distinguish Int vs Double via CFNumber type.
            let cfType = CFNumberGetType(number)
            switch cfType {
            case .floatType, .float32Type, .float64Type, .doubleType, .cgFloatType:
                self = .double
            default:
                self = .integer
            }
            return
        }
        if value is Bool { self = .bool; return }
        if value is String { self = .string; return }
        if value is Date { self = .date; return }
        if value is Data { self = .data; return }
        if value is [Any] { self = .array; return }
        if value is [String: Any] { self = .dictionary; return }
        return nil
    }
}
