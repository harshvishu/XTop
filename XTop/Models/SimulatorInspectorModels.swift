import Foundation

/// A booted iOS Simulator surfaced by the Simulator Inspector.
struct SimulatorDevice: Identifiable, Hashable, Sendable {
    /// `UDID` (e.g. `4F2A...`). Stable across boots.
    let id: String
    /// User-facing device name (e.g. `iPhone 17 Pro`).
    let name: String
    /// Runtime identifier from `simctl` (e.g. `com.apple.CoreSimulator.SimRuntime.iOS-26-0`).
    let runtimeIdentifier: String
    /// Human-readable runtime label derived from the identifier (e.g. `iOS 26.0`).
    let runtimeDisplayName: String
    /// Device type identifier (e.g. `com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro`).
    let deviceTypeIdentifier: String?

    var udid: String { id }
}

/// A third-party app installed on a simulator and visible to the inspector.
struct InstalledApp: Identifiable, Hashable, Sendable {
    var id: String { bundleIdentifier }

    let bundleIdentifier: String
    /// Display name resolved from `CFBundleDisplayName` or `CFBundleName`.
    let displayName: String
    /// Absolute path to the installed `.app` bundle.
    let bundlePath: String
    /// Absolute path to the per-app data container, if it has been created yet.
    let dataContainerPath: String?
    /// Absolute paths to App Group container directories declared by the app.
    let appGroupContainerPaths: [String]
}

/// Set of resolved container paths for an installed app.
struct AppContainerPaths: Hashable, Sendable {
    let bundlePath: String
    let dataContainerPath: String?
    let appGroupContainerPaths: [String]
}

/// Supported plist value types for `UserDefaults` editing.
enum PlistValueType: String, CaseIterable, Hashable, Sendable, Identifiable {
    case bool
    case integer
    case double
    case string
    case date
    case data
    case array
    case dictionary

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bool: return "Bool"
        case .integer: return "Int"
        case .double: return "Double"
        case .string: return "String"
        case .date: return "Date"
        case .data: return "Data"
        case .array: return "Array"
        case .dictionary: return "Dictionary"
        }
    }
}

/// One entry inside an installed app's `UserDefaults` plist.
struct UserDefaultsEntry: Identifiable, Hashable, Sendable {
    var id: String { key }
    let key: String
    let type: PlistValueType
    /// Round-tripped string preview of the value, suitable for table display.
    let displayValue: String
    /// Whether the value is a scalar (Bool/Int/Double/String/Date/Data) editable inline.
    var isScalar: Bool {
        switch type {
        case .array, .dictionary:
            return false
        default:
            return true
        }
    }
}

/// Scope describing which `UserDefaults` plist is being viewed.
enum UserDefaultsScope: Hashable, Sendable, Identifiable {
    case app(bundleIdentifier: String)
    case appGroup(containerPath: String)

    var id: String {
        switch self {
        case .app(let bid): return "app:\(bid)"
        case .appGroup(let path): return "group:\(path)"
        }
    }
}
