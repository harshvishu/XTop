//
//  XTopApp.swift
//  XTop
//
//  Created by harsh vishwakarma on 22/05/26.
//

import SwiftUI


@main
struct XTopApp: App {
    @State private var appState = XTopAppState()
    @State private var settingsActivator = SettingsWindowActivator()
    
    var body: some Scene {
        MenuBarExtra {
            MenuBarPanelView()
                .xtopEnvironment(appState)
        } label: {
            Text(statusTitle(from: appState.viewModel.telemetry))
        }

//        MenuBarExtra("XTop", systemImage: "chart.bar.fill") {
//            MenuBarPanelView()
//                .xtopEnvironment(appState)
//        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .xtopEnvironment(appState)
        }

        Window("Simulator Inspector", id: "simulator-inspector") {
            SimulatorInspectorRootView()
                .xtopEnvironment(appState)
        }
        .windowResizability(.contentMinSize)
    }
    
    private func statusTitle(from telemetry: SystemTelemetrySnapshot) -> String {
        let cpu = telemetry.cpuPercent.value ?? 0
        let mem = telemetry.memoryUsedPercent.value ?? 0
        let symbol: String
        switch telemetry.severity {
            case .healthy:
                symbol = "●"
            case .warning:
                symbol = "◐"
            case .critical:
                symbol = "◉"
            case .unknown:
                symbol = "○"
        }
        
        switch appState.preferences.menuBarSummaryMode {
            case .cpuAndMemory:
                return String(format: "%@ %.0f|%.0f", symbol, cpu, mem)
            case .cpuOnly:
                return String(format: "%@ %.0f%%", symbol, cpu)
            case .iconOnly:
                return symbol
        }
    }
}
