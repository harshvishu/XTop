## Why

XTop currently advertises GPU, temperature, and fan telemetry, but `DefaultSystemTelemetryService` returns those metrics as unavailable and the settings controls only record placeholder setup state. Users need a real, approved helper path for advanced sensors, or the app should stop presenting those controls as functional.

## What Changes

- Add a privileged helper architecture for advanced sensor access, covering installation, user approval, health checks, and metric collection.
- Replace placeholder sensor setup controls with actions that reflect real helper installation and connectivity state.
- Integrate helper-provided GPU, temperature, and fan readings into the existing `SystemTelemetrySnapshot` fields.
- Preserve baseline CPU, memory, storage, disk-cache, and developer telemetry when the helper is missing, disabled, unsupported, or failing.
- Add diagnostics and tests for helper availability, access failures, and fallback behavior.

## Capabilities

### New Capabilities
- `advanced-sensor-helper`: Covers privileged helper setup, user approval, helper health, and advanced GPU, temperature, and fan telemetry.

### Modified Capabilities

## Impact

- Affects `SensorSettingsModel`, `SettingsRootView`, `DefaultSystemTelemetryService`, `SystemTelemetryService`, `SystemTelemetrySnapshot`, app service wiring, and tests.
- Adds a helper executable target or equivalent privileged helper product to the Xcode project.
- Requires macOS-specific privileged-helper packaging, signing, entitlements, launchd registration, and XPC or equivalent secure IPC.
- Does not introduce third-party frameworks unless explicitly approved before implementation.
