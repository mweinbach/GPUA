// Ported from: crates/util/src/command/darwin.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

#if os(macOS)

import Darwin
import Foundation
import MachO

@_silgen_name("_NSGetEnviron")
private func _NSGetEnviron() -> UnsafeMutablePointer<UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>>

public enum DarwinStdio: Sendable, Equatable {
    case piped
    case inherit
    case null

    public static func piped() -> DarwinStdio { .piped }
    public static func inherit() -> DarwinStdio { .inherit }
    public static func null() -> DarwinStdio { .null }
}

public struct DarwinExitStatus: Sendable, Equatable {
    public let raw: Int32

    public init(raw: Int32) {
        self.raw = raw
    }

    public static func fromRaw(_ raw: Int32) -> DarwinExitStatus {
        DarwinExitStatus(raw: raw)
    }

    public func success() -> Bool {
        ((raw & 0x7f) == 0) && (((raw >> 8) & 0xff) == 0)
    }

    public func code() -> Int32? {
        if (raw & 0x7f) == 0 {
            return (raw >> 8) & 0xff
        }
        return nil
    }
}

public struct DarwinOutput: Sendable, Equatable {
    public let status: DarwinExitStatus
    public let stdout: [UInt8]
    public let stderr: [UInt8]

    public init(status: DarwinExitStatus, stdout: [UInt8], stderr: [UInt8]) {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
    }
}

// PORT NOTE: DarwinChildFile is @unchecked Sendable because access to its raw file descriptor and closed state is synchronized via NSLock.
public final class DarwinChildFile: @unchecked Sendable {
    public let fd: Int32
    private var isClosed: Bool = false
    private let lock = NSLock()

    public init(fd: Int32) {
        self.fd = fd
    }

    deinit {
        closeSync()
    }

    private func synchronized<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    public func writeAll(_ bytes: [UInt8]) async throws {
        try await Task.detached {
            try self.writeSync(bytes)
        }.value
    }

    public func writeAll(_ data: Data) async throws {
        try await writeAll(Array(data))
    }

    public func writeSync(_ bytes: [UInt8]) throws {
        try synchronized {
            guard !isClosed else {
                throw POSIXError(.EBADF)
            }
            var written = 0
            while written < bytes.count {
                let res = bytes.withUnsafeBufferPointer { ptr in
                    Darwin.write(fd, ptr.baseAddress! + written, bytes.count - written)
                }
                if res < 0 {
                    let err = errno
                    if err == EINTR { continue }
                    throw POSIXError(POSIXErrorCode(rawValue: err) ?? .EIO)
                }
                written += res
            }
        }
    }

    public func close() async throws {
        closeSync()
    }

    public func closeSync() {
        synchronized {
            guard !isClosed else { return }
            isClosed = true
            Darwin.close(fd)
        }
    }

    public func readToEnd() async throws -> [UInt8] {
        try await Task.detached {
            var buffer = [UInt8]()
            var chunk = [UInt8](repeating: 0, count: 4096)
            while true {
                let shouldContinue: Bool = self.synchronized {
                    !self.isClosed
                }
                guard shouldContinue else { break }

                let res = Darwin.read(self.fd, &chunk, chunk.count)
                if res < 0 {
                    let err = errno
                    if err == EINTR { continue }
                    throw POSIXError(POSIXErrorCode(rawValue: err) ?? .EIO)
                }
                if res == 0 { break }
                buffer.append(contentsOf: chunk[0..<res])
            }
            self.closeSync()
            return buffer
        }.value
    }
}

// PORT NOTE: DarwinChild is @unchecked Sendable because process state, child descriptors, and termination status are synchronized via NSLock.
public final class DarwinChild: @unchecked Sendable {
    public let pid: pid_t
    public var stdin: DarwinChildFile?
    public var stdout: DarwinChildFile?
    public var stderr: DarwinChildFile?
    public var killOnDrop: Bool
    private var cachedStatus: DarwinExitStatus?
    private let lock = NSLock()

    public init(
        pid: pid_t,
        stdin: DarwinChildFile?,
        stdout: DarwinChildFile?,
        stderr: DarwinChildFile?,
        killOnDrop: Bool
    ) {
        self.pid = pid
        self.stdin = stdin
        self.stdout = stdout
        self.stderr = stderr
        self.killOnDrop = killOnDrop
    }

    deinit {
        let shouldKill = synchronized { killOnDrop && cachedStatus == nil }
        if shouldKill {
            _ = kill()
        }
    }

    private func synchronized<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    public func id() -> UInt32 {
        UInt32(pid)
    }

    @discardableResult
    public func kill() -> Result<Void, POSIXError> {
        let res = Darwin.kill(pid, SIGKILL)
        if res == -1 {
            return .failure(POSIXError(POSIXErrorCode(rawValue: errno) ?? .EPERM))
        }
        return .success(())
    }

    public func tryStatus() throws -> DarwinExitStatus? {
        try synchronized {
            if let s = cachedStatus { return s }

            var status: Int32 = 0
            let res = Darwin.waitpid(pid, &status, WNOHANG)
            if res == -1 {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .ECHILD)
            } else if res == 0 {
                return nil
            } else {
                let exitStatus = DarwinExitStatus(raw: status)
                cachedStatus = exitStatus
                return exitStatus
            }
        }
    }

    public func status() async throws -> DarwinExitStatus {
        let (statusCopy, childPid): (DarwinExitStatus?, pid_t) = synchronized {
            stdin?.closeSync()
            stdin = nil
            return (cachedStatus, pid)
        }

        if let s = statusCopy {
            return s
        }

        return try await Task.detached { [weak self] in
            var status: Int32 = 0
            let res = Darwin.waitpid(childPid, &status, 0)
            if res == -1 {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .ECHILD)
            }
            let exitStatus = DarwinExitStatus(raw: status)
            self?.synchronized {
                self?.cachedStatus = exitStatus
            }
            return exitStatus
        }.value
    }

    public func output() async throws -> DarwinOutput {
        let (outReader, errReader): (DarwinChildFile?, DarwinChildFile?) = synchronized {
            let o = stdout
            let e = stderr
            stdout = nil
            stderr = nil
            return (o, e)
        }

        async let stdoutBytes = outReader?.readToEnd() ?? []
        async let stderrBytes = errReader?.readToEnd() ?? []
        async let exitStatus = status()

        let (out, err, st) = try await (stdoutBytes, stderrBytes, exitStatus)
        return DarwinOutput(status: st, stdout: out, stderr: err)
    }
}

// PORT NOTE: DarwinCommand is @unchecked Sendable because it configures builder arguments and env vars before spawning a posix process.
public final class DarwinCommand: @unchecked Sendable {
    private var program: String
    private var argsList: [String] = []
    private var envs: [String: String?] = [:]
    private var isEnvClear: Bool = false
    private var currentDirPath: String?
    private var stdinConfig: DarwinStdio?
    private var stdoutConfig: DarwinStdio?
    private var stderrConfig: DarwinStdio?
    private var isKillOnDrop: Bool = false

    public init(_ program: String) {
        self.program = program
    }

    public static func new(_ program: String) -> DarwinCommand {
        DarwinCommand(program)
    }

    @discardableResult
    public func arg(_ arg: String) -> DarwinCommand {
        argsList.append(arg)
        return self
    }

    @discardableResult
    public func args<S: Sequence>(_ args: S) -> DarwinCommand where S.Element == String {
        argsList.append(contentsOf: args)
        return self
    }

    @discardableResult
    public func env(_ key: String, _ val: String) -> DarwinCommand {
        envs[key] = val
        return self
    }

    @discardableResult
    public func envs<S: Sequence>(_ vars: S) -> DarwinCommand where S.Element == (String, String) {
        for (k, v) in vars {
            envs[k] = v
        }
        return self
    }

    @discardableResult
    public func envRemove(_ key: String) -> DarwinCommand {
        if isEnvClear {
            envs.removeValue(forKey: key)
        } else {
            envs[key] = Optional<String>.none
        }
        return self
    }

    @discardableResult
    public func env_remove(_ key: String) -> DarwinCommand {
        envRemove(key)
    }

    @discardableResult
    public func envClear() -> DarwinCommand {
        isEnvClear = true
        envs.removeAll()
        return self
    }

    @discardableResult
    public func env_clear() -> DarwinCommand {
        envClear()
    }

    @discardableResult
    public func currentDir(_ dir: String) -> DarwinCommand {
        currentDirPath = dir
        return self
    }

    @discardableResult
    public func current_dir(_ dir: String) -> DarwinCommand {
        currentDir(dir)
    }

    @discardableResult
    public func stdin(_ cfg: DarwinStdio) -> DarwinCommand {
        stdinConfig = cfg
        return self
    }

    @discardableResult
    public func stdout(_ cfg: DarwinStdio) -> DarwinCommand {
        stdoutConfig = cfg
        return self
    }

    @discardableResult
    public func stderr(_ cfg: DarwinStdio) -> DarwinCommand {
        stderrConfig = cfg
        return self
    }

    @discardableResult
    public func killOnDrop(_ killOnDrop: Bool) -> DarwinCommand {
        isKillOnDrop = killOnDrop
        return self
    }

    @discardableResult
    public func kill_on_drop(_ killOnDrop: Bool) -> DarwinCommand {
        self.killOnDrop(killOnDrop)
    }

    public func spawn() throws -> DarwinChild {
        let cwd = currentDirPath ?? "."

        guard !program.contains("\0"), !cwd.contains("\0") else {
            throw POSIXError(.EINVAL)
        }
        for arg in argsList {
            guard !arg.contains("\0") else {
                throw POSIXError(.EINVAL)
            }
        }

        let progCStr = strdup(program)
        defer { free(progCStr) }

        var argvPtrs = [UnsafeMutablePointer<CChar>?]()
        argvPtrs.append(progCStr)
        for arg in argsList {
            argvPtrs.append(strdup(arg))
        }
        argvPtrs.append(nil)
        defer {
            for ptr in argvPtrs.dropFirst() {
                if let p = ptr { free(p) }
            }
        }

        // Environment variables
        var envPtrs: [UnsafeMutablePointer<CChar>?]? = nil
        if isEnvClear || !envs.isEmpty {
            var fullEnv = [String: String]()
            if !isEnvClear {
                fullEnv = ProcessInfo.processInfo.environment
            }
            for (key, val) in envs {
                if let v = val {
                    fullEnv[key] = v
                } else {
                    fullEnv.removeValue(forKey: key)
                }
            }
            var list = [UnsafeMutablePointer<CChar>?]()
            for (k, v) in fullEnv {
                list.append(strdup("\(k)=\(v)"))
            }
            list.append(nil)
            envPtrs = list
        }
        defer {
            if let envPtrs = envPtrs {
                for ptr in envPtrs {
                    if let p = ptr { free(p) }
                }
            }
        }

        // Setup pipes / file redirection
        let inCfg = stdinConfig ?? .piped
        let outCfg = stdoutConfig ?? .piped
        let errCfg = stderrConfig ?? .piped

        var stdinReadFd: Int32? = nil
        var stdinWriteFd: Int32? = nil
        switch inCfg {
        case .piped:
            let (r, w) = try createPipe()
            stdinReadFd = r
            stdinWriteFd = w
        case .null:
            let fd = try openDevNull(flags: O_RDONLY)
            stdinReadFd = fd
        case .inherit:
            break
        }

        var stdoutReadFd: Int32? = nil
        var stdoutWriteFd: Int32? = nil
        switch outCfg {
        case .piped:
            let (r, w) = try createPipe()
            stdoutReadFd = r
            stdoutWriteFd = w
        case .null:
            let fd = try openDevNull(flags: O_WRONLY)
            stdoutWriteFd = fd
        case .inherit:
            break
        }

        var stderrReadFd: Int32? = nil
        var stderrWriteFd: Int32? = nil
        switch errCfg {
        case .piped:
            let (r, w) = try createPipe()
            stderrReadFd = r
            stderrWriteFd = w
        case .null:
            let fd = try openDevNull(flags: O_WRONLY)
            stderrWriteFd = fd
        case .inherit:
            break
        }

        var attr: posix_spawnattr_t? = nil
        var fileActions: posix_spawn_file_actions_t? = nil

        posix_spawnattr_init(&attr)
        posix_spawn_file_actions_init(&fileActions)

        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT))

        let excMaskAll: exception_mask_t = ((1 << 1) | (1 << 2) | (1 << 3) | (1 << 4) | (1 << 5) | (1 << 6) | (1 << 7) | (1 << 8) | (1 << 9) | (1 << 11) | (1 << 12) | 0)
        posix_spawnattr_setexceptionports_np(
            &attr,
            excMaskAll,
            mach_port_t(MACH_PORT_NULL),
            EXCEPTION_DEFAULT,
            THREAD_STATE_NONE
        )

        posix_spawn_file_actions_addchdir_np(&fileActions, cwd)

        if let fd = stdinReadFd {
            posix_spawn_file_actions_adddup2(&fileActions, fd, STDIN_FILENO)
            posix_spawn_file_actions_addinherit_np(&fileActions, STDIN_FILENO)
        }
        if let fd = stdoutWriteFd {
            posix_spawn_file_actions_adddup2(&fileActions, fd, STDOUT_FILENO)
            posix_spawn_file_actions_addinherit_np(&fileActions, STDOUT_FILENO)
        }
        if let fd = stderrWriteFd {
            posix_spawn_file_actions_adddup2(&fileActions, fd, STDERR_FILENO)
            posix_spawn_file_actions_addinherit_np(&fileActions, STDERR_FILENO)
        }

        var pid: pid_t = 0
        let spawnResult: Int32
        if var customEnv = envPtrs {
            spawnResult = customEnv.withUnsafeMutableBufferPointer { envBuffer in
                argvPtrs.withUnsafeMutableBufferPointer { argvBuffer in
                    posix_spawnp(
                        &pid,
                        progCStr,
                        &fileActions,
                        &attr,
                        argvBuffer.baseAddress!,
                        envBuffer.baseAddress!
                    )
                }
            }
        } else {
            spawnResult = argvPtrs.withUnsafeMutableBufferPointer { argvBuffer in
                posix_spawnp(
                    &pid,
                    progCStr,
                    &fileActions,
                    &attr,
                    argvBuffer.baseAddress!,
                    _NSGetEnviron().pointee
                )
            }
        }

        posix_spawnattr_destroy(&attr)
        posix_spawn_file_actions_destroy(&fileActions)

        // Close child-side descriptors in parent
        if let fd = stdinReadFd { Darwin.close(fd) }
        if let fd = stdoutWriteFd { Darwin.close(fd) }
        if let fd = stderrWriteFd { Darwin.close(fd) }

        if spawnResult != 0 {
            if let fd = stdinWriteFd { Darwin.close(fd) }
            if let fd = stdoutReadFd { Darwin.close(fd) }
            if let fd = stderrReadFd { Darwin.close(fd) }
            throw POSIXError(POSIXErrorCode(rawValue: spawnResult) ?? .EIO)
        }

        return DarwinChild(
            pid: pid,
            stdin: stdinWriteFd.map { DarwinChildFile(fd: $0) },
            stdout: stdoutReadFd.map { DarwinChildFile(fd: $0) },
            stderr: stderrReadFd.map { DarwinChildFile(fd: $0) },
            killOnDrop: isKillOnDrop
        )
    }

    public func output() async throws -> DarwinOutput {
        if stdinConfig == nil { stdinConfig = .null }
        if stdoutConfig == nil { stdoutConfig = .piped }
        if stderrConfig == nil { stderrConfig = .piped }

        let child = try spawn()
        return try await child.output()
    }

    public func status() async throws -> DarwinExitStatus {
        let child = try spawn()
        return try await child.status()
    }

    private func createPipe() throws -> (Int32, Int32) {
        var fds: [Int32] = [0, 0]
        let res = pipe(&fds)
        if res == -1 {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        return (fds[0], fds[1])
    }

    private func openDevNull(flags: Int32) throws -> Int32 {
        let fd = Darwin.open("/dev/null", flags)
        if fd == -1 {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        return fd
    }
}

public enum DarwinProcess {
    public typealias Command = DarwinCommand
    public typealias Child = DarwinChild
    public typealias Stdio = DarwinStdio
    public typealias ExitStatus = DarwinExitStatus
    public typealias Output = DarwinOutput
    public typealias ChildFile = DarwinChildFile
}

#endif
