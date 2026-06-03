## 1. Sandbox, Entitlements, and Foundations

- [ ] 1.1 Decide and document the access strategy for `~/Library/Developer/CoreSimulator/Devices/` (disable sandbox, absolute-path exception, or security-scoped bookmark) and update the app's entitlements accordingly.
- [ ] 1.2 Verify `xcrun simctl` is invocable via `CommandRunner` under the chosen sandbox posture, including JSON output (`-j`) parsing.
- [ ] 1.3 Add Simulator Inspector domain models: `SimulatorDevice`, `InstalledApp`, `UserDefaultsEntry`, `PlistValueType`, `AppContainerPaths`.

## 2. Discovery Services

- [ ] 2.1 Implement `SimulatorDiscoveryService` that lists booted simulators via `simctl list devices booted -j` and decodes a stable subset of fields.
- [ ] 2.2 Implement `InstalledAppCatalog` that lists installed apps for a simulator via `simctl listapps <UDID> -j` and exposes display name, bundle ID, and `.app` path.
- [ ] 2.3 Resolve each app's data container via `simctl get_app_container <UDID> <bundleID> data` and App Group containers via `... groups`.
- [ ] 2.4 Parse each app's `Info.plist` and load its primary app icon for UI rows.
- [ ] 2.5 Add interval-based refresh of simulator and app lists, plus refresh-on-focus.

## 3. UserDefaults Read / Edit / Delete

- [ ] 3.1 Implement `UserDefaultsStore` that loads `<container>/Library/Preferences/<bundleID>.plist` via `PropertyListSerialization`, preserving original types.
- [ ] 3.2 Implement typed write-back for all supported plist types (Bool, Int, Double, String, Date, Data, Array, Dictionary) and persist as binary plist.
- [ ] 3.3 Implement add-key and delete-key flows with explicit type selection.
- [ ] 3.4 Extend the store to operate on App Group `UserDefaults` plists using resolved App Group container paths.
- [ ] 3.5 Detect whether the target app is currently running and surface a non-blocking warning before any write.
- [ ] 3.6 Ensure all filesystem and serialization work runs off the main actor; publish snapshots back to a `@MainActor` view model.

## 4. Keychain Clear

- [ ] 4.1 Implement `KeychainClearer` that deletes `<device-data>/Library/Keychains/keychain-2-debug.db` and its `-shm` / `-wal` sidecars.
- [ ] 4.2 Gate the action behind a "type to confirm" destructive dialog scoped to the simulator name.
- [ ] 4.3 Require the target app to be terminated before clearing, with a clear error if termination fails.

## 5. App Lifecycle

- [ ] 5.1 Implement `AppLifecycleController` with `terminate(bundleID:on:)` and `launch(bundleID:on:)` using `simctl`.
- [ ] 5.2 Wire a "Relaunch App" action into the inspector toolbar that runs terminate then launch.
- [ ] 5.3 After any successful `UserDefaults` write, surface a non-blocking suggestion to relaunch the app.

## 6. Inspector UI

- [ ] 6.1 Add a "Simulator Inspector" top-level dashboard destination.
- [ ] 6.2 Build the master-detail layout: simulator sidebar → installed apps list → inspector tabs.
- [ ] 6.3 Build the `UserDefaults` tab with a typed key/value table, add/edit/delete affordances, and a per-row type indicator.
- [ ] 6.4 Build the Keychain tab with the "Clear Keychain" destructive action and explanatory copy noting v1 scope.
- [ ] 6.5 Build the App Groups view (tab or scope filter) for App Group `UserDefaults` plists.
- [ ] 6.6 Apply existing `DesignSystem` spacing, typography, and colors; avoid heavy cards per repo UI rules.

## 7. Verification

- [ ] 7.1 Unit tests for `UserDefaultsStore` round-tripping every supported plist type, including nested arrays and dictionaries.
- [ ] 7.2 Unit tests for `simctl` JSON decode covering booted devices and installed apps fixtures.
- [ ] 7.3 Unit tests for `AppLifecycleController` command construction.
- [ ] 7.4 Manual end-to-end pass on a booted iOS Simulator: edit Bool, edit String, add Date, delete key, clear keychain, relaunch app, edit App Group key.
- [ ] 7.5 Build and run XTop under the chosen sandbox posture to confirm filesystem access works end-to-end.
