import AppKit
import ApplicationServices
import Foundation

/// Typed errors surfaced by ``SimulatorWindowTracker``.
enum SimulatorWindowTrackerError: Error, Equatable, Sendable {
    case simulatorAppNotRunning
    case noMatchingWindow(deviceName: String)
    case accessibilityDenied
}

/// Window-frame update or lifecycle event emitted by a tracker.
enum SimulatorWindowEvent: Sendable, Equatable {
    /// New frame in AppKit (bottom-left origin, primary screen) coordinates.
    case frame(CGRect)
    /// The window was minimized; the overlay should hide.
    case minimized
    /// The window was de-minimized; the overlay should reappear at its last frame.
    case deminiaturized
    /// The window was destroyed (simulator shut down / closed). The tracker is
    /// now terminal and emits no further events.
    case destroyed
}

/// Locates the Simulator.app `AXUIElement` window for a given simulator
/// identity and publishes frame / lifecycle updates via an `AsyncStream`.
///
/// The tracker matches the Simulator window by checking that the AX window
/// title contains the simulator's display name. When multiple booted
/// simulators share a device family, callers should disambiguate at the
/// `SimulatorIdentity` level (e.g. by appending UDID suffix into displayName)
/// — v1 falls back to the first matching window with a logged warning.
final class SimulatorWindowTracker: @unchecked Sendable {
    private static let simulatorBundleIdentifier = "com.apple.iphonesimulator"

    let identity: SimulatorIdentity

    private let queue = DispatchQueue(label: "xtop.gridOverlay.windowTracker")
    private var axWindow: AXUIElement?
    private var axObserver: AXObserver?
    private var continuation: AsyncStream<SimulatorWindowEvent>.Continuation?

    init(identity: SimulatorIdentity) {
        self.identity = identity
    }

    deinit {
        stopLocked()
    }

    /// Starts tracking. The returned stream emits one initial `.frame` event
    /// (if a window is found) followed by event-driven updates from
    /// `AXObserver`. Throws if the Simulator process is not running or no
    /// matching window can be located.
    @MainActor
    func start() throws -> AsyncStream<SimulatorWindowEvent> {
        guard AXIsProcessTrusted() else {
            throw SimulatorWindowTrackerError.accessibilityDenied
        }
        guard let pid = SimulatorWindowTracker.simulatorProcessIdentifier() else {
            throw SimulatorWindowTrackerError.simulatorAppNotRunning
        }
        let appElement = AXUIElementCreateApplication(pid)
        guard let window = try SimulatorWindowTracker.findWindow(
            for: identity,
            in: appElement
        ) else {
            throw SimulatorWindowTrackerError.noMatchingWindow(deviceName: identity.displayName)
        }

        let stream = AsyncStream<SimulatorWindowEvent> { continuation in
            self.continuation = continuation
            continuation.onTermination = { [weak self] _ in
                self?.stop()
            }
        }

        queue.sync {
            self.axWindow = window
        }

        // Initial frame.
        if let frame = SimulatorWindowTracker.windowFrame(window) {
            continuation?.yield(.frame(frame))
        }

        // Install AX observer.
        try installObserver(pid: pid, window: window)

        return stream
    }

    /// Stops tracking and tears down any AX observer.
    func stop() {
        queue.sync { stopLocked() }
    }

    /// Returns the current frame in AppKit coordinates, if known.
    @MainActor
    func currentFrame() -> CGRect? {
        queue.sync {
            guard let window = axWindow else { return nil }
            return SimulatorWindowTracker.windowFrame(window)
        }
    }

    /// Returns the rect (in AppKit coordinates) of the simulated device's
    /// rendered screen inside the Simulator window, if it can be identified.
    /// Falls back to the full window frame when no plausible child is found.
    ///
    /// Picks the smallest AX descendant whose area is between 30% and 99% of
    /// the window's area — empirically the simulator's rendered screen view
    /// satisfies this while title-bar buttons, toolbars, and bezel chrome do
    /// not.
    @MainActor
    func currentContentFrame() -> CGRect? {
        queue.sync {
            guard let window = axWindow,
                  let windowFrame = SimulatorWindowTracker.windowFrame(window)
            else { return nil }
            return SimulatorWindowTracker.deviceScreenFrame(in: window, windowFrame: windowFrame)
                ?? windowFrame
        }
    }

    // MARK: - Internals

    private func stopLocked() {
        if let observer = axObserver, let window = axWindow {
            for notification in Self.observedNotifications {
                AXObserverRemoveNotification(observer, window, notification as CFString)
            }
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(observer),
                .commonModes
            )
        }
        axObserver = nil
        axWindow = nil
        continuation?.finish()
        continuation = nil
    }

    private static let observedNotifications: [String] = [
        kAXMovedNotification,
        kAXResizedNotification,
        kAXWindowMovedNotification,
        kAXWindowResizedNotification,
        kAXWindowMiniaturizedNotification,
        kAXWindowDeminiaturizedNotification,
        kAXUIElementDestroyedNotification
    ]

    private func installObserver(pid: pid_t, window: AXUIElement) throws {
        var observer: AXObserver?
        let createResult = AXObserverCreate(pid, Self.axCallback, &observer)
        guard createResult == .success, let observer else {
            throw SimulatorWindowTrackerError.accessibilityDenied
        }

        let context = Unmanaged.passUnretained(self).toOpaque()
        for notification in Self.observedNotifications {
            AXObserverAddNotification(observer, window, notification as CFString, context)
        }
        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .commonModes
        )
        queue.sync { self.axObserver = observer }
    }

    fileprivate func handleAXNotification(_ notification: String, element: AXUIElement) {
        switch notification {
        case kAXUIElementDestroyedNotification:
            continuation?.yield(.destroyed)
            stop()
        case kAXWindowMiniaturizedNotification:
            continuation?.yield(.minimized)
        case kAXWindowDeminiaturizedNotification:
            continuation?.yield(.deminiaturized)
            if let frame = Self.windowFrame(element) {
                continuation?.yield(.frame(frame))
            }
        default:
            if let frame = Self.windowFrame(element) {
                continuation?.yield(.frame(frame))
            }
        }
    }

    // MARK: - Static helpers

    private static let axCallback: AXObserverCallback = { _, element, notificationName, refcon in
        guard let refcon else { return }
        let tracker = Unmanaged<SimulatorWindowTracker>.fromOpaque(refcon).takeUnretainedValue()
        tracker.handleAXNotification(notificationName as String, element: element)
    }

    static func simulatorProcessIdentifier() -> pid_t? {
        NSWorkspace.shared.runningApplications
            .first { $0.bundleIdentifier == simulatorBundleIdentifier }?
            .processIdentifier
    }

    static func findWindow(
        for identity: SimulatorIdentity,
        in appElement: AXUIElement
    ) throws -> AXUIElement? {
        var windowsValue: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXWindowsAttribute as CFString,
            &windowsValue
        )
        guard result == .success, let windows = windowsValue as? [AXUIElement] else {
            return nil
        }
        return Self.matchWindow(for: identity, in: windows) { window in
            var titleValue: AnyObject?
            let titleResult = AXUIElementCopyAttributeValue(
                window,
                kAXTitleAttribute as CFString,
                &titleValue
            )
            guard titleResult == .success else { return nil }
            return titleValue as? String
        }
    }

    /// Pure function: given a list of windows and a way to extract their
    /// titles, pick the best match for the simulator identity. Public for
    /// testability.
    static func matchWindow<Window>(
        for identity: SimulatorIdentity,
        in windows: [Window],
        title: (Window) -> String?
    ) -> Window? {
        guard !windows.isEmpty else { return nil }
        let nameLower = identity.displayName.lowercased()
        let udidLower = identity.udid.lowercased()

        // 1. Exact (case-insensitive) display-name match.
        if let exact = windows.first(where: {
            (title($0) ?? "").lowercased().contains(nameLower)
        }) {
            return exact
        }
        // 2. UDID substring match (rare — only if title encodes UDID).
        if let udidMatch = windows.first(where: {
            (title($0) ?? "").lowercased().contains(udidLower)
        }) {
            return udidMatch
        }
        // 3. No match.
        return nil
    }

    static func windowFrame(_ window: AXUIElement) -> CGRect? {
        var positionValue: AnyObject?
        var sizeValue: AnyObject?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success
        else { return nil }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard let positionAX = positionValue, CFGetTypeID(positionAX) == AXValueGetTypeID() else { return nil }
        guard let sizeAX = sizeValue, CFGetTypeID(sizeAX) == AXValueGetTypeID() else { return nil }
        // swiftlint:disable:next force_cast
        AXValueGetValue(positionAX as! AXValue, .cgPoint, &position)
        // swiftlint:disable:next force_cast
        AXValueGetValue(sizeAX as! AXValue, .cgSize, &size)

        let cgFrame = CGRect(origin: position, size: size)
        return convertToAppKitCoordinates(cgFrame)
    }

    /// AX/CG return window position in "top-left origin, primary display"
    /// coordinates. AppKit's `NSWindow.frame` uses "bottom-left origin, primary
    /// display" coordinates. Flip Y using the primary display height.
    static func convertToAppKitCoordinates(_ cgFrame: CGRect) -> CGRect {
        guard let primary = NSScreen.screens.first else { return cgFrame }
        let primaryHeight = primary.frame.height
        let flippedY = primaryHeight - cgFrame.origin.y - cgFrame.size.height
        return CGRect(
            x: cgFrame.origin.x,
            y: flippedY,
            width: cgFrame.size.width,
            height: cgFrame.size.height
        )
    }

    /// Walks the AX subtree of `window` and returns the smallest descendant
    /// frame (in AppKit coordinates) whose area is between 30% and 99% of
    /// the window's area — the simulator's rendered device screen.
    static func deviceScreenFrame(in window: AXUIElement, windowFrame: CGRect) -> CGRect? {
        var candidates: [CGRect] = []
        collectCandidateFrames(element: window, into: &candidates, depth: 0)
        let windowArea = windowFrame.width * windowFrame.height
        guard windowArea > 0 else { return nil }
        let lower = windowArea * 0.30
        let upper = windowArea * 0.99
        let filtered = candidates.filter { rect in
            let area = rect.width * rect.height
            return area >= lower && area <= upper
        }
        return filtered.min {
            ($0.width * $0.height) < ($1.width * $1.height)
        }
    }

    private static func collectCandidateFrames(
        element: AXUIElement,
        into list: inout [CGRect],
        depth: Int
    ) {
        // Cap recursion depth to keep the AX walk cheap; the simulator's
        // screen view is consistently within ~5 levels of the window.
        guard depth < 6 else { return }
        var childrenValue: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXChildrenAttribute as CFString,
            &childrenValue
        )
        guard result == .success, let children = childrenValue as? [AXUIElement] else { return }
        for child in children {
            if let frame = windowFrame(child) {
                list.append(frame)
            }
            collectCandidateFrames(element: child, into: &list, depth: depth + 1)
        }
    }
}
