import SwiftUI

struct RepositoryDetailView: View {
    @Environment(MacbarViewModel.self) private var viewModel

    let repositoryID: UUID

    @State private var isScanningProject = false
    @State private var scanStatusMessage: String?

    var body: some View {
        Group {
            if let repository {
                ScrollView {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.section) {
                        header(for: repository)
                        gitStatusSection
                        projectSection(for: repository)

                        if isArchManagerAvailable(for: repository) {
                            ArchManagerActionPanel(repositoryID: repositoryID)
                        }

                        simulatorSection
                    }
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .padding(.vertical, DesignSystem.Spacing.md)
                }
            } else {
                Text("Repository no longer exists.")
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.secondaryText)
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .padding(.vertical, DesignSystem.Spacing.md)
            }
        }
        .frame(minWidth: 560, minHeight: 420)
    }

    private var repository: GitMonitoredRepository? {
        viewModel.gitMonitorRegistry.repositories.first(where: { $0.id == repositoryID })
    }

    private var snapshot: GitRepositorySnapshot? {
        viewModel.gitSnapshot(for: repositoryID)
    }

    private func header(for repository: GitMonitoredRepository) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text(repository.displayName)
                .font(DesignSystem.Typography.title)
                .foregroundStyle(DesignSystem.Colors.primaryText)

            Text(repository.path)
                .font(DesignSystem.Typography.rowSecondary)
                .foregroundStyle(DesignSystem.Colors.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)

            RepositoryProjectTypeBadge(projectType: repository.xcodeProjectType)
        }
    }

    private var gitStatusSection: some View {
        RepositoryDetailSection(title: "Git Status") {
            if let snapshot {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    RepositoryInfoRow(label: "Branch", value: snapshot.branch ?? "-")
                    RepositoryInfoRow(label: "Staged", value: "\(snapshot.stagedCount)")
                    RepositoryInfoRow(label: "Unstaged", value: "\(snapshot.unstagedCount)")
                    RepositoryInfoRow(label: "Untracked", value: "\(snapshot.untrackedCount)")
                    RepositoryInfoRow(label: "Ahead/Behind", value: "↑\(snapshot.aheadBy ?? 0) ↓\(snapshot.behindBy ?? 0)")

                    let lastSync = snapshot.lastRemoteSyncAt ?? snapshot.lastLocalSyncAt
                    RepositoryInfoRow(
                        label: "Last Sync",
                        value: lastSync?.formatted(date: .abbreviated, time: .shortened) ?? "No data yet"
                    )
                }
            } else {
                Text("No data yet")
                    .font(DesignSystem.Typography.rowSecondary)
                    .foregroundStyle(DesignSystem.Colors.secondaryText)
            }
        }
    }

    private func projectSection(for repository: GitMonitoredRepository) -> some View {
        RepositoryDetailSection(title: "Project") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    RepositoryProjectTypeBadge(projectType: repository.xcodeProjectType)
                    Button("Scan Project") {
                        scanProject()
                    }
                    .buttonStyle(.bordered)
                    .disabled(isScanningProject)
                }

                if isScanningProject {
                    ProgressView()
                        .controlSize(.small)
                }

                if let scanStatusMessage {
                    Text(scanStatusMessage)
                        .font(DesignSystem.Typography.rowSecondary)
                        .foregroundStyle(DesignSystem.Colors.secondaryText)
                }
            }
        }
    }

    private var simulatorSection: some View {
        RepositoryDetailSection(title: "Simulator") {
            Button("Run on Simulator") {}
                .buttonStyle(.borderedProminent)
                .disabled(true)
                .help("Coming soon")
        }
    }

    private func scanProject() {
        Task {
            isScanningProject = true
            scanStatusMessage = nil
            await viewModel.scanProjectType(for: repositoryID)

            if let projectType = repository?.xcodeProjectType {
                scanStatusMessage = "Detected: \(label(for: projectType))"
            } else {
                scanStatusMessage = "No supported project type detected."
            }

            isScanningProject = false
        }
    }

    private func isArchManagerAvailable(for repository: GitMonitoredRepository) -> Bool {
        switch repository.xcodeProjectType {
        case .xcodeproj, .xcworkspace:
            return true
        default:
            return false
        }
    }

    private func label(for projectType: XcodeProjectType) -> String {
        switch projectType {
        case .xcodeproj:
            return "Xcode Project"
        case .xcworkspace:
            return "Workspace"
        case .swiftPackage:
            return "Swift Package"
        }
    }
}

private struct RepositoryDetailSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text(title)
                .font(DesignSystem.Typography.sectionTitle)
                .foregroundStyle(DesignSystem.Colors.primaryText)

            content
        }
    }
}

private struct RepositoryInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Text(label)
                .font(DesignSystem.Typography.rowSecondary)
                .foregroundStyle(DesignSystem.Colors.secondaryText)

            Spacer()

            Text(value)
                .font(DesignSystem.Typography.rowPrimary)
                .foregroundStyle(DesignSystem.Colors.primaryText)
                .multilineTextAlignment(.trailing)
        }
    }
}
