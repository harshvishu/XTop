import Foundation

struct GitMonitorRegistry: Codable, Sendable {
    var baseFolders: [String]
    var repositories: [GitMonitoredRepository]

    nonisolated init(baseFolders: [String] = [], repositories: [GitMonitoredRepository] = []) {
        self.baseFolders = baseFolders
        self.repositories = repositories
    }
}
