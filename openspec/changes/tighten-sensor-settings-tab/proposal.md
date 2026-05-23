## Why

The Sensors settings tab still carries leftover UI from the privileged-helper era — "Set Up Helper", "Remove Configuration", and a "Helper" section header — but the app now uses in-process IOHIDEventSystemClient + IOAccelerator readers with nothing to install, nothing to remove, and no helper to manage. The accompanying copy still references "SMC reads", which no longer exist. These controls do nothing useful and mislead users about how the app collects sensor data.

Separately, opening Settings from a `MenuBarExtra` (`LSUIElement`) app puts the Settings window behind whatever the user was doing because the app never becomes foreground. The user has to alt-tab to find it. Settings must come to the front and take focus when opened.

The advanced-sensor spec also still mandates SMC behavior (`SMC access is read-only and key-restricted`) and references SMC failures in scenarios, even though `SMCReader` was deleted and replaced with `IOHIDSensorReader`. The spec must match reality.

## What Changes

- Remove "Set Up Helper", "Remove Configuration", and the "Helper" section header from the Sensors tab. Keep Enable/Disable and Test Access.
- Replace the misleading "in-process IOKit and SMC reads" copy with an accurate description of the IOHIDEventSystemClient + IOAccelerator sources, and add a per-metric explanation that "no fan hardware detected" is not a failure.
- Drop `SensorSettingsModel.startSetup()` and `SensorSettingsModel.removeConfiguration()` public methods from the view layer's reach (the underlying client methods stay for protocol compliance but are no longer invoked from settings).
- When the Settings window opens, activate the app and bring the Settings window to the front and key.
- **BREAKING (spec only)**: rewrite the `Advanced sensor settings reflect reader reality` requirement so install/approval/remove affordances are explicitly disallowed, and rewrite the `SMC access is read-only and key-restricted` requirement to describe IOHIDEventSystemClient behavior instead. Add a new requirement covering the "no fan hardware" honest state and a requirement for Settings window focus behavior.

## Capabilities

### New Capabilities
- `settings-window-presentation`: rules for how the Settings window is presented from a `MenuBarExtra`-only app (activation, key window, ordering).

### Modified Capabilities
- `advanced-sensor-readers`: rewrite the SMC-restricted requirement as an IOHIDEventSystemClient-restricted requirement; rewrite the sensor-settings requirement to forbid install/approval/remove affordances; add a "no fan hardware" honest-state requirement.

## Impact

- Code: `XTop/Views/SettingsRootView.swift` (Sensor section rewrite), `XTop/App/XTopApp.swift` (Settings scene activation hook), possibly a small `AppKit` activation helper.
- Models: no changes to `SensorSettingsModel`'s public surface; `startSetup` and `removeConfiguration` simply lose their last UI callers.
- Tests: `XTopTests/AdvancedSensorTests.swift` and `XTopTests/LocalAdvancedSensorTests.swift` may need adjusted expectations for the trimmed settings surface; new test(s) for activation behavior may be added only if non-trivial logic exists outside `NSApp.activate`.
- Specs: deltas on `advanced-sensor-readers`; new spec `settings-window-presentation`.
- No dependency changes. No data migration.
