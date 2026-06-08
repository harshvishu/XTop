## Context

XTop monitors git repositories and surfaces developer tools in a macOS menu bar app. Repositories are currently plain data containers (`GitMonitoredRepository`) with no awareness of project type. The `MacbarViewModel` wires all services and is the single source of truth for view state.

A developer's common pain point working on Xcode projects with a Rosetta environment is the need to modify `EXCLUDED_ARCHS` in `project.pbxproj` — removing `arm64` to run on a real device (reverting Rosetta simulator exclusions) or re-adding it for the Debug configuration. The existing external bash+ruby script solves this but is not integrated into any UI.

The new surfaces must follow existing patterns: `@Observable @MainActor` services, explicit dependency injection into `MacbarViewModel`, SwiftUI views consuming environment-injected state, and `DesignSystem` constants for layout.

## Goals / Non-Goals

**Goals:**
- Detect whether a monitored repository contains an Xcode project, workspace, or Swift Package
- Persist the detected project type and primary project file path on `GitMonitoredRepository`
- Expose an `ExcludedArchsManager` service that applies `clear` or `set-debug-arm64` mutations to a `project.pbxproj`, with backup and dry-run support
- Provide a full `RepositoryDetailView` with git status, project type badge, Arch Manager action panel, and a reserved slot for future Simulator integration
- Wire new services through the existing DI pattern on `MacbarViewModel`

**Non-Goals:**
- Running the project on a simulator (reserved UI slot only — no implementation yet)
- Supporting Podfile simulator exclusion edits (out of scope per original script notes)
- Automatic/scheduled re-detection of project type (on-demand only via explicit scan)
- Modifying `.xcconfig` files or SPM manifests

## Decisions

### 1. Pure Swift `ExcludedArchsManager` (no ruby/bash subprocess)

**Decision**: Reimplement the ruby script logic in Swift using `String` manipulation and `FileManager`, rather than spawning a subprocess to run the original script.

**Rationale**: Eliminates a ruby runtime dependency, avoids subprocess sandboxing issues on macOS, keeps the logic testable with `XCTest`, and removes the need to bundle or locate an external script file.

**Alternatives considered**:
- Bundle the bash script as a resource and invoke via `Process` — rejected because sandbox restrictions on macOS apps make spawning shell scripts fragile and require entitlements.
- Use `NSRegularExpression` for the parsing — rejected in favour of line-by-line character-scanning which more closely mirrors the original and is easier to reason about.

### 2. Detection on explicit scan, result persisted on `GitMonitoredRepository`

**Decision**: Add `xcodeProjectType: XcodeProjectType?` and `detectedProjectFilePath: String?` to `GitMonitoredRepository`. Detection runs when the user taps "Scan" in the detail view (or automatically on first load if never scanned). The result is persisted via the existing `GitRepositoryRegistryStore`.

**Rationale**: Detection requires filesystem access which may be slow or fail; on-demand scanning with a persisted result avoids blocking the monitoring loop. Persisting avoids re-scanning on every view open.

**Alternatives considered**:
- Compute project type transiently in `GitRepositorySnapshot` — rejected because it conflates monitoring state (transient git status) with static project metadata.
- Auto-scan in the monitoring scheduler — rejected to keep the scheduler focused on git operations and avoid filesystem overhead on every refresh cycle.

### 3. `RepositoryDetailView` as a SwiftUI sheet from `GitMonitorCard`

**Decision**: The detail view is presented as a sheet triggered from a per-repository row in `GitMonitorCard`. It receives the repository ID and reads current state via `@Environment(MacbarViewModel.self)`.

**Rationale**: Consistent with how `SimulatorInspectorCard` launches a separate window; sheets work well for focused per-item detail on macOS popover panels. No new window controller needed.

**Alternatives considered**:
- Navigation stack push from a list — rejected because the dashboard panel is not a NavigationStack and restructuring it would be a large change.
- Separate NSWindow — rejected as heavier than needed for a focused action panel.

### 4. `XcodeProjectType` as a dedicated enum

**Decision**: Introduce `enum XcodeProjectType: String, Codable, Sendable` with cases `.xcodeproj`, `.xcworkspace`, `.swiftPackage`. The detection service returns an optional value.

**Rationale**: Strongly typed; directly drives badge display and determines which project file path to pass to `ExcludedArchsManager` (only `.xcodeproj` and `.xcworkspace` have a `project.pbxproj`).

### 5. Dry-run output as a `String?` stored in view state

**Decision**: The `ArchManagerActionPanel` performs a dry-run first, storing the textual output in local `@State`. Confirmation sheet shows the output before the user commits.

**Rationale**: Mirrors the original script's `--dry-run` flag; gives the user visibility into what will change before committing. Avoids a separate service call model; the dry-run result is transient UI state.

## Risks / Trade-offs

- **`project.pbxproj` parsing fragility** → Mitigation: Use the same block-scanning approach as the original ruby script (find `XCBuildConfiguration` section, scan brace depth). Add a unit test with real fixture files. If parsing fails, surface an error without modifying the file.
- **Large `project.pbxproj` performance** → Mitigation: File read and write are O(n) in file size; typical Xcode project files are < 5 MB. Acceptable for an explicit user-triggered action.
- **File written while Xcode has it open** → Mitigation: Xcode re-reads `project.pbxproj` on focus; writing from outside is the standard workflow for scripts like `xcodegen`. Document in UI that Xcode may prompt to reload.
- **`GitMonitoredRepository` model migration** → Mitigation: New fields are `Optional` with `nil` defaults so existing persisted registries decode correctly without migration.
- **Simulator run slot** → The reserved UI slot must remain visually coherent but non-interactive. Use a disabled `Button` with a `help` tooltip indicating "coming soon".

## Migration Plan

1. Add new optional fields to `GitMonitoredRepository` (backward-compatible decode)
2. Add new protocol `XcodeProjectDetecting` and `ExcludedArchsManaging` to `ServiceProtocols.swift`
3. Add concrete implementations and wire into `XTopApp` / `MacbarViewModel`
4. Add `RepositoryDetailView`, `ArchManagerActionPanel` as new SwiftUI files
5. Update `GitMonitorCard` to add a per-row "Manage →" button that presents the detail sheet

Rollback: Remove new files and revert `GitMonitoredRepository`, `ServiceProtocols`, and `MacbarViewModel` changes. Existing registry data decodes safely due to optional fields.

## Open Questions

- Should detection also recognise `Package.swift`-only repos for the arch manager, or only repos with a `.xcodeproj`? (Current design: arch manager only activates for `.xcodeproj`/`.xcworkspace`; SPM badge shown but no arch action.)
- Should a backup of `project.pbxproj` be kept indefinitely or auto-cleaned after N days? (Current: kept indefinitely, user can clean manually.)
