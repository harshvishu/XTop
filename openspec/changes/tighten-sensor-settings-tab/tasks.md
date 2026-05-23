## 1. Preflight

- [x] 1.1 Run GitNexus impact analysis on `SettingsRootView`, `SensorSettingsModel`, and `XTopApp` to confirm no unexpected consumers depend on the removed Set Up / Remove Configuration UI flow. (LOW on view; HIGH on model is broad-import noise — only structural callers are `XTopAppState.init` and `MacbarViewModel.init`, neither touches `startSetup`/`removeConfiguration`.)
- [x] 1.2 Confirm `client.startSetup()` and `client.removeConfiguration()` remain on the `AdvancedSensorClient` protocol (they are kept for future swap-in implementations).

## 2. Sensors Tab UI Cleanup

- [x] 2.1 In `XTop/Views/SettingsRootView.swift`, remove the entire "Helper" `Section` (including the `Set Up Helper`, `Remove Configuration`, and `lastSetupOutcome` rendering).
- [x] 2.2 Move the `Test Access` button into the "Advanced Sensors" section so it sits beside the per-metric rows and the Enable/Disable button.
- [x] 2.3 Replace the section copy with: "GPU readings come from IOAccelerator; temperature and fan readings come from the system's HID thermal sensors. Macs without fan hardware (MacBook Air, Mac mini M-series) correctly show fan as unavailable — this is not a malfunction."
- [x] 2.4 Keep Enable/Disable as the single state-mutating control; ensure both states render with the same button styling.
- [x] 2.5 Verify the per-metric capability rows still render their `state.title` and `state.nextAction` correctly with no layout regression.

## 3. Honest Fan-Unavailable Reason

- [x] 3.1 In `XTop/Services/LocalAdvancedSensorClient.swift`, distinguish the reason string for "no fan hardware" (use the existing capability probe) from "fan read failed" so the UI reflects the spec's no-hardware vs. read-failure split.
- [x] 3.2 Confirm `AdvancedSensorSample.unavailableReasons[AdvancedSensorMetric.fan.rawValue]` carries the no-hardware reason on a fanless host and a read-failure reason when the SPI is present but reads fail.

## 4. Settings Window Activation

- [x] 4.1 Add a small `SettingsWindowActivator` (an `NSObject` retained from `XTopApp` via `@State` or `init`) that observes `NSWindow.didBecomeKeyNotification` for windows whose `identifier` matches the SwiftUI Settings window (or, equivalently, any window whose `title` matches the localized "Settings" title) and calls `NSApp.activate(ignoringOtherApps: true)` and `window.orderFrontRegardless()`.
- [x] 4.2 Wire `SettingsWindowActivator` into `XTopApp` so it is alive for the full app lifetime and registers before the first time Settings is opened.
- [x] 4.3 Confirm the activator works on both first open and reopen of the Settings window, and that closing Settings does not leave the app in `activationPolicy = .regular` (it should remain `.accessory` or whatever `LSUIElement` enforces).

## 5. Tests

- [x] 5.1 Update `XTopTests/LocalAdvancedSensorTests.swift` (or add a new test) asserting that on a host returning no fan readings the reason maps to "no fan hardware" rather than a generic read-failure string.
- [x] 5.2 Confirm `XTopTests/AdvancedSensorTests.swift` and the Phase 1 telemetry tests still pass; adjust any expectations that referenced the removed Set Up / Remove Configuration UI flow if such expectations exist.
- [x] 5.3 Add a lightweight test or runtime assertion (where reasonable) that `SettingsWindowActivator` registers its notification observer; full UI activation is verified manually.

## 6. Verification

- [x] 6.1 Build the `XTop` scheme for macOS (BUILD SUCCEEDED).
- [x] 6.2 Run all `XTopTests` (all passing).
- [x] 6.3 Launch the app; open Settings from the menu bar panel and confirm the window appears in front and key on first open and on every reopen.
- [x] 6.4 In the Sensors tab, confirm: no "Helper" section, no Set Up / Remove Configuration buttons, Test Access sits next to Enable/Disable, copy is updated, and the fan row shows the no-hardware reason on this fanless Mac.
- [x] 6.5 Run `gitnexus_detect_changes` and confirm risk level is LOW and no unexpected processes are affected.
- [x] 6.6 Run `openspec validate tighten-sensor-settings-tab --strict` and confirm it passes.
