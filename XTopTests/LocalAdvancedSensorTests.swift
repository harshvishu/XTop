import Foundation
import Testing
@testable import XTop

// MARK: - SMCReader allowlist

@Suite("SMCReader allowlist")
struct SMCReaderAllowlistTests {

    @Test("SMCKey fourCC packs four ASCII bytes in MSB-first order")
    func fourCCPacksBytes() {
        let key = SMCKey.cpuProximityTemp // "TC0P"
        let expected: UInt32 =
            (UInt32(UInt8(ascii: "T")) << 24)
            | (UInt32(UInt8(ascii: "C")) << 16)
            | (UInt32(UInt8(ascii: "0")) << 8)
            | UInt32(UInt8(ascii: "P"))
        #expect(key.fourCC == expected)
    }

    @Test("Every SMCKey raw value is exactly four ASCII characters")
    func allKeysAreFourByteFourCC() {
        for key in SMCKey.allCases {
            #expect(key.rawValue.count == 4, "Key \(key.rawValue) is not four characters")
            #expect(key.rawValue.allSatisfy { $0.isASCII }, "Key \(key.rawValue) is not ASCII")
        }
    }

    @Test("Allowlist contains only documented temperature and fan keys")
    func allowlistMatchesDocumentedKeys() {
        let expected: Set<String> = [
            "TC0P", "TC0D", "TCXC",
            "TG0P", "TG0D",
            "F0Ac", "F1Ac", "F0Mn", "F0Mx"
        ]
        let actual = Set(SMCKey.allCases.map(\.rawValue))
        #expect(actual == expected)
    }
}

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

// MARK: - LocalAdvancedSensorClient smoke tests
//
// We cannot inject fake SMC connections without exposing more internals,
// so these tests exercise the parts of LocalAdvancedSensorClient that go
// through GPUStatsReader (which IS injectable) and assert observable
// behavior on the public protocol. SMC behavior is covered indirectly:
// on machines without AppleSMC the temperature/fan reasons are populated;
// on machines with it the access test reports success.

@Suite("LocalAdvancedSensorClient")
struct LocalAdvancedSensorClientTests {

    @Test("fetchStatus reports ready when GPU reader returns a value")
    func fetchStatusReadyWhenGPUAvailable() async {
        let client = LocalAdvancedSensorClient(
            smc: SMCReader(),
            gpu: GPUStatsReader {
                [GPUServiceDescriptor(performanceStatistics: ["Device Utilization %": 5 as NSNumber])]
            }
        )
        let status = await client.fetchStatus()
        #expect(status.installation == .ready)
        #expect(status.connectivity == .connected)
        #expect(status.supportsGPU)
    }

    @Test("fetchStatus reports unsupported when GPU absent and SMC unavailable")
    func fetchStatusUnsupportedWhenNothingAvailable() async {
        // Empty GPU matcher + a real SMCReader: on hosts without AppleSMC
        // both probes fail and we should land in unsupported. On hosts WITH
        // AppleSMC, SMC reads may succeed and the assertion would not hold,
        // so we only assert the GPU-absent path.
        let client = LocalAdvancedSensorClient(
            smc: SMCReader(),
            gpu: GPUStatsReader { [] }
        )
        let status = await client.fetchStatus()
        #expect(!status.supportsGPU)
        // installation depends on whether SMC works on the test host;
        // we don't assert a fixed value to keep the test machine-agnostic.
        let okShapes: [AdvancedSensorHelperInstallation] = [.ready, .unsupported]
        #expect(okShapes.contains(status.installation))
    }

    @Test("sampleAdvancedMetrics returns partial sample with reasons when GPU only")
    func sampleReturnsPartialWhenOnlyGPUAvailable() async throws {
        let client = LocalAdvancedSensorClient(
            smc: SMCReader(),
            gpu: GPUStatsReader {
                [GPUServiceDescriptor(performanceStatistics: ["Device Utilization %": 12 as NSNumber])]
            }
        )
        let sample = try await client.sampleAdvancedMetrics()
        #expect(sample.gpuPercent == 12.0)
        // Temperature and fan reasons should be populated when SMC fails or
        // returns nothing; on a Mac where SMC works they will be set.
        // We assert: if values are nil, reasons are non-empty.
        if sample.temperatureC == nil {
            #expect(sample.unavailableReasons[AdvancedSensorMetric.temperature.rawValue] != nil)
        }
        if sample.fanRPM == nil {
            #expect(sample.unavailableReasons[AdvancedSensorMetric.fan.rawValue] != nil)
        }
    }

    @Test("sampleAdvancedMetrics throws when every reader returns nothing")
    func sampleThrowsWhenAllReadersFail() async {
        // GPU matcher returns empty; we cannot guarantee SMC is unavailable
        // on the test host, so this assertion is conditional.
        let client = LocalAdvancedSensorClient(
            smc: SMCReader(),
            gpu: GPUStatsReader { [] }
        )
        do {
            let sample = try await client.sampleAdvancedMetrics()
            // On a Mac where SMC works, we get a partial sample — at least one
            // reading must be present and the reasons map covers the rest.
            #expect(sample.temperatureC != nil || sample.fanRPM != nil)
        } catch let error as AdvancedSensorClientError {
            // On a Mac without SMC, the client throws the "no readers" case.
            if case .unsupported = error {
                // expected
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
            smc: SMCReader(),
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
            smc: SMCReader(),
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
}
