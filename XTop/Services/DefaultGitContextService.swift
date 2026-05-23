import Foundation

actor DefaultGitContextService: GitContextService {
    private let runner: CommandRunner

    init(runner: CommandRunner = CommandRunner()) {
        self.runner = runner
    }

    func collectGitContext(
        for projectResolution: FocusedProjectResolution
    ) async -> GitContextSnapshot {
        guard let projectPath = projectResolution.projectPath else {
            return GitContextSnapshot(
                projectPath: nil,
                repositoryRoot: nil,
                branch: nil,
                worktreePath: nil,
                worktrees: [],
                note: "No focused project detected."
            )
        }

        let directory = (projectPath as NSString).deletingLastPathComponent
        let repoResult = await runner.run(
            command: "git",
            arguments: ["-C", directory, "rev-parse", "--show-toplevel"],
            workingDirectory: directory
        )

        guard repoResult.exitStatus == 0 else {
            return GitContextSnapshot(
                projectPath: projectPath,
                repositoryRoot: nil,
                branch: nil,
                worktreePath: nil,
                worktrees: [],
                note: "Focused project is not in a Git repository."
            )
        }

        let repoRoot = repoResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let branchResult = await runner.run(
            command: "git",
            arguments: ["-C", repoRoot, "branch", "--show-current"],
            workingDirectory: repoRoot
        )
        let branch = branchResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)

        let currentWorktreeResult = await runner.run(
            command: "git",
            arguments: ["-C", repoRoot, "rev-parse", "--show-prefix"],
            workingDirectory: repoRoot
        )
        let worktreePath = currentWorktreeResult.exitStatus == 0 ? directory : nil
        let worktrees = await parseWorktrees(
            repoRoot: repoRoot,
            currentPath: directory
        )

        return GitContextSnapshot(
            projectPath: projectPath,
            repositoryRoot: repoRoot,
            branch: branch.isEmpty ? nil : branch,
            worktreePath: worktreePath,
            worktrees: worktrees,
            note: worktrees.isEmpty ? "No additional worktrees detected." : "Worktrees loaded."
        )
    }

    private func parseWorktrees(
        repoRoot: String,
        currentPath: String
    ) async -> [GitWorktreeSummary] {
        let result = await runner.run(
            command: "git",
            arguments: ["-C", repoRoot, "worktree", "list", "--porcelain"],
            workingDirectory: repoRoot
        )
        guard result.exitStatus == 0 else { return [] }

        var currentPathValue: String?
        var currentBranchValue: String?
        var entries: [GitWorktreeSummary] = []

        for line in result.stdout.split(separator: "\n") {
            let text = String(line)
            if text.hasPrefix("worktree ") {
                if let path = currentPathValue {
                    entries.append(
                        GitWorktreeSummary(
                            path: path,
                            branch: currentBranchValue ?? "detached",
                            isCurrent: path == currentPath
                        )
                    )
                }
                currentPathValue = text.replacingOccurrences(of: "worktree ", with: "")
                currentBranchValue = nil
            } else if text.hasPrefix("branch refs/heads/") {
                currentBranchValue = text.replacingOccurrences(of: "branch refs/heads/", with: "")
            }
        }

        if let path = currentPathValue {
            entries.append(
                GitWorktreeSummary(
                    path: path,
                    branch: currentBranchValue ?? "detached",
                    isCurrent: path == currentPath
                )
            )
        }

        return entries
    }
}
