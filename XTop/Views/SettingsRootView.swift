import Foundation
import Observation
import SwiftUI

// MARK: - Root Settings View

struct SettingsRootView: View {
    var body: some View {
        
        TabView {
            
            DeveloperToolSettingsView()
            .tabItem {
                Label(
                    "Developer Tools",
                    systemImage: "hammer"
                )
            }
            
            GeneralSettingsView()
            .tabItem {
                Label(
                    "General",
                    systemImage: "menubar.rectangle"
                )
            }
            
            SensorSettingsView()
            .tabItem {
                Label(
                    "Sensors",
                    systemImage: "sensor"
                )
            }

            GitMonitorSettingsView()
            .tabItem {
                Label(
                    "Git Monitor",
                    systemImage: "point.topleft.down.curvedto.point.bottomright.up"
                )
            }
        }
        .frame(
            width: 560,
            height: 430
        )
    }
}

// MARK: - General Settings

private struct GeneralSettingsView: View {
    
    @Environment(MacbarPreferences.self) private var preferences
    
    var body: some View {
        @Bindable var preferences = preferences
        
        Form {
            
            Section("Menu Bar") {
                
                Picker(
                    "Summary",
                    selection: $preferences.menuBarSummaryMode
                ) {
                    
                    ForEach(
                        MenuBarSummaryMode.allCases
                    ) { mode in
                        
                        Text(mode.title)
                            .tag(mode)
                    }
                }
                
                Picker(
                    "Refresh",
                    selection: $preferences.refreshInterval
                ) {
                    
                    ForEach(
                        RefreshInterval.allCases
                    ) { interval in
                        
                        Text(interval.title)
                            .tag(interval)
                    }
                }
            }
            
            Section("Dashboard") {
                
                Picker(
                    "Density",
                    selection: $preferences.dashboardDensity
                ) {
                    
                    ForEach(
                        DashboardDensity.allCases
                    ) { density in
                        
                        Text(density.title)
                            .tag(density)
                    }
                }
                
                LabeledContent(
                    "Popover Width"
                ) {
                    
                    Text(
                        "\(Int(preferences.dashboardDensity.width)) pt"
                    )
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Sensor Settings

private struct SensorSettingsView: View {

    @Environment(SensorSettingsModel.self) private var sensors

    var body: some View {

        Form {

            Section("Advanced Sensors") {

                Text(
                    "GPU readings come from IOAccelerator; temperature and fan readings come from the system's HID thermal sensors. Macs without fan hardware (MacBook Air, Mac mini M-series) correctly show fan as unavailable — this is not a malfunction."
                )
                .foregroundStyle(.secondary)

                ForEach(
                    sensors.capabilities
                ) { capability in

                    LabeledContent(
                        capability.metric.rawValue
                    ) {

                        VStack(
                            alignment: .trailing,
                            spacing: 2
                        ) {

                            Text(
                                capability.state.title
                            )

                            Text(
                                capability.state.nextAction
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                        }
                    }
                }

                HStack {

                    if sensors.isEnabled {
                        Button("Disable", systemImage: "pause.circle") {
                            Task { await sensors.disable() }
                        }
                        .disabled(sensors.isPerformingAction)
                    } else {
                        Button("Enable", systemImage: "play.circle") {
                            Task { await sensors.enable() }
                        }
                        .disabled(sensors.isPerformingAction)
                    }

                    Button("Test Access", systemImage: "waveform.path.ecg") {
                        Task { await sensors.testAccess() }
                    }
                    .disabled(sensors.isPerformingAction)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Developer Tool Settings

private struct DeveloperToolSettingsView: View {
    
    @Environment(MacbarPreferences.self) private var preferences
    @Environment(DeveloperDiagnosticsStore.self) private var diagnostics
    @Environment(MacbarViewModel.self) private var viewModel
    @AppStorage("SimulatorInspector.cameraInjectionEnabled") private var cameraInjectionEnabled = false
    
    var body: some View {
        @Bindable var preferences = preferences
        
        Form {
            
            Section("Dashboard") {
                
                Toggle(
                    "Show developer process usage",
                    isOn: $preferences.includesDeveloperProcesses
                )
            }
            
            Section("Simulator Inspector") {
                
                Toggle(
                    "Enable Camera Injection (experimental)",
                    isOn: $cameraInjectionEnabled
                )
                
                Text(
                    "Adds a Camera tab in the Simulator Inspector that streams Mac-side frames into iOS simulator apps via a DYLD shim. Experimental: most production apps with closed-source camera SDKs will not render the stream. Requires restarting the inspector window after toggling."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            
            Section {
                
                ToolAvailabilityRow(
                    title: "Git",
                    isAvailable: diagnostics.toolAvailability.git
                )
                
                ToolAvailabilityRow(
                    title: "xcodebuild",
                    isAvailable: diagnostics.toolAvailability.xcodebuild
                )
                
                ToolAvailabilityRow(
                    title: "CocoaPods",
                    isAvailable: diagnostics.toolAvailability.pod
                )
            } header: {
                HStack {
                    Text("Tool Availability")
                    Spacer()
                    if let lastScan = diagnostics.lastDeveloperScan {
                        Text("checked \(lastScan.formatted(.relative(presentation: .numeric)))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textCase(nil)
                    }
                    Button {
                        Task { await viewModel.refreshDeveloperContext() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Re-check tool availability")
                }
            } footer: {
                Text(
                    "GUI apps inherit a minimal PATH (`/usr/bin:/bin:/usr/sbin:/sbin`). Homebrew tools at `/usr/local/bin` or `/opt/homebrew/bin` will not be found unless symlinked into `/usr/local/bin` or invoked via an absolute path."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            
            if !diagnostics.recentMaintenanceLogs.isEmpty {
                Section("Recent Operations") {
                    ForEach(diagnostics.recentMaintenanceLogs) { log in
                        LabeledContent(log.action) {
                            Text(log.summary)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
            }
            
            Section("Utility Scope") {
                
                Text(
                    "Xcode project, Git worktree, SwiftPM, and CocoaPods actions follow the focused Xcode project or the manual Git override shown in the dashboard detail."
                )
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .task {
            await viewModel.refreshDeveloperContext()
        }
    }
}

// MARK: - Tool Availability Row

private struct ToolAvailabilityRow: View {
    
    let title: String
    let isAvailable: Bool
    
    var body: some View {
        
        LabeledContent(
            title
        ) {
            
            Label(
                isAvailable
                ? "Available"
                : "Unavailable",
                systemImage:
                    isAvailable
                ? "checkmark.circle.fill"
                : "xmark.circle"
            )
            .foregroundStyle(
                isAvailable
                ? .green
                : .secondary
            )
        }
    }
}
