# swift6-environment-injection Specification

## Purpose
TBD - created by archiving change fix-swift6-environment-injection. Update Purpose after archive.
## Requirements
### Requirement: Root-Owned Shared App State
XTop SHALL create exactly one app-owned instance of each shared observable model needed by the menu bar and settings surfaces during app startup.

#### Scenario: App starts
- **WHEN** XTop starts its SwiftUI app scene
- **THEN** the app owns one `MacbarPreferences`, one `SensorSettingsModel`, one `DeveloperDiagnosticsStore`, and one root `MacbarViewModel`

#### Scenario: Shared state identity is preserved
- **WHEN** SwiftUI refreshes the menu bar or settings scene
- **THEN** the shared observable model instances retain identity instead of being recreated by child views

### Requirement: Environment Injection For Shared Models
XTop SHALL inject shared observable models through SwiftUI environment so menu bar and settings content read the same app-owned instances.

#### Scenario: Menu bar reads shared state
- **WHEN** the menu bar panel renders preferences, sensor state, diagnostics, or monitor state
- **THEN** it reads the app-owned instances from SwiftUI environment

#### Scenario: Settings reads shared state
- **WHEN** the settings scene renders preferences, sensor state, diagnostics, or monitor state
- **THEN** it reads the same app-owned instances from SwiftUI environment

#### Scenario: Settings mutates preferences
- **WHEN** a settings control updates an observable preference
- **THEN** the mutation updates the app-owned `MacbarPreferences` instance and is visible to menu bar content using that same instance

### Requirement: No Observable Singletons
XTop SHALL NOT use static singleton instances for `@Observable` app state models.

#### Scenario: Observable model definitions are reviewed
- **WHEN** `MacbarPreferences`, `SensorSettingsModel`, and `DeveloperDiagnosticsStore` are inspected
- **THEN** none of them defines or exposes `static let shared`

#### Scenario: View model dependencies are initialized
- **WHEN** `MacbarViewModel` is initialized
- **THEN** preferences, sensor settings, and diagnostics are passed explicitly rather than defaulting to singleton instances

### Requirement: Swift 6 Main Actor Safety
XTop SHALL resolve `MacbarViewModel` actor-isolation diagnostics by preserving main-actor ownership for UI state and using explicit actor-safe dependency boundaries.

#### Scenario: Main actor observable state is mutated
- **WHEN** `MacbarViewModel` updates telemetry, Xcode context, Git context, tool availability, diagnostics, or task state
- **THEN** the mutation occurs from main-actor-isolated code

#### Scenario: Background context collection completes
- **WHEN** slow developer-context collection finishes
- **THEN** `MacbarViewModel` applies the resulting snapshot on the main actor without relying on `nonisolated` observable or domain model properties

#### Scenario: Swift build emits diagnostics
- **WHEN** the app target is built with the existing approachable concurrency and default main actor isolation settings
- **THEN** no main-actor-isolation warnings remain in `MacbarViewModel`

### Requirement: Explicit Testable Dependencies
XTop SHALL keep view-model service dependencies explicit so tests can construct isolated model graphs without process-global state.

#### Scenario: Focused test creates a view model
- **WHEN** a unit test creates `MacbarViewModel`
- **THEN** it can provide explicit preferences, sensor settings, diagnostics, and service doubles without reading any singleton

#### Scenario: App creates production dependencies
- **WHEN** XTop creates production dependencies
- **THEN** the app root wires concrete services once and passes them into the root `MacbarViewModel`

