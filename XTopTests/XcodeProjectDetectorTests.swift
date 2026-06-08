import Foundation
import Testing
@testable import XTop

@Suite("XcodeProjectDetector")
struct XcodeProjectDetectorTests {

    @Test("Detects xcodeproj with highest priority")
    func detectsXcodeproj() async throws {
        let root = try makeTempDirectory()
        let detector = XcodeProjectDetector(fileManager: .default)

        let xcodeproj = root.appending(path: "App.xcodeproj")
        let workspace = root.appending(path: "App.xcworkspace")
        try FileManager.default.createDirectory(at: xcodeproj, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)

        let detected = await detector.detectProjectType(at: root.path())

        #expect(detected?.type == .xcodeproj)
        #expect(detected?.projectFilePath == xcodeproj.path())
    }

    @Test("Detects xcworkspace when xcodeproj is absent")
    func detectsWorkspace() async throws {
        let root = try makeTempDirectory()
        let detector = XcodeProjectDetector(fileManager: .default)

        let workspace = root.appending(path: "App.xcworkspace")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)

        let detected = await detector.detectProjectType(at: root.path())

        #expect(detected?.type == .xcworkspace)
        #expect(detected?.projectFilePath == workspace.path())
    }

    @Test("Detects swift package when xcode bundles are absent")
    func detectsSwiftPackage() async throws {
        let root = try makeTempDirectory()
        let detector = XcodeProjectDetector(fileManager: .default)

        let packageSwift = root.appending(path: "Package.swift")
        try "// swift-tools-version: 6.0".write(to: packageSwift, atomically: true, encoding: .utf8)

        let detected = await detector.detectProjectType(at: root.path())

        #expect(detected?.type == .swiftPackage)
        #expect(detected?.projectFilePath == packageSwift.path())
    }

    @Test("Returns nil when no supported project file exists")
    func returnsNilWhenNoProjectFound() async throws {
        let root = try makeTempDirectory()
        let detector = XcodeProjectDetector(fileManager: .default)

        let detected = await detector.detectProjectType(at: root.path())

        #expect(detected == nil)
    }

    private func makeTempDirectory() throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "XcodeProjectDetectorTests.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
