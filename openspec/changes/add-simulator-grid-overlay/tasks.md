## 1. Accessibility Permission and Foundations

- [x] 1.1 Confirm XTop can request and detect Accessibility permission (`AXIsProcessTrustedWithOptions`) under the current entitlements/sandbox posture; update entitlements or Info.plist usage strings if required.
- [x] 1.2 Add an `AXPermissionStatus` enum and a small helper that publishes current trust state to `@MainActor` consumers.
- [x] 1.3 Add domain models: `GridAxisSpec` (with `mode`, `uniformSpacing`, `customOffsets`), `GridOverlayConfig` (per-axis specs + opacity + isEnabled), and `SimulatorIdentity` carrying UDID + display name for window matching.

## 2. Configuration Parsing and Storage

- [x] 2.1 Implement a comma-separated offsets parser that accepts `"8, 8, 4, 4"` and rejects empty entries, non-positive values, and non-numeric tokens with a typed error.
- [x] 2.2 Implement `GridOverlayConfigStore` backed by `UserDefaults`, keyed by simulator UDID, with `Codable` round-trip for `GridOverlayConfig` and immediate write-through.
- [x] 2.3 Provide a default `GridOverlayConfig` (disabled, uniform 8 pt both axes, 30% opacity) used on first load for an unseen UDID.

## 3. Simulator Window Tracking

- [x] 3.1 Implement `SimulatorWindowTracker` that, given Simulator.app's PID and a `SimulatorIdentity`, locates the matching `AXUIElement` window using window title + device name heuristics.
- [x] 3.2 Attach `AXObserver` callbacks for window moved, resized, miniaturized, and destroyed; surface frame updates and lifecycle events via an `AsyncStream`.
- [x] 3.3 Convert AX/CG window frames to AppKit coordinates correctly across multi-display setups.
- [x] 3.4 Handle the "Simulator.app not running" and "no matching window" cases with a typed error returned to the controller.

## 4. Overlay Rendering

- [x] 4.1 Implement `GridOverlayController` (`@MainActor`) that owns a transparent, borderless, click-through `NSWindow` per active overlay.
- [x] 4.2 Bind the overlay window's frame to the tracker's `AsyncStream` of frame updates.
- [x] 4.3 Implement a SwiftUI `Canvas` view that resolves a `GridAxisSpec` to line positions (uniform → repeating; custom → cumulative offsets) and draws hairline rules at red, 0.5 pt, configurable opacity.
- [x] 4.4 Ensure the overlay window joins all Spaces and stays above Simulator.app (`level = .floating`, appropriate `collectionBehavior`).
- [x] 4.5 Tear down the overlay window and detach observers on disable, simulator shutdown, or window destruction.

## 5. Grid Tab UI

- [x] 5.1 Add `GridTabView` and wire it as the fifth tab in `SimulatorInspectorRootView`.
- [x] 5.2 Render an AX-permission empty state with a "Grant Accessibility Access" affordance that opens System Settings when the process is not trusted; disable the toggle until granted.
- [x] 5.3 Render the enable toggle, opacity slider (10%–80%), and the per-axis mode picker (Uniform | Custom).
- [x] 5.4 Render the uniform-spacing stepper/numeric field and the custom-offsets text field with inline parser-error feedback.
- [x] 5.5 Render a persistent informational notice instructing the user to keep the Simulator at 100% zoom (Cmd+0).
- [x] 5.6 Apply `DesignSystem.Spacing`, `DesignSystem.Typography`, and `DesignSystem.Colors`; follow XTop UI rules (no heavy cards, compact rows).

## 6. Lifecycle Integration

- [x] 6.1 When the user switches simulators in the inspector, disable the prior overlay and enable the new one if its persisted config is enabled.
- [x] 6.2 When the user navigates away from the Simulator Inspector destination, tear down all overlays; restore on return per persisted config.
- [x] 6.3 When a tracked Simulator window is destroyed (simulator shutdown), automatically tear down and reflect the change in the tab.

## 7. Verification

- [x] 7.1 Unit tests for the comma-separated offsets parser (happy path, whitespace, negative, zero, empty, non-numeric).
- [x] 7.2 Unit tests for `GridAxisSpec` line resolution (uniform fills dimension; custom returns offsets verbatim; overflow clipped).
- [x] 7.3 Unit tests for `GridOverlayConfigStore` round-trip and default generation for unseen UDIDs.
- [x] 7.4 Unit tests for AX window-matching heuristic against synthetic title fixtures.
- [ ] 7.5 Manual end-to-end pass on a booted iOS Simulator at 100% zoom: enable, verify uniform 8 pt grid, switch to custom `[8,8,4,4]` and confirm line placement, drag and resize the Simulator window, shut the simulator down (overlay disappears), switch simulators in the inspector.
- [ ] 7.6 Manual AX-permission denial pass: revoke permission and confirm the tab renders the empty state with a working "Grant Accessibility Access" affordance.
