// Ported from: crates/util/src/shell.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Foundation

/// Shell configuration to open the terminal with.
public enum Shell: Equatable, Hashable, Sendable {
    /// Use the system's default terminal configuration.
    case system
    /// Use a specific program with no arguments.
    case program(String)
    /// Use a specific program with arguments.
    case withArguments(program: String, args: [String], titleOverride: String?)

    public init() {
        self = .system
    }

    public func program() -> String {
        switch self {
        case .program(let program):
            return program
        case .withArguments(let program, _, _):
            return program
        case .system:
            return getSystemShell()
        }
    }

    public func programAndArgs() -> (program: String, args: [String]) {
        switch self {
        case .program(let program):
            return (program, [])
        case .withArguments(let program, let args, _):
            return (program, args)
        case .system:
            return (getSystemShell(), [])
        }
    }

    public func shellKind(isWindows: Bool) -> ShellKind {
        switch self {
        case .program(let program):
            return ShellKind(program: program, isWindows: isWindows)
        case .withArguments(let program, _, _):
            return ShellKind(program: program, isWindows: isWindows)
        case .system:
            return ShellKind.system()
        }
    }
}

extension Shell: Codable {
    private enum CodingKeys: String, CodingKey {
        case program
        case withArguments = "with_arguments"
    }

    private struct WithArgumentsPayload: Codable {
        let program: String
        let args: [String]
        let titleOverride: String?

        enum CodingKeys: String, CodingKey {
            case program
            case args
            case titleOverride = "title_override"
        }
    }

    public init(from decoder: any Decoder) throws {
        if let singleValue = try? decoder.singleValueContainer(),
           let str = try? singleValue.decode(String.self) {
            if str == "system" {
                self = .system
            } else {
                self = .program(str)
            }
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.program) {
            let prog = try container.decode(String.self, forKey: .program)
            self = .program(prog)
        } else if container.contains(.withArguments) {
            let payload = try container.decode(WithArgumentsPayload.self, forKey: .withArguments)
            self = .withArguments(program: payload.program, args: payload.args, titleOverride: payload.titleOverride)
        } else {
            self = .system
        }
    }

    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .system:
            var container = encoder.singleValueContainer()
            try container.encode("system")
        case .program(let prog):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(prog, forKey: .program)
        case .withArguments(let program, let args, let titleOverride):
            var container = encoder.container(keyedBy: CodingKeys.self)
            let payload = WithArgumentsPayload(program: program, args: args, titleOverride: titleOverride)
            try container.encode(payload, forKey: .withArguments)
        }
    }
}

public enum ShellKind: String, Codable, CaseIterable, Equatable, Hashable, Sendable, CustomStringConvertible {
    case posix = "sh"
    case csh = "csh"
    case tcsh = "tcsh"
    case rc = "rc"
    case fish = "fish"
    case powerShell = "powershell"
    case pwsh = "pwsh"
    case nushell = "nu"
    case cmd = "cmd"
    case xonsh = "xonsh"
    case elvish = "elvish"

    public var description: String {
        rawValue
    }

    public static func system() -> ShellKind {
        #if os(Windows)
        return ShellKind(program: getSystemShell(), isWindows: true)
        #else
        return ShellKind(program: getSystemShell(), isWindows: false)
        #endif
    }

    /// Returns whether this shell uses POSIX-like command chaining syntax (`&&`, `||`, `;`, `|`).
    public var supportsPosixChaining: Bool {
        switch self {
        case .posix, .fish, .powerShell, .pwsh, .cmd, .xonsh, .csh, .tcsh:
            return true
        case .nushell, .elvish, .rc:
            return false
        }
    }

    public init(program: String, isWindows: Bool) {
        // Extract stem by taking last component and stripping extension
        let lastComponent: String
        if let backslashIdx = program.lastIndex(of: "\\") {
            lastComponent = String(program[program.index(after: backslashIdx)...])
        } else if let slashIdx = program.lastIndex(of: "/") {
            lastComponent = String(program[program.index(after: slashIdx)...])
        } else {
            lastComponent = program
        }

        let stem: String
        if let dotIdx = lastComponent.lastIndex(of: ".") {
            stem = String(lastComponent[..<dotIdx])
        } else {
            stem = lastComponent
        }

        switch stem.lowercased() {
        case "powershell":
            self = .powerShell
        case "pwsh":
            self = .pwsh
        case "cmd":
            self = .cmd
        case "nu":
            self = .nushell
        case "fish":
            self = .fish
        case "csh":
            self = .csh
        case "tcsh":
            self = .tcsh
        case "rc":
            self = .rc
        case "xonsh":
            self = .xonsh
        case "elvish":
            self = .elvish
        case "sh", "bash", "zsh":
            self = .posix
        default:
            if isWindows {
                self = .powerShell
            } else {
                self = .posix
            }
        }
    }

    public func toShellVariable(_ input: String) -> String {
        switch self {
        case .powerShell, .pwsh:
            return Self.toPowerShellVariable(input)
        case .cmd:
            return Self.toCmdVariable(input)
        case .nushell:
            return Self.toNushellVariable(input)
        case .posix, .fish, .csh, .tcsh, .rc, .xonsh, .elvish:
            return input
        }
    }

    private static func toCmdVariable(_ input: String) -> String {
        if input.hasPrefix("${") {
            let varStr = String(input.dropFirst(2))
            if !varStr.contains(":") && varStr.hasSuffix("}") {
                let name = String(varStr.dropLast())
                return "%\(name)%"
            } else {
                return input
            }
        } else if input.hasPrefix("$") {
            let varStr = String(input.dropFirst(1))
            return "%\(varStr)%"
        } else {
            return input
        }
    }

    private static func toPowerShellVariable(_ input: String) -> String {
        if input.hasPrefix("${") {
            let varStr = String(input.dropFirst(2))
            if !varStr.contains(":") && varStr.hasSuffix("}") {
                let name = String(varStr.dropLast())
                return "$env:\(name)"
            } else {
                return input
            }
        } else if input.hasPrefix("$") {
            let varStr = String(input.dropFirst(1))
            return "$env:\(varStr)"
        } else {
            return input
        }
    }

    private static func toNushellVariable(_ input: String) -> String {
        var result = ""
        var source = input[...]
        var isStart = true

        while true {
            guard let first = source.first else {
                return result
            }
            if first == "$" {
                source = parseNushellVar(source: source.dropFirst(), text: &result, isStart: isStart)
                isStart = false
            } else {
                isStart = false
                let chunkEnd = source.firstIndex(of: "$") ?? source.endIndex
                result.append(contentsOf: source[..<chunkEnd])
                source = source[chunkEnd...]
            }
        }
    }

    private static func parseNushellVar(source: Substring, text: inout String, isStart: Bool) -> Substring {
        if source.hasPrefix("env.") {
            text.append("$")
            return source
        }

        guard let first = source.first else {
            text.append("$")
            return source
        }

        if first == "{" {
            let inner = source.dropFirst()
            if let endIdx = inner.firstIndex(of: "}") {
                let varName = inner[..<endIdx]
                if !varName.isEmpty {
                    if !isStart {
                        text.append("(")
                    }
                    text.append("$env.")
                    text.append(contentsOf: varName)
                    if !isStart {
                        text.append(")")
                    }
                    return inner[inner.index(after: endIdx)...]
                } else {
                    text.append("${}")
                    return inner[inner.index(after: endIdx)...]
                }
            } else {
                text.append("${")
                return inner
            }
        } else if first.isLetter || first == "_" {
            let nonIdentIdx = source.firstIndex(where: { !($0.isLetter || $0.isNumber || $0 == "_") }) ?? source.endIndex
            let varName = source[..<nonIdentIdx]
            if !isStart {
                text.append("(")
            }
            text.append("$env.")
            text.append(contentsOf: varName)
            if !isStart {
                text.append(")")
            }
            return source[nonIdentIdx...]
        } else {
            text.append("$")
            return source
        }
    }

    public func argsForShell(interactive: Bool, combinedCommand: String) -> [String] {
        switch self {
        case .powerShell, .pwsh:
            return ["-C", combinedCommand]
        case .cmd:
            return ["/S", "/C", "\"\(combinedCommand)\""]
        case .posix, .nushell, .fish, .csh, .tcsh, .rc, .xonsh, .elvish:
            var args = [String]()
            if interactive {
                args.append("-i")
            }
            args.append("-c")
            args.append(combinedCommand)
            return args
        }
    }

    public var commandPrefix: Character? {
        switch self {
        case .powerShell, .pwsh:
            return "&"
        case .nushell:
            return "^"
        case .posix, .csh, .tcsh, .rc, .fish, .cmd, .xonsh, .elvish:
            return nil
        }
    }

    public func prependCommandPrefix(_ command: String) -> String {
        guard let prefix = commandPrefix else {
            return command
        }
        if !command.hasPrefix(String(prefix)) {
            return "\(prefix)\(command)"
        }
        return command
    }

    public var sequentialCommandsSeparator: Character {
        switch self {
        case .cmd:
            return "&"
        case .posix, .csh, .tcsh, .rc, .fish, .powerShell, .pwsh, .nushell, .xonsh, .elvish:
            return ";"
        }
    }

    public var sequentialAndCommandsSeparator: String {
        switch self {
        case .cmd, .posix, .csh, .tcsh, .rc, .fish, .pwsh, .powerShell, .xonsh:
            return "&&"
        case .nushell, .elvish:
            return ";"
        }
    }

    public func tryQuote(_ arg: String) -> String? {
        switch self {
        case .powerShell:
            return Self.quotePowerShell(arg)
        case .pwsh:
            return Self.quotePwsh(arg)
        case .cmd:
            return Self.quoteCmd(arg)
        case .posix, .csh, .tcsh, .rc, .fish, .nushell, .xonsh, .elvish:
            return shlexTryQuote(arg)
        }
    }

    private static func quoteWindows(_ arg: String, enclose: Bool) -> String {
        if arg.isEmpty {
            return "\"\""
        }

        let needsQuoting = arg.contains(where: { $0 == " " || $0 == "\t" || $0 == "\"" })
        if !needsQuoting {
            return arg
        }

        var result = ""
        result.reserveCapacity(arg.count + 2)

        if enclose {
            result.append("\"")
        }

        let chars = Array(arg)
        var i = 0

        while i < chars.count {
            if chars[i] == "\\" {
                var numBackslashes = 0
                while i < chars.count && chars[i] == "\\" {
                    numBackslashes += 1
                    i += 1
                }

                if i < chars.count && chars[i] == "\"" {
                    for _ in 0..<(numBackslashes * 2 + 1) {
                        result.append("\\")
                    }
                    result.append("\"")
                    i += 1
                } else if i >= chars.count {
                    for _ in 0..<(numBackslashes * 2) {
                        result.append("\\")
                    }
                } else {
                    for _ in 0..<numBackslashes {
                        result.append("\\")
                    }
                }
            } else if chars[i] == "\"" {
                result.append("\\")
                result.append("\"")
                i += 1
            } else {
                result.append(chars[i])
                i += 1
            }
        }

        if enclose {
            result.append("\"")
        }
        return result
    }

    private static func needsQuotingPowerShell(_ s: String) -> Bool {
        if s.isEmpty { return true }
        return s.contains(where: { c in
            c.isWhitespace || ["\"", "`", "$", "&", "|", "<", ">", ";", "(", ")", "[", "]", "{", "}", ",", "'", "@"].contains(c)
        })
    }

    private static func needQuotesPowerShell(_ arg: String) -> Bool {
        var quoteCount = 0
        for c in arg {
            if c == "\"" {
                quoteCount += 1
            } else if c.isWhitespace && (quoteCount % 2 == 0) {
                return true
            }
        }
        return false
    }

    private static func escapePowerShellQuotes(_ s: String) -> String {
        var result = ""
        result.reserveCapacity(s.count + 4)
        result.append("'")
        for c in s {
            if c == "'" {
                result.append("'")
            }
            result.append(c)
        }
        result.append("'")
        return result
    }

    public static func quotePowerShell(_ arg: String) -> String {
        let psWillQuote = needQuotesPowerShell(arg)
        let crtQuoted = quoteWindows(arg, enclose: !psWillQuote)

        if !needsQuotingPowerShell(arg) {
            return crtQuoted
        }

        return escapePowerShellQuotes(crtQuoted)
    }

    public static func quotePwsh(_ arg: String) -> String {
        if arg.isEmpty {
            return "''"
        }

        if !needsQuotingPowerShell(arg) {
            return arg
        }

        return escapePowerShellQuotes(arg)
    }

    public static func quoteCmd(_ arg: String) -> String {
        let crtQuoted = quoteWindows(arg, enclose: true)

        let needsCmdEscaping = crtQuoted.contains("\"")
            || crtQuoted.contains("%")
            || crtQuoted.contains(where: { ["^", "<", ">", "&", "|", "(", ")"].contains($0) })

        if !needsCmdEscaping {
            return crtQuoted
        }

        var result = ""
        result.reserveCapacity(crtQuoted.count * 2)
        for c in crtQuoted {
            switch c {
            case "^", "\"", "<", ">", "&", "|", "(", ")":
                result.append("^")
                result.append(c)
            case "%":
                result.append("%%cd:~,%")
            default:
                result.append(c)
            }
        }
        return result
    }

    /// Quotes the given argument if necessary, taking into account the command prefix.
    public func tryQuotePrefixAware(_ arg: String) -> String? {
        if let prefix = commandPrefix {
            let prefixStr = String(prefix)
            if arg.hasPrefix(prefixStr) {
                let stripped = String(arg.dropFirst(prefixStr.count))
                for quoteChar in ["'", "\""] {
                    if stripped.hasPrefix(quoteChar) && stripped.hasSuffix(quoteChar) && stripped.count >= 2 {
                        let inner = String(stripped.dropFirst().dropLast())
                        guard let quoted = tryQuote(inner) else { return nil }
                        if quoted.hasPrefix("'") || quoted.hasPrefix("\"") {
                            return prependCommandPrefix(quoted)
                        } else {
                            return prependCommandPrefix("\(quoteChar)\(quoted)\(quoteChar)")
                        }
                    }
                }
                guard let quoted = tryQuote(stripped) else { return nil }
                return prependCommandPrefix(quoted)
            }
        }
        guard let quoted = tryQuote(arg) else { return nil }
        if quoted != arg {
            return prependCommandPrefix(quoted)
        } else {
            return arg
        }
    }

    public func split(_ input: String) -> [String]? {
        shlexSplit(input)
    }

    public var activateKeyword: String {
        switch self {
        case .cmd:
            return ""
        case .nushell:
            return "overlay use"
        case .powerShell, .pwsh:
            return "."
        case .fish, .csh, .tcsh, .posix, .rc, .xonsh, .elvish:
            return "source"
        }
    }

    public var clearScreenCommand: String {
        switch self {
        case .cmd:
            return "cls"
        case .posix, .csh, .tcsh, .rc, .fish, .powerShell, .pwsh, .nushell, .xonsh, .elvish:
            return "clear"
        }
    }

    public var ttyEscapeArgs: Bool {
        switch self {
        case .cmd:
            return false
        case .posix, .csh, .tcsh, .rc, .fish, .powerShell, .pwsh, .nushell, .xonsh, .elvish:
            return true
        }
    }
}

// MARK: - POSIX shlex implementation

private enum ShlexQuotingStrategy {
    case unquoted
    case singleQuoted
    case doubleQuoted
}

private func shlexUnquotedOk(_ c: UInt8) -> Bool {
    switch c {
    case UInt8(ascii: "+"), UInt8(ascii: "-"), UInt8(ascii: "."), UInt8(ascii: "/"),
         UInt8(ascii: ":"), UInt8(ascii: "@"), UInt8(ascii: "]"), UInt8(ascii: "_"),
         UInt8(ascii: "0")...UInt8(ascii: "9"),
         UInt8(ascii: "A")...UInt8(ascii: "Z"),
         UInt8(ascii: "a")...UInt8(ascii: "z"):
        return true
    default:
        return false
    }
}

private func shlexSingleQuotedOk(_ c: UInt8) -> Bool {
    switch c {
    case UInt8(ascii: "'"), UInt8(ascii: "^"), UInt8(ascii: "\\"):
        return false
    default:
        return true
    }
}

private func shlexDoubleQuotedOk(_ c: UInt8) -> Bool {
    switch c {
    case UInt8(ascii: "`"), UInt8(ascii: "$"), UInt8(ascii: "!"), UInt8(ascii: "^"):
        return false
    default:
        return true
    }
}

private func shlexQuotingStrategy(inBytes: [UInt8]) -> (Int, ShlexQuotingStrategy) {
    let unquotedFlag: UInt8 = 1
    let singleQuotedFlag: UInt8 = 2
    let doubleQuotedFlag: UInt8 = 4

    var prevOk = singleQuotedFlag | doubleQuotedFlag | unquotedFlag
    var i = 0

    if inBytes.first == UInt8(ascii: "^") {
        prevOk = singleQuotedFlag
        i = 1
    }

    while i < inBytes.count {
        let c = inBytes[i]
        var curOk = prevOk

        if c >= 0x80 {
            curOk &= ~unquotedFlag
        } else {
            if !shlexUnquotedOk(c) {
                curOk &= ~unquotedFlag
            }
            if !shlexSingleQuotedOk(c) {
                curOk &= ~singleQuotedFlag
            }
            if !shlexDoubleQuotedOk(c) {
                curOk &= ~doubleQuotedFlag
            }
        }

        if curOk == 0 {
            break
        }

        prevOk = curOk
        i += 1
    }

    let strategy: ShlexQuotingStrategy
    if (prevOk & unquotedFlag) != 0 {
        strategy = .unquoted
    } else if (prevOk & singleQuotedFlag) != 0 {
        strategy = .singleQuoted
    } else if (prevOk & doubleQuotedFlag) != 0 {
        strategy = .doubleQuoted
    } else {
        strategy = .unquoted
    }

    return (max(1, i), strategy)
}

private func shlexAppendQuotedChunk(out: inout [UInt8], curChunk: [UInt8], strategy: ShlexQuotingStrategy) {
    switch strategy {
    case .unquoted:
        out.append(contentsOf: curChunk)
    case .singleQuoted:
        out.reserveCapacity(out.count + curChunk.count + 2)
        out.append(UInt8(ascii: "'"))
        out.append(contentsOf: curChunk)
        out.append(UInt8(ascii: "'"))
    case .doubleQuoted:
        out.reserveCapacity(out.count + curChunk.count + 2)
        out.append(UInt8(ascii: "\""))
        for c in curChunk {
            if c == UInt8(ascii: "$") || c == UInt8(ascii: "`") || c == UInt8(ascii: "\"") || c == UInt8(ascii: "\\") {
                out.append(UInt8(ascii: "\\"))
            }
            out.append(c)
        }
        out.append(UInt8(ascii: "\""))
    }
}

public func shlexTryQuote(_ arg: String) -> String? {
    if arg.isEmpty {
        return "''"
    }
    let inBytes = Array(arg.utf8)
    if inBytes.contains(0) {
        return nil
    }

    var remaining = inBytes[...]
    var out: [UInt8] = []

    while !remaining.isEmpty {
        let currentArray = Array(remaining)
        let (curLen, strategy) = shlexQuotingStrategy(inBytes: currentArray)
        if curLen == inBytes.count && strategy == .unquoted && out.isEmpty {
            return arg
        }
        let curChunk = Array(currentArray.prefix(curLen))
        remaining = remaining.dropFirst(curLen)
        shlexAppendQuotedChunk(out: &out, curChunk: curChunk, strategy: strategy)
    }

    return String(decoding: out, as: UTF8.self)
}

public func shlexSplit(_ input: String) -> [String]? {
    let bytes = Array(input.utf8)
    var index = 0
    var lineNo = 1
    var hadError = false

    func nextChar() -> UInt8? {
        guard index < bytes.count else { return nil }
        let c = bytes[index]
        index += 1
        if c == UInt8(ascii: "\n") {
            lineNo += 1
        }
        return c
    }

    func parseDouble(result: inout [UInt8]) -> Bool {
        while let ch2 = nextChar() {
            if ch2 == UInt8(ascii: "\\") {
                guard let ch3 = nextChar() else { return false }
                if ch3 == UInt8(ascii: "$") || ch3 == UInt8(ascii: "`") || ch3 == UInt8(ascii: "\"") || ch3 == UInt8(ascii: "\\") {
                    result.append(ch3)
                } else if ch3 == UInt8(ascii: "\n") {
                    // \<newline> => nothing
                } else {
                    result.append(UInt8(ascii: "\\"))
                    result.append(ch3)
                }
            } else if ch2 == UInt8(ascii: "\"") {
                return true
            } else {
                result.append(ch2)
            }
        }
        return false
    }

    func parseSingle(result: inout [UInt8]) -> Bool {
        while let ch2 = nextChar() {
            if ch2 == UInt8(ascii: "'") {
                return true
            } else {
                result.append(ch2)
            }
        }
        return false
    }

    func parseWord(initialCh: UInt8) -> [UInt8]? {
        var result: [UInt8] = []
        var ch = initialCh
        while true {
            if ch == UInt8(ascii: "\"") {
                if !parseDouble(result: &result) {
                    hadError = true
                    return nil
                }
            } else if ch == UInt8(ascii: "'") {
                if !parseSingle(result: &result) {
                    hadError = true
                    return nil
                }
            } else if ch == UInt8(ascii: "\\") {
                if let ch2 = nextChar() {
                    if ch2 != UInt8(ascii: "\n") {
                        result.append(ch2)
                    }
                } else {
                    hadError = true
                    return nil
                }
            } else if ch == UInt8(ascii: " ") || ch == UInt8(ascii: "\t") || ch == UInt8(ascii: "\n") {
                break
            } else {
                result.append(ch)
            }

            if let ch2 = nextChar() {
                ch = ch2
            } else {
                break
            }
        }
        return result
    }

    var words: [String] = []

    while let mutCh = nextChar() {
        var ch = mutCh
        var skip = false
        while true {
            if ch == UInt8(ascii: " ") || ch == UInt8(ascii: "\t") || ch == UInt8(ascii: "\n") {
                // whitespace
            } else if ch == UInt8(ascii: "#") {
                while let ch2 = nextChar() {
                    if ch2 == UInt8(ascii: "\n") { break }
                }
            } else {
                break
            }
            if let ch2 = nextChar() {
                ch = ch2
            } else {
                skip = true
                break
            }
        }
        if skip { break }

        guard let wordBytes = parseWord(initialCh: ch) else {
            return nil
        }
        words.append(String(decoding: wordBytes, as: UTF8.self))
    }

    if hadError {
        return nil
    }
    return words
}

// MARK: - System Shell Lookups

public func getSystemShell() -> String {
    #if os(Windows)
    return getWindowsSystemShell()
    #else
    return ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/sh"
    #endif
}

public func getDefaultSystemShell() -> String {
    #if os(Windows)
    return getWindowsSystemShell()
    #else
    return "/bin/sh"
    #endif
}

public func getDefaultSystemShellPreferringBash() -> String {
    #if os(Windows)
    return getWindowsBash() ?? getWindowsSystemShell()
    #else
    return "/bin/sh"
    #endif
}

private func whichExecutable(_ program: String) -> String? {
    let fileManager = FileManager.default
    if program.contains("/") || program.contains("\\") {
        if fileManager.isExecutableFile(atPath: program) {
            return program
        }
        return nil
    }

    guard let pathVar = ProcessInfo.processInfo.environment["PATH"] else {
        return nil
    }

    #if os(Windows)
    let separator: Character = ";"
    #else
    let separator: Character = ":"
    #endif

    let dirs = pathVar.split(separator: separator, omittingEmptySubsequences: true)
    for dir in dirs {
        let candidate = (String(dir) as NSString).appendingPathComponent(program)
        if fileManager.isExecutableFile(atPath: candidate) {
            return candidate
        }
    }
    return nil
}

public func getWindowsBash() -> String? {
    let fileManager = FileManager.default
    if let userProfile = ProcessInfo.processInfo.environment["USERPROFILE"] {
        let scoopBash = (userProfile as NSString).appendingPathComponent("scoop\\shims\\bash.exe")
        if fileManager.fileExists(atPath: scoopBash) {
            return scoopBash
        }
    }
    if let git = whichExecutable("git") ?? whichExecutable("git.exe") {
        let gitDir = (git as NSString).deletingLastPathComponent
        let gitParent = (gitDir as NSString).deletingLastPathComponent
        let gitBash = ((gitParent as NSString).appendingPathComponent("bin") as NSString).appendingPathComponent("bash.exe")
        if fileManager.fileExists(atPath: gitBash) {
            return gitBash
        }
    }
    return nil
}

public func getWindowsSystemShell() -> String {
    let fileManager = FileManager.default

    func findPwshInProgramFiles(findAlternate: Bool, findPreview: Bool) -> String? {
        let envVar: String
        #if arch(x86_64) || arch(arm64)
        envVar = findAlternate ? "ProgramFiles(x86)" : "ProgramFiles"
        #else
        envVar = findAlternate ? "ProgramW6432" : "ProgramFiles"
        #endif

        guard let base = ProcessInfo.processInfo.environment[envVar] else { return nil }
        let installBaseDir = (base as NSString).appendingPathComponent("PowerShell")
        guard let entries = try? fileManager.contentsOfDirectory(atPath: installBaseDir) else { return nil }

        var candidates: [(version: UInt32, path: String)] = []
        for entry in entries {
            let fullPath = (installBaseDir as NSString).appendingPathComponent(entry)
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: fullPath, isDirectory: &isDir), isDir.boolValue else {
                continue
            }

            let version: UInt32?
            if findPreview {
                if let dashIndex = entry.firstIndex(of: "-") {
                    let suffix = entry[entry.index(after: dashIndex)...]
                    guard suffix == "preview" else { continue }
                    version = UInt32(entry[..<dashIndex])
                } else {
                    continue
                }
            } else {
                version = UInt32(entry)
            }

            guard let ver = version else { continue }
            let exePath = (fullPath as NSString).appendingPathComponent("pwsh.exe")
            if fileManager.fileExists(atPath: exePath) {
                candidates.append((ver, exePath))
            }
        }

        candidates.sort(by: { $0.version > $1.version })
        return candidates.first?.path
    }

    func findPwshInMsix(findPreview: Bool) -> String? {
        guard let localAppData = ProcessInfo.processInfo.environment["LOCALAPPDATA"] else { return nil }
        let msixAppDir = ((localAppData as NSString).appendingPathComponent("Microsoft") as NSString).appendingPathComponent("WindowsApps")
        guard let entries = try? fileManager.contentsOfDirectory(atPath: msixAppDir) else { return nil }

        let prefix = findPreview ? "Microsoft.PowerShellPreview_" : "Microsoft.PowerShell_"
        for entry in entries {
            if entry.hasPrefix(prefix) {
                let fullPath = (msixAppDir as NSString).appendingPathComponent(entry)
                var isDir: ObjCBool = false
                if fileManager.fileExists(atPath: fullPath, isDirectory: &isDir), isDir.boolValue {
                    let exePath = (fullPath as NSString).appendingPathComponent("pwsh.exe")
                    if fileManager.fileExists(atPath: exePath) {
                        return exePath
                    }
                }
            }
        }
        return nil
    }

    func findPwshInScoop() -> String? {
        guard let userProfile = ProcessInfo.processInfo.environment["USERPROFILE"] else { return nil }
        let scoopPwsh = (((userProfile as NSString).appendingPathComponent("scoop") as NSString).appendingPathComponent("shims") as NSString).appendingPathComponent("pwsh.exe")
        return fileManager.fileExists(atPath: scoopPwsh) ? scoopPwsh : nil
    }

    let searchSteps: [() -> String?] = [
        { findPwshInProgramFiles(findAlternate: false, findPreview: false) },
        { findPwshInProgramFiles(findAlternate: true, findPreview: false) },
        { findPwshInMsix(findPreview: false) },
        { findPwshInProgramFiles(findAlternate: false, findPreview: true) },
        { findPwshInMsix(findPreview: true) },
        { findPwshInProgramFiles(findAlternate: true, findPreview: true) },
        { findPwshInScoop() },
        { whichExecutable("pwsh.exe") },
        { whichExecutable("powershell.exe") }
    ]

    for step in searchSteps {
        if let found = step() {
            return found
        }
    }

    return "cmd.exe"
}
