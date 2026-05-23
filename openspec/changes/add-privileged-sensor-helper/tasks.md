## 1. Preflight and Architecture Boundaries

- [x] 1.1 Run GitNexus impact analysis for each code symbol that will be edited before making implementation changes.
- [ ] 1.2 Confirm the minimum supported macOS version and select the first-party privileged helper installation API for that target.
- [x] 1.3 Define app-side protocols and models for helper status, advanced sensor samples, metric-level unavailable reasons, and access test results.
- [ ] 1.4 Decide whether GPU utilization is included in the first implementation or reported as independently unavailable until a reliable source is validated.

## 2. Helper Product and Security Setup

- [ ] 2.1 Add a privileged helper executable target or equivalent helper product to the Xcode project.
- [ ] 2.2 Configure helper bundle identifiers, launchd registration metadata, signing, entitlements, and install-time authorization requirements.
- [ ] 2.3 Implement a narrow read-only helper API for advanced sensor status checks and metric sampling.
- [ ] 2.4 Add helper-side validation so the helper only serves the expected XTop client and does not execute arbitrary commands.

## 3. App-to-Helper Integration

- [x] 3.1 Implement an app-side advanced sensor client that handles helper installation checks, approval state, connectivity, sampling, timeouts, and errors.
- [x] 3.2 Wire the advanced sensor client into `XTopAppServices` and `DefaultSystemTelemetryService`.
- [x] 3.3 Replace hardcoded GPU, temperature, and fan unavailable values with helper-backed metric values and explicit fallbacks.
- [x] 3.4 Ensure baseline telemetry collection succeeds when the helper is absent, disabled, unsupported, disconnected, or slow.

## 4. Settings and Diagnostics

- [x] 4.1 Replace manual "Record Helper" and "Record Approval" state toggles with real setup, approval, connectivity, and access-test actions.
- [x] 4.2 Update `SensorSettingsModel` so setup state reflects observed helper state plus the user's enabled/disabled preference.
- [x] 4.3 Update sensor settings and diagnostics copy to distinguish installation, approval, connection, host support, disabled, and sample failure states.
- [x] 4.4 Keep the settings UI compact and restrained, avoiding new card-heavy or decorative layout.

## 5. Tests

- [x] 5.1 Add unit tests for advanced sensor setup state resolution from real helper status inputs.
- [x] 5.2 Add telemetry service tests for connected helper samples, partial helper samples, helper failures, disabled sensors, and timeouts.
- [x] 5.3 Add tests confirming baseline telemetry remains available when advanced sensors are unavailable.
- [x] 5.4 Add tests for settings diagnostics messages and access-test result updates.

## 6. Verification

- [x] 6.1 Build the `XTop` scheme for macOS.
- [x] 6.2 Run focused `XTopTests`.
- [ ] 6.3 Run `./script/build_and_run.sh --verify` and confirm the menu bar monitor launches without requiring helper installation.
- [ ] 6.4 Verify helper-connected behavior on a signed local build or document any signing limitation that prevents local validation.
- [x] 6.5 Run `gitnexus_detect_changes()` before committing to verify the affected symbols and flows match this change.
- [x] 6.6 Re-run `openspec status --change add-privileged-sensor-helper` and confirm the implementation tasks are tracked.
