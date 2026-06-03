//
//  MenuBarPanelView.swift
//  XTop
//
//  Created by harsh vishwakarma on 22/05/26.
//

import AppKit
import SwiftUI

struct MenuBarPanelView: View {
    @AppStorage("showsRefreshSeconds") private var showsRefreshSeconds = false
    @Environment(MacbarPreferences.self) private var preferences
    @Environment(MacbarViewModel.self) private var viewModel
    @Environment(\.openSettings) private var openSettings
    @State private var lastRefresh = Date.now
    
    var body: some View {
        GroupBox {
            //            MenuBarHeaderView()
            
            //            StatusSummaryView(
            //                lastRefresh: lastRefresh,
            //                showsSeconds: showsRefreshSeconds,
            //                telemetry: viewModel.telemetry
            //            )
            
            DashboardRootView()
                .padding(.horizontal, 8)
            
            Divider()
            
            HStack {
                Button("Refresh", systemImage: "arrow.clockwise", action: refresh)

                Button("Settings", systemImage: "gearshape", action: openAppSettings)

                Button("Quit", systemImage: "power", action: quit)
            }
            .padding(8)
        }
        .frame(width: preferences.dashboardDensity.width)
        .task {
            viewModel.startSampling()
        }
        .onDisappear {
            viewModel.stopSampling()
        }
    }
    
    private func refresh() {
        Task {
            await viewModel.refresh()
            lastRefresh = .now
        }
    }
    
    private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func openAppSettings() {
        openSettings()
        SettingsWindowActivator.bringToFront()
    }
}

#Preview {
    MenuBarPanelView()
        .xtopEnvironment(XTopAppState())
}
