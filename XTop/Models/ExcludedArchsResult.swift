import Foundation

struct ExcludedArchsResult: Sendable {
    let changedBlocks: Int
    let changedLines: Int
    let debugBlocksChanged: Int
    let nonDebugBlocksChanged: Int
    let backupPath: String?
    let message: String

    nonisolated init(
        changedBlocks: Int,
        changedLines: Int,
        debugBlocksChanged: Int,
        nonDebugBlocksChanged: Int,
        backupPath: String? = nil,
        message: String
    ) {
        self.changedBlocks = changedBlocks
        self.changedLines = changedLines
        self.debugBlocksChanged = debugBlocksChanged
        self.nonDebugBlocksChanged = nonDebugBlocksChanged
        self.backupPath = backupPath
        self.message = message
    }
}
