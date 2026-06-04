## Context

XTop already hosts a Simulator Inspector that selects a booted iOS Simulator by UDID and presents per-app tools (UserDefaults, Keychain, App Groups, Camera). Designers and iOS engineers using the inspector also need a way to verify on-screen alignment against a spacing system (typically 4 / 8 pt grids, sometimes irregular custom offsets). The Grid overlay is a peer tool in the same inspector that draws a thin alignment grid on top of the Simulator window itself, so the developer can check spacing live without leaving XTop or capturing screenshots.

The Grid overlay is intentionally scoped to one thing: pixel-accurate alignment lines over a 100%-zoom Simulator window. It does not interact with the simulated app, does not change anything on disk, and does not interpose itself between the user and the simulator.

## Goals / Non-Goals

**Goals:**
- Let the user toggle a thin grid overlay over the currently selected simulator's window from a new Grid tab inside the Simulator Inspector.
- Support uniform spacing (single value) and custom offsets (comma-separated list) independently for the horizontal and vertical axes, with uniform expressed as sugar over the same offset model.
- Keep the overlay pinned to the Simulator window as the user moves, resizes, focuses, or closes it.
- Keep the simulator interactive — the overlay must not capture clicks, scrolls, keystrokes, or hover.
- Persist grid configuration per simulator UDID so each simulator remembers its own grid.

**Non-Goals:**
- Supporting Simulator zoom levels other than 100% in v1.
- Inferring the simulated device screen rect inside the Simulator window (full-window overlay only).
- A grid color picker (single red color in v1; opacity is configurable).
- On-screen rulers, drag-to-measure, baseline overlays, or N-column / gutter presets.
- Real-device overlays or any in-app injection.

## Decisions

1. Draw the grid in a host-side transparent `NSWindow`, not via in-app injection.
- Decision: Create a borderless, transparent `NSWindow` per active grid, layered above the Simulator window, with `ignoresMouseEvents = true` and a SwiftUI `Canvas` drawing the lines.
- Rationale: Zero cooperation from the simulated app is required, the overlay works for any app on any simulator, and click-through preserves full simulator interactivity.
- Alternative considered: Injecting a debug overlay into the iOS app. Rejected because it requires app-side cooperation and would not help when QA-ing third-party builds.

2. Use the macOS Accessibility API to locate and follow the Simulator window.
- Decision: Resolve `Simulator.app` via `NSWorkspace.runningApplications`, walk its `AXUIElement` window list, match the window whose title encodes the target simulator's name/UDID, and attach an `AXObserver` for `kAXMovedNotification`, `kAXResizedNotification`, `kAXWindowMiniaturizedNotification`, `kAXWindowDeminiaturizedNotification`, and `kAXUIElementDestroyedNotification`. Reposition or hide the overlay window in response.
- Rationale: AX is the public, supported way to read window geometry across processes on macOS. It avoids private API and works under hardened runtime.
- Alternative considered: `CGWindowListCopyWindowInfo` polling. Rejected because polling is wasteful and laggy compared to AX notifications, and CG window info does not expose the live geometry change events as cleanly.

3. Restrict v1 to 100% Simulator zoom, with an in-tab notice rather than auto-detection.
- Decision: Do not attempt to detect the Simulator's zoom level. Render the grid assuming 1 simulated point = 1 host point and show a static notice in the Grid tab telling the user to set Simulator zoom to 100% (`Cmd+0`).
- Rationale: Simulator's zoom level is not exposed via AX in a stable way, and supporting all zoom levels expands the spike into private-API or calibration UX that is disproportionate to v1 value. 100% is the default workflow for alignment QA.
- Alternative considered: Manual two-point calibration ("click top-left, click bottom-right"). Deferred to a follow-up if 100%-only proves limiting.

4. Cover the full Simulator window, not just the simulated screen rect.
- Decision: The overlay matches the Simulator window's frame exactly, including the device bezel area, in v1.
- Rationale: Detecting the bezel inset per device requires either device-database lookup or image analysis; full-window is unambiguous and visually trivial to reason about (lines that fall on the bezel are simply ignored by the eye).
- Alternative considered: Insetting to the simulated display rect. Deferred; if multiple users find the bezel lines confusing, add a "constrain to screen" toggle later.

5. Treat uniform spacing as sugar over custom offsets.
- Decision: Persist a single `GridAxisSpec` per axis with `mode: { uniform, custom }`, `uniformSpacing: CGFloat`, and `customOffsets: [CGFloat]`. The renderer always asks the spec to produce a `[CGFloat]` of line positions; uniform mode generates that list by repeating the spacing across the axis length.
- Rationale: One drawing path, one mental model. The UI just toggles which input drives the resolved offset list.
- Alternative considered: Two separate axis types (`UniformAxis`, `CustomAxis`). Rejected because it duplicates rendering, persistence, and validation logic.

6. Custom offsets are cumulative gaps from the leading edge, in points.
- Decision: For an entry like `8,8,4,4`, lines are drawn at cumulative offsets `8, 16, 20, 24` from the leading (left for vertical lines, top for horizontal lines) edge of the Simulator window. Values must be positive `CGFloat`s; invalid tokens are rejected with inline parse feedback in the text field.
- Rationale: This matches how designers describe spacing systems ("first item starts 8 from the edge, then another 8 gap, then 4, then 4") and matches the user's stated example from the proposal discussion.
- Alternative considered: Absolute positions from the origin. Rejected as less natural to type and harder to extend with a future "repeat-from-here" affordance.

7. One fixed color, one opacity slider, hairline width.
- Decision: Lines are drawn in red at 0.5 pt width, with opacity user-configurable via a slider (default 30%). No color picker, no per-axis styling.
- Rationale: Single decision surface for v1; red is unambiguous against most iOS UIs; hairline + low opacity is the de facto convention for designer overlays.
- Alternative considered: Per-axis color and width. Deferred until users actually ask for it.

8. Persist grid configuration per simulator UDID.
- Decision: Store `GridOverlayConfig` keyed by simulator UDID in `UserDefaults` via a dedicated `GridOverlayConfigStore`. Configuration includes `isEnabled`, `opacity`, and `horizontal` / `vertical` axis specs.
- Rationale: Each simulator can have its own grid (e.g. iPhone 16 Pro at 8 pt, iPad at custom offsets). UDID-keyed persistence matches how the rest of the inspector scopes per-simulator state.
- Alternative considered: Per device-type (model name). Rejected for v1 — UDID is what the inspector already keys off and adding model-level inheritance is more state-management surface than it is worth right now.

9. One overlay window per active simulator, owned by an `@MainActor` controller.
- Decision: `GridOverlayController` is a `@MainActor`-isolated `@Observable` class that maps simulator UDID → (`SimulatorWindowTracker`, overlay `NSWindow`). Toggling the grid on for a UDID creates the pair; toggling off, simulator shutdown, or app quit tears it down.
- Rationale: Multiple simulators can be booted at once and the user may want grids on more than one. Per-UDID ownership keeps lifecycle local and avoids global state.
- Alternative considered: A single shared overlay window that re-parents to the currently focused simulator. Rejected because the inspector explicitly supports multiple booted simulators and per-UDID config.

## Risks / Trade-offs

- [Accessibility permission is required, and denied permission disables the tab] -> Mitigation: detect via `AXIsProcessTrusted()` on tab appear, show an inline explainer + "Open System Settings" deep link, disable the toggle until granted.
- [Simulator window title format changes between Xcode versions] -> Mitigation: match by simulator name first, then by UDID substring, and log a single warning if neither matches; fall back to "no window found" UX instead of crashing.
- [Simulator zoom != 100% silently misaligns the grid] -> Mitigation: show a persistent notice in the Grid tab; in a later iteration consider detecting via window-size heuristics or AX attributes.
- [Multiple displays / display reconfiguration mid-session] -> Mitigation: the AX observer fires on move/resize when the window crosses screens; the overlay window follows. Verify behavior on a hot-swapped external display during manual QA.
- [Custom-offset parse errors are easy to make] -> Mitigation: parse on every keystroke, reject non-numeric / non-positive tokens, surface a compact inline error and keep the last valid spec applied.
- [Overlay window stealing focus or breaking key events] -> Mitigation: set `ignoresMouseEvents = true`, `level = .floating`, `acceptsMouseMovedEvents = false`, and never call `makeKey`. Verify with a manual QA pass that keyboard input still routes to the simulator.
- [Drawing many lines on large windows could jank under animation] -> Mitigation: SwiftUI `Canvas` with a single `path` per axis. Limit custom-offset list length to a sane maximum (e.g. 256 entries) with inline UI feedback.
- [Tearing down the overlay window on simulator shutdown could race with AX notifications on a background thread] -> Mitigation: marshal all AX callbacks onto the main actor via `DispatchSource` + `MainActor.assumeIsolated` pattern already used elsewhere in XTop services.

## Migration Plan

1. Add `GridAxisSpec`, `GridOverlayConfig`, and `GridOverlayConfigStore` (UserDefaults-backed, per-UDID).
2. Add `SimulatorWindowTracker` that resolves and observes the Simulator window for a UDID via AX.
3. Add `GridOverlayController` (`@MainActor`, `@Observable`) that owns one transparent `NSWindow` per active UDID and mirrors the tracker frame.
4. Implement the SwiftUI `Canvas`-based grid renderer that consumes the resolved per-axis offset list and current opacity.
5. Add `GridTabView` to the Simulator Inspector with the enable toggle, opacity slider, per-axis mode selector (uniform / custom), inputs, the 100%-zoom notice, and an AX-permission gate.
6. Wire the new tab as the fifth peer in `SimulatorInspectorRootView` and update the `simulator-inspector-surface` capability spec to reflect the additional tab.
7. Add unit tests for `GridAxisSpec` offset resolution (uniform expansion, custom parsing, invalid-input rejection) and for `GridOverlayConfigStore` per-UDID persistence round-trip.
8. Manual QA pass: toggle grid on iPhone 16 Pro at 100% zoom, drag the window between displays, resize, shut the simulator down, relaunch, verify uniform vs custom rendering, verify click-through.
