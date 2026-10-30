// Tests ported from: crates/util/src/command/darwin.rs (#[cfg(test)] items)
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

#if os(macOS)

import Testing
import Foundation
@testable import ZedUtil

typealias Command = DarwinCommand
typealias Stdio = DarwinStdio
typealias Child = DarwinChild
typealias ExitStatus = DarwinExitStatus
typealias Output = DarwinOutput

@Suite("Darwin Command & Process Spawning Tests")
struct DarwinCommandTests {
    @Test
    func test_spawn_echo() async throws {
        let output = try await Command.new("/bin/echo")
            .args(["-n", "hello world"])
            .output()

        #expect(output.status.success())
        #expect(output.stdout == Array("hello world".utf8))
    }

    @Test
    func test_spawn_cat_stdin() async throws {
        let child = try Command.new("/bin/cat")
            .stdin(Stdio.piped())
            .stdout(Stdio.piped())
            .spawn()

        if let stdin = child.stdin {
            try await stdin.writeAll(Array("hello from stdin".utf8))
            try await stdin.close()
        }
        child.stdin = nil

        let output = try await child.output()
        #expect(output.status.success())
        #expect(output.stdout == Array("hello from stdin".utf8))
    }

    @Test
    func test_spawn_stderr() async throws {
        let output = try await Command.new("/bin/sh")
            .args(["-c", "echo error >&2"])
            .output()

        #expect(output.status.success())
        #expect(output.stderr == Array("error\n".utf8))
    }

    @Test
    func test_spawn_exit_code() async throws {
        let output = try await Command.new("/bin/sh")
            .args(["-c", "exit 42"])
            .output()

        #expect(!output.status.success())
        #expect(output.status.code() == 42)
    }

    @Test
    func test_spawn_current_dir() async throws {
        let output = try await Command.new("/bin/pwd")
            .currentDir("/tmp")
            .output()

        #expect(output.status.success())
        let pwd = String(decoding: output.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(pwd == "/tmp" || pwd == "/private/tmp")
    }

    @Test
    func test_spawn_env() async throws {
        let output = try await Command.new("/bin/sh")
            .args(["-c", "echo $MY_TEST_VAR"])
            .env("MY_TEST_VAR", "test_value")
            .output()

        #expect(output.status.success())
        let text = String(decoding: output.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(text == "test_value")
    }

    @Test
    func test_spawn_status() async throws {
        let statusTrue = try await Command.new("/usr/bin/true")
            .status()
        #expect(statusTrue.success())

        let statusFalse = try await Command.new("/usr/bin/false")
            .status()
        #expect(!statusFalse.success())
    }

    @Test
    func test_env_remove_removes_set_env() async throws {
        let output = try await Command.new("/bin/sh")
            .args(["-c", "echo ${MY_VAR:-unset}"])
            .env("MY_VAR", "set_value")
            .envRemove("MY_VAR")
            .output()

        #expect(output.status.success())
        let text = String(decoding: output.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(text == "unset")
    }

    @Test
    func test_env_remove_removes_inherited_env() async throws {
        setenv("TEST_INHERITED_VAR", "inherited_value", 1)
        defer { unsetenv("TEST_INHERITED_VAR") }

        let output = try await Command.new("/bin/sh")
            .args(["-c", "echo ${TEST_INHERITED_VAR:-unset}"])
            .envRemove("TEST_INHERITED_VAR")
            .output()

        #expect(output.status.success())
        let text = String(decoding: output.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(text == "unset")
    }

    @Test
    func test_env_after_env_remove() async throws {
        let output = try await Command.new("/bin/sh")
            .args(["-c", "echo ${MY_VAR:-unset}"])
            .envRemove("MY_VAR")
            .env("MY_VAR", "new_value")
            .output()

        #expect(output.status.success())
        let text = String(decoding: output.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(text == "new_value")
    }

    @Test
    func test_env_remove_after_env_clear() async throws {
        let output = try await Command.new("/bin/sh")
            .args(["-c", "echo ${MY_VAR:-unset}"])
            .envClear()
            .env("MY_VAR", "set_value")
            .envRemove("MY_VAR")
            .output()

        #expect(output.status.success())
        let text = String(decoding: output.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(text == "unset")
    }

    @Test
    func test_stdio_null_stdin() async throws {
        let child = try Command.new("/bin/cat")
            .stdin(Stdio.null())
            .stdout(Stdio.piped())
            .spawn()

        let output = try await child.output()
        #expect(output.status.success())
        #expect(output.stdout.isEmpty)
    }

    @Test
    func test_stdio_null_stdout() async throws {
        let child = try Command.new("/bin/echo")
            .args(["hello"])
            .stdout(Stdio.null())
            .spawn()

        #expect(child.stdout == nil)
        let status = try await child.status()
        #expect(status.success())
    }

    @Test
    func test_stdio_null_stderr() async throws {
        let child = try Command.new("/bin/sh")
            .args(["-c", "echo error >&2"])
            .stderr(Stdio.null())
            .spawn()

        #expect(child.stderr == nil)
        let status = try await child.status()
        #expect(status.success())
    }

    @Test
    func test_stdio_piped_stdin() async throws {
        let child = try Command.new("/bin/cat")
            .stdin(Stdio.piped())
            .stdout(Stdio.piped())
            .spawn()

        #expect(child.stdin != nil)

        if let stdin = child.stdin {
            try await stdin.writeAll(Array("piped input".utf8))
            try await stdin.close()
        }
        child.stdin = nil

        let output = try await child.output()
        #expect(output.status.success())
        #expect(output.stdout == Array("piped input".utf8))
    }
}

#endif
