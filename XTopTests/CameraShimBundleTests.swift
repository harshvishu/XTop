import Foundation
import Testing
@testable import XTop

@Suite("Camera shim bundle")
struct CameraShimBundleTests {
    @Test func shimResourceIsBundledInAppBundle() throws {
        let url = try CameraShimBundle.resolvedURL()
        #expect(FileManager.default.isReadableFile(atPath: url.path))
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs[.size] as? Int) ?? 0
        #expect(size > 0)
    }

    @Test func shimIsUniversalArm64AndX8664() async throws {
        let url = try CameraShimBundle.resolvedURL()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["lipo", "-info", url.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        #expect(output.contains("arm64"), "lipo output missing arm64 slice: \(output)")
        #expect(output.contains("x86_64"), "lipo output missing x86_64 slice: \(output)")
    }
}
