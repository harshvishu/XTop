import Foundation
import SwiftUI

/// Centralized design tokens for the Simulator Inspector and other newer surfaces.
///
/// Kept intentionally compact per the project's UI rules: flat surfaces, subtle
/// separation, controlled hierarchy. Existing screens may continue using their
/// local `DashboardTheme` until migrated.
enum DesignSystem {
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let section: CGFloat = 20
        static let rowVertical: CGFloat = 6
        static let rowHorizontal: CGFloat = 10
    }

    enum Typography {
        static let title = Font.title3.weight(.semibold)
        static let sectionTitle = Font.headline
        static let body = Font.body
        static let rowPrimary = Font.callout
        static let rowSecondary = Font.caption
        static let monoBody = Font.system(.body, design: .monospaced)
        static let monoRow = Font.system(.callout, design: .monospaced)
        static let monoCaption = Font.system(.caption, design: .monospaced)
    }

    enum Colors {
        static let primaryText = Color.primary
        static let secondaryText = Color.secondary
        static let tertiaryText = Color.secondary.opacity(0.7)
        static let stroke = Color.primary.opacity(0.08)
        static let rowHover = Color.primary.opacity(0.06)
        static let destructive = Color.red
        static let accent = Color.accentColor
        static let warningBackground = Color.orange.opacity(0.12)
        static let warningStroke = Color.orange.opacity(0.4)
    }

    enum Radius {
        static let row: CGFloat = 6
        static let card: CGFloat = 10
    }
}
