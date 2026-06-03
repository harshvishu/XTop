import Foundation

actor GitRemoteCommandGateway {
    private let runner: CommandRunner

    nonisolated init(runner: CommandRunner) {
        self.runner = runner
    }

    func runGitCommand(
        repositoryPath: String,
        arguments: [String],
        accountProfile: GitMonitorAccountProfile?
    ) async -> CommandResult {
        let plan = Self.plan(
            repositoryPath: repositoryPath,
            arguments: arguments,
            accountProfile: accountProfile
        )
        return await runner.run(
            command: plan.command,
            arguments: plan.arguments,
            workingDirectory: repositoryPath,
            environment: Self.unattendedGitEnvironment
        )
    }

    /// Environment overrides applied to every git invocation so credential
    /// resolution behaves like VS Code / Xcode (which shell out to git and let
    /// the system credential helper + ssh-agent handle auth), while keeping
    /// background polling non-interactive.
    ///
    /// - `GIT_TERMINAL_PROMPT=0` — never block waiting for a TTY username/password.
    /// - `GIT_ASKPASS=/usr/bin/true` — suppress GUI askpass popups; missing
    ///   credentials surface as an auth failure instead of a modal prompt.
    /// - `SSH_ASKPASS=/usr/bin/true` + `SSH_ASKPASS_REQUIRE=never` — same for SSH.
    ///
    /// `PATH`, `HOME`, and `SSH_AUTH_SOCK` are inherited from the parent
    /// process so `git-credential-osxkeychain`, `~/.gitconfig`, `~/.ssh/config`,
    /// and `ssh-agent` continue to resolve correctly.
    nonisolated static let unattendedGitEnvironment: [String: String] = [
        "GIT_TERMINAL_PROMPT": "0",
        "GIT_ASKPASS": "/usr/bin/true",
        "SSH_ASKPASS": "/usr/bin/true",
        "SSH_ASKPASS_REQUIRE": "never"
    ]

    struct CommandPlan: Equatable, Sendable {
        let command: String
        let arguments: [String]
    }

    nonisolated static func plan(
        repositoryPath: String,
        arguments: [String],
        accountProfile: GitMonitorAccountProfile?
    ) -> CommandPlan {
        if let accountProfile, accountProfile.authMode == .sshKey,
           let keyPath = accountProfile.sshPrivateKeyPath,
           !keyPath.isEmpty {
            let sshCommand = "ssh -i \(shellEscape(keyPath)) -o IdentitiesOnly=yes"
            let gitCommand = "GIT_SSH_COMMAND=\(shellEscape(sshCommand)) git -C \(shellEscape(repositoryPath)) \(arguments.map(shellEscape).joined(separator: " "))"
            return CommandPlan(command: "sh", arguments: ["-c", gitCommand])
        }

        return CommandPlan(
            command: "git",
            arguments: ["-C", repositoryPath] + arguments
        )
    }

    private nonisolated static func shellEscape(_ input: String) -> String {
        "'" + input.replacing("'", with: "'\\''") + "'"
    }

    private func shellEscape(_ input: String) -> String {
        Self.shellEscape(input)
    }
}
