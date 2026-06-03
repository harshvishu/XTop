## Why

iOS developers using XTop have to drop into Terminal, dig into `~/Library/Developer/CoreSimulator/Devices/<UDID>/data/...`, and hand-edit plists to inspect or tweak a simulator app's `UserDefaults`, and they have no good way to clear a keychain between runs. Third-party tools (RocketSim, custom inspectors) fill this gap but require a separate app. XTop is already an always-on macOS companion for developer workflows, so it is the natural place to host a lightweight simulator inspector that lets developers pick a booted simulator, pick an installed app, and edit `UserDefaults` or clear its keychain without leaving the app.

## What Changes

- Introduce a Simulator Inspector domain that enumerates booted iOS Simulators, lists installed apps per simulator, and resolves each app's data container path.
- Add `UserDefaults` read/edit/add/delete support backed by the app's `<bundleID>.plist` in the simulator container, preserving plist value types (Bool, Int, Double, String, Date, Data, Array, Dictionary).
- Add a "Clear Keychain" action that removes the simulator's keychain database file with explicit confirmation (per-item keychain viewing/editing is out of scope for v1).
- Add an "App Group containers" view that surfaces shared App Group `UserDefaults` plists for the same app.
- Add a "Relaunch App" action (`simctl terminate` + `simctl launch`) so plist edits take effect, and surface a non-blocking reminder whenever `UserDefaults` is written while the target app is running.
- Add a new top-level Simulator Inspector destination in the dashboard with a master-detail layout (simulator → app → inspector tabs).
- Introduce required entitlements / security-scoped bookmark flow so the app can read and write inside `~/Library/Developer/CoreSimulator/Devices/` under the current sandbox posture.

## Capabilities

### New Capabilities
- `simulator-inspector-discovery`: Enumerate booted simulators, list installed apps per simulator, and resolve app data and App Group container paths.
- `simulator-inspector-userdefaults`: Read, add, edit, and delete typed `UserDefaults` entries for an installed simulator app and its App Groups.
- `simulator-inspector-keychain`: Clear an entire simulator's keychain database with explicit confirmation.
- `simulator-inspector-app-lifecycle`: Terminate and relaunch an installed simulator app to apply inspector edits.
- `simulator-inspector-surface`: Present simulator → app → inspector navigation in the dashboard with destructive-action confirmation patterns consistent with the rest of XTop.

### Modified Capabilities
- None.

## Impact

- Adds a new feature area, services, models, and views; does not modify existing Git, sensor, or dashboard capabilities.
- Requires the app to access `~/Library/Developer/CoreSimulator/Devices/` and to shell out via `xcrun simctl`. Sandbox/entitlement posture is a hard dependency and must be resolved before UI work begins.
- Adds polling or `FSEventStream`-backed observation of the CoreSimulator devices folder to keep the simulator list fresh.
- Introduces destructive actions (delete `UserDefaults` keys, clear keychain) that require confirmation and a recoverable error story; no auth secrets are stored.

## Non-Goals (v1)

- Per-item keychain viewing or editing (the simulator keychain DB is an undocumented SQLite format; viewing/editing is deferred).
- Real-device inspection (requires `devicectl`/paired-device entitlements outside the simulator scope).
- File browser, Core Data browser, photo library, push notifications, deeplink launcher, or network capture (potential follow-ups, intentionally excluded from v1).
- Live streaming of `UserDefaults` writes via filesystem watch (snapshot/refresh only in v1).
- Inspecting apps that are not installed on a currently booted simulator.
