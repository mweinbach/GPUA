// Tests ported from: crates/util/src/shell_builder.rs (#[cfg(test)] items)
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Foundation
import Testing
@testable import ZedUtil

@Suite("ShellBuilder Tests")
struct ShellBuilderTests {
    @Test
    func test_nu_shell_variable_substitution() {
        let shell = Shell.program("nu")
        let shellBuilder = ShellBuilder(shell: shell, isWindows: false)

        let (program, args) = shellBuilder.build(
            taskCommand: "echo",
            taskArgs: [
                "${hello}",
                "$world",
                "nothing",
                "--$something",
                "$",
                "${test",
            ]
        )

        #expect(program == "nu")
        #expect(
            args == [
                "-i",
                "-c",
                "echo '$env.hello' '$env.world' nothing '--($env.something)' '$' '${test'",
            ]
        )
    }

    @Test
    func test_redirect_stdin_to_dev_null_precedence() {
        let shell = Shell.program("nu")
        let shellBuilder = ShellBuilder(shell: shell, isWindows: false)

        let (program, args) = shellBuilder
            .redirectStdinToDevNull()
            .build(taskCommand: "echo", taskArgs: ["nothing"])

        #expect(program == "nu")
        #expect(args == ["-i", "-c", "(echo nothing) </dev/null"])
    }

    @Test
    func test_redirect_stdin_to_dev_null_fish() {
        let shell = Shell.program("fish")
        let shellBuilder = ShellBuilder(shell: shell, isWindows: false)

        let (program, args) = shellBuilder
            .redirectStdinToDevNull()
            .build(taskCommand: "echo", taskArgs: ["test"])

        #expect(program == "fish")
        #expect(args == ["-i", "-c", "begin; echo test; end </dev/null"])
    }

    @Test
    func test_does_not_quote_sole_command_only() {
        let shell = Shell.program("fish")
        let shellBuilder = ShellBuilder(shell: shell, isWindows: false)

        let (program1, args1) = shellBuilder.build(taskCommand: "echo", taskArgs: [])
        #expect(program1 == "fish")
        #expect(args1 == ["-i", "-c", "echo"])

        let shell2 = Shell.program("fish")
        let shellBuilder2 = ShellBuilder(shell: shell2, isWindows: false)

        let (program2, args2) = shellBuilder2.build(taskCommand: "echo oo", taskArgs: [])
        #expect(program2 == "fish")
        #expect(args2 == ["-i", "-c", "echo oo"])
    }

    @Test
    func test_command_label() {
        let posixBuilder = ShellBuilder(shell: .program("/bin/zsh"), isWindows: false)
        #expect(posixBuilder.commandLabel("") == "/bin/zsh")
        #expect(posixBuilder.commandLabel("ls -la") == "/bin/zsh -i -c 'ls -la'")
        #expect(posixBuilder.nonInteractive().commandLabel("ls -la") == "/bin/zsh -c 'ls -la'")

        let pwshBuilder = ShellBuilder(shell: .program("pwsh.exe"), isWindows: true)
        #expect(pwshBuilder.commandLabel("Get-ChildItem") == "pwsh.exe -C 'Get-ChildItem'")

        let cmdBuilder = ShellBuilder(shell: .program("cmd.exe"), isWindows: true)
        #expect(cmdBuilder.commandLabel("dir") == "cmd.exe /C \"dir\"")
    }

    @Test
    func test_build_no_quote_and_redirects() {
        let cmdBuilder = ShellBuilder(shell: .program("cmd.exe"), isWindows: true)
            .redirectStdinToDevNull()
        let (_, cmdArgs) = cmdBuilder.build(taskCommand: "dir", taskArgs: ["/w"])
        #expect(cmdArgs.contains("/C"))
        #expect(cmdArgs.last?.contains("< NUL") == true)

        let pwshBuilder = ShellBuilder(shell: .program("powershell.exe"), isWindows: true)
            .redirectStdinToDevNull()
        let (_, pwshArgs) = pwshBuilder.build(taskCommand: "ls", taskArgs: ["-Force"])
        #expect(pwshArgs.contains("-C"))
        #expect(pwshArgs.last?.contains("$null | & {") == true)

        let noQuoteBuilder = ShellBuilder(shell: .program("bash"), isWindows: false)
        let (_, noQuoteArgs) = noQuoteBuilder.buildNoQuote(taskCommand: "echo", taskArgs: ["$VAR"])
        #expect(noQuoteArgs == ["-i", "-c", "echo $VAR"])
    }
}
