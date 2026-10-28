// Ported from: crates/util/src/command.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Foundation

public final class Command: @unchecked Sendable {
    private let process: Process
    private var arguments: [String] = []

    public init(_ program: String) {
        self.process = Process()
        self.process.executableURL = URL(fileURLWithPath: program)
    }

    public static func newCommand(_ program: String) -> Command {
        Command(program)
    }

    public func arg(_ arg: String) -> Self {
        arguments.append(arg)
        return self
    }

    public func args(_ args: [String]) -> Self {
        arguments.append(contentsOf: args)
        return self
    }

    public func env(_ key: String, _ value: String) -> Self {
        var environment = process.environment ?? ProcessInfo.processInfo.environment
        environment[key] = value
        process.environment = environment
        return self
    }

    public func currentDir(_ dir: String) -> Self {
        process.currentDirectoryURL = URL(fileURLWithPath: dir)
        return self
    }

    public func output() throws -> (status: Int32, stdout: Data, stderr: Data) {
        process.arguments = arguments
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        try process.run()
        process.waitUntilExit()
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        return (process.terminationStatus, stdoutData, stderrData)
    }
}

public func newCommand(_ program: String) -> Command {
    Command(program)
}

public func newStdCommand(_ program: String) -> Process {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: program)
    return process
}
