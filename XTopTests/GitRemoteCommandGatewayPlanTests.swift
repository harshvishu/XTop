import Foundation
import Testing
@testable import XTop

@Suite("GitRemoteCommandGatewayPlan")
struct GitRemoteCommandGatewayPlanTests {

    @Test("HTTPS profile uses plain git command without GIT_SSH_COMMAND")
    func httpsProfileUsesPlainGit() {
        let profile = GitMonitorAccountProfile(
            displayName: "Work",
            host: "github.com",
            username: "harsh",
            authMode: .httpsToken
        )

        let plan = GitRemoteCommandGateway.plan(
            repositoryPath: "/tmp/repo",
            arguments: ["status"],
            accountProfile: profile
        )

        #expect(plan.command == "git")
        #expect(plan.arguments == ["-C", "/tmp/repo", "status"])
    }

    @Test("No profile defaults to plain git command")
    func noProfileUsesPlainGit() {
        let plan = GitRemoteCommandGateway.plan(
            repositoryPath: "/tmp/repo",
            arguments: ["fetch"],
            accountProfile: nil
        )

        #expect(plan.command == "git")
        #expect(plan.arguments == ["-C", "/tmp/repo", "fetch"])
    }

    @Test("SSH profile with key path scopes GIT_SSH_COMMAND per command")
    func sshProfileScopesIdentitySwitch() {
        let profile = GitMonitorAccountProfile(
            displayName: "Personal",
            host: "github.com",
            username: "harsh",
            authMode: .sshKey,
            sshPrivateKeyPath: "/Users/harsh/.ssh/id_ed25519"
        )

        let plan = GitRemoteCommandGateway.plan(
            repositoryPath: "/tmp/repo",
            arguments: ["fetch"],
            accountProfile: profile
        )

        #expect(plan.command == "sh")
        #expect(plan.arguments.count == 2)
        #expect(plan.arguments[0] == "-c")
        let shell = plan.arguments[1]
        #expect(shell.contains("GIT_SSH_COMMAND="))
        #expect(shell.contains("/Users/harsh/.ssh/id_ed25519"))
        #expect(shell.contains("IdentitiesOnly=yes"))
        #expect(shell.contains("git -C "))
        #expect(shell.contains("fetch"))
    }

    @Test("SSH profile without key falls back to plain git")
    func sshProfileWithoutKeyFallsBack() {
        let profile = GitMonitorAccountProfile(
            displayName: "Broken",
            host: "github.com",
            username: "harsh",
            authMode: .sshKey,
            sshPrivateKeyPath: ""
        )

        let plan = GitRemoteCommandGateway.plan(
            repositoryPath: "/tmp/repo",
            arguments: ["fetch"],
            accountProfile: profile
        )

        #expect(plan.command == "git")
    }
}
