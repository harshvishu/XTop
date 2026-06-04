//
//  XTopApp.swift
//  XTop
//
//  Created by harsh vishwakarma on 22/05/26.
//

import AppKit
import SwiftUI


@main
struct XTopApp: App {
    @State private var appState = XTopAppState()
    @State private var settingsActivator = SettingsWindowActivator()
    @State private var dockVisibility = DockVisibilityController()
    
    var body: some Scene {
        MenuBarExtra {
            MenuBarPanelView()
                .xtopEnvironment(appState)
        } label: {
            MenuBarStatusLabel()
                .xtopEnvironment(appState)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .xtopEnvironment(appState)
        }

        Window("Simulator Inspector", id: "simulator-inspector") {
            SimulatorInspectorRootView(gridConfigStore: appState.gridOverlayConfigStore)
                .xtopEnvironment(appState)
                .onAppear {
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .windowResizability(.contentMinSize)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
    }
}

private struct MenuBarStatusLabel: View {
    @Environment(MacbarPreferences.self) private var preferences
    @Environment(MacbarViewModel.self) private var viewModel

    var body: some View {
        Text(statusTitle)
    }

    private var statusTitle: String {
        let telemetry = viewModel.telemetry
        let cpu = telemetry.cpuPercent.value ?? 0
        let mem = telemetry.memoryUsedPercent.value ?? 0
        let symbol: String
        switch telemetry.severity {
        case .healthy: symbol = "●"
        case .warning: symbol = "◐"
        case .critical: symbol = "◉"
        case .unknown: symbol = "○"
        }

        switch preferences.menuBarSummaryMode {
        case .cpuAndMemory:
            return String(format: "%@ %.0f|%.0f", symbol, cpu, mem)
        case .cpuOnly:
            return String(format: "%@ %.0f%%", symbol, cpu)
        case .iconOnly:
            return symbol
        }
    }
}
