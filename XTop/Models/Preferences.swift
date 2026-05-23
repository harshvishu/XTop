import Foundation
import Observation
import SwiftUI

// MARK: - Menu Bar Summary Mode

enum MenuBarSummaryMode: String, CaseIterable, Identifiable {
    case cpuAndMemory
    case cpuOnly
    case iconOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpuAndMemory:
            "CPU and Memory"
        case .cpuOnly:
            "CPU Only"
        case .iconOnly:
            "Status Icon"
        }
    }
}

// MARK: - Dashboard Density

enum DashboardDensity: String, CaseIterable, Identifiable {
    case compact
    case comfortable

    var id: String { rawValue }

    var title: String {
        rawValue.capitalized
    }

    var width: CGFloat {
        switch self {
        case .compact:
            280
        case .comfortable:
            320
        }
    }
}

// MARK: - Refresh Interval

enum RefreshInterval: String, CaseIterable, Identifiable {
    case twoSeconds
    case fiveSeconds
    case tenSeconds

    var id: String { rawValue }

    var title: String {
        switch self {
        case .twoSeconds:
            "2 seconds"
        case .fiveSeconds:
            "5 seconds"
        case .tenSeconds:
            "10 seconds"
        }
    }

    var seconds: TimeInterval {
        switch self {
        case .twoSeconds:
            2
        case .fiveSeconds:
            5
        case .tenSeconds:
            10
        }
    }
}

// MARK: - Preferences

@MainActor
@Observable
final class MacbarPreferences {
    var menuBarSummaryMode: MenuBarSummaryMode {
        didSet {
            defaults.set(
                menuBarSummaryMode.rawValue,
                forKey: Keys.menuBarSummaryMode
            )
        }
    }

    var dashboardDensity: DashboardDensity {
        didSet {
            defaults.set(
                dashboardDensity.rawValue,
                forKey: Keys.dashboardDensity
            )
        }
    }

    var refreshInterval: RefreshInterval {
        didSet {
            defaults.set(
                refreshInterval.rawValue,
                forKey: Keys.refreshInterval
            )
        }
    }

    var includesDeveloperProcesses: Bool {
        didSet {
            defaults.set(
                includesDeveloperProcesses,
                forKey: Keys.includesDeveloperProcesses
            )
        }
    }

    @ObservationIgnored
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        self.menuBarSummaryMode = MenuBarSummaryMode(
            rawValue: defaults.string(
                forKey: Keys.menuBarSummaryMode
            ) ?? ""
        ) ?? .cpuAndMemory

        self.dashboardDensity = DashboardDensity(
            rawValue: defaults.string(
                forKey: Keys.dashboardDensity
            ) ?? ""
        ) ?? .compact

        self.refreshInterval = RefreshInterval(
            rawValue: defaults.string(
                forKey: Keys.refreshInterval
            ) ?? ""
        ) ?? .twoSeconds

        self.includesDeveloperProcesses =
            defaults.object(
                forKey: Keys.includesDeveloperProcesses
            ) as? Bool ?? true
    }

    private enum Keys {
        static let menuBarSummaryMode =
            "preferences.menuBarSummaryMode"
        static let dashboardDensity =
            "preferences.dashboardDensity"
        static let refreshInterval =
            "preferences.refreshInterval"
        static let includesDeveloperProcesses =
            "preferences.includesDeveloperProcesses"
    }
}
