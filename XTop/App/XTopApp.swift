//
//  XTopApp.swift
//  XTop
//
//  Created by harsh vishwakarma on 22/05/26.
//

import SwiftUI

@main
struct XTopApp: App {
    var body: some Scene {
        MenuBarExtra("XTop", systemImage: "chart.bar.fill") {
            MenuBarPanelView()
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}
