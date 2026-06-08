import SwiftUI

struct ArchManagerActionPanel: View {
    @Environment(MacbarViewModel.self) private var viewModel

    let repositoryID: UUID

    @State private var pendingMode: ExcludedArchsMode?
    @State private var dryRunResult: ExcludedArchsResult?
    @State private var actionResultMessage: String?
    @State private var actionErrorMessage: String?
    @State private var isRunning = false

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Text("Arch Manager")
                .font(DesignSystem.Typography.sectionTitle)
                .foregroundStyle(DesignSystem.Colors.primaryText)

            HStack(spacing: DesignSystem.Spacing.sm) {
                Button("Clear arm64") {
                    runDryPreview(for: .clearArm64)
                }
                .buttonStyle(.bordered)
                .disabled(isRunning)

                Button("Set Debug arm64") {
                    runDryPreview(for: .setDebugArm64)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRunning)
            }

            if let actionResultMessage {
                Text(actionResultMessage)
                    .font(DesignSystem.Typography.rowSecondary)
                    .foregroundStyle(DesignSystem.Colors.secondaryText)
            }

            if let actionErrorMessage {
                Text(actionErrorMessage)
                    .font(DesignSystem.Typography.rowSecondary)
                    .foregroundStyle(DesignSystem.Colors.destructive)
            }
        }
        .confirmationDialog(
            confirmationTitle,
            isPresented: pendingConfirmationBinding,
            titleVisibility: .visible
        ) {
            Button("Apply") {
                applyPendingAction()
            }
            Button("Cancel", role: .cancel) {
                pendingMode = nil
                dryRunResult = nil
            }
        } message: {
            Text(dryRunResult?.message ?? "No dry-run details available.")
        }
    }

    private var confirmationTitle: String {
        switch pendingMode {
        case .clearArm64:
            return "Apply Clear arm64"
        case .setDebugArm64:
            return "Apply Set Debug arm64"
        case nil:
            return "Confirm Arch Action"
        }
    }

    private var pendingConfirmationBinding: Binding<Bool> {
        Binding(
            get: { pendingMode != nil },
            set: { presented in
                if !presented {
                    pendingMode = nil
                    dryRunResult = nil
                }
            }
        )
    }

    private func runDryPreview(for mode: ExcludedArchsMode) {
        Task {
            isRunning = true
            actionErrorMessage = nil
            actionResultMessage = nil

            do {
                let result = try await viewModel.dryRunArchsAction(
                    mode: mode,
                    repositoryID: repositoryID
                )
                dryRunResult = result
                pendingMode = mode
            } catch {
                actionErrorMessage = error.localizedDescription
            }

            isRunning = false
        }
    }

    private func applyPendingAction() {
        guard let mode = pendingMode else {
            return
        }

        Task {
            isRunning = true
            actionErrorMessage = nil

            do {
                let result = try await viewModel.applyArchsAction(
                    mode: mode,
                    repositoryID: repositoryID
                )
                actionResultMessage = result.message
            } catch {
                actionErrorMessage = error.localizedDescription
            }

            pendingMode = nil
            dryRunResult = nil
            isRunning = false
        }
    }
}
