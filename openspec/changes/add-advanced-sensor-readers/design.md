## Context

Phase 1 of advanced sensor work landed the `AdvancedSensorClient` protocol, model types, telemetry wiring, settings rewrite, and a stub `UnavailableAdvancedSensorClient`. The original plan was to back the protocol with a privileged XPC helper installed via `SMAppService`. Investigation in Phase 2 found that on macOS 13+:

- `IOServiceMatching("IOAccelerator")` + `PerformanceStatistics` dictionary access works without entitlements (GPU utilization is solved).
- **AppleSMC user-client reads do NOT work from unprivileged user processes on Apple Silicon.** A live probe of every documented key (`TC0P`, `TG0P`, `F0Ac`, etc.) via `IOConnectCallStructMethod` selector 2 (`kSMCReadKey`) returns `0xe00002c2` (`kIOReturnNotPrivileged`) on every call. The IORegistry confirms the cause: `AppleSMC` carries `DeviceOpenedByEventSystem = true`, meaning the HID event system holds the SMC user-client exclusively.
- The correct unprivileged path on Apple Silicon is the **private `IOHIDEventSystemClient` SPI**, the same surface used by `stats` (MIT), iStat Menus, Sensei, and Hot. Temperature sensors appear on usage page `0xff00` (event type `kIOHIDEventTypeTemperature = 15`); power/fan sensors appear on page `0xff08` (event type `kIOHIDEventTypePower = 25`). A live probe on this Mac enumerated 71 temperature services and 100 power services returning real values (PMU die temps ~36 °C, NAND temp, battery temp).
- An unsigned helper cannot be registered with `SMAppService` on this development machine (no Developer ID), so the helper path is unverifiable in the current environment. Even with a signed helper, the right thermal API on Apple Silicon is IOHIDEventSystemClient, not AppleSMC.

Given the open-source distribution model and the SMC findings, the helper would solve a non-existent problem on Apple Silicon. In-process readers (IOAccelerator for GPU, IOHIDEventSystemClient for thermal/fan) deliver the same user-visible metrics today, without a helper and without elevated privileges.

## Goals / Non-Goals

**Goals:**
- Replace the stub client with real readers for GPU utilization, die temperature, and fan RPM.
- Keep the `AdvancedSensorClient` protocol unchanged so a future helper-backed implementation is a drop-in swap.
- Use private SPI only via narrow, documented `@_silgen_name` bindings isolated in one file (`IOHIDPrivate` namespace).
- Degrade per-metric: missing GPU stats must not hide temperature, and vice versa.
- Distinguish "sensor unavailable" from "no such hardware" (fanless Macs report fan as "no fan hardware detected", not as a failure).
- Preserve the 750 ms sampling budget enforced by `DefaultSystemTelemetryService`.

**Non-Goals:**
- Ship a privileged helper, XPC protocol, or `SMAppService` registration code.
- Read AppleSMC keys (it's blocked on Apple Silicon and superseded by IOHIDEventSystemClient).
- Provide write access to any sensor surface.
- Add settings UI for helper install/approval flows that no longer apply.
- Per-sensor UI breakdown (averaged metrics ship in v1; per-sensor diagnostics are available via the reader's `collectTemperatureReadings()` API for future use).

## Decisions

- Implement `LocalAdvancedSensorClient` behind the existing `AdvancedSensorClient` protocol.
  - Rationale: zero consumer churn; future migration to a different reader or a helper only changes one line in `XTopAppServices`.
  - Alternative considered: collapse the protocol and inline reads into `DefaultSystemTelemetryService`. Rejected because it loses the timeout boundary and test seam.

- Use `IOHIDEventSystemClient` (private SPI) for temperature and fan readings on Apple Silicon.
  - Rationale: AppleSMC `kSMCReadKey` returns `kIOReturnNotPrivileged` for unprivileged processes on every Apple Silicon Mac we tested. IOHIDEventSystemClient is the path Apple ships internally (used by powermetrics, the menu bar battery/CPU temp indicators, and every shipping monitoring app). It works without entitlements, root, or a helper.
  - Trade-off: it is a private SPI. We isolate the surface inside a single `IOHIDPrivate` enum with `@_silgen_name` bindings so a future public replacement is a one-file swap. Distribution is open-source, so App Store rejection risk does not apply.
  - Alternative considered: ship a privileged helper that opens AppleSMC. Rejected because (a) the HID event system already holds AppleSMC exclusively even from root, and (b) the helper requires Developer ID we don't have.

- Delete the SMC reader rather than keep it as Intel-Mac fallback.
  - Rationale: Intel Mac support is out of scope for v1, and a code path that always fails on the primary target architecture is dead weight that confuses future contributors.
  - Alternative considered: keep `SMCReader` behind `#if arch(x86_64)`. Deferred until Intel support is explicitly requested.

- Resolve GPU stats via the first IOAccelerator service that publishes `PerformanceStatistics`.
  - Rationale: on Apple Silicon there is typically one accelerator; on Intel + discrete GPUs we report the discrete GPU when present. Reading from the first matching service avoids ambiguity in v1.
  - Alternative considered: enumerate all accelerators and aggregate. Deferred until multi-GPU support is requested.

- Treat `AdvancedSensorHelperStatus` as a reader status, not a daemon status.
  - Rationale: installation = "this Mac exposes the readers we need", approval = always granted (no system prompt), connectivity = "the last sample succeeded". This keeps the protocol stable while honestly reflecting in-process reality.

- Average die-temperature sensors (`PMU tdie*`, `pACC*`) rather than picking one.
  - Rationale: a single sensor reading is noisy and depends on workload locality. Averaging the named die sensors yields a stable "SoC temperature" comparable to what menu bar apps display.
  - Alternative considered: max across sensors. Deferred — average is what users expect from a single "Temperature" tile.

- Keep failures localized per metric.
  - Rationale: `AdvancedSensorSample.unavailableReasons` already supports per-metric reasons. Returning a partial sample is preferable to failing the entire advanced collection. Fan-less Macs get a distinct "no fan hardware detected" reason so the UI can present truth, not an error.

## Risks / Trade-offs

- IOHIDEventSystemClient is private SPI → isolated to one file with `@_silgen_name` bindings; if Apple removes or changes it, swap to whatever ships next without touching the rest of the app.
- Sensor naming varies by Mac (`PMU tdie*` on M1/M2, possibly different on future SoCs) → the reader falls back to averaging any in-range temperature reading when no `tdie*` services are present.
- IOAccelerator dictionary keys are private and may change → guard every key lookup, treat missing keys as unavailable, log no errors that would scare users.
- Reading IOKit/IOHID on the telemetry actor must not block → the 750 ms timeout in `DefaultSystemTelemetryService` already protects this; readers are fast (low single-digit milliseconds) but the budget remains.
- A future macOS version may restrict IOHIDEventSystemClient → at that point we re-evaluate (the path Apple's own UI uses is unlikely to vanish without a public replacement); the protocol boundary ensures no other code changes when the implementation swaps.

## Migration Plan

1. Add `IOHIDSensorReader`, `GPUStatsReader`, and `LocalAdvancedSensorClient` under `XTop/Services/`.
2. Swap `UnavailableAdvancedSensorClient` for `LocalAdvancedSensorClient` in `XTopAppServices`.
3. Update settings copy in `SensorSettingsView` to reflect "no installation required" (install/approval buttons become no-ops that report success immediately; enable/disable + test access remain meaningful).
4. Add tests covering IOHID reader safety, GPU reader fallback when no accelerator publishes stats, and end-to-end `LocalAdvancedSensorClient.sample()` behaviour with partial readers.
5. Update Phase 1 tests as needed (the existing `StubAdvancedSensorClient` stays valid).
6. Build, run focused tests, and verify the menu bar app shows real GPU/temp values on this host and correctly reports "no fan hardware detected" on fanless Macs.

Rollback: revert the `XTopAppServices` line that swaps in `LocalAdvancedSensorClient`. The stub client comes back, baseline telemetry continues to work, advanced metrics return unavailable.

## Open Questions

- Should we surface a per-sensor diagnostic (list of detected services and current values) in settings to help users on unusual Macs verify the right sensors are being read? The reader already exposes `collectTemperatureReadings()` for this — deferred unless users hit gaps.
- Should we offer max-temperature alongside average in a future UI revision? Deferred until users ask for it.
