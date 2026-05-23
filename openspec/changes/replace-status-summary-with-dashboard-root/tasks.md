## 1. Confirm Dashboard Integration Scope

- [ ] 1.1 Confirm `MenuBarPanelView` renders `DashboardRootView` as the primary dashboard content.
- [ ] 1.2 Confirm `DashboardRootView` reads shared telemetry and settings from the root-injected `MacbarViewModel` environment instance.

## 2. Fix Async Dashboard Actions

- [ ] 2.1 Replace direct synchronous calls to `performMaintenanceAction(_:)` in the confirmation dialog with an awaited async task.
- [ ] 2.2 Replace direct synchronous calls to `performMaintenanceAction(_:)` in dashboard utility rows with awaited async tasks.
- [ ] 2.3 Keep maintenance action state cleanup on the main actor after confirmed actions are scheduled.

## 3. SwiftUI Compatibility Pass

- [ ] 3.1 Remove compile-blocking Swift concurrency mismatches introduced by the copied dashboard view.
- [ ] 3.2 Check for obvious SwiftUI data-flow regressions such as local view-model ownership or singleton use in the dashboard path.

## 4. Verify

- [ ] 4.1 Build the `XTop` scheme and confirm `DashboardRootView` compiles.
- [ ] 4.2 Run focused `XTopTests`.
- [ ] 4.3 Run the app verification script to confirm the menu bar app launches with the dashboard-enabled build.
- [ ] 4.4 Re-run OpenSpec status and confirm all tasks are tracked.
