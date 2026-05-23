//
//  SettingsView.swift
//  XTop
//
//  Created by harsh vishwakarma on 22/05/26.
//

import SwiftUI

struct SettingsView: View {
    var body: some View {
        SettingsRootView()
    }
}

#Preview {
    SettingsView()
        .xtopEnvironment(XTopAppState())
}
