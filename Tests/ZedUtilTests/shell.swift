// Tests ported from: crates/util/src/shell.rs (#[cfg(test)] items)
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Foundation
import Testing
@testable import ZedUtil

@Suite("Shell Tests")
struct ShellTests {
    @Test
    func test_try_quote_powershell() {
        let shellKind = ShellKind.powerShell
        #expect(
            shellKind
                .tryQuote("C:\\Users\\johndoe\\dev\\python\\39007\\tests\\.venv\\Scripts\\python.exe -m pytest \"test_foo.py::test_foo\"") ==
            "'C:\\Users\\johndoe\\dev\\python\\39007\\tests\\.venv\\Scripts\\python.exe -m pytest \\\"test_foo.py::test_foo\\\"'"
        )
    }

    @Test
    func test_try_quote_cmd() {
        let shellKind = ShellKind.cmd
        #expect(
            shellKind
                .tryQuote("C:\\Users\\johndoe\\dev\\python\\39007\\tests\\.venv\\Scripts\\python.exe -m pytest \"test_foo.py::test_foo\"") ==
            "^\"C:\\Users\\johndoe\\dev\\python\\39007\\tests\\.venv\\Scripts\\python.exe -m pytest \\^\"test_foo.py::test_foo\\^\"^\""
        )
    }

    @Test
    func test_try_quote_powershell_edge_cases() {
        let shellKind = ShellKind.powerShell

        // Empty string
        #expect(shellKind.tryQuote("") == "'\"\"'")

        // String without special characters (no quoting needed)
        #expect(shellKind.tryQuote("simple") == "simple")

        // String with spaces
        #expect(shellKind.tryQuote("hello world") == "'hello world'")

        // String with dollar signs
        #expect(shellKind.tryQuote("$variable") == "'$variable'")

        // String with backticks
        #expect(shellKind.tryQuote("test`command") == "'test`command'")

        // String with multiple special characters
        #expect(shellKind.tryQuote("test `\"$var`\" end") == "'test `\\\"$var`\\\" end'")

        // String with backslashes and colon (path without spaces doesn't need quoting)
        #expect(shellKind.tryQuote("C:\\path\\to\\file") == "C:\\path\\to\\file")
    }

    @Test
    func test_try_quote_cmd_edge_cases() {
        let shellKind = ShellKind.cmd

        // Empty string
        #expect(shellKind.tryQuote("") == "^\"^\"")

        // String without special characters (no quoting needed)
        #expect(shellKind.tryQuote("simple") == "simple")

        // String with spaces
        #expect(shellKind.tryQuote("hello world") == "^\"hello world^\"")

        // String with space and backslash (backslash not at end, so not doubled)
        #expect(shellKind.tryQuote("path\\ test") == "^\"path\\ test^\"")

        // String ending with backslash (must be doubled before closing quote)
        #expect(shellKind.tryQuote("test path\\") == "^\"test path\\\\^\"")

        // String ending with multiple backslashes (all doubled before closing quote)
        #expect(shellKind.tryQuote("test path\\\\") == "^\"test path\\\\\\\\^\"")

        // String with embedded quote (quote is escaped, backslash before it is doubled)
        #expect(shellKind.tryQuote("test\\\"quote") == "^\"test\\\\\\^\"quote^\"")

        // String with multiple backslashes before embedded quote (all doubled)
        #expect(shellKind.tryQuote("test\\\\\"quote") == "^\"test\\\\\\\\\\^\"quote^\"")

        // String with backslashes not before quotes (path without spaces doesn't need quoting)
        #expect(shellKind.tryQuote("C:\\path\\to\\file") == "C:\\path\\to\\file")
    }

    @Test
    func test_try_quote_nu_command() {
        let shellKind = ShellKind.nushell
        #expect(shellKind.tryQuote("'uname'") == "\"'uname'\"")
        #expect(shellKind.tryQuotePrefixAware("'uname'") == "^\"'uname'\"")
        #expect(shellKind.tryQuote("^uname") == "'^uname'")
        #expect(shellKind.tryQuotePrefixAware("^uname") == "^uname")
        #expect(shellKind.tryQuote("^'uname'") == "'^'\"'uname'\"")
        #expect(shellKind.tryQuotePrefixAware("^'uname'") == "^'uname'")
        #expect(shellKind.tryQuote("'uname a'") == "\"'uname a'\"")
        #expect(shellKind.tryQuotePrefixAware("'uname a'") == "^\"'uname a'\"")
        #expect(shellKind.tryQuote("^'uname a'") == "'^'\"'uname a'\"")
        #expect(shellKind.tryQuotePrefixAware("^'uname a'") == "^'uname a'")
        #expect(shellKind.tryQuote("uname") == "uname")
        #expect(shellKind.tryQuotePrefixAware("uname") == "uname")
    }

    @Test
    func test_try_quote_single_quote_paths() {
        let pathWithQuote = "C:\\Temp\\O'Brien\\repo"
        let shlexShells: [ShellKind] = [
            .posix,
            .fish,
            .csh,
            .tcsh,
            .rc,
            .xonsh,
            .elvish,
            .nushell,
        ]

        for shellKind in shlexShells {
            let quoted = shellKind.tryQuote(pathWithQuote)
            #expect(quoted != nil)
            guard let quoted = quoted else { continue }
            #expect(quoted != pathWithQuote)
            #expect(shlexSplit(quoted) == [pathWithQuote])

            if shellKind == .nushell {
                let prefixed = shellKind.prependCommandPrefix(quoted)
                #expect(prefixed.hasPrefix("^"))
            }
        }

        for shellKind in [ShellKind.powerShell, ShellKind.pwsh] {
            let quoted = shellKind.tryQuote(pathWithQuote)
            #expect(quoted != nil)
            guard let quoted = quoted else { continue }
            #expect(quoted.hasPrefix("'"))
            #expect(quoted.hasSuffix("'"))
            #expect(quoted.contains("O''Brien"))
        }
    }

    @Test
    func test_shell_enum_properties() {
        let systemShell = Shell.system
        #expect(!systemShell.program().isEmpty)
        #expect(systemShell.programAndArgs().args.isEmpty)

        let programShell = Shell.program("/usr/local/bin/zsh")
        #expect(programShell.program() == "/usr/local/bin/zsh")
        #expect(programShell.programAndArgs().program == "/usr/local/bin/zsh")
        #expect(programShell.programAndArgs().args.isEmpty)
        #expect(programShell.shellKind(isWindows: false) == .posix)

        let withArgs = Shell.withArguments(program: "powershell.exe", args: ["-NoProfile"], titleOverride: "PS")
        #expect(withArgs.program() == "powershell.exe")
        #expect(withArgs.programAndArgs().args == ["-NoProfile"])
        #expect(withArgs.shellKind(isWindows: true) == .powerShell)
    }

    @Test
    func test_shell_kind_stem_detection() {
        #expect(ShellKind(program: "C:\\Program Files\\PowerShell\\7\\pwsh.exe", isWindows: true) == .pwsh)
        #expect(ShellKind(program: "powershell.exe", isWindows: true) == .powerShell)
        #expect(ShellKind(program: "cmd.exe", isWindows: true) == .cmd)
        #expect(ShellKind(program: "/usr/bin/nu", isWindows: false) == .nushell)
        #expect(ShellKind(program: "/usr/bin/fish", isWindows: false) == .fish)
        #expect(ShellKind(program: "/bin/csh", isWindows: false) == .csh)
        #expect(ShellKind(program: "/bin/tcsh", isWindows: false) == .tcsh)
        #expect(ShellKind(program: "/usr/bin/rc", isWindows: false) == .rc)
        #expect(ShellKind(program: "/usr/bin/xonsh", isWindows: false) == .xonsh)
        #expect(ShellKind(program: "/usr/bin/elvish", isWindows: false) == .elvish)
        #expect(ShellKind(program: "/bin/bash", isWindows: false) == .posix)
        #expect(ShellKind(program: "/bin/zsh", isWindows: false) == .posix)
        #expect(ShellKind(program: "unknown.exe", isWindows: true) == .powerShell)
        #expect(ShellKind(program: "/opt/custom/shell", isWindows: false) == .posix)
    }

    @Test
    func test_shell_variables_and_chaining() {
        #expect(ShellKind.posix.supportsPosixChaining)
        #expect(ShellKind.fish.supportsPosixChaining)
        #expect(ShellKind.powerShell.supportsPosixChaining)
        #expect(ShellKind.pwsh.supportsPosixChaining)
        #expect(ShellKind.cmd.supportsPosixChaining)
        #expect(!ShellKind.nushell.supportsPosixChaining)
        #expect(!ShellKind.elvish.supportsPosixChaining)
        #expect(!ShellKind.rc.supportsPosixChaining)

        #expect(ShellKind.cmd.toShellVariable("${VAR}") == "%VAR%")
        #expect(ShellKind.cmd.toShellVariable("$VAR") == "%VAR%")
        #expect(ShellKind.powerShell.toShellVariable("${VAR}") == "$env:VAR")
        #expect(ShellKind.powerShell.toShellVariable("$VAR") == "$env:VAR")
        #expect(ShellKind.posix.toShellVariable("$VAR") == "$VAR")

        #expect(ShellKind.cmd.sequentialCommandsSeparator == "&")
        #expect(ShellKind.posix.sequentialCommandsSeparator == ";")
        #expect(ShellKind.posix.sequentialAndCommandsSeparator == "&&")
        #expect(ShellKind.nushell.sequentialAndCommandsSeparator == ";")

        #expect(ShellKind.cmd.clearScreenCommand == "cls")
        #expect(ShellKind.posix.clearScreenCommand == "clear")
        #expect(ShellKind.cmd.activateKeyword == "")
        #expect(ShellKind.nushell.activateKeyword == "overlay use")
        #expect(ShellKind.posix.activateKeyword == "source")
    }
}
