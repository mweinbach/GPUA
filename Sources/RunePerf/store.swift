// Ported from: crates/rune-perf/src/store.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Foundation
import Procwatch
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Android)
import Android
#elseif canImport(WASILibc)
import WASILibc
#elseif canImport(WinSDK)
import WinSDK
#endif

internal let LOG_BYTES: UInt64 = 4 << 20
internal let INCIDENT_BYTES: Int = 256 << 10
internal let SNAPSHOT_EVERY: Duration = .seconds(2)

@inline(__always)
private func storeCurrentPid() -> Int32 {
    #if os(WASI)
    return 1
    #elseif os(Windows)
    return Int32(bitPattern: GetCurrentProcessId())
    #else
    return Int32(getpid())
    #endif
}

@inline(__always)
private func nowMs() -> UInt64 {
    let interval = Date().timeIntervalSince1970
    guard interval > 0 else { return 0 }
    return UInt64(interval * 1000.0)
}

@inline(__always)
private func elapsedMs(since start: ContinuousClock.Instant) -> UInt64 {
    let now = ContinuousClock.now
    guard now >= start else { return 0 }
    let (secs, attos) = start.duration(to: now).components
    return UInt64(max(0, secs * 1000 + attos / 1_000_000_000_000_000))
}

@inline(__always)
private func saturatingDurationUntil(_ target: ContinuousClock.Instant) -> Duration {
    let now = ContinuousClock.now
    return target > now ? now.duration(to: target) : .zero
}

// MARK: - Cross-Platform Per-Handle Advisory Lock (.perf.lock)

internal enum TryLockOutcome {
    case acquired
    case wouldBlock
}

#if os(Windows)
@inline(__always) private func win32StoreOk(_ v: Bool) -> Bool { v }
@inline(__always) private func win32StoreOk(_ v: WindowsBool) -> Bool { v != false }
@inline(__always) private func win32StoreOk(_ v: Int32) -> Bool { v != 0 }
#endif

// PORT NOTE: Wraps OS per-open-file-description lock (`flock` on Unix, `LockFileEx` on Windows) matching Rust `std::fs::File::try_lock`.
internal final class LockFile: @unchecked Sendable {
    #if os(Windows)
    private var handle: HANDLE?
    #elseif !os(WASI)
    private var fd: Int32 = -1
    #endif

    init(opening path: URL) throws {
        #if os(WASI)
        _ = path
        #elseif os(Windows)
        let widePath = Array(path.path.utf16) + [0]
        let h = widePath.withUnsafeBufferPointer { ptr in
            CreateFileW(
                ptr.baseAddress,
                DWORD(GENERIC_READ | GENERIC_WRITE),
                DWORD(FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE),
                nil,
                DWORD(OPEN_ALWAYS),
                DWORD(FILE_ATTRIBUTE_NORMAL),
                nil
            )
        }
        guard let h, h != INVALID_HANDLE_VALUE else {
            throw RunePerfError.ioError("failed to open lock file \(path.path)")
        }
        self.handle = h
        #else
        let opened = open(path.path, O_CREAT | O_RDWR, mode_t(0o666))
        guard opened >= 0 else {
            throw RunePerfError.ioError("open(\(path.path)) failed with errno \(errno)")
        }
        self.fd = opened
        #endif
    }

    func lockBlocking() throws {
        #if os(WASI)
        return
        #elseif os(Windows)
        guard let handle else { throw RunePerfError.ioError("closed lock handle") }
        var overlapped = OVERLAPPED()
        guard win32StoreOk(LockFileEx(handle, DWORD(LOCKFILE_EXCLUSIVE_LOCK), 0, UInt32.max, UInt32.max, &overlapped)) else {
            throw RunePerfError.ioError("LockFileEx failed with \(GetLastError())")
        }
        #else
        while true {
            if flock(fd, LOCK_EX) == 0 {
                return
            }
            if errno == EINTR {
                continue
            }
            throw RunePerfError.ioError("flock(LOCK_EX) failed with errno \(errno)")
        }
        #endif
    }

    func tryLock() throws -> TryLockOutcome {
        #if os(WASI)
        return .acquired
        #elseif os(Windows)
        guard let handle else { throw RunePerfError.ioError("closed lock handle") }
        var overlapped = OVERLAPPED()
        if win32StoreOk(LockFileEx(
            handle,
            DWORD(LOCKFILE_EXCLUSIVE_LOCK | LOCKFILE_FAIL_IMMEDIATELY),
            0,
            UInt32.max,
            UInt32.max,
            &overlapped
        )) {
            return .acquired
        }
        let err = GetLastError()
        if err == DWORD(ERROR_LOCK_VIOLATION) || err == DWORD(ERROR_IO_PENDING) {
            return .wouldBlock
        }
        throw RunePerfError.ioError("LockFileEx(try) failed with \(err)")
        #else
        while true {
            if flock(fd, LOCK_EX | LOCK_NB) == 0 {
                return .acquired
            }
            let err = errno
            if err == EINTR {
                continue
            }
            if err == EWOULDBLOCK || err == EAGAIN {
                return .wouldBlock
            }
            throw RunePerfError.ioError("flock(LOCK_EX|LOCK_NB) failed with errno \(err)")
        }
        #endif
    }

    func closeHandle() {
        #if os(Windows)
        if let h = handle {
            _ = CloseHandle(h)
            handle = nil
        }
        #elseif !os(WASI)
        if fd >= 0 {
            close(fd)
            fd = -1
        }
        #endif
    }

    deinit {
        closeHandle()
    }
}

internal func acquire(_ lock: LockFile, _ health: Health) throws -> Bool {
    while true {
        if health.isStopped() {
            return false
        }
        switch try lock.tryLock() {
        case .acquired:
            return true
        case .wouldBlock:
            health.waitStop(timeoutMs: 100)
        }
    }
}

// MARK: - Atomic JSON & Rotating Log

private func atomicRenameFile(from tmp: URL, to dest: URL) throws {
    #if os(Windows)
    let wTmp = Array(tmp.path.utf16) + [0]
    let wDest = Array(dest.path.utf16) + [0]
    let ok = wTmp.withUnsafeBufferPointer { pTmp in
        wDest.withUnsafeBufferPointer { pDest in
            MoveFileExW(pTmp.baseAddress, pDest.baseAddress, DWORD(MOVEFILE_REPLACE_EXISTING))
        }
    }
    if !win32StoreOk(ok) {
        throw RunePerfError.ioError("MoveFileExW failed with \(GetLastError())")
    }
    #else
    if rename(tmp.path, dest.path) != 0 {
        throw RunePerfError.ioError("rename(\(tmp.path) -> \(dest.path)) failed with errno \(errno)")
    }
    #endif
}

internal func atomicJson<T: Encodable>(_ dir: URL, _ name: String, _ value: T, _ limit: Int) throws {
    let bytes = try JSONEncoder().encode(value)
    if bytes.count > limit {
        throw RunePerfError.recordExceedsByteCap("performance record exceeds byte cap")
    }
    let tmp = dir.appendingPathComponent(".\(name).tmp")
    let dest = dir.appendingPathComponent(name)
    try bytes.write(to: tmp)
    try atomicRenameFile(from: tmp, to: dest)
}

internal struct Log {
    var dir: URL
    var size: UInt64
    var limit: UInt64

    mutating func append(_ value: JsonValue) throws {
        var line = try JSONEncoder().encode(value)
        line.append(0x0A)
        if UInt64(line.count) > limit {
            throw RunePerfError.recordExceedsByteCap("performance record exceeds log limit")
        }
        let path = dir.appendingPathComponent("perf.log")
        // Re-read actual file size so retries after partial writes cannot exceed the cap.
        if FileManager.default.fileExists(atPath: path.path) {
            let attrs = try FileManager.default.attributesOfItem(atPath: path.path)
            size = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
        } else {
            size = 0
        }

        if size + UInt64(line.count) > limit {
            let rotated = dir.appendingPathComponent("perf.log.1")
            try atomicRenameFile(from: path, to: rotated)
            size = 0
        }

        if !FileManager.default.fileExists(atPath: path.path) {
            try line.write(to: path)
        } else {
            let handle = try FileHandle(forWritingTo: path)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        }

        let updatedAttrs = try FileManager.default.attributesOfItem(atPath: path.path)
        size = (updatedAttrs[.size] as? NSNumber)?.uint64Value ?? UInt64(line.count)
    }
}

private func usageJson(_ u: Usage) -> JsonValue {
    .object([
        "resident_bytes": u.resident.map { .uint($0) } ?? .null,
        "footprint_bytes": u.footprint.map { .uint($0) } ?? .null,
        "peak_footprint_bytes": u.footprintPeak.map { .uint($0) } ?? .null,
        "open_fds": u.fds.map { .uint(UInt64($0)) } ?? .null,
    ])
}

// MARK: - Writer & PerfStore

internal struct Writer {
    let config: Config
    let health: Health
    let start: ContinuousClock.Instant
    let launch: String
    let startedAt: UInt64
    var stats: Stats
    var detector: Detector
    var log: Log
    var memoryAt: UInt64
    var incidents: UInt64
    var hookDropped: UInt64

    init(_ config: Config, _ start: ContinuousClock.Instant, _ health: Health) {
        let elapsed = elapsedMs(since: start)
        let currentWall = nowMs()
        let startedAt = currentWall >= elapsed ? (currentWall - elapsed) : 0
        let pid = storeCurrentPid()
        let perfLogPath = config.directory.appendingPathComponent("perf.log").path
        let initialSize: UInt64
        if let attrs = try? FileManager.default.attributesOfItem(atPath: perfLogPath),
           let num = attrs[.size] as? NSNumber
        {
            initialSize = num.uint64Value
        } else {
            initialSize = 0
        }
        self.config = config
        self.health = health
        self.start = start
        self.launch = "\(pid)-\(startedAt)"
        self.startedAt = startedAt
        self.stats = Stats()
        self.detector = Detector()
        self.log = Log(dir: config.directory, size: initialSize, limit: LOG_BYTES)
        self.memoryAt = 0
        self.incidents = 0
        self.hookDropped = 0
    }

    mutating func accept(_ s: Sample) {
        if stats.accept(s) {
            do {
                try log.append(.object([
                    "kind": .string("frame"),
                    "launch": .string(launch),
                    "frame": s.json(),
                ]))
            } catch {
                recordError(error)
            }
        }
        if let f = detector.frame(s, stats) {
            incident(s.atMs, f)
        }
    }

    mutating func incident(_ now: UInt64, _ f: Finding) {
        guard detector.admit(now, f) else { return }
        let record = Incident(
            schema: 1,
            app: config.app,
            build: config.buildIdentity,
            launch: launch,
            pid: storeCurrentPid(),
            createdAtMs: nowMs(),
            rule: f.rule.id(),
            window: f.window,
            source: f.source,
            evidence: f.evidence,
            history: stats.recent.map { $0.json() },
            droppedSamples: health.dropped()
        )
        let slot = incidents % 16
        let slotStr = slot < 10 ? "0\(slot)" : "\(slot)"
        let name = "perf-incident-\(slotStr).json"
        do {
            try atomicJson(config.directory, name, record, INCIDENT_BYTES)
            incidents += 1
            if let hook = config.incidentSender {
                let incidentPath = config.directory.appendingPathComponent(name)
                if !hook.trySend(incidentPath) {
                    hookDropped += 1
                }
            }
        } catch {
            recordError(error)
        }
    }

    mutating func snapshot() {
        let now = elapsedMs(since: start)
        stats.prune(now)
        let memory = Procwatch.usage()
        for f in detector.process(now, memory) {
            incident(now, f)
        }
        let frames = stats.json()
        let snapshotValue: JsonValue = .object([
            "schema": .int(1),
            "recorder_version": .string(RECORDER_VERSION),
            "app": .string(config.app),
            "version": .string(config.buildIdentity),
            "launch": .string(launch),
            "pid": .int(Int64(storeCurrentPid())),
            "started_at_ms": .uint(startedAt),
            "updated_at_ms": .uint(nowMs()),
            "uptime_ms": .uint(now),
            "scope": .string("work_ms = update + compositor wall time; input_to_frame_ms ends at encoding, not presentation; allocation requests are not retained heap"),
            "slow_ms": .double(SLOW_MS),
            "large_bytes": .uint(LARGE_BYTES),
            "memory": usageJson(memory),
            "capabilities": .object([
                "process_memory": .bool(memory.resident != nil),
                "file_descriptors": .bool(memory.fds != nil),
                "ui_allocations": .bool(!frames["ui_allocated_bytes"].isNull),
                "input_to_frame": .bool(!frames["input_to_frame_ms"].isNull),
                "gpu_timestamps": .bool(!frames["gpu_ms"].isNull),
                "presentation": .bool(false),
            ]),
            "dropped_samples": .uint(health.dropped()),
            "write_errors": .uint(health.errors()),
            "incidents": .uint(incidents),
            "incidents_suppressed": .uint(detector.suppressed),
            "incident_notifications_dropped": .uint(hookDropped),
            "frames": frames,
        ])
        do {
            try atomicJson(config.directory, "perf.json", snapshotValue, INCIDENT_BYTES)
        } catch {
            recordError(error)
        }

        if now >= memoryAt {
            do {
                try log.append(.object([
                    "kind": .string("memory"),
                    "at_ms": .uint(now),
                    "launch": .string(launch),
                    "memory": usageJson(memory),
                ]))
            } catch {
                recordError(error)
            }
            memoryAt = now + 30_000
        }
    }

    private func recordError(_ err: any Error) {
        if health.fetchAddError() == 0 {
            FileHandle.standardError.write(Data("rune-perf: write failed: \(err)\n".utf8))
        }
    }
}

/// Bounded local persistence store for ``Recorder``.
public enum PerfStore {
    public static let logBytes: UInt64 = LOG_BYTES
    public static let incidentBytes: Int = INCIDENT_BYTES
    public static let snapshotEvery: Duration = SNAPSHOT_EVERY

    internal static func run(
        _ config: Config,
        _ rx: SyncReceiver<Sample>,
        _ start: ContinuousClock.Instant,
        _ health: Health
    ) throws {
        try FileManager.default.createDirectory(at: config.directory, withIntermediateDirectories: true)
        let lockPath = config.directory.appendingPathComponent(".perf.lock")
        let lock = try LockFile(opening: lockPath)
        defer { lock.closeHandle() }
        guard try acquire(lock, health) else {
            return
        }
        var writer = Writer(config, start, health)
        var next = ContinuousClock.now
        while true {
            switch rx.recvTimeout(saturatingDurationUntil(next)) {
            case .value(let s):
                writer.accept(s)
            case .disconnected:
                writer.snapshot()
                return
            case .timeout:
                break
            }
            if ContinuousClock.now >= next {
                writer.snapshot()
                next = ContinuousClock.now + SNAPSHOT_EVERY
            }
        }
    }
}
