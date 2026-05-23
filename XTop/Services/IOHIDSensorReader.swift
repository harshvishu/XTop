import Foundation

// MARK: - Public Types

/// Errors surfaced by ``IOHIDSensorReader``.
enum IOHIDSensorReaderError: Error, Sendable, Equatable {
    /// The private IOHIDEventSystemClient could not be created.
    case clientUnavailable

    /// No services matching the requested sensor category were found on
    /// this host. This is the normal "no-fan MacBook Air" case for fan
    /// readings — not a malfunction.
    case noSensorsAvailable
}

// MARK: - IOHIDSensorReader

/// Reads thermal and power sensors via the private `IOHIDEventSystemClient`
/// API. This is the standard mechanism on Apple Silicon Macs since macOS 12+;
/// the public AppleSMC user-client interface no longer exposes key reads
/// to unprivileged user processes (it returns -10054 / kIOReturnNotPrivileged
/// for every `kSMCReadKey` request).
///
/// The reader is intentionally narrow: it returns averaged temperature in °C
/// across the SoC die sensors and averaged fan RPM across detected fan
/// services. Per-sensor enumeration is exposed for diagnostics but the
/// public API returns one number per metric to match the existing telemetry
/// shape.
///
/// Privacy / security: this uses the same IOHIDEventSystemClient surface
/// that `stats`, `iStat Menus`, `Sensei`, and `Hot` use. It does not require
/// entitlements, root, or a privileged helper, but it is a private SPI so
/// future macOS releases may change behavior. The reader degrades gracefully
/// when the SPI is unavailable.
final class IOHIDSensorReader: @unchecked Sendable {

    // IOHIDEventSystem usage page / usage constants.
    // page = kHIDPage_AppleVendor (0xff00) + usage = kHIDUsage_AppleVendor_TemperatureSensor (5)
    private static let temperaturePage = 0xff00
    private static let powerPage = 0xff08
    private static let sensorUsage = 5

    // IOHIDEventType values.
    // kIOHIDEventTypeTemperature = 15
    // kIOHIDEventTypePower       = 25
    private static let temperatureEvent: Int64 = 15
    private static let powerEvent: Int64 = 25

    private static let temperatureField: Int32 = Int32(15 << 16)
    private static let powerField: Int32 = Int32(25 << 16)

    private let lock = NSLock()
    private var client: AnyObject?

    init() {}

    // MARK: Public API

    /// Average die temperature in °C across recognized SoC sensors.
    ///
    /// Returns `nil` when no temperature service produced a reading in the
    /// recognized range (0–150 °C). Throws when the IOHIDEventSystemClient
    /// itself cannot be constructed.
    func readAverageDieTemperature() throws -> Double? {
        let readings = try collectTemperatureReadings()
        let sensorReadings = readings
            .filter { $0.product.hasPrefix("PMU tdie") || $0.product.hasPrefix("pACC") }
            .map(\.value)
        if sensorReadings.isEmpty {
            // Fall back to any temperature reading — battery/NAND are not
            // ideal but better than nothing on hosts where tdie isn't named
            // as expected.
            let fallback = readings.map(\.value).filter { $0 > 0 && $0 < 150 }
            guard !fallback.isEmpty else { return nil }
            return fallback.reduce(0, +) / Double(fallback.count)
        }
        return sensorReadings.reduce(0, +) / Double(sensorReadings.count)
    }

    /// Average fan RPM across detected fan services. Returns `nil` on Macs
    /// without fan hardware (MacBook Air, Mac mini M-series) — that is a
    /// real "no fan present" state, not a failure.
    func readAverageFanRPM() throws -> Double? {
        let readings = try collectFanReadings()
        guard !readings.isEmpty else { return nil }
        let values = readings.map(\.value).filter { $0 > 0 && $0 < 20_000 }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// True when this host has any fan service registered. Used by
    /// capability reporting so the settings UI can distinguish "no fans"
    /// from "fan read failed".
    func hostHasFanHardware() -> Bool {
        (try? collectFanReadings().isEmpty == false) ?? false
    }

    // MARK: Diagnostics

    /// Per-sensor reading for diagnostics or richer UI later.
    struct Reading: Sendable, Equatable {
        let product: String
        let value: Double
    }

    func collectTemperatureReadings() throws -> [Reading] {
        try collect(
            page: IOHIDSensorReader.temperaturePage,
            usage: IOHIDSensorReader.sensorUsage,
            eventType: IOHIDSensorReader.temperatureEvent,
            field: IOHIDSensorReader.temperatureField,
            validate: { $0 > 0 && $0 < 150 }
        )
    }

    /// Fan services historically use a separate page on Intel; on Apple
    /// Silicon fans (when present) appear under the same vendor pages.
    /// We probe both temperature and power pages for services whose
    /// product name contains "Fan" or "fan".
    func collectFanReadings() throws -> [Reading] {
        var all: [Reading] = []
        let pages = [IOHIDSensorReader.temperaturePage, IOHIDSensorReader.powerPage]
        for page in pages {
            let candidates = try collect(
                page: page,
                usage: IOHIDSensorReader.sensorUsage,
                eventType: IOHIDSensorReader.powerEvent,
                field: IOHIDSensorReader.powerField,
                validate: { $0 >= 0 && $0 < 20_000 }
            )
            all.append(contentsOf: candidates.filter {
                $0.product.localizedCaseInsensitiveContains("fan")
            })
        }
        return all
    }

    // MARK: Client lifecycle

    private func ensureClient() throws -> AnyObject {
        lock.lock()
        defer { lock.unlock() }
        if let existing = client {
            return existing
        }
        guard let raw = IOHIDPrivate.createEventSystemClient() else {
            throw IOHIDSensorReaderError.clientUnavailable
        }
        let instance = raw.takeRetainedValue()
        client = instance
        return instance
    }

    private func collect(
        page: Int,
        usage: Int,
        eventType: Int64,
        field: Int32,
        validate: (Double) -> Bool
    ) throws -> [Reading] {
        let client = try ensureClient()
        guard let array = IOHIDPrivate.copyServices(client) else {
            throw IOHIDSensorReaderError.noSensorsAvailable
        }
        let count = CFArrayGetCount(array)
        var readings: [Reading] = []
        for index in 0..<count {
            let raw = CFArrayGetValueAtIndex(array, index)
            let service = unsafeBitCast(raw, to: AnyObject.self)
            let svcPage = (IOHIDPrivate.copyProperty(service, "PrimaryUsagePage") as? NSNumber)?.intValue ?? 0
            let svcUsage = (IOHIDPrivate.copyProperty(service, "PrimaryUsage") as? NSNumber)?.intValue ?? 0
            guard svcPage == page, svcUsage == usage else { continue }
            guard let eventRaw = IOHIDPrivate.copyEvent(service, type: eventType) else { continue }
            let event = eventRaw.takeRetainedValue()
            let value = IOHIDPrivate.eventFloatValue(event, field: field)
            guard validate(value) else { continue }
            let product = IOHIDPrivate.copyProperty(service, "Product") as? String ?? "(no product)"
            readings.append(Reading(product: product, value: value))
        }
        return readings
    }
}

// MARK: - Private SPI bridge

/// Wraps the unpublished `IOHIDEventSystemClient` and `IOHIDServiceClient`
/// C entry points. Keeping these in one place makes it trivial to swap to
/// a published API if Apple ever ships one, and isolates the @_silgen_name
/// surface for review.
enum IOHIDPrivate {

    static func createEventSystemClient() -> Unmanaged<AnyObject>? {
        IOHIDEventSystemClientCreate(kCFAllocatorDefault)
    }

    static func copyServices(_ client: AnyObject) -> CFArray? {
        IOHIDEventSystemClientCopyServices(client)
    }

    static func copyProperty(_ service: AnyObject, _ key: String) -> CFTypeRef? {
        IOHIDServiceClientCopyProperty(service, key as CFString)
    }

    static func copyEvent(_ service: AnyObject, type: Int64) -> Unmanaged<AnyObject>? {
        IOHIDServiceClientCopyEvent(service, type, 0, 0)
    }

    static func eventFloatValue(_ event: AnyObject, field: Int32) -> Double {
        IOHIDEventGetFloatValue(event, field)
    }
}

// MARK: - Private C symbols

@_silgen_name("IOHIDEventSystemClientCreate")
private func IOHIDEventSystemClientCreate(_ allocator: CFAllocator?) -> Unmanaged<AnyObject>?

@_silgen_name("IOHIDEventSystemClientCopyServices")
private func IOHIDEventSystemClientCopyServices(_ client: AnyObject) -> CFArray?

@_silgen_name("IOHIDServiceClientCopyProperty")
private func IOHIDServiceClientCopyProperty(_ service: AnyObject, _ property: CFString) -> CFTypeRef?

@_silgen_name("IOHIDServiceClientCopyEvent")
private func IOHIDServiceClientCopyEvent(
    _ service: AnyObject,
    _ type: Int64,
    _ options: Int32,
    _ timestamp: Int64
) -> Unmanaged<AnyObject>?

@_silgen_name("IOHIDEventGetFloatValue")
private func IOHIDEventGetFloatValue(_ event: AnyObject, _ field: Int32) -> Double
