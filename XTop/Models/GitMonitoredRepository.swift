import Foundation

struct GitMonitoredRepository: Codable, Identifiable, Sendable {
    let id: UUID
    var displayName: String
    var path: String
    var canonicalPath: String
    var isPrimary: Bool
    var isActive: Bool
    var boundAccountProfileID: UUID?
    var createdAt: Date
    var updatedAt: Date
    var lastSeenAt: Date?

    nonisolated init(
        id: UUID = UUID(),
        displayName: String,
        path: String,
        canonicalPath: String,
        isPrimary: Bool = false,
        isActive: Bool = true,
        boundAccountProfileID: UUID? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        lastSeenAt: Date? = .now
    ) {
        self.id = id
        self.displayName = displayName
        self.path = path
        self.canonicalPath = canonicalPath
        self.isPrimary = isPrimary
        self.isActive = isActive
        self.boundAccountProfileID = boundAccountProfileID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastSeenAt = lastSeenAt
    }
}
