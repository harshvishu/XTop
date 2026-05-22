//
//  StatusSummaryView.swift
//  XTop
//
//  Created by harsh vishwakarma on 22/05/26.
//

import SwiftUI

struct StatusSummaryView: View {
    let lastRefresh: Date
    let showsSeconds: Bool

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("State") {
                    Label("Ready", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }

                LabeledContent("Last refresh") {
                    if showsSeconds {
                        Text(lastRefresh, format: .dateTime.hour().minute().second())
                    } else {
                        Text(lastRefresh, format: .dateTime.hour().minute())
                    }
                }
            }
        }
    }
}

#Preview {
    StatusSummaryView(lastRefresh: .now, showsSeconds: true)
        .padding()
}
