import Foundation

/// The four built-in frame source kinds the user can choose in the Camera tab.
enum CameraSourceKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case testPattern
    case webcam
    case videoFile
    case screenRegion

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .testPattern: return "Test Pattern"
        case .webcam: return "Mac Webcam"
        case .videoFile: return "Video File"
        case .screenRegion: return "Screen Region"
        }
    }

    var requiresHostPermission: Bool {
        switch self {
        case .testPattern, .videoFile: return false
        case .webcam, .screenRegion: return true
        }
    }
}

/// Connection lifecycle reported by the transport.
enum CameraTransportState: Sendable, Equatable {
    case stopped
    case listening(port: UInt16)
    case connected(port: UInt16, peer: String)
    case streaming(port: UInt16, peer: String)
    case failed(String)

    var isConnected: Bool {
        switch self {
        case .connected, .streaming: return true
        default: return false
        }
    }

    var port: UInt16? {
        switch self {
        case let .listening(p), let .connected(p, _), let .streaming(p, _): return p
        default: return nil
        }
    }
}

/// Overall feature state for the Camera tab.
enum CameraInjectionPhase: Sendable, Equatable {
    case idle
    case preparing
    case awaitingClient(port: UInt16)
    case running(port: UInt16, pid: Int32?)
    case stopping
    case error(String)
}

/// Persistence record for "last-used source per app".
struct CameraSourcePreference: Codable, Sendable, Equatable {
    var kind: CameraSourceKind
    var videoFileBookmark: Data?
    var screenWindowID: UInt32?
    var jpegQuality: Double

    static let `default` = CameraSourcePreference(
        kind: .testPattern,
        videoFileBookmark: nil,
        screenWindowID: nil,
        jpegQuality: 0.7
    )
}
