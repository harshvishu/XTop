## Context

Phase 1 of advanced sensor work landed the `AdvancedSensorClient` protocol, model types, telemetry wiring, settings rewrite, and a stub `UnavailableAdvancedSensorClient`. The original plan was to back the protocol with a privileged XPC helper installed via `SMAppService`. Investigation found that on macOS 13+:

- Read-only SMC requests (`kSMCReadKey`) succeed from regular user processes for the temperature and fan key set we care about.
- `IOServiceMatching("IOAccelerator")` + `PerformanceStatistics` dictionary access works without entitlements.
- An unsigned helper cannot be registered with `SMAppService` on this development machine (no Developer ID), making the helper path unverifiable in the current environment.

Given the open-source distribution model and lack of a paid developer account, the helper would ship as a non-functional architecture diagram. In-process readers deliver the same user-visible metrics today.

## Goals / Non-Goals

**Goals:**
- Replace the stub client with real readers for GPU utilization, CPU/GPU temperature, and fan RPM.
- Keep the `AdvancedSensorClient` protocol unchanged so a future helper-backed implementation is a drop-in swap.
- Restrict SMC interaction to read-only operations on a fixed key allowlist.
- Degrade per-metric: missing GPU stats must not hide temperature, and vice versa.
- Preserve the 750 ms sampling budget enforced by `DefaultSystemTelemetryService`.

**Non-Goals:**
- Ship a privileged helper, XPC protocol, or `SMAppService` registration code.
- Support every Mac model identically; older Intel SMC layouts and Apple Silicon SMC differences are handled per-key with graceful fallback.
- Provide write access to SMC for any reason.
- Add settings UI for helper install/approval flows that no longer apply.

## Decisions

- Implement `LocalAdvancedSensorClient` behind the existing `AdvancedSensorClient` protocol.
  - Rationale: zero consumer churn; future migration to a real helper only changes one line in `XTopAppServices`.
  - Alternative considered: collapse the protocol and inline reads into `DefaultSystemTelemetryService`. Rejected because it loses the timeout boundary and test seam.

- Vendor a minimal read-only SMC reader instead of adopting a third-party package.
  - Rationale: third-party SMC packages often include write opcodes, fan control, and elevated-privilege helpers we explicitly do not want. AGENTS.md requires explicit approval for third-party frameworks.
  - Alternative considered: depend on a community SMC package. Rejected for surface-area and security reasons.

- Enforce an SMC key allowlist at the reader boundary.
  - Rationale: the only legitimate calls are reads of CPU/GPU temperature and fan RPM/min/max keys. Refusing other keys at the API boundary prevents future call sites from accidentally probing SMC for unrelated data.
  - Alternative considered: allow arbitrary key reads and rely on callers. Rejected because it weakens the audit story.

- Treat `AdvancedSensorHelperStatus` as a reader status, not a daemon status.
  - Rationale: installation = "this Mac exposes the readers we need", approval = always granted (no system prompt), connectivity = "the last sample succeeded". This keeps the protocol stable while honestly reflecting in-process reality.
  - Alternative considered: rename status types. Rejected to avoid churn; the existing names map cleanly to reader semantics.

- Resolve GPU stats via the first IOAccelerator service that publishes `PerformanceStatistics`.
  - Rationale: on Apple Silicon there is typically one accelerator; on Intel + discrete GPUs we report the discrete GPU when present. Reading from the first matching service avoids ambiguity in v1.
  - Alternative considered: enumerate all accelerators and aggregate. Deferred until multi-GPU support is requested.

- Keep failures localized per metric.
  - Rationale: `AdvancedSensorSample.unavailableReasons` already supports per-metric reasons. Returning a partial sample is preferable to failing the entire advanced collection.

## Risks / Trade-offs

- SMC key layout varies by Mac model and macOS version → probe a small list of fallback keys for CPU temperature and report unavailable rather than wrong values.
- IOAccelerator dictionary keys are private and may change → guard every key lookup, treat missing keys as unavailable, log no errors that would scare users.
- Reading SMC and IOKit on the telemetry actor must not block → the 750 ms timeout in `DefaultSystemTelemetryService` already protects this; readers should be fast (single-digit milliseconds) but the budget remains.
- A future macOS version may restrict unprivileged SMC reads → at that point we swap `LocalAdvancedSensorClient` for a helper-backed client; the protocol boundary ensures no other code changes.

## Migration Plan

1. Add `SMCReader`, `GPUStatsReader`, and `LocalAdvancedSensorClient` under `XTop/Services/AdvancedSensors/`.
2. Swap `UnavailableAdvancedSensorClient` for `LocalAdvancedSensorClient` in `XTopAppServices`.
3. Update settings copy in `SensorSettingsView` to reflect "no installation required" (install/approval buttons become no-ops that report success immediately; enable/disable + test access remain meaningful).
4. Add tests covering SMC key allowlist rejection, GPU reader fallback when no accelerator publishes stats, and end-to-end `LocalAdvancedSensorClient.sample()` with mocked readers.
5. Update Phase 1 tests as needed (the existing `StubAdvancedSensorClient` stays valid).
6. Build, run focused tests, and verify the menu bar app shows real GPU/temp/fan values on this host.

Rollback: revert the `XTopAppServices` line that swaps in `LocalAdvancedSensorClient`. The stub client comes back, baseline telemetry continues to work, advanced metrics return unavailable.

## Open Questions

- Should we surface a "discovered SMC keys" diagnostic in settings to help users on unusual Macs report missing sensors? Deferred unless the first batch of users hits gaps.
