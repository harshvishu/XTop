import Foundation

typealias CommandScopeValidator = @Sendable (
    String,
    [String],
    String
) -> Bool

actor CommandRunner {
    private let allowedCommands: Set<String>

    init(allowedCommands: Set<String> = ["git", "xcodebuild", "pod", "rm", "find", "security", "osascript", "defaults", "du", "vm_stat", "sh", "xcrun"]) {
        self.allowedCommands = allowedCommands
    }

    func isCommandAvailable(_ command: String) -> Bool {
        let process = Process()
        let nullOutput = FileHandle.nullDevice
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["which", command]
        process.standardOutput = nullOutput
        process.standardError = nullOutput

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    func run(
        command: String,
        arguments: [String],
        workingDirectory: String,
        environment: [String: String]? = nil,
        validateScope: CommandScopeValidator? = nil
    ) -> CommandResult {
        let startedAt = Date.now

        guard allowedCommands.contains(command) else {
            return CommandResult(
                command: command,
                arguments: arguments,
                workingDirectory: workingDirectory,
                exitStatus: 127,
                stdout: "",
                stderr: "Command not allowed by safety policy.",
                startedAt: startedAt,
                endedAt: .now
            )
        }

        if let validateScope, !validateScope(command, arguments, workingDirectory) {
            return CommandResult(
                command: command,
                arguments: arguments,
                workingDirectory: workingDirectory,
                exitStatus: 126,
                stdout: "",
                stderr: "Scope validation failed for command.",
                startedAt: startedAt,
                endedAt: .now
            )
        }

        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        if let environment {
            var merged = ProcessInfo.processInfo.environment
            for (key, value) in environment {
                merged[key] = value
            }
            process.environment = merged
        }

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return CommandResult(
                command: command,
                arguments: arguments,
                workingDirectory: workingDirectory,
                exitStatus: 1,
                stdout: "",
                stderr: "Failed to run process: \(error.localizedDescription)",
                startedAt: startedAt,
                endedAt: .now
            )
        }

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        return CommandResult(
            command: command,
            arguments: arguments,
            workingDirectory: workingDirectory,
            exitStatus: process.terminationStatus,
            stdout: stdout,
            stderr: stderr,
            startedAt: startedAt,
            endedAt: .now
        )
    }
}
