## Context

`XTop` is a new macOS menu bar app scaffold with a placeholder `MenuBarExtra` panel and a small settings form. The older `/Users/harsh/Projects/macbar` project already contains a working menu bar implementation built around an AppKit `NSStatusItem`, an `NSPopover`, a sampling view model, and service-backed SwiftUI dashboard sections. Some `macbar` dashboard and service files have already been copied into `XTop`, but the imported views still depend on old models, settings types, and maintenance paths that are not yet present in the target app.

The port needs to keep `XTop` runnable while extracting the useful monitor behavior from `macbar`. Baseline telemetry and Xcode/Git introspection use local macOS APIs, filesystem scans, AppleScript/Xcode metadata, and developer tools that can be missing or fail independently, so the UI must tolerate partial data without blocking the menu bar experience.

## Goals / Non-Goals

**Goals:**
- Recreate the proven menu bar status item and popover interaction in `XTop`.
- Provide a live, responsive dashboard for baseline system telemetry and read-only Xcode developer context.
- Keep telemetry sampling, developer-context refresh, domain models, and UI hosting separated enough to trim and test the imported code safely.
- Reuse the old project as source material while renaming or reshaping target-owned types to fit `XTop`.

**Non-Goals:**
- Porting advanced GPU, temperature, or fan helper setup.
- Porting destructive maintenance workflows for DerivedData, caches, SwiftPM, or CocoaPods.
- Building a general Xcode replacement, signing manager, Git GUI, or diagnostics export surface.
- Preserving every old `macbar` setting or internal type name.

## Decisions

1. Use an AppKit status item and popover host for the primary menu bar surface.
   - `macbar` already proves that `NSStatusItem` plus `NSPopover` supports a compact live summary and the dashboard interaction the user wants to preserve.
   - The status item host will own popover toggling, dashboard model lifetime, and status-title updates.
   - Alternative considered: continue with SwiftUI `MenuBarExtra`. It is simpler, but it would require reshaping the existing working menu item behavior before the port is stable.

2. Port a trimmed monitor model instead of importing the full old view-model graph unchanged.
   - `XTop` needs domain snapshots, telemetry scheduling, and developer-context refresh state to back the dashboard.
   - Advanced sensor settings, diagnostics storage, and maintenance mutations will be removed from the initial target graph or kept outside the dashboard path.
   - Alternative considered: copy `MacbarViewModel`, all models, and all dashboard sections verbatim. That is faster initially but keeps missing dependencies and out-of-scope actions coupled to the first working build.

3. Keep baseline telemetry and Xcode/Git introspection behind services.
   - Existing copied service protocols provide a useful seam for Mach telemetry, filesystem scanning, Xcode metadata discovery, Git lookup, and command availability checks.
   - Telemetry refresh can stay frequent while slower developer-context scans run at a separate cadence and return partial results.
   - Alternative considered: collect data directly in SwiftUI views. That would make popover rendering responsible for command execution and filesystem scans.

4. Make the dashboard read-only for this change.
   - The system section and Xcode/Git context sections provide immediate value without mutating user projects or developer caches.
   - Read-only scope lowers the blast radius while the target app absorbs copied code and gets build/runtime verification.
   - Alternative considered: retain old maintenance rows but disable them. Disabled destructive controls still keep maintenance models, command runners, and user expectations in the first port.

5. Treat missing data as a visible state rather than a launch failure.
   - CPU, memory, storage, project discovery, Git context, profiles, and certificates can each fail for different reasons.
   - Snapshot models and section rendering will carry empty, unavailable, or error states so the rest of the dashboard remains usable.
   - Alternative considered: fail a whole refresh when one collector fails. That would make the menu bar app brittle in ordinary toolchain variance.

## Risks / Trade-offs

- [AppKit hosting adds lifecycle code beside SwiftUI scenes] -> Keep status-item ownership narrow and centralize popover/model lifetime in one host.
- [Copied dashboard code still references out-of-scope `macbar` types] -> Trim views and dependencies while introducing only the target-owned models needed by read-only sections.
- [Filesystem scans and developer-tool commands can be slow] -> Keep slow context refresh work off the high-frequency telemetry path and preserve last-known data where appropriate.
- [AppleScript, `git`, keychain metadata, or Xcode state may be unavailable] -> Render partial results and actionable empty/unavailable states instead of blocking the dashboard.
- [Scope drift can reintroduce destructive maintenance actions] -> Keep maintenance services and controls outside the change requirements and tasks.

## Migration Plan

1. Establish the `XTop` menu bar host and trimmed dashboard model path.
2. Bring in only the domain snapshots and views needed for system telemetry plus Xcode/Git read-only context.
3. Remove or isolate placeholder and copied out-of-scope dashboard/settings dependencies until the app builds through the new path.
4. Verify the menu bar item, popover toggling, live refresh behavior, and fallback states in a local macOS run.

Rollback strategy:
- Revert the new status-item host and restore the current placeholder `MenuBarExtra` panel path if the AppKit port regresses launch behavior before the dashboard is ready.

## Open Questions

- Which compact status-title modes should remain user-configurable after the first port versus fixed to the best default?
- Should the initial settings window expose any monitor options beyond the controls needed by the trimmed dashboard?
