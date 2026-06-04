import AppKit
import Observation
import SwiftUI

/// Owns transparent, click-through overlay windows that mirror the frames of
/// tracked Simulator.app windows. One overlay per active simulator UDID.
///
/// `@MainActor` because all `NSWindow` mutation and AX observer wiring must
/// happen on the main thread.
@MainActor
@Observable
final class GridOverlayController {
    /// Lifecycle state for the current active overlay, surfaced to the UI.
    enum ActivationState: Sendable, Equatable {
        case inactive
        case active
        case error(String)
    }

    private(set) var stateByUDID: [String: ActivationState] = [:]

    @ObservationIgnored private var entries: [String: Entry] = [:]

    init() {}

    /// Activates the overlay for `identity`, rendering `config` on the
    /// matching Simulator window. If already active for the same UDID, the
    /// configuration is updated in place (no window recreation).
    func activate(for identity: SimulatorIdentity, config: GridOverlayConfig) {
        if let existing = entries[identity.udid] {
            existing.update(config: config)
            stateByUDID[identity.udid] = .active
            return
        }

        let tracker = SimulatorWindowTracker(identity: identity)
        let entry = Entry(
            identity: identity,
            tracker: tracker,
            config: config
        )
        entries[identity.udid] = entry

        do {
            let stream = try tracker.start()
            entry.attachOverlayWindow()
            entry.startConsuming(stream: stream) { [weak self] in
                self?.handleTermination(udid: identity.udid)
            }
            stateByUDID[identity.udid] = .active
        } catch let error as SimulatorWindowTrackerError {
            entry.tearDown()
            entries.removeValue(forKey: identity.udid)
            stateByUDID[identity.udid] = .error(message(for: error, deviceName: identity.displayName))
        } catch {
            entry.tearDown()
            entries.removeValue(forKey: identity.udid)
            stateByUDID[identity.udid] = .error(error.localizedDescription)
        }
    }

    /// Disables the overlay for a UDID (closes the window, detaches the
    /// observer). The persisted configuration is untouched.
    func deactivate(udid: String) {
        guard let entry = entries.removeValue(forKey: udid) else {
            stateByUDID[udid] = .inactive
            return
        }
        entry.tearDown()
        stateByUDID[udid] = .inactive
    }

    /// Tears down every active overlay (called on inspector navigation away
    /// and on view disappearance).
    func deactivateAll() {
        for (udid, entry) in entries {
            entry.tearDown()
            stateByUDID[udid] = .inactive
        }
        entries.removeAll()
    }

    /// Updates the rendered configuration for an already-active overlay.
    /// No-op if the overlay is not active.
    func updateConfig(_ config: GridOverlayConfig, udid: String) {
        entries[udid]?.update(config: config)
    }

    func isActive(udid: String) -> Bool {
        if case .active = stateByUDID[udid] { return true }
        return false
    }

    func currentState(udid: String) -> ActivationState {
        stateByUDID[udid] ?? .inactive
    }

    private func handleTermination(udid: String) {
        guard let entry = entries.removeValue(forKey: udid) else { return }
        entry.tearDown()
        stateByUDID[udid] = .inactive
    }

    private func message(for error: SimulatorWindowTrackerError, deviceName: String) -> String {
        switch error {
        case .simulatorAppNotRunning:
            return "Simulator.app is not running. Boot a simulator and try again."
        case .noMatchingWindow:
            return "Could not find a Simulator window titled \"\(deviceName)\". Make sure the simulator window is visible and not minimized."
        case .accessibilityDenied:
            return "Accessibility permission denied. Grant access in System Settings → Privacy & Security → Accessibility."
        }
    }
}

// MARK: - Entry

@MainActor
private final class Entry {
    let identity: SimulatorIdentity
    let tracker: SimulatorWindowTracker
    private var config: GridOverlayConfig
    private var overlayWindow: NSWindow?
    private var renderState: GridRenderState
    private var consumeTask: Task<Void, Never>?
    private var isMinimized = false
    private var pollTimer: Timer?

    init(identity: SimulatorIdentity, tracker: SimulatorWindowTracker, config: GridOverlayConfig) {
        self.identity = identity
        self.tracker = tracker
        self.config = config
        self.renderState = GridRenderState(config: config)
    }

    func attachOverlayWindow() {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        // Use the normal window level so the overlay participates in regular
        // z-ordering: other apps' windows can occlude it just like they
        // occlude the Simulator window. We then re-stack it directly above
        // the Simulator window so it always rides along with it.
        window.level = .normal
        window.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false

        let hosting = NSHostingView(rootView: GridOverlayCanvas(state: renderState))
        hosting.frame = window.contentLayoutRect
        hosting.autoresizingMask = [.width, .height]
        window.contentView = hosting

        if let frame = tracker.currentFrame() {
            window.setFrame(frame, display: false)
        }
        overlayWindow = window
        updateVisibilityAndStacking()

        // Poll periodically to follow z-order changes (other apps coming to
        // the front, the simulator being brought forward via Cmd+Tab, etc.).
        // AX does not deliver z-order change notifications cross-process, so
        // a low-frequency poll is the simplest robust option.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateVisibilityAndStacking()
            }
        }
    }

    func startConsuming(
        stream: AsyncStream<SimulatorWindowEvent>,
        onTerminated: @escaping @MainActor () -> Void
    ) {
        consumeTask = Task { @MainActor [weak self] in
            for await event in stream {
                guard let self else { return }
                self.apply(event: event)
            }
            onTerminated()
        }
    }

    func update(config: GridOverlayConfig) {
        self.config = config
        renderState.update(config: config)
    }

    func tearDown() {
        consumeTask?.cancel()
        consumeTask = nil
        pollTimer?.invalidate()
        pollTimer = nil
        tracker.stop()
        overlayWindow?.orderOut(nil)
        overlayWindow?.contentView = nil
        overlayWindow = nil
    }

    private func apply(event: SimulatorWindowEvent) {
        switch event {
        case .frame(let frame):
            overlayWindow?.setFrame(frame, display: true)
            updateVisibilityAndStacking()
        case .minimized:
            isMinimized = true
            updateVisibilityAndStacking()
        case .deminiaturized:
            isMinimized = false
            updateVisibilityAndStacking()
        case .destroyed:
            tearDown()
        }
    }

    /// Hide the overlay when the Simulator window is minimized; otherwise
    /// show it and re-stack it directly above the simulator window so the
    /// natural z-order causes other windows in front of the simulator to
    /// occlude the overlay as well.
    private func updateVisibilityAndStacking() {
        guard let window = overlayWindow else { return }
        if isMinimized {
            if window.isVisible { window.orderOut(nil) }
            return
        }
        guard let frame = tracker.currentFrame(),
              let simulatorWindowNumber = simulatorWindowNumber(near: frame) else {
            // Simulator window not currently locatable in the on-screen list
            // (occluded across spaces, hidden, etc.). Hide rather than float.
            if window.isVisible { window.orderOut(nil) }
            return
        }
        if !window.isVisible {
            window.order(.above, relativeTo: simulatorWindowNumber)
        } else {
            // Always re-stack: cheap, idempotent, and corrects drift when the
            // user clicks another app then returns to the simulator.
            window.order(.above, relativeTo: simulatorWindowNumber)
        }
    }

    /// Look up the Simulator process's on-screen window whose bounds best
    /// match `frame` (in AppKit coordinates) and return its CGWindowID as
    /// `Int`, suitable for `NSWindow.order(_:relativeTo:)`.
    private func simulatorWindowNumber(near frame: CGRect) -> Int? {
        guard let simulatorPID = NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == "com.apple.iphonesimulator" })?
            .processIdentifier
        else { return nil }

        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        // CGWindow bounds use top-left origin coordinates referenced to the
        // primary display, while NSWindow.frame uses bottom-left origin.
        // Convert `frame` back to CG coordinates for comparison.
        guard let primary = NSScreen.screens.first else { return nil }
        let cgFrame = CGRect(
            x: frame.origin.x,
            y: primary.frame.height - frame.origin.y - frame.size.height,
            width: frame.size.width,
            height: frame.size.height
        )

        var best: (number: Int, distance: CGFloat)?
        for entry in windowList {
            guard let ownerPID = entry[kCGWindowOwnerPID as String] as? Int32,
                  ownerPID == simulatorPID,
                  let number = entry[kCGWindowNumber as String] as? Int,
                  let boundsDict = entry[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
            else { continue }

            let layer = (entry[kCGWindowLayer as String] as? Int) ?? 0
            // The simulator's primary window lives at layer 0. Skip menu
            // extras, tooltips, etc.
            guard layer == 0 else { continue }

            let dx = bounds.origin.x - cgFrame.origin.x
            let dy = bounds.origin.y - cgFrame.origin.y
            let dw = bounds.size.width - cgFrame.size.width
            let dh = bounds.size.height - cgFrame.size.height
            let distance = dx * dx + dy * dy + dw * dw + dh * dh
            if best == nil || distance < best!.distance {
                best = (number, distance)
            }
        }
        return best?.number
    }
}

// MARK: - Renderer

@MainActor
@Observable
private final class GridRenderState {
    var config: GridOverlayConfig

    init(config: GridOverlayConfig) {
        self.config = config
    }

    func update(config: GridOverlayConfig) {
        self.config = config
    }
}

private struct GridOverlayCanvas: View {
    @State var state: GridRenderState

    var body: some View {
        // Read the config out here so the Observation framework registers a
        // dependency on `state.config` for this `body` and invalidates it on
        // every mutation. Reads inside the Canvas drawing closure are NOT
        // tracked because that closure runs outside of `body` evaluation.
        let config = state.config
        return Canvas { context, size in
            guard config.isEnabled else { return }
            let opacity = config.opacity
            let lineColor = Color.red.opacity(opacity)
            let lineWidth: CGFloat = 0.5

            // Vertical lines: x positions from leading edge.
            let xs = config.vertical.resolvedLinePositions(filling: size.width)
            if !xs.isEmpty {
                var path = Path()
                for x in xs {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                }
                context.stroke(path, with: .color(lineColor), lineWidth: lineWidth)
            }

            // Horizontal lines: y positions from top edge.
            let ys = config.horizontal.resolvedLinePositions(filling: size.height)
            if !ys.isEmpty {
                var path = Path()
                for y in ys {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                }
                context.stroke(path, with: .color(lineColor), lineWidth: lineWidth)
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}
