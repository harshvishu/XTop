## Why

The repositories feature in XTop currently tracks git repositories for monitoring purposes only, with no awareness of project type. Developers working on Xcode/iOS/Swift projects need a dedicated toolset — specifically the ability to manage `EXCLUDED_ARCHS` in their `project.pbxproj` to toggle arm64 exclusion for Rosetta compatibility — without leaving XTop or reaching for a separate script. A full-fledged repository detail UI with project-type awareness lays the groundwork for this and future actions like running projects on simulators.

## What Changes

- `GitMonitoredRepository` gains an optional `xcodeProjectType` field to classify detected Xcode project types (`.xcodeproj`, `.xcworkspace`, SPM `Package.swift`)
- A new `XcodeProjectDetector` service scans a repository path and returns the detected project type and primary project file path
- A new `ExcludedArchsManager` service wraps the `excluded-archs` logic (clear arm64 / set-debug-arm64) against a `project.pbxproj` file using native Swift — no external ruby/bash dependency
- A full-fledged **Repositories detail view** replaces the minimal settings row, with sections for git status, detected project type, and available actions
- An **Arch Manager action panel** appears within the repository detail when an Xcode project is detected, with `Clear arm64` and `Set Debug arm64` buttons and dry-run preview
- The `GitMonitorCard` on the dashboard is updated to surface a "Manage" button that opens the new detail view
- UI is designed with a placeholder slot for a future **Run on Simulator** button

## Capabilities

### New Capabilities

- `xcode-project-detection`: Detects whether a monitored repository contains an Xcode project (`.xcodeproj`), Xcode workspace (`.xcworkspace`), or Swift Package (`Package.swift`) and records the result on the repository model
- `excluded-archs-manager`: Allows the user to clear arm64 exclusions or set Debug arm64 exclusions in a repository's `project.pbxproj`, with optional dry-run preview and automatic backup creation
- `repository-detail-view`: A dedicated full-fledged UI for a single monitored repository showing git status, project type badge, available developer actions, and a reserved slot for future simulator integration

### Modified Capabilities

- `swift6-environment-injection`: The new services (`XcodeProjectDetector`, `ExcludedArchsManager`) must be injected via the existing environment injection pattern and exposed on `MacbarViewModel`

## Impact

- `GitMonitoredRepository` model (add `xcodeProjectType`, `detectedProjectFilePath`)
- `MacbarViewModel` — new service dependencies, new published state, action methods
- `GitMonitorCard` / `DashboardRootView` — minor update to add "Manage" entry point
- `GitMonitorSettingsView` — repository rows gain project-type badge
- New files: `XcodeProjectDetector.swift`, `ExcludedArchsManager.swift`, `RepositoryDetailView.swift`, `ArchManagerActionPanel.swift`, `XcodeProjectType.swift`
- No new third-party dependencies; ruby/bash script is replaced by a pure Swift implementation
