import AppKit
import Foundation

// MARK: - DockVisibilityController

/// Toggles the app's Dock icon visibility based on whether any of XTop's
/// "real" windows are open.
///
/// XTop ships with `LSUIElement = true` so it normally runs as a menu-bar
/// agent with no Dock presence. However, when the user opens the Settings
/// window or the Simulator Inspector window, those windows behave like
/// regular app windows and the user expects a Dock icon they can click,
/// Cmd-Tab to, and use Window menu features with.
///
/// This controller observes window lifecycle notifications and switches
/// `NSApp.activationPolicy` between `.accessory` (no Dock icon, menu-bar
/// only) and `.regular` (Dock icon visible) depending on whether any
/// tracked window is currently on-screen.
@MainActor
final class DockVisibilityController: NSObject {

    private var observers: [NSObjectProtocol] = []

    override init() {
        super.init()
        register()
        // Establish the correct initial policy in case a window is already
        // present (e.g. state restoration). Deferred to the next run-loop
        // tick because `NSApp` may not yet be initialized when this
        // controller is constructed from `XTopApp`'s `@State` initializers.
        Task { @MainActor in
            updateActivationPolicy()
        }
    }

    deinit {
        for token in observers {
            NotificationCenter.default.removeObserver(token)
        }
    }

    // MARK: - Registration

    private func register() {
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didBecomeMainNotification,
            NSWindow.willCloseNotification,
            NSWindow.didChangeOcclusionStateNotification,
        ]

        observers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                MainActor.assumeIsolated {
                    let closing = notification.name == NSWindow.willCloseNotification
                        ? notification.object as? NSWindow
                        : nil
                    self?.updateActivationPolicy(closingWindow: closing)
                }
            }
        }
    }

    // MARK: - Policy

    /// Sets `.regular` when any tracked window is currently visible, otherwise
    /// `.accessory`. Notifications fire before `willClose` removes a window
    /// from `NSApp.windows`, so we additionally filter out the window that is
    /// about to close.
    private func updateActivationPolicy(closingWindow: NSWindow? = nil) {
        guard let app = NSApplication.shared as NSApplication? else { return }

        let hasTrackedWindow = app.windows.contains { window in
            guard window !== closingWindow else { return false }
            guard window.isVisible else { return false }
            return Self.isTrackedWindow(window)
        }

        let desired: NSApplication.ActivationPolicy = hasTrackedWindow ? .regular : .accessory
        guard app.activationPolicy() != desired else { return }
        app.setActivationPolicy(desired)
    }

    // MARK: - Window matching

    /// Returns `true` for windows that should keep the Dock icon visible.
    /// Currently: the SwiftUI Settings window and the Simulator Inspector
    /// window (registered with id `"simulator-inspector"`).
    static func isTrackedWindow(_ window: NSWindow) -> Bool {
        if SettingsWindowActivator.isSettingsWindow(window) {
            return true
        }
        if let identifier = window.identifier?.rawValue,
           identifier.localizedCaseInsensitiveContains("simulator-inspector")
        {
            return true
        }
        return false
    }
}
