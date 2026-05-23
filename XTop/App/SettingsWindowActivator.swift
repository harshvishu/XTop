import AppKit
import Foundation

// MARK: - SettingsWindowActivator

/// Brings the SwiftUI `Settings` scene window to the front and makes it the
/// key window whenever it appears.
///
/// XTop runs as `LSUIElement = true` (menu bar only) and uses a SwiftUI
/// `Settings { … }` scene reached via `SettingsLink`. macOS does not promote
/// `LSUIElement` apps to foreground when the Settings window opens, so the
/// window typically appears behind whatever the user was doing and lacks
/// keyboard focus. The user then has to alt-tab to find it.
///
/// This activator observes `NSWindow.didBecomeKeyNotification` for the
/// lifetime of the app and, when the Settings window is the one becoming
/// key (or being shown), calls `NSApp.activate(ignoringOtherApps:)` and
/// `orderFrontRegardless()`. It also observes `NSWindow.didBecomeMainNotification`
/// to cover the first-open path where SwiftUI orders the window in before
/// it ever receives key status.
///
/// The activator is intentionally a small `NSObject` rather than a SwiftUI
/// modifier so it can be retained for the full app lifetime from
/// `XTopApp.init` without coupling to a particular view.
@MainActor
final class SettingsWindowActivator: NSObject {

    private var observers: [NSObjectProtocol] = []

    override init() {
        super.init()
        register()
    }

    deinit {
        // NotificationCenter holds the tokens; remove on tear-down. This
        // runs on whatever queue deinit is invoked from, which is safe for
        // NotificationCenter.removeObserver.
        for token in observers {
            NotificationCenter.default.removeObserver(token)
        }
    }

    // MARK: - Registration

    private func register() {
        let center = NotificationCenter.default

        let keyToken = center.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                self?.handleWindowEvent(notification)
            }
        }

        let mainToken = center.addObserver(
            forName: NSWindow.didBecomeMainNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                self?.handleWindowEvent(notification)
            }
        }

        observers = [keyToken, mainToken]
    }

    // MARK: - Window matching

    private func handleWindowEvent(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        guard Self.isSettingsWindow(window) else { return }

        // Activate the app first so the window can legitimately come to the
        // front. `ignoringOtherApps: true` is required for menu-bar-only
        // apps because they are otherwise blocked from stealing focus.
        NSApp.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
    }

    /// Heuristic match for the SwiftUI Settings scene window.
    ///
    /// SwiftUI does not expose a stable identifier for the Settings window
    /// on macOS. The window's `identifier` typically contains
    /// "com_apple_SwiftUI_Settings_window" and its `frameAutosaveName`
    /// contains "Settings". We accept either signal; matching on the
    /// localized window title is avoided to keep this language-independent.
    static func isSettingsWindow(_ window: NSWindow) -> Bool {
        if let identifier = window.identifier?.rawValue,
           identifier.localizedCaseInsensitiveContains("settings")
            || identifier.localizedCaseInsensitiveContains("preferences")
        {
            return true
        }
        if window.frameAutosaveName.localizedCaseInsensitiveContains("settings")
            || window.frameAutosaveName.localizedCaseInsensitiveContains("preferences")
        {
            return true
        }
        return false
    }
}
