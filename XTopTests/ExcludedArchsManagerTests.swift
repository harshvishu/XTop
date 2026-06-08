import Foundation
import Testing
@testable import XTop

@Suite("ExcludedArchsManager")
struct ExcludedArchsManagerTests {

    @Test("clearArm64 replaces unscoped exclusions")
    func clearArm64ReplacesExclusions() async throws {
        let projectFile = try makeProjectFile(content: fixtureWithArm64)
        let manager = ExcludedArchsManager(fileManager: .default)

        let result = try await manager.apply(mode: .clearArm64, projectFilePath: projectFile.path())
        let updated = try String(contentsOf: projectFile, encoding: .utf8)

        #expect(result.changedBlocks > 0)
        #expect(updated.localizedStandardContains("EXCLUDED_ARCHS = \"\";"))
        #expect(!updated.localizedStandardContains("EXCLUDED_ARCHS = arm64;"))
        #expect(result.backupPath != nil)
    }

    @Test("setDebugArm64 inserts exclusion when missing")
    func setDebugArm64InsertsMissingEntry() async throws {
        let projectFile = try makeProjectFile(content: fixtureWithoutExcludedArch)
        let manager = ExcludedArchsManager(fileManager: .default)

        _ = try await manager.apply(mode: .setDebugArm64, projectFilePath: projectFile.path())
        let updated = try String(contentsOf: projectFile, encoding: .utf8)

        #expect(updated.localizedStandardContains("name = Debug;"))
        #expect(updated.localizedStandardContains("EXCLUDED_ARCHS = arm64;"))
    }

    @Test("setDebugArm64 updates existing non-arm64 value")
    func setDebugArm64UpdatesValue() async throws {
        let projectFile = try makeProjectFile(content: fixtureDebugNonArm64)
        let manager = ExcludedArchsManager(fileManager: .default)

        _ = try await manager.apply(mode: .setDebugArm64, projectFilePath: projectFile.path())
        let updated = try String(contentsOf: projectFile, encoding: .utf8)

        #expect(updated.localizedStandardContains("EXCLUDED_ARCHS = arm64;"))
        #expect(!updated.localizedStandardContains("EXCLUDED_ARCHS = i386;"))
    }

    @Test("dryRun does not modify file")
    func dryRunDoesNotModifyFile() async throws {
        let projectFile = try makeProjectFile(content: fixtureWithArm64)
        let manager = ExcludedArchsManager(fileManager: .default)

        let before = try String(contentsOf: projectFile, encoding: .utf8)
        let result = try await manager.dryRun(mode: .clearArm64, projectFilePath: projectFile.path())
        let after = try String(contentsOf: projectFile, encoding: .utf8)

        #expect(before == after)
        #expect(result.backupPath == nil)
        #expect(result.message.localizedStandardContains("Dry run only"))
    }

    @Test("No-op mode returns no changes required")
    func noOpReturnsNoChanges() async throws {
        let projectFile = try makeProjectFile(content: fixtureWithoutExcludedArch)
        let manager = ExcludedArchsManager(fileManager: .default)

        let result = try await manager.dryRun(mode: .clearArm64, projectFilePath: projectFile.path())

        #expect(result.changedBlocks == 0)
        #expect(result.message.localizedStandardContains("No changes required"))
    }

    @Test("Missing XCBuildConfiguration section throws")
    func missingSectionThrows() async throws {
        let fileURL = URL.temporaryDirectory.appending(path: "ExcludedArchsManagerTests.\(UUID().uuidString).pbxproj")
        try "// no build config section".write(to: fileURL, atomically: true, encoding: .utf8)
        let manager = ExcludedArchsManager(fileManager: .default)

        await #expect(throws: ExcludedArchsManager.Error.self) {
            _ = try await manager.dryRun(mode: .clearArm64, projectFilePath: fileURL.path())
        }
    }

    private func makeProjectFile(content: String) throws -> URL {
        let fileURL = URL.temporaryDirectory.appending(path: "ExcludedArchsManagerTests.\(UUID().uuidString).pbxproj")
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    private var fixtureWithArm64: String {
        """
/* Begin XCBuildConfiguration section */
	A1 /* Debug */ = {
		isa = XCBuildConfiguration;
		buildSettings = {
			EXCLUDED_ARCHS = arm64;
			SWIFT_VERSION = 6.0;
		};
		name = Debug;
	};
	B1 /* Release */ = {
		isa = XCBuildConfiguration;
		buildSettings = {
			EXCLUDED_ARCHS = arm64;
		};
		name = Release;
	};
/* End XCBuildConfiguration section */
"""
    }

    private var fixtureWithoutExcludedArch: String {
        """
/* Begin XCBuildConfiguration section */
	A1 /* Debug */ = {
		isa = XCBuildConfiguration;
		buildSettings = {
			SWIFT_VERSION = 6.0;
		};
		name = Debug;
	};
	B1 /* Release */ = {
		isa = XCBuildConfiguration;
		buildSettings = {
			SWIFT_VERSION = 6.0;
		};
		name = Release;
	};
/* End XCBuildConfiguration section */
"""
    }

    private var fixtureDebugNonArm64: String {
        """
/* Begin XCBuildConfiguration section */
	A1 /* Debug */ = {
		isa = XCBuildConfiguration;
		buildSettings = {
			EXCLUDED_ARCHS = i386;
			SWIFT_VERSION = 6.0;
		};
		name = Debug;
	};
	B1 /* Release */ = {
		isa = XCBuildConfiguration;
		buildSettings = {
			SWIFT_VERSION = 6.0;
		};
		name = Release;
	};
/* End XCBuildConfiguration section */
"""
    }
}
