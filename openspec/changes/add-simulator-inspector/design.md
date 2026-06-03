## Context

XTop is a SwiftUI macOS companion app that already shells out to local toolchains (e.g. `git`, sensor readers) through `CommandRunner` and presents read-only developer telemetry. iOS developers using XTop need a way to inspect and tweak per-app state on booted iOS Simulators — primarily `UserDefaults`, and at minimum a "clear keychain" escape hatch — without leaving the dashboard or dropping into Terminal.

The Simulator Inspector is a new feature area that builds on XTop's existing shell-out infrastructure and dashboard layout. It is intentionally scoped to the simulator filesystem and `xcrun simctl`; no private API or device-side tooling is required for v1.

## Goals / Non-Goals

**Goals:**
- Let a developer pick a booted iOS Simulator and an installed app, then view, add, edit, and delete typed `UserDefaults` keys for that app and its App Groups.
- Let a developer clear an entire simulator's keychain with explicit confirmation.
- Let a developer terminate and relaunch the inspected app so edits take effect.
- Keep the simulator and app list fresh while the inspector is open.
- Make the feature safe under XTop's sandbox posture, including any required entitlement or user-granted folder access.

**Non-Goals:**
- Per-item simulator keychain viewing or editing.
- Real-device inspection or any paired-device workflows.
- File browser, Core Data browser, photo library, push, deeplinks, or network capture.
- Live streaming of `UserDefaults` writes via filesystem watch.
- Cloud sync of inspector state.

## Decisions

1. Use `xcrun simctl` for all device, app, and lifecycle operations.
- Decision: Discovery (`simctl list devices booted -j`), installed-app enumeration (`simctl listapps <UDID> -j`), container resolution (`simctl get_app_container <UDID> <bundleID> data` / `groups`), termination (`simctl terminate`), and launch (`simctl launch`) all go through `CommandRunner`.
- Rationale: Public, stable, no private API. Matches existing XTop shell-out patterns.
- Alternative considered: Parsing `device.plist` and `Library/Caches/com.apple.mobile.installation.plist` directly. Rejected because `simctl listapps` is the supported source of truth and handles edge cases like reinstalled apps.

2. Operate directly on the on-disk `<bundleID>.plist` for `UserDefaults`.
- Decision: Read and write `<container>/Library/Preferences/<bundleID>.plist` using `PropertyListSerialization`, preserving original plist value types.
- Rationale: This is the format `NSUserDefaults` writes; it is documented filesystem behavior and matches what existing inspector tools and blogs rely on. No daemon or injected library is required.
- Alternative considered: Using `defaults read/write` via shell. Rejected because it round-trips through a textual format that loses type fidelity (especially `Data`, `Date`, nested types) and is slower at scale.

3. Always require app termination before writing `UserDefaults`, and offer relaunch after.
- Decision: Inspector writes call `simctl terminate <UDID> <bundleID>` before saving, then offer (not auto-run) `simctl launch`. A warning banner appears whenever the inspected app is detected as running.
- Rationale: A running app holds the `NSUserDefaults` in memory and rewrites the plist on next sync, silently overwriting edits.
- Alternative considered: Edit live and warn. Rejected because silent data loss is the worst possible failure mode for an inspector.

4. Keychain support in v1 is "clear all", not per-item.
- Decision: Provide a single destructive "Clear Keychain" action that deletes `<device-data>/Library/Keychains/keychain-2-debug.db` (and sidecar `-shm` / `-wal` files), gated behind a confirmation dialog, and recommends an app relaunch afterward.
- Rationale: The simulator keychain DB is an undocumented SQLite schema with Apple-internal encoding. Reverse-engineering item parsing is a multi-week effort and a known maintenance treadmill. "Clear" solves the highest-frequency developer need (force re-login / reset onboarding) with zero ambiguity.
- Alternative considered: Ship a read-only viewer in v1. Rejected because partial keychain visibility is misleading (some items would not decode) and the implementation cost is disproportionate to v1 value.

5. Treat sandbox / filesystem access as a first-class architectural concern.
- Decision: Before any UI work, decide between (a) disabling App Sandbox for XTop, (b) adding a `com.apple.security.temporary-exception.files.absolute-path.read-write` entitlement for `~/Library/Developer/CoreSimulator/Devices/`, or (c) prompting the user once for a security-scoped bookmark to that folder and persisting it. The decision is captured in task 1.1.
- Rationale: Every other piece of the design assumes read/write access to the CoreSimulator devices tree. If this is not resolved early, the inspector cannot ship at all.
- Alternative considered: Defer to runtime trial-and-error. Rejected; it would block late in development.

6. Snapshot-and-refresh model, no live filesystem watching in v1.
- Decision: The simulator list and installed-app list refresh on an interval (and on window focus); plist values refresh on explicit user action and after writes. No `FSEventStream` integration in v1.
- Rationale: Avoids file-watch complexity, debouncing, and partial-write races. Matches v1 scope and the snapshot-style data flow already used elsewhere in XTop.
- Alternative considered: Live watch with diff overlay. Deferred; documented as a likely follow-up.

7. Inspector lives as a new top-level dashboard destination.
- Decision: Add a "Simulator Inspector" entry alongside existing dashboard destinations, using master-detail navigation (simulator sidebar → app list → inspector tabs).
- Rationale: Keeps the feature discoverable, isolated from Git/sensor surfaces, and within XTop's existing UI conventions.
- Alternative considered: Hide behind a menubar item only. Rejected because plist editing benefits from a wider canvas.

8. Bundle metadata (display name, icon) is read from the installed app's `Info.plist` and `.app` bundle.
- Decision: Resolve each installed app's `.app` bundle via `simctl get_app_container <UDID> <bundleID> app`, parse `Info.plist` for `CFBundleDisplayName` / `CFBundleName`, and load the primary `AppIcon` PNG for the row icon.
- Rationale: Matches what Simulator.app shows and avoids brittle icon-cache scraping.

## Risks / Trade-offs

- [App Sandbox blocks reads from `~/Library/Developer/CoreSimulator/`] -> Mitigation: resolve entitlement strategy in task 1.1 before UI work; document chosen strategy in design and update if changed.
- [Writing `<bundleID>.plist` while app is running silently loses edits] -> Mitigation: always terminate the target app before write, surface a "running" warning, and recommend relaunch.
- [Clearing the keychain DB while the app is running can corrupt the open SQLite handle] -> Mitigation: terminate the target app first and recommend relaunching the simulator's `securityd` (or the whole sim) if subsequent keychain operations fail; document fallback in UI.
- [Plist value type preservation is easy to get wrong (Bool vs Int, NSNumber vs NSString)] -> Mitigation: round-trip via `PropertyListSerialization` with binary format, expose an explicit type picker per key, and add unit tests covering all supported types and nested containers.
- [`xcrun simctl` output schema can shift between Xcode versions] -> Mitigation: decode only the fields actually needed, treat unknown fields as ignorable, and add a single decode site with tests so breakage surfaces in one place.
- [Destructive actions (delete key, clear keychain) are irreversible] -> Mitigation: required confirmation dialogs with explicit "type to confirm" for keychain clear; no in-app undo is promised in v1.
- [Reading large plists (megabyte-scale) on the main actor would jank the UI] -> Mitigation: do filesystem and `PropertyListSerialization` work off the main actor and publish snapshots back to the `@MainActor` view model.

## Migration Plan

1. Resolve sandbox/entitlement strategy and add any required entitlements or bookmark prompt.
2. Add Simulator Inspector domain models (`SimulatorDevice`, `InstalledApp`, `UserDefaultsEntry`, `PlistValueType`).
3. Add discovery service (`SimulatorDiscoveryService`, `InstalledAppCatalog`) backed by `simctl` via `CommandRunner`.
4. Add `UserDefaultsStore` with typed read/write and round-trip tests.
5. Add `KeychainClearer` for the "clear all" action with the confirmation dialog.
6. Add `AppLifecycleController` for terminate/launch.
7. Add Simulator Inspector dashboard destination and master-detail UI.
8. Add unit tests for plist round-trip, `simctl` decode, and app-lifecycle command construction.
9. Manually verify on a booted iOS Simulator with a dev app: edit a bool, edit a string, add a date, delete a key, clear keychain, relaunch app.

## Open Questions

- Is XTop currently App-Sandbox enabled, and which entitlement strategy (disable sandbox vs absolute-path exception vs security-scoped bookmark) best fits its distribution model?
- Should App Group container `UserDefaults` be shown as separate tabs per group ID, or merged with the primary app's view with a "scope" filter?
- Should "Clear Keychain" also offer "reset onboarding only" by deleting `<bundleID>.plist` as a one-click compound action, or keep the actions strictly separate?
- How should the inspector behave when the app is not currently installed on any booted simulator (greyed out vs hidden)?
- Should we support reading `UserDefaults` from the `.GlobalPreferences` plist as a separate read-only tab for debugging system-wide values?
