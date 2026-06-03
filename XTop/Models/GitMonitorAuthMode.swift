import Foundation

enum GitMonitorAuthMode: String, Codable, CaseIterable, Sendable {
    case httpsToken
    case sshKey
}
