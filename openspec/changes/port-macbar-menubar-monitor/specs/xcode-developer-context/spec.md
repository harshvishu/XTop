## ADDED Requirements

### Requirement: Xcode environment context is read-only
XTop SHALL collect and display read-only Xcode environment context including DerivedData usage, open Xcode project or workspace context, provisioning profile summaries, and code-signing certificate summaries.

#### Scenario: Xcode context is collected
- **WHEN** Xcode environment collectors return data
- **THEN** the dashboard shows the collected DerivedData, project, profile, and certificate summaries without mutating local developer state

#### Scenario: Xcode context is partial
- **WHEN** one Xcode environment subsection cannot be collected
- **THEN** the dashboard preserves available Xcode context and exposes an error or unavailable state for the failed subsection

### Requirement: Focused project Git context is shown
XTop SHALL resolve a focused or user-selected project path and show read-only Git repository, branch, and worktree context when the project belongs to a Git repository.

#### Scenario: Focused project is in a Git repository
- **WHEN** XTop resolves a focused Xcode project path inside a Git repository
- **THEN** the dashboard shows repository context, current branch information, and worktree information for that project

#### Scenario: Focused project is unresolved
- **WHEN** focused Xcode project resolution is unavailable or ambiguous
- **THEN** the dashboard provides a clear unresolved state and a way to refresh context from a user-selected project path

#### Scenario: Selected project has no Git repository
- **WHEN** the resolved project path does not belong to a Git repository
- **THEN** the dashboard reports that Git context is unavailable without hiding Xcode environment context

### Requirement: Developer context refresh does not block telemetry
XTop SHALL refresh slower Xcode and Git developer context independently from the baseline telemetry display path.

#### Scenario: Developer context scan is slow
- **WHEN** Xcode or Git context collection takes longer than a telemetry refresh
- **THEN** the dashboard can continue showing telemetry and last-known developer context while the developer-context refresh completes
