## 1. Trim The Imported Monitor Model

- [ ] 1.1 Audit the copied `macbar` dashboard and service files in `XTop` and identify the model, settings, and UI dependencies required only by the read-only monitor scope.
- [ ] 1.2 Add target-owned telemetry, Xcode context, Git context, and metric domain models needed by the system and developer-context dashboard sections.
- [ ] 1.3 Add a trimmed dashboard view model that schedules baseline telemetry refresh separately from slower Xcode and Git developer-context refresh.
- [ ] 1.4 Remove or isolate imported dependencies on advanced sensor setup, diagnostics history, and destructive maintenance actions from the first dashboard path.

## 2. Port The Menu Bar Host

- [ ] 2.1 Replace the placeholder `MenuBarExtra` panel path with an AppKit status-item and popover host derived from the working `macbar` menu bar behavior.
- [ ] 2.2 Wire dashboard model lifetime, sampling start/stop, and compact status-title updates into the status-item host.
- [ ] 2.3 Keep the settings scene and app activation behavior consistent with a menu-bar-first XTop launch path.

## 3. Build The Read-Only Dashboard

- [ ] 3.1 Trim the imported dashboard view to render baseline system metrics, per-core CPU detail, developer process summaries, and unavailable states without advanced sensor setup controls.
- [ ] 3.2 Render DerivedData, open Xcode project or workspace, provisioning profile, and certificate summaries with partial-failure states.
- [ ] 3.3 Render focused-project Git repository, branch, and worktree context plus unresolved and non-repository states.
- [ ] 3.4 Remove or simplify placeholder panel and copied settings views that no longer match the trimmed dashboard scope.

## 4. Verify The Port

- [ ] 4.1 Add focused tests for trimmed telemetry/model behavior and read-only developer-context fallback handling where existing `macbar` tests provide useful coverage.
- [ ] 4.2 Build and run `XTop` locally to verify status-item launch, popover toggle behavior, live telemetry refresh, and partial Xcode/Git context rendering.
- [ ] 4.3 Review the final diff to confirm maintenance mutations and advanced sensor helper setup were not pulled into this change.
