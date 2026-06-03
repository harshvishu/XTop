import SwiftUI

struct SimulatorListSidebar: View {
    @Environment(SimulatorInspectorViewModel.self) private var viewModel

    var body: some View {
        @Bindable var bindable = viewModel
        List(selection: $bindable.selectedSimulatorID) {
            Section("Booted Simulators") {
                if viewModel.simulators.isEmpty {
                    Text(viewModel.isRefreshingSimulators ? "Loading…" : "No booted simulators.")
                        .font(DesignSystem.Typography.rowSecondary)
                        .foregroundStyle(DesignSystem.Colors.secondaryText)
                } else {
                    ForEach(viewModel.simulators) { device in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(device.name)
                                .font(DesignSystem.Typography.rowPrimary)
                                .foregroundStyle(DesignSystem.Colors.primaryText)
                            Text(device.runtimeDisplayName)
                                .font(DesignSystem.Typography.rowSecondary)
                                .foregroundStyle(DesignSystem.Colors.secondaryText)
                        }
                        .padding(.vertical, 2)
                        .tag(device.id as String?)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
}
