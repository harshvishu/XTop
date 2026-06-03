import SwiftUI

struct AppGroupsTabView: View {
    @Environment(SimulatorInspectorViewModel.self) private var viewModel
    @State private var selectedGroupPath: String?

    var body: some View {
        Group {
            if let app = viewModel.selectedApp {
                if app.appGroupContainerPaths.isEmpty {
                    emptyState("This app does not declare any App Group entitlements.")
                } else {
                    HSplitView {
                        groupList(for: app)
                            .frame(minWidth: 200, idealWidth: 240)
                        UserDefaultsTabView()
                            .frame(maxWidth: .infinity)
                    }
                }
            } else {
                emptyState("Select an app to view its App Group containers.")
            }
        }
        .onChange(of: selectedGroupPath) { _, newValue in
            if let path = newValue {
                viewModel.selectScope(.appGroup(containerPath: path))
            } else if let bundle = viewModel.selectedBundleIdentifier {
                viewModel.selectScope(.app(bundleIdentifier: bundle))
            }
        }
    }

    private func groupList(for app: InstalledApp) -> some View {
        List(selection: $selectedGroupPath) {
            Section("App Groups") {
                ForEach(app.appGroupContainerPaths, id: \.self) { path in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(URL(fileURLWithPath: path).lastPathComponent)
                            .font(DesignSystem.Typography.rowPrimary)
                        Text(path)
                            .font(DesignSystem.Typography.monoCaption)
                            .foregroundStyle(DesignSystem.Colors.secondaryText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .tag(path as String?)
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func emptyState(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text)
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.secondaryText)
                .multilineTextAlignment(.center)
                .padding(DesignSystem.Spacing.xl)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
