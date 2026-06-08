import SwiftUI

struct RepositoryProjectTypeBadge: View {
    let projectType: XcodeProjectType?

    var body: some View {
        Text(label)
            .font(DesignSystem.Typography.rowSecondary)
            .foregroundStyle(foreground)
            .padding(.horizontal, DesignSystem.Spacing.sm)
            .padding(.vertical, DesignSystem.Spacing.xs)
            .background(background)
            .clipShape(.rect(cornerRadius: DesignSystem.Radius.row))
    }

    private var label: String {
        switch projectType {
        case .xcodeproj:
            return "Xcode Project"
        case .xcworkspace:
            return "Workspace"
        case .swiftPackage:
            return "Swift Package"
        case nil:
            return "Not scanned"
        }
    }

    private var foreground: Color {
        switch projectType {
        case .xcodeproj:
            return DesignSystem.Colors.accent
        case .xcworkspace:
            return .green
        case .swiftPackage:
            return .orange
        case nil:
            return DesignSystem.Colors.secondaryText
        }
    }

    private var background: Color {
        switch projectType {
        case .xcodeproj:
            return DesignSystem.Colors.accent.opacity(0.12)
        case .xcworkspace:
            return Color.green.opacity(0.12)
        case .swiftPackage:
            return Color.orange.opacity(0.12)
        case nil:
            return DesignSystem.Colors.rowHover
        }
    }
}
