## Why

`MacbarViewModel` currently reaches main-actor-isolated singleton state through `.shared` defaults, which produces Swift 6 actor-isolation warnings and hides app state ownership. Fixing this now keeps `XTop` aligned with SwiftUI's modern `@Observable` data-flow model before more menu bar and settings surfaces depend on the same shared models.

## What Changes

- Replace `MacbarPreferences.shared`, `SensorSettingsModel.shared`, and `DeveloperDiagnosticsStore.shared` with single app-owned instances created at the SwiftUI root.
- Inject the app-owned instances through SwiftUI `Environment` so menu bar content, settings content, and child views consume the same models without static singleton access.
- Update `MacbarViewModel` initialization so preferences, sensor settings, diagnostics, and services are explicit dependencies rather than defaulting to main-actor-isolated static properties.
- Resolve the `MainActor.run` capture warnings in `MacbarViewModel` by keeping mutations on the main actor and using explicit capture semantics.
- Remove any previously added `nonisolated` workaround from observable models, model properties, or pure value types when the actual issue is app state ownership.
- Preserve the existing menu bar UX and focused unit-test verification path while making the dependency graph testable.

## Capabilities

### New Capabilities
- `swift6-environment-injection`: Define Swift 6-safe ownership and injection rules for XTop's shared app models and `MacbarViewModel` dependencies.

### Modified Capabilities
- None.

## Impact

- Affects `XTop/App/XTopApp.swift`, `XTop/ViewModels/MacbarViewModel.swift`, `XTop/Views/SettingsRootView.swift`, `XTop/Views/SettingsView.swift`, and any menu bar/dashboard views that read preferences, sensors, diagnostics, or the monitor view model.
- May require small environment-key or `@Entry` definitions for `MacbarPreferences`, `SensorSettingsModel`, `DeveloperDiagnosticsStore`, and the root `MacbarViewModel`.
- Keeps `@Observable` UI-bound types main-actor isolated and avoids marking their properties or value-model members `nonisolated`.
- Verification should include a clean app build plus focused `XTopTests` execution; full UI-test execution may remain unreliable for this menu-bar-only app.
