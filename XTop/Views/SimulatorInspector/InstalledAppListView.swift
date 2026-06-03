import SwiftUI

struct InstalledAppListView: View {
    @Environment(SimulatorInspectorViewModel.self) private var viewModel

    var body: some View {
        @Bindable var bindable = viewModel
        List(selection: $bindable.selectedBundleIdentifier) {
            Section("Installed Apps") {
                if viewModel.selectedSimulatorID == nil {
                    Text("Select a simulator to see installed apps.")
                        .font(DesignSystem.Typography.rowSecondary)
                        .foregroundStyle(DesignSystem.Colors.secondaryText)
                } else if viewModel.isRefreshingApps && viewModel.installedApps.isEmpty {
                    Text("Loading…")
                        .font(DesignSystem.Typography.rowSecondary)
                        .foregroundStyle(DesignSystem.Colors.secondaryText)
                } else if viewModel.installedApps.isEmpty {
                    Text("No third-party apps installed on this simulator.")
                        .font(DesignSystem.Typography.rowSecondary)
                        .foregroundStyle(DesignSystem.Colors.secondaryText)
                } else {
                    ForEach(viewModel.installedApps) { app in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.displayName)
                                .font(DesignSystem.Typography.rowPrimary)
                                .foregroundStyle(DesignSystem.Colors.primaryText)
                            Text(app.bundleIdentifier)
                                .font(DesignSystem.Typography.monoCaption)
                                .foregroundStyle(DesignSystem.Colors.secondaryText)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            if app.dataContainerPath == nil {
                                Text("Not launched yet")
                                    .font(DesignSystem.Typography.rowSecondary)
                                    .foregroundStyle(DesignSystem.Colors.tertiaryText)
                            }
                        }
                        .padding(.vertical, 2)
                        .tag(app.bundleIdentifier as String?)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
}
