import Foundation
import Testing
@testable import XTop

// MARK: - GPUStatsReader

@Suite("GPUStatsReader")
struct GPUStatsReaderTests {

    @Test("Returns utilization when accelerator publishes Device Utilization %")
    func returnsDeviceUtilization() throws {
        let reader = GPUStatsReader {
            [GPUServiceDescriptor(performanceStatistics: ["Device Utilization %": 42 as NSNumber])]
        }
        let value = try reader.readUtilizationPercent()
        #expect(value == 42.0)
    }

    @Test("Falls back to alternate utilization key when primary is missing")
    func fallsBackToAlternateKey() throws {
        let reader = GPUStatsReader {
            [GPUServiceDescriptor(performanceStatistics: ["Renderer Utilization %": 17 as NSNumber])]
        }
        let value = try reader.readUtilizationPercent()
        #expect(value == 17.0)
    }

    @Test("Throws when no accelerator is available")
    func throwsWhenNoAccelerator() {
        let reader = GPUStatsReader { [] }
        #expect(throws: GPUStatsReaderError.noAcceleratorAvailable) {
            try reader.readUtilizationPercent()
        }
    }

    @Test("Throws when accelerators publish no recognized key")
    func throwsWhenNoRecognizedKey() {
        let reader = GPUStatsReader {
            [GPUServiceDescriptor(performanceStatistics: ["Unknown Key": 99 as NSNumber])]
        }
        #expect(throws: GPUStatsReaderError.noAcceleratorAvailable) {
            try reader.readUtilizationPercent()
        }
    }

    @Test("Clamps utilization values above 100")
    func clampsAboveHundred() throws {
        let reader = GPUStatsReader {
            [GPUServiceDescriptor(performanceStatistics: ["Device Utilization %": 250 as NSNumber])]
        }
        let value = try reader.readUtilizationPercent()
        #expect(value == 100.0)
    }

    @Test("Walks descriptors in order until a usable value is found")
    func walksDescriptorsInOrder() throws {
        let reader = GPUStatsReader {
            [
                GPUServiceDescriptor(performanceStatistics: [:]),
                GPUServiceDescriptor(performanceStatistics: ["GPU Core Utilization": 30 as NSNumber])
            ]
        }
        let value = try reader.readUtilizationPercent()
        #expect(value == 30.0)
    }
}

// MARK: - IOHIDSensorReader smoke tests
//
// The IOHID SPI does not allow us to inject fake services without leaking
// CoreFoundation internals into the test target, so these tests probe the
// live host. On Apple Silicon Macs the temperature path should return at
// least one usable reading; on hosts without the SPI it should throw
// .clientUnavailable. Either outcome is acceptable.

@Suite("IOHIDSensorReader")
struct IOHIDSensorReaderTests {

    @Test("Temperature collection returns finite values or throws cleanly")
    func temperatureReadingsAreFiniteOrError() throws {
        let reader = IOHIDSensorReader()
        do {
            let readings = try reader.collectTemperatureReadings()
            for reading in readings {
                #expect(reading.value > 0)
                #expect(reading.value < 150)
            }
        } catch IOHIDSensorReaderError.clientUnavailable {
            // Acceptable on hosts where the SPI is not present.
        } catch IOHIDSensorReaderError.noSensorsAvailable {
            // Acceptable when the SPI exists but exposes nothing.
        }
    }

    @Test("Fan capability probe returns a boolean without throwing")
    func fanCapabilityProbeIsSafe() {
        let reader = IOHIDSensorReader()
        _ = reader.hostHasFanHardware()
    }
}

// MARK: - LocalAdvancedSensorClient smoke tests

@Suite("LocalAdvancedSensorClient")
struct LocalAdvancedSensorClientTests {

    @Test("fetchStatus reports ready when GPU reader returns a value")
    func fetchStatusReadyWhenGPUAvailable() async {
        let client = LocalAdvancedSensorClient(
            hid: IOHIDSensorReader(),
            gpu: GPUStatsReader {
                [GPUServiceDescriptor(performanceStatistics: ["Device Utilization %": 5 as NSNumber])]
            }
        )
        let status = await client.fetchStatus()
        #expect(status.installation == .ready)
        #expect(status.connectivity == .connected)
        #expect(status.supportsGPU)
    }

    @Test("fetchStatus stays in a known installation state when GPU absent")
    func fetchStatusKnownStateWhenGPUAbsent() async {
        // With no GPU and depending on host HID availability the client may
        // land in either .ready (HID temperature present) or .unsupported
        // (HID SPI missing). Both are valid.
        let client = LocalAdvancedSensorClient(
            hid: IOHIDSensorReader(),
            gpu: GPUStatsReader { [] }
        )
        let status = await client.fetchStatus()
        #expect(!status.supportsGPU)
        let okShapes: [AdvancedSensorHelperInstallation] = [.ready, .unsupported]
        #expect(okShapes.contains(status.installation))
    }

    @Test("sampleAdvancedMetrics returns partial sample with reasons when GPU only")
    func sampleReturnsPartialWhenOnlyGPUAvailable() async throws {
        let client = LocalAdvancedSensorClient(
            hid: IOHIDSensorReader(),
            gpu: GPUStatsReader {
                [GPUServiceDescriptor(performanceStatistics: ["Device Utilization %": 12 as NSNumber])]
            }
        )
        let sample = try await client.sampleAdvancedMetrics()
        #expect(sample.gpuPercent == 12.0)
        // Missing values must carry a human-readable reason.
        if sample.temperatureC == nil {
            #expect(sample.unavailableReasons[AdvancedSensorMetric.temperature.rawValue] != nil)
        }
        if sample.fanRPM == nil {
            #expect(sample.unavailableReasons[AdvancedSensorMetric.fan.rawValue] != nil)
        }
    }

    @Test("sampleAdvancedMetrics throws only when every reader returns nothing")
    func sampleThrowsWhenAllReadersFail() async {
        let client = LocalAdvancedSensorClient(
            hid: IOHIDSensorReader(),
            gpu: GPUStatsReader { [] }
        )
        do {
            let sample = try await client.sampleAdvancedMetrics()
            // On hosts where HID temperature works, we get a partial sample.
            #expect(sample.temperatureC != nil || sample.fanRPM != nil)
        } catch let error as AdvancedSensorClientError {
            if case .unsupported = error {
                // expected on hosts without any sensor source
            } else {
                Issue.record("Unexpected error case: \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("performAccessTest summarizes available metrics")
    func accessTestSummarizesAvailableMetrics() async {
        let client = LocalAdvancedSensorClient(
            hid: IOHIDSensorReader(),
            gpu: GPUStatsReader {
                [GPUServiceDescriptor(performanceStatistics: ["Device Utilization %": 8 as NSNumber])]
            }
        )
        let result = await client.performAccessTest()
        #expect(result.succeeded)
        #expect(result.summary.contains("GPU"))
    }

    @Test("startSetup mirrors fetchStatus when GPU is available")
    func startSetupReadyWhenGPUAvailable() async {
        let client = LocalAdvancedSensorClient(
            hid: IOHIDSensorReader(),
            gpu: GPUStatsReader {
                [GPUServiceDescriptor(performanceStatistics: ["Device Utilization %": 1 as NSNumber])]
            }
        )
        let outcome = await client.startSetup()
        if case .ready = outcome {
            // expected
        } else {
            Issue.record("Expected .ready, got \(outcome)")
        }
    }

    @Test("Fan reason distinguishes no-hardware from read-failure")
    func fanReasonReflectsHostHardware() async throws {
        // Use a real IOHID reader to query the host capability so the test
        // adapts to whatever Mac it runs on instead of asserting one fixed
        // string. The contract: when fanRPM is nil the reason MUST be the
        // no-hardware string on a host that has no fan service registered,
        // and MUST be a read-failure string on a host that does.
        let hid = IOHIDSensorReader()
        let client = LocalAdvancedSensorClient(
            hid: hid,
            gpu: GPUStatsReader {
                [GPUServiceDescriptor(performanceStatistics: ["Device Utilization %": 1 as NSNumber])]
            }
        )
        let sample = try await client.sampleAdvancedMetrics()
        guard sample.fanRPM == nil else { return } // host with working fans
        let reason = sample.unavailableReasons[AdvancedSensorMetric.fan.rawValue] ?? ""
        if hid.hostHasFanHardware() {
            #expect(reason.localizedCaseInsensitiveContains("readable")
                || reason.localizedCaseInsensitiveContains("failed"))
        } else {
            #expect(reason.localizedCaseInsensitiveContains("no fan hardware"))
        }
    }
}
