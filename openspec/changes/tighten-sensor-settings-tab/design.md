## Context

After Phase 2 of the advanced-sensor work (commit `84ed1c3`), the `LocalAdvancedSensorClient` is fully in-process: GPU data comes from IOAccelerator, thermal data comes from IOHIDEventSystemClient. There is no helper, no installation step, no system approval prompt. But the Sensors settings tab still renders the helper-era UI:

- "Helper" section header
- "Set Up Helper" button → calls `client.startSetup()` which now just returns `.ready` synthetically.
- "Test Access" button → still meaningful (real one-shot sample).
- "Disable" / "Enable" → still meaningful (skips advanced reads in `DefaultSystemTelemetryService`).
- "Remove Configuration" button → calls `client.removeConfiguration()` which is a no-op.
- Section copy reads "GPU, temperature, and fan readings come from in-process IOKit and SMC reads." — `SMCReader` was deleted; the source is IOHIDEventSystemClient.

The actions that no longer mean anything (Set Up, Remove Configuration) confuse users into thinking there is state to manage. Per-metric capability rows already render correctly from the unchanged `SensorSettingsModel.capabilities` derivation, including the "no fan hardware" reason on fanless Macs.

Separately, the app is `LSUIElement=true` (menu bar only). When the user clicks "Open Settings…" from the menu bar panel, macOS opens the `Settings` scene window but does not activate the app, so the window often appears behind other windows or on a different Space. Standard fix in MenuBarExtra apps is to call `NSApp.activate(ignoringOtherApps: true)` and order the settings window to the front when it appears.

## Goals / Non-Goals

**Goals:**
- Sensors tab shows only controls that map to real in-process reader behavior.
- Copy in the Sensors tab accurately describes the IOHIDEventSystemClient + IOAccelerator sources.
- Settings window comes to the front, becomes key, and activates the app when opened from the menu bar panel or any other entry point.
- Spec for `advanced-sensor-readers` matches the shipped implementation (no more SMC requirement).
- Add a new spec capturing the Settings window presentation rule so the behavior is testable/contractual.

**Non-Goals:**
- Change the `AdvancedSensorClient` protocol or remove `startSetup` / `removeConfiguration` from the protocol. They stay for future swap-in implementations (e.g., a helper-backed client on Intel Macs or a future macOS that restricts IOHID).
- Add per-sensor diagnostics or a "discovered sensors" panel (still deferred from the previous change).
- Change `SensorSettingsModel.disable()` / `enable()` semantics.
- Migrate to `Settings` scene replacement APIs (`SettingsLink` already used; this change only adjusts window activation).

## Decisions

- **Remove the "Helper" section and its two dead buttons from the Sensor tab; merge "Test Access" up into the Advanced Sensors section beside Enable/Disable.**
  - Rationale: the section title was lying. The remaining controls (Test Access, Enable/Disable) are honest and small enough to live alongside the capability rows.
  - Alternative considered: keep "Helper" renamed to "Reader" and keep all four buttons. Rejected — Set Up and Remove still do nothing meaningful even with a renamed header.

- **Keep `SensorSettingsModel.startSetup()` and `SensorSettingsModel.removeConfiguration()` methods on the model.**
  - Rationale: the protocol surface they wrap is shared with `UnavailableAdvancedSensorClient` and any future helper-backed client. Deleting them now would force a re-add later. Removing only the UI callers is reversible and zero-risk.
  - Alternative considered: deprecate both with `@available(*, deprecated)`. Deferred — there are no out-of-app consumers, so churn buys nothing.

- **Rewrite the section copy as two sentences: one describes what is read and from where, the other describes the fan-availability honesty rule.**
  - Rationale: users frequently take "Unavailable" to mean broken. Stating up front that a fanless Mac reports fan as unavailable by design prevents support questions.
  - Copy: "GPU readings come from IOAccelerator; temperature and fan readings come from the system's HID thermal sensors. Macs without fan hardware (MacBook Air, Mac mini M-series) correctly show fan as unavailable — this is not a malfunction."

- **Activate the app and bring the Settings window to the front via an AppKit hook installed once on app launch.**
  - Rationale: macOS does not promote `LSUIElement` apps to foreground when `Settings` opens. The simplest, most reliable hook is `NSApplication.didBecomeActiveNotification` plus a one-shot `NSWindow.didBecomeKeyNotification` observer on the settings window, calling `NSApp.activate(ignoringOtherApps: true)` and `window.orderFrontRegardless()`. Wiring this in `XTopApp.init()` or via a tiny `AppDelegate`-style helper keeps it out of the view layer.
  - Alternative considered: call `NSApp.activate` from inside `SettingsRootView.onAppear`. Rejected — view appearance runs after the window has already been ordered behind others, causing a visible jump. Doing it at window-key-notification time is earlier and smoother.
  - Alternative considered: switch to `LSUIElement=false`. Rejected — it would put a permanent Dock icon on the app, contrary to the menu-bar-only design.

- **Express the Settings activation rule as its own spec (`settings-window-presentation`) rather than appending to the sensors spec.**
  - Rationale: it is cross-cutting (applies to any future settings entry point, not only the Sensors tab). A standalone spec keeps the responsibility discoverable.

- **Rewrite the SMC requirement in `advanced-sensor-readers` rather than deleting it.**
  - Rationale: the spec's intent — restrict the thermal data path to a narrow, read-only surface — is still valid; only the surface changed (IOHIDEventSystemClient instead of AppleSMC). Rewriting preserves the intent and the spec ID.

## Risks / Trade-offs

- Removing the "Set Up Helper" button might surprise a user mid-flow if they were following old screenshots. → Acceptable; the feature has not shipped publicly and the in-process path is strictly simpler.
- `NSApp.activate` may interrupt a user's current full-screen app context briefly when they open Settings. → That is the expected, desired behavior — they explicitly asked for Settings; the window must be visible and focused.
- The window-key observer must be installed before the first time Settings opens; missing the first activation leaves the window behind. → Install it from `XTopApp` `init` via a `@State` `AppDelegate`-style helper that registers immediately and survives the app lifetime.

## Migration Plan

1. Edit `XTop/Views/SettingsRootView.swift` — remove the "Helper" section, drop Set Up and Remove Configuration buttons, fold Test Access next to Enable/Disable, rewrite the description.
2. Add a tiny `SettingsWindowActivator` (or inline observer in `XTopApp`) that listens for the Settings window appearing and calls `NSApp.activate(ignoringOtherApps: true)` + `orderFrontRegardless()`.
3. Run focused tests; UI-verify Sensors tab; open Settings from the menu bar and confirm it appears in front and key.
4. Update `openspec` deltas + new spec; archive after merge.

Rollback: revert the view-file diff. The model and client are untouched.

## Open Questions

- Should we also hide the entire Sensors tab when no readers are usable on the host? Deferred — current behavior of showing all-unavailable rows + a Test Access button gives the user a way to confirm "yes, nothing works here" rather than silently disappearing.
