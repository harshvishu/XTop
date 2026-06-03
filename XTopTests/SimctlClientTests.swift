import Foundation
import Testing
@testable import XTop

@Suite("SimctlClient JSON decoding")
struct SimctlClientDecodeTests {
    @Test func decodesBootedDevicesPayload() throws {
        let json = """
        {
          "devices": {
            "com.apple.CoreSimulator.SimRuntime.iOS-26-0": [
              {
                "udid": "AAA",
                "name": "iPhone 17 Pro",
                "state": "Booted",
                "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro"
              },
              {
                "udid": "BBB",
                "name": "iPhone 17",
                "state": "Shutdown",
                "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-17"
              }
            ]
          }
        }
        """

        let payload = try SimctlClient.decode(json, as: SimctlClient.DevicesPayload.self)
        let runtime = try #require(payload.devices["com.apple.CoreSimulator.SimRuntime.iOS-26-0"])
        #expect(runtime.count == 2)
        #expect(runtime[0].udid == "AAA")
        #expect(runtime[0].state == "Booted")
    }

    @Test func runtimeDisplayNameStripsPrefixAndFormatsVersion() {
        let label = SimulatorDiscoveryService.displayName(
            forRuntime: "com.apple.CoreSimulator.SimRuntime.iOS-26-0"
        )
        #expect(label == "iOS 26.0")
    }
}
