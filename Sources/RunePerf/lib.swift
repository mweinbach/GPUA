// Ported from: crates/rune-perf/src/lib.rs
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
#elseif canImport(WinSDK)
import WinSDK
#endif

internal let QUEUE: Int = 256
internal let RECENT: Int = 600
internal let WINDOW_MS: UInt64 = 60_000
internal let SLOW_MS: Double = 1000.0 / 60.0
internal let LARGE_BYTES: UInt64 = 8 << 20
internal let RECORDER_VERSION: String = "0.1.0"

// MARK: - JSON Value (Codable)

/// Schema-faithful JSON value encoded and decoded via `Foundation`'s `Codable`.
public enum JsonValue: Codable, Equatable, Sendable, CustomStringConvertible {
    case null
    case bool(Bool)
    case int(Int64)
    case uint(UInt64)
    case double(Double)
    case string(String)
    case array([JsonValue])
    case object([String: JsonValue])

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let i = try? container.decode(Int64.self) {
            self = .int(i)
        } else if let u = try? container.decode(UInt64.self) {
            self = .uint(u)
        } else if let d = try? container.decode(Double.self) {
            self = .double(d)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let arr = try? container.decode([JsonValue].self) {
            self = .array(arr)
        } else if let obj = try? container.decode([String: JsonValue].self) {
            self = .object(obj)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let b):
            try container.encode(b)
        case .int(let i):
            try container.encode(i)
        case .uint(let u):
            try container.encode(u)
        case .double(let d):
            try container.encode(d)
        case .string(let s):
            try container.encode(s)
        case .array(let arr):
            try container.encode(arr)
        case .object(let obj):
            try container.encode(obj)
        }
    }

    public static func == (lhs: JsonValue, rhs: JsonValue) -> Bool {
        switch (lhs, rhs) {
        case (.null, .null):
            return true
        case (.bool(let a), .bool(let b)):
            return a == b
        case (.string(let a), .string(let b)):
            return a == b
        case (.array(let a), .array(let b)):
            return a == b
        case (.object(let a), .object(let b)):
            return a == b
        case (.int(let a), .int(let b)):
            return a == b
        case (.uint(let a), .uint(let b)):
            return a == b
        case (.int(let a), .uint(let b)):
            return a >= 0 && UInt64(a) == b
        case (.uint(let a), .int(let b)):
            return b >= 0 && a == UInt64(b)
        case (.double(let a), .double(let b)):
            return a == b
        case (.int(let a), .double(let b)), (.double(let b), .int(let a)):
            return Double(a) == b
        case (.uint(let a), .double(let b)), (.double(let b), .uint(let a)):
            return Double(a) == b
        default:
            return false
        }
    }

    public var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    public var asArray: [JsonValue]? {
        if case .array(let arr) = self { return arr }
        return nil
    }

    public var asObject: [String: JsonValue]? {
        if case .object(let obj) = self { return obj }
        return nil
    }

    public subscript(_ key: String) -> JsonValue {
        if case .object(let obj) = self, let v = obj[key] {
            return v
        }
        return .null
    }

    public subscript(_ index: Int) -> JsonValue {
        if case .array(let arr) = self, index >= 0 && index < arr.count {
            return arr[index]
        }
        return .null
    }

    public var description: String {
        guard let data = try? JSONEncoder().encode(self),
              let str = String(data: data, encoding: .utf8)
        else {
            return "null"
        }
        return str
    }
}

// MARK: - Bounded Sync Channel

public enum RecvTimeoutResult<T: Sendable>: Sendable {
    case value(T)
    case timeout
    case disconnected
}

// PORT NOTE: Synchronized via internal NSCondition over a fixed-capacity ring buffer so `trySend` never allocates.
internal final class BoundedChannelCore<T: Sendable>: @unchecked Sendable {
    private let condition = NSCondition()
    private let capacity: Int
    private var buffer: [T?]
    private var head: Int = 0
    private var tail: Int = 0
    private var count: Int = 0
    private var senderCount: Int = 1
    private var receiverOpen: Bool = true
    private var waitingReceivers: Int = 0

    init(capacity: Int) {
        let cap = max(1, capacity)
        self.capacity = cap
        self.buffer = Array(repeating: nil, count: cap)
    }

    func retainSender() {
        condition.lock()
        senderCount += 1
        condition.unlock()
    }

    func releaseSender() {
        condition.lock()
        if senderCount > 0 {
            senderCount -= 1
        }
        let wake = (senderCount == 0 && waitingReceivers > 0)
        if wake {
            condition.broadcast()
        }
        condition.unlock()
    }

    func closeAllSenders() {
        condition.lock()
        senderCount = 0
        if waitingReceivers > 0 {
            condition.broadcast()
        }
        condition.unlock()
    }

    func closeReceiver() {
        condition.lock()
        receiverOpen = false
        condition.unlock()
    }

    @inline(__always)
    func trySend(_ item: T) -> Bool {
        condition.lock()
        guard receiverOpen, senderCount > 0, count < capacity else {
            condition.unlock()
            return false
        }
        buffer[tail] = item
        tail += 1
        if tail == capacity { tail = 0 }
        count += 1
        if waitingReceivers > 0 {
            condition.signal()
        }
        condition.unlock()
        return true
    }

    func tryRecv() -> T? {
        condition.lock()
        guard count > 0 else {
            condition.unlock()
            return nil
        }
        let item = buffer[head]
        buffer[head] = nil
        head += 1
        if head == capacity { head = 0 }
        count -= 1
        condition.unlock()
        return item
    }

    func recv() -> T? {
        condition.lock()
        defer { condition.unlock() }
        while count == 0 {
            if senderCount == 0 {
                return nil
            }
            waitingReceivers += 1
            condition.wait()
            waitingReceivers -= 1
        }
        let item = buffer[head]
        buffer[head] = nil
        head += 1
        if head == capacity { head = 0 }
        count -= 1
        return item
    }

    func recvTimeout(_ timeout: Duration) -> RecvTimeoutResult<T> {
        let (secs, attos) = timeout.components
        let totalSecs = Double(secs) + Double(attos) * 1e-18
        let deadline = Date(timeIntervalSinceNow: max(0.0, totalSecs))

        condition.lock()
        defer { condition.unlock() }
        while count == 0 {
            if senderCount == 0 {
                return .disconnected
            }
            if Date() >= deadline {
                return .timeout
            }
            waitingReceivers += 1
            _ = condition.wait(until: deadline)
            waitingReceivers -= 1
        }
        let item = buffer[head]!
        buffer[head] = nil
        head += 1
        if head == capacity { head = 0 }
        count -= 1
        return .value(item)
    }

    func drainAvailable() -> [T] {
        condition.lock()
        var out: [T] = []
        out.reserveCapacity(count)
        while count > 0 {
            if let item = buffer[head] {
                out.append(item)
                buffer[head] = nil
            }
            head += 1
            if head == capacity { head = 0 }
            count -= 1
        }
        condition.unlock()
        return out
    }
}

// PORT NOTE: Ref-counted sender token releasing its sender registration on deinit.
private final class SenderRegistration<T: Sendable>: @unchecked Sendable {
    let core: BoundedChannelCore<T>
    private let lock = NSLock()
    private var closed = false

    init(core: BoundedChannelCore<T>) {
        self.core = core
    }

    func close() {
        var shouldRelease = false
        lock.lock()
        if !closed {
            closed = true
            shouldRelease = true
        }
        lock.unlock()
        if shouldRelease {
            core.releaseSender()
        }
    }

    deinit {
        close()
    }
}

/// Bounded non-blocking channel sender, mirroring Rust's `std::sync::mpsc::SyncSender<T>`.
public struct SyncSender<T: Sendable>: Sendable {
    private let registration: SenderRegistration<T>

    fileprivate init(core: BoundedChannelCore<T>) {
        self.registration = SenderRegistration(core: core)
    }

    /// Clones a new sender registration onto the same bounded channel.
    public func clone() -> SyncSender<T> {
        registration.core.retainSender()
        return SyncSender(core: registration.core)
    }

    @inline(__always)
    @discardableResult
    public func trySend(_ value: T) -> Bool {
        registration.core.trySend(value)
    }

    internal func close() {
        registration.close()
    }
}

/// Bounded channel receiver, mirroring Rust's `std::sync::mpsc::Receiver<T>`.
// PORT NOTE: Receiver wraps BoundedChannelCore and marks receiver closed on deinit.
public final class SyncReceiver<T: Sendable>: @unchecked Sendable {
    private let core: BoundedChannelCore<T>

    fileprivate init(core: BoundedChannelCore<T>) {
        self.core = core
    }

    public func recv() -> T? {
        core.recv()
    }

    public func recvTimeout(_ timeout: Duration) -> RecvTimeoutResult<T> {
        core.recvTimeout(timeout)
    }

    public func tryRecv() -> T? {
        core.tryRecv()
    }

    public func tryIter() -> [T] {
        core.drainAvailable()
    }

    deinit {
        core.closeReceiver()
    }
}

/// Creates a bounded synchronous channel pair `(SyncSender<T>, SyncReceiver<T>)`.
public func syncChannel<T: Sendable>(_ capacity: Int, of _: T.Type = T.self) -> (SyncSender<T>, SyncReceiver<T>) {
    let core = BoundedChannelCore<T>(capacity: capacity)
    return (SyncSender(core: core), SyncReceiver(core: core))
}

// MARK: - Config, Outcome, Frame, Sample

/// One process/launch per directory. Use separate directories for dev and captures.
public struct Config: Sendable {
    public var directory: URL
    public var app: String
    internal var buildIdentity: String
    internal var incidentSender: SyncSender<URL>?

    public init(_ directory: URL, _ app: String) {
        self.directory = directory
        self.app = app
        self.buildIdentity = ""
        self.incidentSender = nil
    }

    public init(_ directory: String, _ app: String) {
        self.init(URL(fileURLWithPath: directory), app)
    }

    public static func new(_ directory: URL, _ app: String) -> Config {
        Config(directory, app)
    }

    public static func new(_ directory: String, _ app: String) -> Config {
        Config(directory, app)
    }

    /// Build identity written into snapshots and incidents, such as a version or commit.
    public func build(_ build: String) -> Config {
        var copy = self
        copy.buildIdentity = build
        return copy
    }

    /// Bounded notification queue for incident paths. A full/disconnected receiver loses a
    /// notification, never the incident file.
    public func incidents(_ tx: SyncSender<URL>) -> Config {
        var copy = self
        copy.incidentSender = tx
        return copy
    }
}

/// Frame completion outcome.
public enum Outcome: String, Codable, Equatable, Hashable, Sendable {
    case drawn = "drawn"
    case unchanged = "unchanged"
    case skipped = "skipped"

    public init() {
        self = .skipped
    }

    public func name() -> String {
        rawValue
    }
}

/// Fixed-size report; an unset measurement is unavailable, never an invented zero.
/// Times describe work, not gaps between frames. The caller owns window/source IDs.
public struct Frame: Equatable, Sendable {
    internal var windowId: UInt64
    internal var seqNum: UInt64
    internal var frameOutcome: Outcome
    internal var updateMsVal: Double?
    internal var renderMsVal: Double?
    internal var inputToFrameMsVal: Double?
    internal var gpuMsVal: Double?
    internal var allocatedBytesVal: UInt64?
    internal var sourceVal: UInt64?

    public init() {
        self.windowId = 0
        self.seqNum = 0
        self.frameOutcome = .skipped
        self.updateMsVal = nil
        self.renderMsVal = nil
        self.inputToFrameMsVal = nil
        self.gpuMsVal = nil
        self.allocatedBytesVal = nil
        self.sourceVal = nil
    }

    public init(_ window: UInt64, _ seq: UInt64, _ outcome: Outcome) {
        self.init()
        self.windowId = window
        self.seqNum = seq
        self.frameOutcome = outcome
    }

    public static func new(_ window: UInt64, _ seq: UInt64, _ outcome: Outcome) -> Frame {
        Frame(window, seq, outcome)
    }

    public func updateMs(_ ms: Double?) -> Frame {
        var copy = self
        copy.updateMsVal = ms
        return copy
    }

    /// Compositor (render and encode) wall time.
    public func renderMs(_ ms: Double?) -> Frame {
        var copy = self
        copy.renderMsVal = ms
        return copy
    }

    /// Input receipt to the encoding boundary, NOT input-to-screen latency.
    public func inputToFrameMs(_ ms: Double?) -> Frame {
        var copy = self
        copy.inputToFrameMsVal = ms
        return copy
    }

    /// Resolved GPU timestamp duration, only when the backend supplies one.
    public func gpuMs(_ ms: Double?) -> Frame {
        var copy = self
        copy.gpuMsVal = ms
        return copy
    }

    /// Successful allocation requests on the reporting thread since its last report,
    /// usually ``takeAllocatedBytes()``.
    public func allocatedBytes(_ bytes: UInt64?) -> Frame {
        var copy = self
        copy.allocatedBytesVal = bytes
        return copy
    }

    /// Stable numeric source identifier; never user text or content.
    public func source(_ id: UInt64?) -> Frame {
        var copy = self
        copy.sourceVal = id
        return copy
    }

    /// Update plus compositor time, when both were measured.
    public func workMs() -> Double? {
        guard let u = updateMsVal, let r = renderMsVal else {
            return nil
        }
        let sum = u + r
        return sum.isFinite ? sum : nil
    }

    internal func sanitize() -> Frame {
        var copy = self
        if let v = copy.updateMsVal, !(v.isFinite && v >= 0.0) { copy.updateMsVal = nil }
        if let v = copy.renderMsVal, !(v.isFinite && v >= 0.0) { copy.renderMsVal = nil }
        if let v = copy.inputToFrameMsVal, !(v.isFinite && v >= 0.0) { copy.inputToFrameMsVal = nil }
        if let v = copy.gpuMsVal, !(v.isFinite && v >= 0.0) { copy.gpuMsVal = nil }
        return copy
    }
}

// MARK: - Per-thread Allocation Delta

private struct PerfTlsBaseline {
    var hasBaseline: Bool = false
    var lastBytes: UInt64 = 0
}

#if os(WASI)
// PORT NOTE: WASI (wasm32-unknown-wasip1) is single-threaded; thread-local baseline maps to static storage.
nonisolated(unsafe) private var wasiAllocatedBaseline = PerfTlsBaseline()

@inline(__always)
private func mutatePerfBaseline<R>(_ body: (inout PerfTlsBaseline) -> R) -> R {
    body(&wasiAllocatedBaseline)
}
#elseif os(Windows)
private let perfTlsIndex: DWORD = {
    let idx = TlsAlloc()
    precondition(idx != TLS_OUT_OF_INDEXES, "RunePerf: TlsAlloc failed")
    return idx
}()

@inline(__always)
private func mutatePerfBaseline<R>(_ body: (inout PerfTlsBaseline) -> R) -> R {
    let ptr: UnsafeMutablePointer<PerfTlsBaseline>
    if let raw = TlsGetValue(perfTlsIndex) {
        ptr = raw.assumingMemoryBound(to: PerfTlsBaseline.self)
    } else {
        ptr = UnsafeMutablePointer<PerfTlsBaseline>.allocate(capacity: 1)
        ptr.initialize(to: PerfTlsBaseline())
        _ = TlsSetValue(perfTlsIndex, UnsafeMutableRawPointer(ptr))
    }
    return body(&ptr.pointee)
}
#else
#if canImport(Darwin)
private func runePerfTlsDestructor(_ raw: UnsafeMutableRawPointer) {
    let ptr = raw.assumingMemoryBound(to: PerfTlsBaseline.self)
    ptr.deinitialize(count: 1)
    ptr.deallocate()
}
#else
private func runePerfTlsDestructor(_ raw: UnsafeMutableRawPointer?) {
    guard let raw else { return }
    let ptr = raw.assumingMemoryBound(to: PerfTlsBaseline.self)
    ptr.deinitialize(count: 1)
    ptr.deallocate()
}
#endif

private let perfTlsKey: pthread_key_t = {
    var key = pthread_key_t()
    let rc = pthread_key_create(&key, runePerfTlsDestructor)
    precondition(rc == 0, "RunePerf: pthread_key_create failed with \(rc)")
    return key
}()

@inline(__always)
private func mutatePerfBaseline<R>(_ body: (inout PerfTlsBaseline) -> R) -> R {
    let ptr: UnsafeMutablePointer<PerfTlsBaseline>
    if let raw = pthread_getspecific(perfTlsKey) {
        ptr = raw.assumingMemoryBound(to: PerfTlsBaseline.self)
    } else {
        ptr = UnsafeMutablePointer<PerfTlsBaseline>.allocate(capacity: 1)
        ptr.initialize(to: PerfTlsBaseline())
        _ = pthread_setspecific(perfTlsKey, UnsafeMutableRawPointer(ptr))
    }
    return body(&ptr.pointee)
}
#endif

/// Bytes this thread asked the allocator for since its previous call, for
/// ``Frame/allocatedBytes(_:)``. Needs `Procwatch.alloc.Counting` active.
/// `nil` when it isn't installed, and on a thread's first call, which only sets the baseline.
/// Never allocates in steady state.
public func takeAllocatedBytes() -> UInt64? {
    guard let now = Procwatch.alloc.threadAllocatedBytes() else {
        return nil
    }
    return mutatePerfBaseline { state in
        if !state.hasBaseline {
            state.hasBaseline = true
            state.lastBytes = now
            return nil
        }
        let prev = state.lastBytes
        state.lastBytes = now
        return now &- prev
    }
}

/// Timestamped frame sample processed by ``Stats`` and ``Detector``.
public struct Sample: Equatable, Sendable {
    public var atMs: UInt64
    public var frame: Frame

    public init(atMs: UInt64, frame: Frame) {
        self.atMs = atMs
        self.frame = frame
    }

    public func anomaly() -> Bool {
        if let ms = frame.workMs(), ms >= SLOW_MS {
            return true
        }
        if let n = frame.allocatedBytesVal, n >= LARGE_BYTES {
            return true
        }
        return false
    }

    public func json() -> JsonValue {
        let f = frame
        return .object([
            "at_ms": .uint(atMs),
            "window": .uint(f.windowId),
            "source": f.sourceVal.map { .uint($0) } ?? .null,
            "seq": .uint(f.seqNum),
            "outcome": .string(f.frameOutcome.name()),
            "update_ms": f.updateMsVal.map { .double($0) } ?? .null,
            "render_ms": f.renderMsVal.map { .double($0) } ?? .null,
            "work_ms": f.workMs().map { .double($0) } ?? .null,
            "input_to_frame_ms": f.inputToFrameMsVal.map { .double($0) } ?? .null,
            "gpu_ms": f.gpuMsVal.map { .double($0) } ?? .null,
            "ui_allocated_bytes": f.allocatedBytesVal.map { .uint($0) } ?? .null,
        ])
    }
}
