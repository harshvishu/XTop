## Why

The menu bar panel now needs to use the richer `DashboardRootView` UI that was copied from the older macOS app, but the imported view still assumes synchronous maintenance actions. This leaves the project unable to compile after the Swift concurrency refactor.

## What Changes

- Replace the status summary section in `MenuBarPanelView` with `DashboardRootView` as the primary panel content.
- Adapt `DashboardRootView` maintenance action triggers to the async `MacbarViewModel.performMaintenanceAction(_:)` API.
- Keep shared dashboard data coming from the root-injected `MacbarViewModel` environment instance.
- Preserve the imported dashboard layout while removing compile errors and obvious SwiftUI/concurrency regressions.

## Capabilities

### New Capabilities
- `dashboard-root-menu-bar`: Covers using the full dashboard root as the menu bar panel content and wiring its actions to the app's async view-model API.

### Modified Capabilities

## Impact

- Affects `XTop/Views/MenuBarPanelView.swift` and `XTop/Views/DashboardRootView.swift`.
- Uses existing `MacbarViewModel`, telemetry, Xcode, Git, sensor, diagnostics, and maintenance models.
- No new third-party dependencies or external APIs.
