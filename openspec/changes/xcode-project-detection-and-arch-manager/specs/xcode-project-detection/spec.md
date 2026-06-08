# xcode-project-detection Specification

## ADDED Requirements

### Requirement: Detect Xcode project type for a monitored repository
The system SHALL scan a repository's root directory and classify it as containing an Xcode project (`.xcodeproj`), Xcode workspace (`.xcworkspace`), Swift Package (`Package.swift`), or no recognised project type.

#### Scenario: Repository contains an xcodeproj
- **WHEN** the user triggers a project scan for a monitored repository whose root contains a `.xcodeproj` bundle
- **THEN** the detected project type is set to `xcodeproj` and `detectedProjectFilePath` is set to the `.xcodeproj` path

#### Scenario: Repository contains an xcworkspace
- **WHEN** the user triggers a project scan for a repository whose root contains a `.xcworkspace` bundle and no `.xcodeproj`
- **THEN** the detected project type is set to `xcworkspace` and `detectedProjectFilePath` is set to the `.xcworkspace` path

#### Scenario: Repository contains only Package.swift
- **WHEN** the user triggers a project scan for a repository whose root contains `Package.swift` but no `.xcodeproj` or `.xcworkspace`
- **THEN** the detected project type is set to `swiftPackage` and `detectedProjectFilePath` is set to `Package.swift`

#### Scenario: Repository contains no recognised project
- **WHEN** the user triggers a project scan for a repository that has none of the above
- **THEN** `xcodeProjectType` remains `nil` and `detectedProjectFilePath` remains `nil`

### Requirement: Persist detected project type on the repository model
The system SHALL store `xcodeProjectType` and `detectedProjectFilePath` as optional fields on `GitMonitoredRepository` and persist them via the existing registry store.

#### Scenario: Scan result is saved
- **WHEN** a scan completes successfully
- **THEN** the updated `GitMonitoredRepository` is written to persistent storage and the in-memory registry is refreshed

#### Scenario: Existing registry loads without new fields
- **WHEN** a registry persisted before this change is loaded
- **THEN** `xcodeProjectType` decodes as `nil` and `detectedProjectFilePath` decodes as `nil` without a decoding error

### Requirement: Surface project type badge in repository UI
The system SHALL display a visible badge or label indicating the detected project type (or "Not scanned") in both `RepositoryDetailView` and `GitMonitorSettingsView` repository rows.

#### Scenario: Project type detected and displayed
- **WHEN** a repository has a non-nil `xcodeProjectType`
- **THEN** the repository row and detail view show the corresponding badge (e.g., "Xcode Project", "Workspace", "Swift Package")

#### Scenario: Repository not yet scanned
- **WHEN** `xcodeProjectType` is nil
- **THEN** the badge shows "Not scanned" in secondary style
