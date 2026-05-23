## Context

XTop already models GPU, temperature, and fan values in `SystemTelemetrySnapshot`, and settings currently expose an "Advanced Sensors" setup surface through `SensorSettingsModel`. The implementation is only a scaffold: `collectAdvancedMetrics()` hardcodes GPU, temperature, and fan as unavailable, while the setup buttons only flip `UserDefaults` flags.

The transcript investigation concluded that temperature and fan readings require privileged sensor access on macOS, and real-time GPU utilization is not reliable as a direct sandboxed app query. The helper path therefore needs to become a real architecture decision, not a cosmetic settings state.

## Goals / Non-Goals

**Goals:**
- Add a real privileged helper path for GPU, temperature, and fan telemetry.
- Keep the main menu bar app sandbox-friendly and focused on SwiftUI presentation and sampling orchestration.
- Expose helper setup, approval, connectivity, and failures through `SensorSettingsModel` and settings diagnostics.
- Preserve baseline telemetry when advanced sensors are unavailable.
- Keep the helper boundary testable through protocols and focused fakes.

**Non-Goals:**
- Add third-party sensor frameworks without explicit approval.
- Guarantee identical sensor availability across every Mac model.
- Make advanced sensors required for app launch, menu bar status, dashboard rendering, or baseline telemetry.
- Redesign the dashboard beyond what is needed to show real advanced sensor state.

## Decisions

- Use a separate privileged helper product for advanced sensors.
  - Rationale: the main app should not attempt privileged SMC or low-level hardware access directly, and the current code already treats these metrics as optional advanced sensors.
  - Alternative considered: query metrics directly from `DefaultSystemTelemetryService`. Rejected because temperature and fan access require privileges and would make sandbox/App Review behavior brittle.

- Communicate with the helper through a narrow async IPC boundary owned by an app-side sensor client protocol.
  - Rationale: `DefaultSystemTelemetryService` can request a typed advanced sensor snapshot without knowing launchd, helper installation, or transport details.
  - Alternative considered: invoke a command-line helper ad hoc with shell commands. Rejected because it is harder to authenticate, harder to report health, and weaker as a long-term macOS security model.

- Treat helper setup state as observed reality, not manual flags.
  - Rationale: the current "Record Helper" and "Record Approval" controls can claim success without any installed helper. The settings model should reflect install status, authorization status, last connection result, and last sample result from real checks.
  - Alternative considered: keep the manual controls as developer toggles. Rejected for production UI because it misleads users and hides the real failure mode.

- Keep advanced sensor failures localized to advanced metrics.
  - Rationale: baseline telemetry is already useful and must remain available when privileged access fails, is unsupported, or has not been approved.
  - Alternative considered: fail the entire telemetry sample when the helper fails. Rejected because it would make optional sensors degrade the primary menu bar monitor.

- Prefer first-party macOS APIs and project-local code.
  - Rationale: AGENTS.md disallows third-party frameworks without asking first, and privileged helper code is security-sensitive.
  - Alternative considered: adopt an SMC helper package immediately. Deferred until implementation proves first-party or small project-local code is insufficient and the user approves the dependency.

## Risks / Trade-offs

- Privileged helper signing and installation can fail across developer machines -> isolate signing and entitlement configuration, document the expected local development path, and surface actionable diagnostics in settings.
- Hardware sensor availability differs by Mac model and OS version -> represent each advanced metric independently with available/unavailable values and reasons.
- IPC or helper sampling can be slow -> enforce sampling timeouts so menu bar refreshes do not block on advanced sensors.
- Root helper code raises security risk -> keep the helper API read-only, authenticate the client, validate requests, and avoid arbitrary command execution.
- App Store distribution may reject privileged helper behavior -> keep the helper optional and document distribution constraints before release packaging.

## Migration Plan

1. Add the helper target, IPC protocol, install/check client, and advanced metric models behind protocols.
2. Wire `SensorSettingsModel` to real helper state while preserving existing user defaults only for user preferences such as enabled/disabled.
3. Replace `collectAdvancedMetrics()` placeholders with the helper client path and unavailable fallbacks.
4. Update settings diagnostics to show helper install, approval, connection, and last sample state.
5. Add focused unit tests for connected, unavailable, failing, disabled, and timeout paths.
6. Verify the app builds, focused tests pass, and the menu bar monitor still launches without helper installation.

Rollback is straightforward if helper integration destabilizes baseline behavior: remove the helper client wiring from `DefaultSystemTelemetryService` and keep advanced metrics returning unavailable while leaving baseline telemetry intact.

## Open Questions

- Which minimum macOS version and signing setup should the helper installation path target?
- Should the first implementation include GPU utilization, or ship temperature and fan first if GPU data proves less reliable?
- Should advanced sensor setup appear in production settings immediately, or stay behind a diagnostics/developer section until signing is validated?
