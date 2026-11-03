// Ported from: crates/rune/src/platform/ready_signal.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! A launcher can wait for readiness. With `RUNE_READY_DIR` set, the process writes
//! `$RUNE_READY_DIR/<bundle id>.<pid>` once its first window's `onReady` has returned (or would
//! have, with none), and removes it when it exits normally.

#if !os(WASI)
import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Android)
import Android
#elseif canImport(Musl)
import Musl
#elseif os(Windows)
import ucrt
#endif

let runeReadyPackageVersion = "0.0.1"
private let readyDirEnvVar = "RUNE_READY_DIR"

struct ReadySignalError: Error, CustomStringConvertible, Sendable, Equatable {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
}

private let readySignalLock = NSLock()
// PORT NOTE: Guarded by `readySignalLock`, matching `RUN` and `WRITTEN` in `ready_signal.rs`.
nonisolated(unsafe) private var readyRunStartInstant: RuneInstant? = nil
/// `nil` until the first `onReady`; then `.some(pathOrNil)` for the file written, if any.
// PORT NOTE: Guarded by `readySignalLock`, matching `WRITTEN: Mutex<Option<Option<PathBuf>>>` in `ready_signal.rs`.
nonisolated(unsafe) private var readyWrittenPath: String?? = nil
// PORT NOTE: Guarded by `readySignalLock` to register `atexit` at most once per process.
nonisolated(unsafe) private var readyExitHookRegistered: Bool = false

/// `run` starts the event loop.
func readySignalRunStarts() {
    readySignalLock.lock()
    defer { readySignalLock.unlock() }
    if readyRunStartInstant == nil {
        readyRunStartInstant = .now()
    }
}

/// A window's `onReady` returned. Only the process's first writes the file.
func readySignalReady() {
    readySignalReadyIn(ProcessInfo.processInfo.environment[readyDirEnvVar])
}

func readySignalReadyIn(_ dir: String?) {
    readySignalLock.lock()
    defer { readySignalLock.unlock() }
    if readyWrittenPath != nil {
        return
    }
    guard let dir, !dir.isEmpty else {
        readyWrittenPath = .some(nil)
        return
    }
    let readyMs: UInt64
    if let start = readyRunStartInstant {
        let elapsed = start.elapsed()
        readyMs = UInt64(max(0, elapsed.components.seconds)) * 1000
            + UInt64(max(0, elapsed.components.attoseconds) / 1_000_000_000_000_000)
    } else {
        readyMs = 0
    }
    let signal = ReadySignal(
        pid: UInt32(ProcessInfo.processInfo.processIdentifier),
        bundleId: readySignalBundleId(),
        readyMs: readyMs
    )
    switch signal.writeIn(dir) {
    case .some(.success(let path)):
        registerReadySignalOnExit()
        readyWrittenPath = .some(path)
    case .some(.failure(let error)):
        #if DEBUG
        FileHandle.standardError.write(Data("rune: couldn't write the \(readyDirEnvVar) readiness file: \(error)\n".utf8))
        #else
        _ = error
        #endif
        readyWrittenPath = .some(nil)
    case nil:
        readyWrittenPath = .some(nil)
    }
}

/// Removes the file, if this process wrote one. Runs as the event loop returns and at exit.
func readySignalClear() {
    // At exit, another thread may hold the lock; leaving the file then is what a kill does.
    guard readySignalLock.try() else { return }
    defer { readySignalLock.unlock() }
    if case .some(.some(let path)) = readyWrittenPath {
        readyWrittenPath = .some(nil)
        try? FileManager.default.removeItem(atPath: path)
    }
}

func readySignalResetForTests() {
    readySignalLock.lock()
    defer { readySignalLock.unlock() }
    readyWrittenPath = nil
}

/// What the file says.
struct ReadySignal: Sendable, Equatable {
    var pid: UInt32
    var bundleId: String
    var readyMs: UInt64

    func json() -> String {
        let idJson: String
        if let encoded = try? JSONEncoder().encode(bundleId),
           let s = String(data: encoded, encoding: .utf8)
        {
            idJson = s
        } else {
            idJson = "\"\""
        }
        return "{\"pid\":\(pid),\"bundle_id\":\(idJson),\"ready_ms\":\(readyMs),\"rune\":\"\(runeReadyPackageVersion)\"}"
    }

    /// Writes the file into `dir`, made 0700 if it's missing, through a temporary file renamed
    /// over it. Nothing without a `dir`.
    func writeIn(_ dir: String?) -> Result<String, ReadySignalError>? {
        guard let dir, !dir.isEmpty else { return nil }
        do {
            let fm = FileManager.default
            let dirExisted = fm.fileExists(atPath: dir)
            try fm.createDirectory(
                atPath: dir,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: NSNumber(value: Int16(0o700))]
            )
            #if !os(Windows)
            if !dirExisted {
                _ = dir.withCString { chmod($0, 0o700) }
            }
            #endif
            let sanitized = bundleId
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "\\", with: "_")
            let name = "\(sanitized).\(pid)"
            let dirURL = URL(fileURLWithPath: dir, isDirectory: true)
            let pathURL = dirURL.appendingPathComponent(name)
            let tempURL = dirURL.appendingPathComponent(".\(name).tmp")
            let payload = Data("\(json())\n".utf8)
            try payload.write(to: tempURL)
            #if os(Windows)
            if fm.fileExists(atPath: pathURL.path) {
                try? fm.removeItem(at: pathURL)
            }
            do {
                try fm.moveItem(at: tempURL, to: pathURL)
            } catch {
                try? fm.removeItem(at: tempURL)
                throw error
            }
            #else
            let renamed = tempURL.path.withCString { src in
                pathURL.path.withCString { dst in
                    rename(src, dst)
                }
            }
            if renamed != 0 {
                try? fm.removeItem(at: tempURL)
                return .failure(ReadySignalError("rename failed with errno \(errno)"))
            }
            #endif
            return .success(pathURL.path)
        } catch {
            return .failure(ReadySignalError("\(error)"))
        }
    }
}

/// The main bundle's identifier on macOS, else the executable's name.
func readySignalBundleId() -> String {
    #if os(macOS)
    if let id = Bundle.main.bundleIdentifier, !id.isEmpty {
        return id
    }
    #endif
    if let arg0 = CommandLine.arguments.first, !arg0.isEmpty {
        let name = URL(fileURLWithPath: arg0).lastPathComponent
        if !name.isEmpty {
            return name
        }
    }
    return "rune-app"
}

private func readySignalAtExitCallback() {
    readySignalClear()
}

/// Removes the file when the process exits through `exit`, as AppKit's Quit does.
private func registerReadySignalOnExit() {
    #if !os(Windows)
    if !readyExitHookRegistered {
        readyExitHookRegistered = true
        atexit(readySignalAtExitCallback)
    }
    #endif
}
#else
func readySignalRunStarts() {}
func readySignalReady() {}
func readySignalClear() {}
#endif
