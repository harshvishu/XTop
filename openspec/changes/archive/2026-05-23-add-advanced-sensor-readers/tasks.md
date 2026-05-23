## 1. Preflight and Architecture Boundaries

- [x] 1.1 Run GitNexus impact analysis on `XTopAppServices`, `UnavailableAdvancedSensorClient`, and `SensorSettingsView` before swapping implementations.
- [x] 1.2 Confirm in-process IOAccelerator reads work on macOS 13+ without elevated privileges; confirm IOHIDEventSystemClient is the working thermal source on Apple Silicon (AppleSMC `kSMCReadKey` returns `kIOReturnNotPrivileged` for unprivileged user processes — decision recorded in design.md).
- [x] 1.3 Confirm `AdvancedSensorClient` protocol surface from Phase 1 covers in-process reader needs without modification.

## 2. Thermal / Fan Reader (IOHIDEventSystemClient)

- [x] 2.1 Add `IOHIDSensorReader` that creates an `IOHIDEventSystemClient` and enumerates services on Apple vendor pages (`0xff00` temperature, `0xff08` power) via private `@_silgen_name` bindings.
- [x] 2.2 Read temperature events (`kIOHIDEventTypeTemperature = 15`) and power/fan events (`kIOHIDEventTypePower = 25`) using `IOHIDServiceClientCopyEvent` + `IOHIDEventGetFloatValue`.
- [x] 2.3 Average die-temperature sensors (`PMU tdie*`, `pACC*`) with a sensible fallback when no recognized die sensor is present.
- [x] 2.4 Surface fan capability honestly: report "no fan hardware detected" when no fan-named services exist (correct state on MacBook Air / Mac mini M-series).
- [x] 2.5 Provide graceful failure (`clientUnavailable`, `noSensorsAvailable`) without crashing when the private SPI is missing.
- [x] 2.6 Remove the dead `SMCReader` — every `kSMCReadKey` request returns `kIOReturnNotPrivileged` on Apple Silicon because the HID event system holds AppleSMC exclusively (`DeviceOpenedByEventSystem = true`).

## 3. GPU Stats Reader

- [x] 3.1 Add `GPUStatsReader` that matches the first `IOAccelerator` service publishing a `PerformanceStatistics` dictionary.
- [x] 3.2 Extract GPU utilization from the recognized keys (`Device Utilization %`, `GPU Core Utilization`, etc.) with graceful fallback to unavailable.
- [x] 3.3 Release IOKit objects deterministically and avoid leaks across repeated reads.

## 4. Local Advanced Sensor Client

- [x] 4.1 Add `LocalAdvancedSensorClient` that implements `AdvancedSensorClient` by composing `IOHIDSensorReader` (temperature/fan) and `GPUStatsReader` (GPU).
- [x] 4.2 Map reader availability to `AdvancedSensorHelperStatus` (installation/approval/connectivity, capability list).
- [x] 4.3 Return per-metric unavailable reasons in `AdvancedSensorSample.unavailableReasons` when any reader fails (distinguishing "SPI missing" from "no fan hardware").
- [x] 4.4 Implement `fetchStatus`, `startSetup`, `testAccess`, `disable`, and `removeConfiguration` with semantics appropriate for an in-process reader (setup/disable/remove become no-ops that update preference; testAccess performs a real one-shot sample).

## 5. App Wiring and Settings Copy

- [x] 5.1 Swap `UnavailableAdvancedSensorClient` for `LocalAdvancedSensorClient` in `XTopAppServices`.
- [x] 5.2 Update `SensorSettingsView` copy to remove install/approval language; keep enable/disable and access-test affordances.
- [x] 5.3 Verify `DashboardRootView` advanced metric tiles render real values when readers succeed.

## 6. Tests

- [x] 6.1 Add tests for `GPUStatsReader` covering missing accelerator, alternate key fallback, clamping, and walk-in-order behavior.
- [x] 6.2 Add smoke tests for `IOHIDSensorReader` (finite-value invariants when the SPI is present; graceful handling when absent).
- [x] 6.3 Add tests for `LocalAdvancedSensorClient` covering ready/unsupported status resolution, partial samples with reasons, and access-test summarization.
- [x] 6.4 Confirm the Phase 1 telemetry/settings test suites still pass against the new client.

## 7. Verification

- [x] 7.1 Build the `XTop` scheme for macOS. (BUILD SUCCEEDED.)
- [x] 7.2 Run focused `XTopTests`. (All tests passing.)
- [x] 7.3 Launch the app and confirm GPU and temperature tiles show real values on this Mac; fan tile correctly reports "no fan hardware detected" on the fanless host. (User-verified.)
- [x] 7.4 Run `gitnexus_detect_changes` on the repo before committing. (LOW risk — local to sensor reader boundary.)
- [x] 7.5 Re-run `openspec status --change add-advanced-sensor-readers` and confirm tracking.
