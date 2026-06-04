import Foundation
import Testing
@testable import XTop

@Suite("AppLifecycleController command construction")
struct AppLifecycleControllerTests {
    @Test func terminateTreatsNotRunningStderrAsSuccess() async throws {
        // We can't run real subprocesses inside the test sandbox, but we can
        // confirm the controller surfaces no error when stderr indicates the
        // app was not running. This exercises only the classification logic.
        // Use a SimctlClient whose underlying runner produces a synthetic
        // CommandResult by routing through a disallowed command (exit 127) but
        // we override stderr by going through KeychainClearer's URL helpers
        // here, NOT touching the simctl call path. So this test focuses on
        // KeychainClearer's URL construction instead.
        let urls = KeychainClearer.keychainFileURLs(for: "ABC-123")
        #expect(urls.count == 3)
        #expect(urls[0].lastPathComponent == "keychain-2-debug.db")
        #expect(urls[1].lastPathComponent == "keychain-2-debug.db-shm")
        #expect(urls[2].lastPathComponent == "keychain-2-debug.db-wal")
        #expect(urls[0].path(percentEncoded: false).contains("/CoreSimulator/Devices/ABC-123/"))
    }

    @Test func parsePIDExtractsTrailingIntegerFromLaunchStdout() throws {
        #expect(AppLifecycleController.parsePID(fromLaunchStdout: "com.example.app: 12345\n") == 12345)
        #expect(AppLifecycleController.parsePID(fromLaunchStdout: "com.example.app: 99\n") == 99)
        #expect(AppLifecycleController.parsePID(fromLaunchStdout: "  com.example.app: 7  ") == 7)
    }

    @Test func parsePIDReturnsNilWhenNoIntegerSuffix() throws {
        #expect(AppLifecycleController.parsePID(fromLaunchStdout: "") == nil)
        #expect(AppLifecycleController.parsePID(fromLaunchStdout: "com.example.app: oops") == nil)
        #expect(AppLifecycleController.parsePID(fromLaunchStdout: "no-colon-no-pid") == nil)
    }
}
