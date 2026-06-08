## 1. Data Model

- [x] 1.1 Create `XcodeProjectType.swift` — `enum XcodeProjectType: String, Codable, Sendable` with cases `.xcodeproj`, `.xcworkspace`, `.swiftPackage`
- [x] 1.2 Add optional `xcodeProjectType: XcodeProjectType?` and `detectedProjectFilePath: String?` fields to `GitMonitoredRepository` with `nil` defaults
- [x] 1.3 Verify existing `GitMonitoredRepository` fixtures decode correctly with missing new fields (update `GitMonitorStorageTests` if needed)

## 2. XcodeProjectDetector Service

- [x] 2.1 Add `XcodeProjectDetecting` protocol to `ServiceProtocols.swift` — `func detectProjectType(at repositoryPath: String) async -> (type: XcodeProjectType, projectFilePath: String)?`
- [x] 2.2 Create `XcodeProjectDetector.swift` as an `actor` conforming to `XcodeProjectDetecting` — scans repository root for `.xcodeproj`, `.xcworkspace`, `Package.swift` in that priority order
- [x] 2.3 Write unit tests in `XTopTests` covering each detection scenario (xcodeproj, xcworkspace, swiftPackage, none)

## 3. ExcludedArchsManager Service

- [x] 3.1 Add `ExcludedArchsManaging` protocol to `ServiceProtocols.swift` with methods `func dryRun(mode: ExcludedArchsMode, projectFilePath: String) async throws -> ExcludedArchsResult` and `func apply(mode: ExcludedArchsMode, projectFilePath: String) async throws -> ExcludedArchsResult`
- [x] 3.2 Create `ExcludedArchsMode.swift` — `enum ExcludedArchsMode: Sendable` with cases `.clearArm64`, `.setDebugArm64`
- [x] 3.3 Create `ExcludedArchsResult.swift` — `struct ExcludedArchsResult: Sendable` with `changedBlocks: Int`, `changedLines: Int`, `debugBlocksChanged: Int`, `nonDebugBlocksChanged: Int`, `backupPath: String?`, `message: String`
- [x] 3.4 Create `ExcludedArchsManager.swift` as an `actor` conforming to `ExcludedArchsManaging`:
  - Parse `XCBuildConfiguration` section using brace-depth block scanner (mirrors ruby logic)
  - For `.clearArm64`: replace `EXCLUDED_ARCHS = arm64;` → `EXCLUDED_ARCHS = "";` in all blocks
  - For `.setDebugArm64`: in `Debug` blocks, update or insert `EXCLUDED_ARCHS = arm64;` in `buildSettings`
  - Write timestamped backup before applying; handle collision with incrementing suffix
  - Dry-run returns result without writing any file
- [x] 3.5 Write unit tests using fixture `project.pbxproj` files covering: clear-arm64 success, set-debug-arm64 insert, set-debug-arm64 update, dry-run (no file written), no-op (no changes required), missing `XCBuildConfiguration` section error

## 4. MacbarViewModel Wiring

- [x] 4.1 Add `XcodeProjectDetecting` and `ExcludedArchsManaging` as `@ObservationIgnored private let` properties on `MacbarViewModel`
- [x] 4.2 Add both as explicit parameters to `MacbarViewModel.init`, with concrete defaults constructed in the initializer for the production path
- [x] 4.3 Add `func scanProjectType(for repositoryID: UUID) async` on `MacbarViewModel` — calls detector, then updates the repository via `gitMonitorService` and refreshes `gitMonitorRegistry`
- [x] 4.4 Add `func dryRunArchsAction(mode: ExcludedArchsMode, repositoryID: UUID) async throws -> ExcludedArchsResult` on `MacbarViewModel`
- [x] 4.5 Add `func applyArchsAction(mode: ExcludedArchsMode, repositoryID: UUID) async throws -> ExcludedArchsResult` on `MacbarViewModel`
- [x] 4.6 Wire concrete `XcodeProjectDetector` and `ExcludedArchsManager` instances in `XTopApp` where `MacbarViewModel` is constructed
- [x] 4.7 Update `GitMonitorService` protocol and `DefaultGitMonitorService` with `func updateRepositoryMetadata(id: UUID, xcodeProjectType: XcodeProjectType?, detectedProjectFilePath: String?) async`

## 5. Repository Detail UI

- [x] 5.1 Create `RepositoryDetailView.swift` — top-level sheet view accepting a `repositoryID: UUID`, reading state from `@Environment(MacbarViewModel.self)`:
  - Header: display name, path (truncated), project type badge
  - Git status section: branch, staged/unstaged/untracked counts, ahead/behind, last sync
  - Project detection section: badge, "Scan Project" button with loading state
  - Arch Manager panel (conditional on xcodeproj/xcworkspace) — see task 5.2
  - Reserved simulator slot: disabled "Run on Simulator" button with help tooltip "Coming soon"
- [x] 5.2 Create `ArchManagerActionPanel.swift` — embedded panel within `RepositoryDetailView`:
  - "Clear arm64" button — triggers dry-run then shows confirmation sheet
  - "Set Debug arm64" button — triggers dry-run then shows confirmation sheet
  - Confirmation sheet shows `ExcludedArchsResult` summary (changed blocks/lines)
  - On confirm, calls `applyArchsAction` and shows result banner
  - Error handling: surface `Error` as inline alert
- [x] 5.3 Add project type badge component (inline in detail view or small private struct) — maps `XcodeProjectType?` to a label string and `.tint` colour
- [x] 5.4 Apply `DesignSystem.Spacing`, `DesignSystem.Typography`, `DesignSystem.Colors` throughout; no hard-coded padding or font sizes

## 6. GitMonitorCard & Settings Integration

- [x] 6.1 Add a "Manage →" button to each repository row in `GitMonitorCard` (or the existing row component) that sets a `@State var managedRepositoryID: UUID?` and presents `RepositoryDetailView` as a sheet
- [x] 6.2 Add project type badge to `RepositorySettingsRow` in `GitMonitorSettingsView` — same badge component used in detail view
- [x] 6.3 Verify `GitMonitorCard` sheet presentation uses `sheet(item:)` or `sheet(isPresented:)` correctly with the repository ID

## 7. Tests & Cleanup

- [x] 7.1 Update `GitMonitorRegistryLifecycleTests` and `GitMonitorStorageTests` to cover new `GitMonitoredRepository` fields
- [ ] 7.2 Add view model tests for `scanProjectType` and `applyArchsAction` using stub service implementations
- [ ] 7.3 Build the target and resolve any Swift 6 concurrency warnings introduced by new actors/protocols
- [ ] 7.4 Confirm `ExcludedArchsManager` unit tests pass with all fixture scenarios
