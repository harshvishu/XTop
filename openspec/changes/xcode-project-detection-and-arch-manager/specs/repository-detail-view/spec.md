# repository-detail-view Specification

## ADDED Requirements

### Requirement: Repository detail sheet accessible from GitMonitorCard
The system SHALL provide a "Manage" entry point on each repository row in `GitMonitorCard` that opens `RepositoryDetailView` as a sheet.

#### Scenario: User opens repository detail
- **WHEN** the user taps the "Manage" button on a repository row in `GitMonitorCard`
- **THEN** `RepositoryDetailView` is presented as a sheet for that repository

### Requirement: RepositoryDetailView shows git status section
The system SHALL display current git status information for the selected repository in the detail view, including branch, staged/unstaged/untracked counts, ahead/behind counts, and last sync time.

#### Scenario: Repository has git snapshot data
- **WHEN** `RepositoryDetailView` opens for a repository with a `GitRepositorySnapshot`
- **THEN** the git status section shows branch name, change counts, and ahead/behind indicators

#### Scenario: Repository has no snapshot yet
- **WHEN** `RepositoryDetailView` opens for a repository with no snapshot
- **THEN** the git status section shows a "No data yet" placeholder in secondary style

### Requirement: RepositoryDetailView shows project type section with scan action
The system SHALL display the detected project type (or "Not scanned") and a "Scan Project" button that triggers `XcodeProjectDetector`.

#### Scenario: User scans project type
- **WHEN** the user taps "Scan Project"
- **THEN** detection runs, the badge updates to reflect the result, and any loading state is shown during the scan

#### Scenario: Scan is in progress
- **WHEN** detection is running
- **THEN** the Scan button shows a progress indicator and is disabled

### Requirement: RepositoryDetailView shows Arch Manager panel for eligible repositories
The system SHALL display the Arch Manager panel when the repository has a detected project type of `xcodeproj` or `xcworkspace`.

#### Scenario: Arch manager panel is visible
- **WHEN** the repository detail opens for an xcodeproj repository
- **THEN** the Arch Manager panel shows "Clear arm64" and "Set Debug arm64" buttons

#### Scenario: Arch action requires confirmation
- **WHEN** the user taps an arch action button
- **THEN** a dry-run runs and a confirmation sheet shows the summary before any file is modified

#### Scenario: Action result is shown
- **WHEN** an arch action completes (success or failure)
- **THEN** a result banner or alert is shown with the outcome message

### Requirement: RepositoryDetailView reserves a Simulator slot
The system SHALL display a disabled "Run on Simulator" button in the detail view as a placeholder for future simulator integration.

#### Scenario: Simulator slot is visible but disabled
- **WHEN** the repository detail view is displayed for any repository
- **THEN** a "Run on Simulator" button is visible, disabled, and has a help tooltip stating the feature is coming soon

### Requirement: Detail view layout follows XTop design guidelines
The system SHALL use compact spacing, `DesignSystem.Spacing`, `DesignSystem.Typography`, `DesignSystem.Colors`, and avoid unnecessary card containers or decorative backgrounds.

#### Scenario: View renders with correct design tokens
- **WHEN** `RepositoryDetailView` is rendered
- **THEN** all spacing, typography, and colors are sourced from `DesignSystem` constants and no hard-coded pixel values appear for padding or font sizes
