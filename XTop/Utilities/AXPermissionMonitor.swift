import ApplicationServices
import Foundation
import Observation

/// Current macOS Accessibility trust state for the host process.
enum AXPermissionStatus: Sendable, Equatable {
    case unknown
    case granted
    case denied
}

/// Small `@MainActor`, `@Observable` helper that publishes the current
/// Accessibility trust state and lets callers re-check or prompt the user.
@MainActor
@Observable
final class AXPermissionMonitor {
    private(set) var status: AXPermissionStatus

    init() {
        self.status = AXPermissionMonitor.currentStatus(prompt: false)
    }

    /// Re-reads the AX trust state without prompting the user. Cheap; safe
    /// to call on tab appear / periodic ticks.
    func refresh() {
        status = AXPermissionMonitor.currentStatus(prompt: false)
    }

    /// Calls `AXIsProcessTrustedWithOptions` with the system prompt option,
    /// which triggers macOS to open the Accessibility settings pane and add
    /// XTop to the list if it isn't already. Returns the resulting status.
    @discardableResult
    func requestAccess() -> AXPermissionStatus {
        status = AXPermissionMonitor.currentStatus(prompt: true)
        return status
    }

    private static func currentStatus(prompt: Bool) -> AXPermissionStatus {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        let options: CFDictionary = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options) ? .granted : .denied
    }
}
