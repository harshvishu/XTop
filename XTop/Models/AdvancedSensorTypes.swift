import Foundation

// MARK: - Helper Installation State

/// Observed installation state of the privileged sensor helper.
///
/// This is what the app **observes** about the helper, not what the user
/// claims. State transitions are driven by real probes performed by
/// ``AdvancedSensorClient``, never by manual UI toggles.
enum AdvancedSensorHelperInstallation: String, Sendable, Codable {

    /// The helper product is not present on the host.
    case notInstalled

    /// The helper is present but the user has not approved privileged access.
    case awaitingApproval

    /// The helper is installed and approved, ready to serve sample requests.
    case ready

    /// The host (Mac model, OS, sandbox configuration) cannot run the helper.
    case unsupported
}

// MARK: - Connectivity State

/// Result of the most recent connectivity probe to the helper.
enum AdvancedSensorHelperConnectivity: Sendable, Equatable {

    /// No probe has run yet, or the last probe was reset.
    case unknown

    /// The helper responded to the last probe.
    case connected

    /// The helper failed to respond. The associated reason is suitable
    /// for surfacing to the user in diagnostics.
    case failed(reason: String)
}

// MARK: - Helper Status Snapshot

/// Complete observed status of the helper at a point in time.
///
/// `AdvancedSensorClient.fetchStatus()` returns this. The settings model
/// derives its UI state from this snapshot plus the user's enabled/disabled
/// preference.
struct AdvancedSensorHelperStatus: Sendable, Equatable {

    let installation: AdvancedSensorHelperInstallation
    let connectivity: AdvancedSensorHelperConnectivity
    let supportsGPU: Bool
    let supportsTemperature: Bool
    let supportsFan: Bool

    /// True when the host supports at least one advanced sensor metric.
    var hostSupportsAnyMetric: Bool {
        supportsGPU || supportsTemperature || supportsFan
    }

    /// Convenience baseline used when no helper is available on the host.
    static let unavailable = AdvancedSensorHelperStatus(
        installation: .notInstalled,
        connectivity: .unknown,
        supportsGPU: false,
        supportsTemperature: false,
        supportsFan: false
    )

    /// Convenience baseline used when the host is fundamentally unsupported.
    static let unsupportedHost = AdvancedSensorHelperStatus(
        installation: .unsupported,
        connectivity: .unknown,
        supportsGPU: false,
        supportsTemperature: false,
        supportsFan: false
    )
}

// MARK: - Sample

/// A single helper-sourced sample of advanced sensor metrics.
///
/// Each field is optional because hardware and helper capabilities can
/// degrade per metric without invalidating the whole sample. A missing
/// field becomes an `unavailable` ``MetricValue`` in the snapshot, with
/// the reason populated from ``unavailableReasons``.
struct AdvancedSensorSample: Sendable, Equatable {

    let gpuPercent: Double?
    let temperatureC: Double?
    let fanRPM: Double?

    /// Per-metric reason text used when a value is missing. Keys are the
    /// raw values of ``AdvancedSensorMetric``.
    let unavailableReasons: [String: String]

    /// Empty sample — every metric is unavailable for the given reason.
    static func allUnavailable(reason: String) -> AdvancedSensorSample {
        AdvancedSensorSample(
            gpuPercent: nil,
            temperatureC: nil,
            fanRPM: nil,
            unavailableReasons: [
                AdvancedSensorMetric.gpu.rawValue: reason,
                AdvancedSensorMetric.temperature.rawValue: reason,
                AdvancedSensorMetric.fan.rawValue: reason
            ]
        )
    }
}

// MARK: - Errors

/// Errors surfaced by ``AdvancedSensorClient`` operations.
///
/// All error cases carry a human-readable `reason` already suitable for
/// settings diagnostics; callers should not need to reformat the message.
enum AdvancedSensorClientError: Error, Sendable, Equatable {
    case notInstalled(reason: String)
    case awaitingApproval(reason: String)
    case unsupported(reason: String)
    case disabled(reason: String)
    case timedOut(reason: String)
    case communicationFailed(reason: String)
    case helperReturnedInvalidData(reason: String)

    var reason: String {
        switch self {
        case .notInstalled(let reason),
             .awaitingApproval(let reason),
             .unsupported(let reason),
             .disabled(let reason),
             .timedOut(let reason),
             .communicationFailed(let reason),
             .helperReturnedInvalidData(let reason):
            return reason
        }
    }
}

// MARK: - Access Test

/// Result of an end-to-end "test access" action triggered from settings.
///
/// Captures both whether the test succeeded and a human-readable summary
/// that the settings view can display directly.
struct AdvancedSensorAccessTestResult: Sendable, Equatable {

    let succeeded: Bool
    let summary: String
    let performedAt: Date

    static let neverRun = AdvancedSensorAccessTestResult(
        succeeded: false,
        summary: "No sensor access test has run.",
        performedAt: .distantPast
    )
}

// MARK: - Setup Operation Result

/// Outcome of a `startSetup` operation.
///
/// `startSetup` is a real install attempt in production. In stub builds
/// where no helper exists, it returns `.unsupported` rather than fabricating
/// success.
enum AdvancedSensorSetupOutcome: Sendable, Equatable {
    case awaitingApproval(message: String)
    case ready(message: String)
    case unsupported(message: String)
    case failed(message: String)

    var message: String {
        switch self {
        case .awaitingApproval(let message),
             .ready(let message),
             .unsupported(let message),
             .failed(let message):
            return message
        }
    }
}

// MARK: - Client Protocol

/// App-side boundary for the privileged sensor helper.
///
/// All methods are asynchronous, never throw for "expected" missing-helper
/// situations (those become explicit return values), and are safe to call
/// from any task. Implementations must enforce their own timeouts so the
/// telemetry sampling loop never blocks on advanced sensors.
///
/// In Phase 1 the only implementation is ``UnavailableAdvancedSensorClient``,
/// which mirrors the current "no helper installed" behavior while presenting
/// the real protocol surface to the rest of the app.
protocol AdvancedSensorClient: Sendable {

    /// Probe the helper for its installation, approval, connectivity, and
    /// host-support state. Never throws — failure modes are encoded in the
    /// returned ``AdvancedSensorHelperStatus``.
    func fetchStatus() async -> AdvancedSensorHelperStatus

    /// Attempt to perform the installation/approval flow.
    func startSetup() async -> AdvancedSensorSetupOutcome

    /// Drop the local helper configuration. Equivalent to a soft uninstall
    /// from the app's perspective; the helper binary itself may persist
    /// until the OS reclaims it.
    func removeConfiguration() async

    /// Sample advanced sensors via the helper. Throws on every kind of
    /// helper failure (missing, awaiting approval, timeout, transport).
    /// Callers should map errors to per-metric unavailable values.
    func sampleAdvancedMetrics() async throws -> AdvancedSensorSample

    /// Run an end-to-end access test and return a summary suitable for
    /// settings diagnostics.
    func performAccessTest() async -> AdvancedSensorAccessTestResult
}
