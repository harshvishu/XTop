import Foundation
import Testing
@testable import XTop

@Suite("GitMonitorSyncClassification")
struct GitMonitorSyncClassificationTests {

    @Test("Timeout stderr classifies as timeout")
    func timeoutStderrClassifiesAsTimeout() {
        let state = DefaultGitMonitorService.classifyRemoteFailure("fatal: Operation timed out after 20s")
        #expect(state == .timeout)
    }

    @Test("Permission denied stderr classifies as authRequired")
    func permissionDeniedClassifiesAsAuthRequired() {
        let state = DefaultGitMonitorService.classifyRemoteFailure("git@github.com: Permission denied (publickey).")
        #expect(state == .authRequired)
    }

    @Test("Authentication stderr classifies as authRequired")
    func authenticationClassifiesAsAuthRequired() {
        let state = DefaultGitMonitorService.classifyRemoteFailure("remote: Invalid username or password. Authentication failed.")
        #expect(state == .authRequired)
    }

    @Test("Could not read from remote stderr classifies as authRequired")
    func couldNotReadFromRemoteClassifiesAsAuthRequired() {
        let state = DefaultGitMonitorService.classifyRemoteFailure("Could not read from remote repository.")
        #expect(state == .authRequired)
    }

    @Test("Generic stderr classifies as failed")
    func genericStderrClassifiesAsFailed() {
        let state = DefaultGitMonitorService.classifyRemoteFailure("fatal: unable to access 'https://x/': SSL certificate problem")
        #expect(state == .failed)
    }
}
