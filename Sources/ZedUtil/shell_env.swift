// Ported from: crates/util/src/shell_env.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Foundation
#if !os(WASI)
import Dispatch
#endif

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Android)
import Android
#elseif canImport(WASILibc)
import WASILibc
#elseif os(Windows)
import CRT
#endif

public struct ShellEnvError: Error, CustomStringConvertible, Sendable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var description: String {
        message
    }
}

/// Serializes environment variables into formatted JSON.
public func formatEnvJson(_ envVars: [String: String]) throws -> String {
    let encoder = JSONEncoder()
    var formatting: JSONEncoder.OutputFormatting = [.prettyPrinted, .sortedKeys]
    if #available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, *) {
        formatting.insert(.withoutEscapingSlashes)
    }
    encoder.outputFormatting = formatting
    let data = try encoder.encode(envVars)
    guard let str = String(data: data, encoding: .utf8) else {
        throw ShellEnvError("Failed to encode environment variables as UTF-8 JSON")
    }
    return str
}

/// Deserializes environment variables from JSON.
public func parseEnvJson(_ jsonString: String) throws -> [String: String] {
    guard let data = jsonString.data(using: .utf8) else {
        throw ShellEnvError("Invalid UTF-8 in JSON string")
    }
    let decoder = JSONDecoder()
    return try decoder.decode([String: String].self, from: data)
}

/// Print current process environment variables in pretty JSON format to stdout.
public func printEnv() {
    let envVars = ProcessInfo.processInfo.environment
    do {
        let json = try formatEnvJson(envVars)
        print(json)
    } catch {
        let errMsg = "Error serializing environment variables: \(error)\n"
        try? FileHandle.standardError.write(contentsOf: Data(errMsg.utf8))
        #if canImport(Darwin)
        Darwin.exit(1)
        #elseif canImport(Glibc)
        Glibc.exit(1)
        #elseif canImport(Android)
        Android.exit(1)
        #elseif os(Windows)
        CRT.exit(1)
        #else
        exit(1)
        #endif
    }
}

/// Capture all environment variables from the login shell in the given directory.
public func capture(
    shellPath: String,
    args: [String] = [],
    directory: String
) async throws -> [String: String] {
    #if os(WASI) || os(iOS) || os(visionOS) || os(Android)
    _ = shellPath
    _ = args
    _ = directory
    return ProcessInfo.processInfo.environment
    #elseif os(Windows)
    return try await captureWindows(shellPath: shellPath, args: args, directory: directory)
    #else
    return try await captureUnix(shellPath: shellPath, args: args, directory: directory)
    #endif
}

#if !os(Windows) && !os(WASI) && !os(iOS) && !os(visionOS) && !os(Android)
private func captureUnix(
    shellPath: String,
    args: [String],
    directory: String
) async throws -> [String: String] {
    let shellKind = ShellKind(program: shellPath, isWindows: false)
    let currentExecutable = Bundle.main.executablePath ?? CommandLine.arguments[0]

    var commandArgs: [String] = args

    switch shellKind {
    case .csh, .tcsh:
        commandArgs.append("-l")
    case .fish:
        commandArgs.append("-l")
    default:
        commandArgs.append("-l")
    }

    switch shellKind {
    case .nushell:
        commandArgs.append("-e")
    default:
        commandArgs.append(contentsOf: ["-i", "-c"])
    }

    var commandString = ""
    if shellKind == .fish {
        commandString.append("emit fish_prompt;")
    }
    commandString.append("cd '\(directory)';")
    if let prefix = shellKind.commandPrefix {
        commandString.append(prefix)
    }

    let quotedExec = shellKind.tryQuote(currentExecutable) ?? currentExecutable
    commandString.append("\(quotedExec) --printenv")

    if shellKind == .nushell {
        commandString.append("; exit")
    }

    commandArgs.append(commandString)

    let process = Process()
    process.executableURL = URL(fileURLWithPath: shellPath)
    process.arguments = commandArgs

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe
    process.standardInput = FileHandle.nullDevice

    return try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global().async {
            do {
                try process.run()
                process.waitUntilExit()

                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                guard process.terminationStatus == 0 else {
                    let stdoutStr = String(decoding: stdoutData, as: UTF8.self)
                    let stderrStr = String(decoding: stderrData, as: UTF8.self)
                    continuation.resume(throwing: ShellEnvError("Login shell exited with \(process.terminationStatus). stdout: \(stdoutStr), stderr: \(stderrStr)"))
                    return
                }

                guard let outputString = String(data: stdoutData, encoding: .utf8) else {
                    continuation.resume(throwing: ShellEnvError("Failed to decode shell output as UTF-8"))
                    return
                }

                let envMap = try parseEnvJson(outputString)
                continuation.resume(returning: envMap)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
#endif

#if !os(WASI) && !os(iOS) && !os(visionOS) && !os(Android)
public func captureWindows(
    shellPath: String,
    args: [String],
    directory: String
) async throws -> [String: String] {
    let shellKind = ShellKind(program: shellPath, isWindows: true)
    let currentExecutable = CommandLine.arguments.first ?? "zed.exe"

    let quoteForShell = { (value: String) -> String in
        shellKind.tryQuote(value) ?? value
    }

    var cmdArgs = args
    switch shellKind {
    case .csh, .tcsh, .rc, .fish, .xonsh, .posix:
        let quotedDir = quoteForShell(directory)
        let quotedExec = quoteForShell(currentExecutable)
        cmdArgs.append(contentsOf: ["-l", "-i", "-c", "cd \(quotedDir); \(quotedExec) --printenv"])
    case .powerShell, .pwsh:
        let quotedDir = ShellKind.quotePwsh(directory)
        let quotedExec = ShellKind.quotePwsh(currentExecutable)
        cmdArgs.append(contentsOf: ["-NonInteractive", "-NoProfile", "-Command", "Set-Location \(quotedDir); & \(quotedExec) --printenv"])
    case .elvish:
        let quotedDir = quoteForShell(directory)
        let quotedExec = quoteForShell(currentExecutable)
        cmdArgs.append(contentsOf: ["-c", "cd \(quotedDir); \(quotedExec) --printenv"])
    case .nushell:
        let quotedDir = quoteForShell(directory)
        let quotedExec = quoteForShell(currentExecutable)
        let zedCmd = shellKind.prependCommandPrefix(quotedExec)
        cmdArgs.append(contentsOf: ["-c", "cd \(quotedDir); \(zedCmd) --printenv"])
    case .cmd:
        cmdArgs.append(contentsOf: ["/c", "cd", directory, "&&", currentExecutable, "--printenv"])
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: shellPath)
    process.arguments = cmdArgs

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe
    process.standardInput = FileHandle.nullDevice

    return try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global().async {
            do {
                try process.run()
                process.waitUntilExit()

                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                guard process.terminationStatus == 0 else {
                    let stdoutStr = String(decoding: stdoutData, as: UTF8.self)
                    let stderrStr = String(decoding: stderrData, as: UTF8.self)
                    continuation.resume(throwing: ShellEnvError("Command failed with \(process.terminationStatus). stdout: \(stdoutStr), stderr: \(stderrStr)"))
                    return
                }

                guard let outputString = String(data: stdoutData, encoding: .utf8) else {
                    continuation.resume(throwing: ShellEnvError("Failed to decode shell output as UTF-8"))
                    return
                }

                let envMap = try parseEnvJson(outputString)
                continuation.resume(returning: envMap)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
#endif
