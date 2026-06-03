import SwiftUI

struct KeychainTabView: View {
    @Environment(SimulatorInspectorViewModel.self) private var viewModel
    @State private var confirmationText = ""
    @State private var showConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Text("Keychain")
                .font(DesignSystem.Typography.sectionTitle)

            Text("v1 supports only clearing the simulator's entire keychain. Per-item inspection and editing are not available.")
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.secondaryText)

            if let device = viewModel.selectedSimulator {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    Text("Target")
                        .font(DesignSystem.Typography.rowSecondary)
                        .foregroundStyle(DesignSystem.Colors.secondaryText)
                    Text("\(device.name) — \(device.runtimeDisplayName)")
                        .font(DesignSystem.Typography.rowPrimary)
                }
            } else {
                Text("Select a simulator to enable keychain actions.")
                    .font(DesignSystem.Typography.rowSecondary)
                    .foregroundStyle(DesignSystem.Colors.secondaryText)
            }

            Button(role: .destructive) {
                showConfirm = true
                confirmationText = ""
            } label: {
                Label("Clear Keychain…", systemImage: "trash")
            }
            .disabled(viewModel.selectedSimulator == nil)
            .controlSize(.large)

            Spacer()
        }
        .padding(DesignSystem.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $showConfirm) {
            confirmSheet
        }
    }

    private var confirmSheet: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Text("Clear Keychain")
                .font(DesignSystem.Typography.sectionTitle)
            if let device = viewModel.selectedSimulator {
                Text("This deletes the keychain database for **\(device.name)**. The selected app will be terminated first. This cannot be undone.")
                    .font(DesignSystem.Typography.body)
                Text("Type the simulator name to confirm.")
                    .font(DesignSystem.Typography.rowSecondary)
                    .foregroundStyle(DesignSystem.Colors.secondaryText)
                TextField(device.name, text: $confirmationText)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("Cancel", role: .cancel) { showConfirm = false }
                    Spacer()
                    Button("Clear Keychain", role: .destructive) {
                        showConfirm = false
                        Task { await viewModel.clearSelectedKeychain() }
                    }
                    .disabled(confirmationText != device.name)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(DesignSystem.Spacing.lg)
        .frame(width: 440)
    }
}
