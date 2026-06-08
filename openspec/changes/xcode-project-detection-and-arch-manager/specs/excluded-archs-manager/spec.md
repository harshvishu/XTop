# excluded-archs-manager Specification

## ADDED Requirements

### Requirement: Apply clear-arm64 mutation to project.pbxproj
The system SHALL replace all unscoped `EXCLUDED_ARCHS = arm64;` entries in the `XCBuildConfiguration` section of a `project.pbxproj` with `EXCLUDED_ARCHS = "";`, across all build configurations.

#### Scenario: Clear arm64 succeeds
- **WHEN** the user confirms the "Clear arm64" action for a repository with an `.xcodeproj`
- **THEN** all `EXCLUDED_ARCHS = arm64;` lines in the `XCBuildConfiguration` section become `EXCLUDED_ARCHS = "";` and the file is written atomically with a timestamped backup

#### Scenario: No arm64 exclusions present
- **WHEN** the project file contains no `EXCLUDED_ARCHS = arm64;` entries
- **THEN** the file is not modified and the system reports "No changes required"

### Requirement: Apply set-debug-arm64 mutation to project.pbxproj
The system SHALL ensure every `Debug` build configuration block in `XCBuildConfiguration` has `EXCLUDED_ARCHS = arm64;`. If the entry is missing it SHALL be inserted; if it exists with a different value it SHALL be updated.

#### Scenario: Set Debug arm64 on configuration with existing entry
- **WHEN** a Debug block already has `EXCLUDED_ARCHS` set to a value other than `arm64`
- **THEN** that line is updated to `EXCLUDED_ARCHS = arm64;` and a backup is written

#### Scenario: Set Debug arm64 on configuration with missing entry
- **WHEN** a Debug block has no `EXCLUDED_ARCHS` entry
- **THEN** `EXCLUDED_ARCHS = arm64;` is inserted inside the `buildSettings` block and a backup is written

#### Scenario: Non-Debug configurations are not modified
- **WHEN** the set-debug-arm64 action runs
- **THEN** Release and any other non-Debug configuration blocks are not modified

### Requirement: Dry-run preview before mutation
The system SHALL offer a dry-run mode that produces a textual summary of the changes that would be made, without modifying the file.

#### Scenario: Dry run produces summary
- **WHEN** the user initiates a dry-run
- **THEN** the system returns a summary string listing affected block count, changed lines, and debug vs non-debug breakdown, without writing any file

#### Scenario: Confirmation sheet shows dry-run output
- **WHEN** the user taps an arch manager action button
- **THEN** a dry-run runs automatically and the confirmation sheet displays its summary before the user confirms

### Requirement: Automatic timestamped backup before mutation
The system SHALL write a timestamped backup of the original `project.pbxproj` before applying any mutation.

#### Scenario: Backup is created on apply
- **WHEN** a mutation is applied
- **THEN** a file named `project.pbxproj.backup.<timestamp>` is written to the same directory before the new content is written

#### Scenario: Backup filename collision is resolved
- **WHEN** a backup file with the same timestamp already exists
- **THEN** an incrementing numeric suffix is appended until the path is unique

### Requirement: Arch manager only available for xcodeproj and xcworkspace repositories
The system SHALL only display the Arch Manager action panel for repositories whose detected project type is `xcodeproj` or `xcworkspace`. Repositories with `swiftPackage` or undetected type SHALL NOT show arch manager controls.

#### Scenario: xcodeproj repository shows arch manager
- **WHEN** a repository detail view opens for a repository with `xcodeProjectType == .xcodeproj`
- **THEN** the Arch Manager panel is visible with both action buttons

#### Scenario: Swift Package repository hides arch manager
- **WHEN** a repository detail view opens for a repository with `xcodeProjectType == .swiftPackage`
- **THEN** no Arch Manager panel is shown
