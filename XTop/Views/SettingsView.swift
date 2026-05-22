//
//  SettingsView.swift
//  XTop
//
//  Created by harsh vishwakarma on 22/05/26.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("showsRefreshSeconds") private var showsRefreshSeconds = false

    var body: some View {
        Form {
            Toggle("Show seconds in refresh time", isOn: $showsRefreshSeconds)
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 360)
    }
}

#Preview {
    SettingsView()
}
