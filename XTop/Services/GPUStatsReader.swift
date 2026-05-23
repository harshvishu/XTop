import Foundation
import IOKit

// MARK: - Public Types

/// Errors surfaced by ``GPUStatsReader``.
enum GPUStatsReaderError: Error, Sendable, Equatable {
    /// No IOAccelerator service published a usable `PerformanceStatistics`
    /// dictionary on this host.
    case noAcceleratorAvailable
}

// MARK: - GPUStatsReader

/// Reads GPU utilization from the first IOKit accelerator that publishes a
/// `PerformanceStatistics` dictionary.
///
/// The reader is intentionally narrow: it returns one number (0–100% GPU
/// utilization). Power, memory, and bandwidth keys are deliberately out of
/// scope for the first implementation — they vary heavily by GPU vendor
/// and would clutter the dashboard.
///
/// On Apple Silicon there is normally one accelerator; on Intel Macs we
/// pick the first match, which is typically the discrete GPU when one is
/// present and otherwise the integrated GPU. Multi-GPU aggregation is
/// deferred until requested.
struct GPUStatsReader: Sendable {

    /// Optional override for testability. Producing an alternate matching
    /// iterator from a stub lets tests cover the "no accelerator" path
    /// without touching real IOKit.
    typealias ServiceMatcher = @Sendable () -> [GPUServiceDescriptor]

    private let matcher: ServiceMatcher

    init(matcher: @escaping ServiceMatcher = GPUStatsReader.defaultMatcher) {
        self.matcher = matcher
    }

    /// Read the current GPU utilization in percent (0–100), or throw
    /// ``GPUStatsReaderError/noAcceleratorAvailable`` when no accelerator
    /// publishes statistics.
    func readUtilizationPercent() throws -> Double {
        let descriptors = matcher()
        for descriptor in descriptors {
            if let value = utilization(from: descriptor.performanceStatistics) {
                return value
            }
        }
        throw GPUStatsReaderError.noAcceleratorAvailable
    }

    // MARK: Dictionary parsing

    /// Recognized utilization keys, in priority order. IOAccelerator key
    /// naming differs across drivers (Apple Silicon, AMD, Intel UHD), so
    /// the reader tries each.
    private static let utilizationKeys: [String] = [
        "Device Utilization %",
        "GPU Core Utilization",
        "Renderer Utilization %",
        "GPU Utilization"
    ]

    private func utilization(from stats: [String: Any]) -> Double? {
        for key in GPUStatsReader.utilizationKeys {
            guard let raw = stats[key] else { continue }
            if let number = raw as? NSNumber {
                let value = number.doubleValue
                if value >= 0 {
                    return min(value, 100.0)
                }
            }
        }
        return nil
    }
}

// MARK: - Service descriptors

/// A lightweight snapshot of a single IOAccelerator's published
/// performance dictionary. Owning a value type instead of a raw
/// `io_registry_entry_t` lets the reader stay `Sendable` and lets tests
/// fabricate descriptors without IOKit.
struct GPUServiceDescriptor: Sendable {
    let performanceStatistics: [String: Any]

    init(performanceStatistics: [String: Any]) {
        self.performanceStatistics = performanceStatistics
    }
}

extension GPUStatsReader {

    /// Default matcher: iterate live IOAccelerator services and copy their
    /// `PerformanceStatistics` dictionaries into value-type descriptors.
    static let defaultMatcher: ServiceMatcher = {
        var descriptors: [GPUServiceDescriptor] = []

        var iterator: io_iterator_t = 0
        let matchResult = IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOAccelerator"),
            &iterator
        )
        guard matchResult == kIOReturnSuccess else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }

            var unmanagedStats: Unmanaged<CFMutableDictionary>?
            let statsResult = IORegistryEntryCreateCFProperty(
                service,
                "PerformanceStatistics" as CFString,
                kCFAllocatorDefault,
                0
            )
            guard let cfValue = statsResult?.takeRetainedValue(),
                  let dict = cfValue as? [String: Any] else {
                _ = unmanagedStats
                continue
            }
            descriptors.append(GPUServiceDescriptor(performanceStatistics: dict))
        }

        return descriptors
    }
}
