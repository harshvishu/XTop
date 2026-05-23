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
    let telemetry: SystemTelemetrySnapshot

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

                LabeledContent("CPU") {
                    metricText(telemetry.cpuPercent)
                }

                LabeledContent("Memory") {
                    metricText(telemetry.memoryUsedPercent)
                }
            }
        }
    }

    @ViewBuilder
    private func metricText(_ metric: MetricValue) -> some View {
        if let value = metric.value {
            Text(value / 100, format: .percent.precision(.fractionLength(0)))
        } else {
            Text("Unavailable")
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    StatusSummaryView(
        lastRefresh: .now,
        showsSeconds: true,
        telemetry: .empty
    )
        .padding()
}
