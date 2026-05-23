## Why

XTop currently advertises GPU, temperature, and fan telemetry, but `DefaultSystemTelemetryService` returns those metrics as unavailable and the settings controls only record placeholder setup state. Phase 1 introduced the `AdvancedSensorClient` abstraction and a stub implementation; this change replaces the stub with real readers that pull GPU utilization from IOKit and temperature/fan data from SMC, all running inside the main app process.

A privileged helper was considered and rejected for the first implementation: on macOS 13+, read-only `kSMCReadKey` requests and `IOAccelerator` performance statistics both succeed from a regular user process. Shipping a helper today would add an unsigned-helper installation problem without unlocking any additional metric. The `AdvancedSensorClient` protocol remains in place so a future helper-backed implementation can swap in without changing consumers.

## What Changes

- Add `LocalAdvancedSensorClient` that implements `AdvancedSensorClient` using in-process IOKit and SMC reads.
- Add a vendored read-only `SMCReader` limited to a fixed allowlist of temperature and fan keys; no write opcodes are exposed.
- Add `GPUStatsReader` that reads IOAccelerator `PerformanceStatistics` for the primary GPU and degrades gracefully when unavailable.
- Replace `UnavailableAdvancedSensorClient` with `LocalAdvancedSensorClient` in `XTopAppServices`.
- Update `AdvancedSensorHelperStatus` semantics: installation reports whether the in-process readers are usable on this host; approval is implicit (no system prompt required); connectivity reflects whether the last read succeeded.
- Keep settings copy and diagnostics accurate for an in-process reader (no install/approval steps to perform; only enable/disable and access-test actions remain meaningful).
- Add focused tests for SMC key allowlist enforcement, GPU reader fallback, and end-to-end client behavior.

## Capabilities

### New Capabilities
- `advanced-sensor-readers`: Covers in-process advanced sensor readers, SMC key safety, GPU statistics extraction, and the unchanged advanced sensor client contract.

### Modified Capabilities

## Impact

- Affects `XTopAppServices` (swap stub for real client), `SensorSettingsModel` copy, `SettingsRootView` copy, and existing advanced sensor tests.
- Adds `LocalAdvancedSensorClient`, `SMCReader`, `GPUStatsReader` source files under `XTop/Services/AdvancedSensors/`.
- Adds new tests under `XTopTests/AdvancedSensors/`.
- No project.pbxproj target additions (synchronized file groups pick up new Swift files automatically).
- No new third-party frameworks. SMC and IOKit access uses Apple system frameworks only.
- A future privileged helper can replace `LocalAdvancedSensorClient` without changing any consumer because the `AdvancedSensorClient` protocol boundary is preserved.
