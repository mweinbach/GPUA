// Ported from: crates/util/src/shell_builder.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Foundation

/// ShellBuilder is used to turn a user-requested task into a
/// program that can be executed by the shell.
public struct ShellBuilder: Sendable {
    /// The shell to run
    private var program: String
    private var args: [String]
    private var interactive: Bool
    /// Whether to redirect stdin to /dev/null for the spawned command as a subshell.
    private var redirectStdin: Bool
    private var kind: ShellKind

    /// Create a new ShellBuilder as configured.
    public init(shell: Shell, isWindows: Bool) {
        let (prog, initialArgs) = shell.programAndArgs()
        self.program = prog
        self.args = initialArgs
        self.interactive = true
        self.kind = ShellKind(program: prog, isWindows: isWindows)
        self.redirectStdin = false
    }

    public func nonInteractive() -> Self {
        var copy = self
        copy.interactive = false
        return copy
    }

    /// Returns the label to show in the terminal tab
    public func commandLabel(_ commandToUseInLabel: String) -> String {
        if commandToUseInLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return program
        } else {
            switch kind {
            case .powerShell, .pwsh:
                return "\(program) -C '\(commandToUseInLabel)'"
            case .cmd:
                return "\(program) /C \"\(commandToUseInLabel)\""
            case .posix, .nushell, .fish, .csh, .tcsh, .rc, .xonsh, .elvish:
                let interactivity = interactive ? "-i " : ""
                return "\(program) \(interactivity)-c '\(commandToUseInLabel)'"
            }
        }
    }

    public func redirectStdinToDevNull() -> Self {
        var copy = self
        copy.redirectStdin = true
        return copy
    }

    /// Returns the program and arguments to run this task in a shell.
    public func build(
        taskCommand: String?,
        taskArgs: [String]
    ) -> (program: String, args: [String]) {
        var resultArgs = self.args
        if let taskCommand = taskCommand {
            let taskCmd: String
            if !taskArgs.isEmpty {
                taskCmd = kind.tryQuotePrefixAware(taskCommand) ?? taskCommand
            } else {
                taskCmd = taskCommand
            }

            var combinedCommand = taskArgs.reduce(taskCmd) { command, arg in
                var cmd = command
                cmd.append(" ")
                let shellVariable = kind.toShellVariable(arg)
                let quoted = kind.tryQuote(shellVariable) ?? shellVariable
                cmd.append(quoted)
                return cmd
            }

            if redirectStdin {
                switch kind {
                case .fish:
                    combinedCommand = "begin; \(combinedCommand); end </dev/null"
                case .posix, .nushell, .csh, .tcsh, .rc, .xonsh, .elvish:
                    combinedCommand = "(\(combinedCommand)) </dev/null"
                case .powerShell, .pwsh:
                    combinedCommand = "$null | & {\(combinedCommand)}"
                case .cmd:
                    combinedCommand = "\(combinedCommand)< NUL"
                }
            }

            resultArgs.append(contentsOf: kind.argsForShell(interactive: interactive, combinedCommand: combinedCommand))
        }

        return (program, resultArgs)
    }

    /// This should not exist, but our task infra is broken beyond repair right now
    public func buildNoQuote(
        taskCommand: String?,
        taskArgs: [String]
    ) -> (program: String, args: [String]) {
        var resultArgs = self.args
        if let taskCommand = taskCommand {
            var combinedCommand = taskArgs.reduce(taskCommand) { command, arg in
                var cmd = command
                cmd.append(" ")
                cmd.append(kind.toShellVariable(arg))
                return cmd
            }

            if redirectStdin {
                switch kind {
                case .fish:
                    combinedCommand = "begin; \(combinedCommand); end </dev/null"
                case .posix, .nushell, .csh, .tcsh, .rc, .xonsh, .elvish:
                    combinedCommand = "(\(combinedCommand)) </dev/null"
                case .powerShell, .pwsh:
                    combinedCommand = "$null | & {\(combinedCommand)}"
                case .cmd:
                    combinedCommand = "\(combinedCommand)< NUL"
                }
            }

            resultArgs.append(contentsOf: kind.argsForShell(interactive: interactive, combinedCommand: combinedCommand))
        }

        return (program, resultArgs)
    }

    #if !os(WASI) && !os(iOS) && !os(visionOS) && !os(Android)
    /// Builds a Foundation `Process` with the given task command and arguments.
    public func buildStdCommand(
        taskCommand: String?,
        taskArgs: [String]
    ) -> Process {
        var cmd = taskCommand
        if taskArgs.isEmpty {
            cmd = cmd.flatMap { kind.tryQuotePrefixAware($0) } ?? cmd
        }
        let (prog, builtArgs) = build(taskCommand: cmd, taskArgs: taskArgs)
        let process = newStdCommand(prog)
        process.arguments = builtArgs
        return process
    }
    #endif

    public var shellKind: ShellKind {
        kind
    }
}
