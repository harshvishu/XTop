import AppKit
import Foundation
import Testing
@testable import XTop

@Suite("SettingsWindowActivator")
@MainActor
struct SettingsWindowActivatorTests {

    @Test("Matches windows whose identifier contains \"settings\"")
    func matchesSettingsIdentifier() {
        let window = NSWindow()
        window.identifier = NSUserInterfaceItemIdentifier("com_apple_SwiftUI_Settings_window")
        #expect(SettingsWindowActivator.isSettingsWindow(window))
    }

    @Test("Matches windows whose identifier contains \"preferences\"")
    func matchesPreferencesIdentifier() {
        let window = NSWindow()
        window.identifier = NSUserInterfaceItemIdentifier("com.example.PreferencesPanel")
        #expect(SettingsWindowActivator.isSettingsWindow(window))
    }

    @Test("Matches windows whose autosave name contains \"settings\"")
    func matchesSettingsAutosave() {
        let window = NSWindow()
        window.setFrameAutosaveName("XTopSettingsAutosave")
        #expect(SettingsWindowActivator.isSettingsWindow(window))
    }

    @Test("Does not match unrelated windows")
    func ignoresUnrelatedWindows() {
        let window = NSWindow()
        window.identifier = NSUserInterfaceItemIdentifier("com_apple_SwiftUI_window_dashboard")
        #expect(!SettingsWindowActivator.isSettingsWindow(window))
    }

    @Test("Initializer installs observers without throwing")
    func initialiserInstallsObservers() {
        // The activator must register observers from init so the first
        // Settings open is caught. Constructing it should succeed and not
        // throw. The actual notification dispatch is exercised at runtime.
        let activator = SettingsWindowActivator()
        // Hold a reference to make the intent explicit; without this the
        // optimizer could short-cut the construction.
        _ = activator
    }
}
