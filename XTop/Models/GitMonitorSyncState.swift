import Foundation

enum GitMonitorSyncState: String, Codable, Sendable {
    case idle
    case syncingLocal
    case syncingRemote
    case healthy
    case authRequired
    case timeout
    case failed
}
