## ADDED Requirements

### Requirement: Dashboard root renders as menu bar content
The system SHALL render `DashboardRootView` as the primary content inside the menu bar panel while continuing to use the root-injected app state from SwiftUI environment.

#### Scenario: Menu bar panel opens dashboard
- **WHEN** the menu bar panel content is built
- **THEN** it displays `DashboardRootView` instead of the previous `StatusSummaryView` summary section

#### Scenario: Dashboard uses shared view model
- **WHEN** dashboard telemetry, Xcode, Git, sensor, diagnostics, or maintenance data is displayed
- **THEN** the dashboard reads from the same root-injected `MacbarViewModel` instance used by the menu bar scene

### Requirement: Dashboard maintenance actions use async view-model API
The system SHALL invoke maintenance actions from `DashboardRootView` through the async `MacbarViewModel.performMaintenanceAction(_:)` API without compile errors or synchronous blocking wrappers.

#### Scenario: Confirmed maintenance action runs
- **WHEN** the user confirms a destructive maintenance action in the dashboard confirmation dialog
- **THEN** the action is launched through an awaited async view-model call

#### Scenario: Direct utility action runs
- **WHEN** the user selects a dashboard utility action that does not require confirmation
- **THEN** the action is launched through an awaited async view-model call

### Requirement: Imported dashboard remains compatible with Swift 6 project rules
The system SHALL keep the imported dashboard compatible with the project's Swift 6 concurrency and SwiftUI environment data-flow rules.

#### Scenario: Project builds with dashboard enabled
- **WHEN** the XTop debug scheme is built for macOS
- **THEN** the build succeeds with `DashboardRootView` included in the target
