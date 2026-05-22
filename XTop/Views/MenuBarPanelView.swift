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
    @State private var lastRefresh = Date.now

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MenuBarHeaderView()

            StatusSummaryView(
                lastRefresh: lastRefresh,
                showsSeconds: showsRefreshSeconds
            )

            HStack {
                Button("Refresh", systemImage: "arrow.clockwise", action: refresh)

                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
            }

            Divider()

            Button("Quit XTop", systemImage: "power", action: quit)
        }
        .padding()
        .frame(width: 300)
    }

    private func refresh() {
        lastRefresh = .now
    }

    private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

#Preview {
    MenuBarPanelView()
}
