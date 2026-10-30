// Ported from: crates/util/src/redact.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Foundation

private let redactRegex: NSRegularExpression = {
    let pattern = "([A-Z_][A-Z0-9_]*)=(\"(?:[^\"\\\\]|\\\\.)*\"|'(?:[^'\\\\]|\\\\.)*'|\\S+)"
    // PORT NOTE: Compile-time constant regex pattern is known-valid and tested.
    // swiftlint:disable:next force_try
    return try! NSRegularExpression(pattern: pattern)
}()

private let redactedSuffixes: [String] = [
    "KEY",
    "TOKEN",
    "PASSWORD",
    "SECRET",
    "PASS",
    "CREDENTIALS",
    "LICENSE",
]

/// Whether a given environment variable name should have its value redacted
public func shouldRedact(_ envVarName: String) -> Bool {
    redactedSuffixes.contains { suffix in
        envVarName.hasSuffix(suffix)
    }
}

/// Redact a string which could include a command with environment variables
public func redactCommand(_ command: String) -> String {
    let nsString = command as NSString
    let fullRange = NSRange(location: 0, length: nsString.length)
    let matches = redactRegex.matches(in: command, range: fullRange)

    guard !matches.isEmpty else {
        return command
    }

    var result = ""
    var lastIndex = 0

    for match in matches {
        let matchRange = match.range
        if matchRange.location > lastIndex {
            result += nsString.substring(with: NSRange(location: lastIndex, length: matchRange.location - lastIndex))
        }

        let varName = nsString.substring(with: match.range(at: 1))
        let value = nsString.substring(with: match.range(at: 2))

        if shouldRedact(varName) {
            result += "\(varName)=\"[REDACTED]\""
        } else {
            result += "\(varName)=\(value)"
        }

        lastIndex = matchRange.location + matchRange.length
    }

    if lastIndex < nsString.length {
        result += nsString.substring(with: NSRange(location: lastIndex, length: nsString.length - lastIndex))
    }

    return result
}

/// Alias for `redactCommand`
public func redactString(_ command: String) -> String {
    redactCommand(command)
}
