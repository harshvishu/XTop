## Why

Designers and iOS engineers using XTop's Simulator Inspector need a way to verify visual alignment, padding, and spacing rhythm in the running simulated app without screenshotting, importing into Figma, or installing a separate alignment tool. Today there is no in-XTop way to overlay reference rulers on a booted iOS Simulator. A thin, configurable grid pinned over the Simulator window — driven by the same Simulator Inspector context the user is already in — turns XTop into a one-screen "is this aligned?" check during UI work.

## What Changes

- Add a "Grid" tab to the Simulator Inspector alongside `UserDefaults`, `Keychain`, `App Groups`, and `Camera`.
- Use the Accessibility API to locate and track the Simulator window for the currently selected simulator UDID and mirror its frame with a transparent, click-through `NSWindow` overlay rendered in SwiftUI.
- Draw horizontal and vertical hairline rules across the entire Simulator window from a per-axis spec.
- Support two configuration modes per axis, both stored as a list of point offsets (`[CGFloat]`):
  - **Uniform** — single spacing value (e.g. `8`) that expands to `[8, 8, 8, …]` filling the window dimension. UI sugar over the custom model.
  - **Custom** — explicit comma-separated offsets from the previous line (e.g. `[8, 8, 4, 4]` places vertical lines at x = 8, 16, 20, 24 pt from the left edge).
- Ship with a fixed line style: red, hairline (0.5 pt), default 30% opacity, with a single opacity slider exposed in the tab.
- Persist grid configuration per simulator UDID in `UserDefaults`.
- Show a tab-level notice instructing the user to keep the Simulator at 100% zoom (Cmd+0); document that alignment accuracy is only guaranteed at 100%.
- Tear down the overlay window when the simulator shuts down, the user leaves the inspector, or the toggle is turned off; the configuration persists for next time.

## Capabilities

### New Capabilities
- `simulator-inspector-grid-overlay`: Configure and render a thin alignment grid pinned over a booted iOS Simulator window, driven by per-axis point offsets.

### Modified Capabilities
- `simulator-inspector-surface`: Add the Grid tab as the fifth inspector tab.

## Impact

- Adds a new tab, services, models, and views inside the existing Simulator Inspector domain; does not modify Git, sensor, or dashboard capabilities outside the inspector.
- Requires macOS Accessibility (`AXIsProcessTrusted`) permission to locate and observe the Simulator window. XTop must prompt for permission on first use and surface a clear remediation path if denied.
- Adds a transparent, borderless, click-through `NSWindow` per active overlay; lifecycle is bound to the inspector selection and the tracked Simulator window.
- Introduces no destructive actions and writes no data to the simulator; the feature is entirely read-only with respect to simulator state.

## Non-Goals (v1)

- Simulator zoom levels other than 100% (the overlay assumes 1 pt = 1 host point).
- Grid clipping to the simulated device "screen" rect; v1 covers the full Simulator window including bezel.
- Column/gutter ("12-column") grid presets — out of scope; revisit if requested.
- Baseline / typographic rhythm presets — out of scope.
- Color customization beyond opacity in v1.
- Drag-to-measure rulers, snapping, or interactive guides; v1 is a static render.
- Overlay on real devices, recorded videos, or screenshots.
- Multi-monitor follow-the-display heuristics beyond what AX provides for window frame.
## Why

Designers and iOS developers using XTop need to verify that the UI they are building lines up to a consistent spacing system (4 / 8 pt grids, custom paddings, alignment between rows). Today the only way to check alignment on a booted iOS Simulator is to take a screenshot, drop it into a design tool, and overlay a ruler — which is slow, breaks the live-feedback loop, and is impossible during interactive flows like scrolling or animation. XTop already hosts a Simulator Inspector that targets booted simulators, so it is the natural place to project a thin, configurable alignment grid over the Simulator window using the macOS Accessibility API to track the window frame.

## What Changes

- Add a new "Grid" tab to the Simulator Inspector that toggles a thin alignment grid drawn over the currently selected simulator's window.
- Track the Simulator window's frame for a given device UDID via the macOS Accessibility API (`AXUIElement`) and follow move/resize/close events with an `AXObserver`.
- Render the grid in a borderless, transparent, click-through `NSWindow` pinned over the Simulator window so the underlying app remains fully interactive.
- Support two grid modes per axis (horizontal and vertical), with "uniform" implemented as sugar over the same underlying offset list:
  - **Uniform spacing** — a single point value `N` that places lines at `N, 2N, 3N, …` from the leading edge.
  - **Custom offsets** — a comma-separated list such as `8,8,4,4` that places lines at the cumulative offsets `8, 16, 20, 24` from the leading edge.
- Ship one fixed line color (red) at hairline width (0.5 pt) with a user-controlled opacity slider (default 30%).
- Persist grid configuration per simulator UDID in `UserDefaults`, so each simulator remembers its own grid setup across launches.
- Show a non-blocking notice in the Grid tab reminding the user that the Simulator window must be at 100% zoom (`Cmd+0`) for the grid to map points 1:1 onto the simulated screen.

## Capabilities

### New Capabilities
- `simulator-inspector-grid-overlay`: Configure and render a thin alignment grid over a booted simulator's window using uniform or custom per-axis spacing, persisted per UDID.

### Modified Capabilities
- `simulator-inspector-surface`: Add the Grid tab as a fifth peer to the existing UserDefaults / Keychain / App Groups / Camera tabs.

## Impact

- Adds a new tab, a window-tracking service, an overlay controller, and a config store; does not modify existing UserDefaults, Keychain, App Groups, or Camera tabs.
- Requires the macOS Accessibility permission (System Settings → Privacy & Security → Accessibility) for XTop. If the user has already granted it for any existing AX-dependent feature this is a no-op; otherwise the Grid tab surfaces a permission prompt and disables itself until granted.
- Adds a per-simulator `NSWindow` lifecycle that must be torn down when the grid is toggled off, the simulator is shut down, the inspector is dismissed, or the host app quits.
- No new shell-outs, no new entitlements beyond Accessibility, no changes to simctl plumbing.

## Non-Goals (v1)

- Detecting or compensating for Simulator zoom levels other than 100% (a warning is shown; calibration is deferred).
- Auto-aligning the grid origin to the simulated device's screen rect (the grid covers the entire Simulator window, including bezel, in v1).
- A color picker for the grid lines (single red color in v1; opacity is configurable).
- Drag-to-measure, on-screen rulers, baseline overlays, column-grid (N-columns + gutter) presets, or safe-area overlays — possible follow-ups.
- Overlays on real devices, on the iOS app itself, or on non-Simulator windows.
- Multi-monitor edge cases beyond "follow the window to whichever screen it currently lives on."
