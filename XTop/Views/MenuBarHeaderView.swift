//
//  MenuBarHeaderView.swift
//  XTop
//
//  Created by harsh vishwakarma on 22/05/26.
//

import SwiftUI

struct MenuBarHeaderView: View {
    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text("XTop")
                    .font(.headline)

                Text("Menu bar utility")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "chart.bar.fill")
                .foregroundStyle(.tint)
        }
    }
}

#Preview {
    MenuBarHeaderView()
        .padding()
}
