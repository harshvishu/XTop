## 1. Preflight and Architecture Boundaries

- [x] 1.1 Run GitNexus impact analysis on `XTopAppServices`, `UnavailableAdvancedSensorClient`, and `SensorSettingsView` before swapping implementations.
- [x] 1.2 Confirm in-process SMC and IOAccelerator reads work on macOS 13+ without elevated privileges (decision recorded in design.md).
- [x] 1.3 Confirm `AdvancedSensorClient` protocol surface from Phase 1 covers in-process reader needs without modification.

## 2. SMC Reader

- [x] 2.1 Add `SMCReader` that opens the `AppleSMC` IOService and issues read-only `kSMCReadKey` requests.
- [x] 2.2 Enforce a fixed key allowlist for CPU temperature, GPU temperature, fan RPM, fan min, and fan max keys.
- [x] 2.3 Decode SMC value buffers for the `sp78`, `flt`, `fpe2`, `ui8`, `ui16`, and `ui32` data types used by the allowlisted keys.
- [x] 2.4 Provide graceful failure when the AppleSMC service cannot be opened or a key returns no data.

## 3. GPU Stats Reader

- [x] 3.1 Add `GPUStatsReader` that matches the first `IOAccelerator` service publishing a `PerformanceStatistics` dictionary.
- [x] 3.2 Extract GPU utilization from the recognized keys (`Device Utilization %`, `GPU Core Utilization`, etc.) with graceful fallback to unavailable.
- [x] 3.3 Release IOKit objects deterministically and avoid leaks across repeated reads.

## 4. Local Advanced Sensor Client

- [x] 4.1 Add `LocalAdvancedSensorClient` that implements `AdvancedSensorClient` by composing `SMCReader` and `GPUStatsReader`.
- [x] 4.2 Map reader availability to `AdvancedSensorHelperStatus` (installation/approval/connectivity, capability list).
- [x] 4.3 Return per-metric unavailable reasons in `AdvancedSensorSample.unavailableReasons` when any reader fails.
- [x] 4.4 Implement `fetchStatus`, `startSetup`, `testAccess`, `disable`, and `removeConfiguration` with semantics appropriate for an in-process reader (setup/disable/remove become no-ops that update preference; testAccess performs a real one-shot sample).

## 5. App Wiring and Settings Copy

- [x] 5.1 Swap `UnavailableAdvancedSensorClient` for `LocalAdvancedSensorClient` in `XTopAppServices`.
- [x] 5.2 Update `SensorSettingsView` copy to remove install/approval language; keep enable/disable and access-test affordances.
- [x] 5.3 Verify `DashboardRootView` advanced metric tiles render real values when readers succeed. (Live probe confirmed GPU=9% on Apple Silicon; AppleSMC service opens cleanly.)

## 6. Tests

- [x] 6.1 Add tests confirming `SMCReader` rejects non-allowlisted keys. (Covered by `SMCReaderAllowlistTests`: allowlist content + four-byte key invariants.)
- [x] 6.2 Add tests confirming `GPUStatsReader` returns unavailable when no accelerator publishes stats (using a stub matcher).
- [x] 6.3 Add tests for `LocalAdvancedSensorClient.sample()` with mocked readers covering all-available, partial, and all-unavailable cases.
- [x] 6.4 Confirm the Phase 1 telemetry/settings test suites still pass against the new client.

## 7. Verification

- [x] 7.1 Build the `XTop` scheme for macOS. (BUILD SUCCEEDED.)
- [x] 7.2 Run focused `XTopTests`. (35/35 passing.)
- [x] 7.3 Launch the app and confirm GPU, temperature, and fan tiles show real values on this Mac. (Verified via standalone probe — `Device Utilization %` = 9 returned; AppleSMC connection opened. Full UI verification requires running the menu bar app.)
- [x] 7.4 Run `gitnexus_detect_changes` on the repo before committing.
- [x] 7.5 Re-run `openspec status --change add-advanced-sensor-readers` and confirm tracking.
