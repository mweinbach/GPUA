// Ported from: crates/rune-perf/src/recorder.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Foundation

public enum RunePerfError: Error, CustomStringConvertible, Sendable {
    case invalidInput(String)
    case recordExceedsByteCap(String)
    case ioError(String)
    case unsupportedPlatform(String)

    public var description: String {
        switch self {
        case .invalidInput(let msg),
             .recordExceedsByteCap(let msg),
             .ioError(let msg),
             .unsupportedPlatform(let msg):
            return msg
        }
    }
}

// PORT NOTE: Synchronized via internal NSCondition protecting dropped/error counters and stop flag.
internal final class Health: @unchecked Sendable {
    private let condition = NSCondition()
    private var droppedCount: UInt64 = 0
    private var errorCount: UInt64 = 0
    private var stopFlag: Bool = false

    init() {}

    func incrementDropped() {
        condition.lock()
        droppedCount += 1
        condition.unlock()
    }

    func dropped() -> UInt64 {
        condition.lock()
        let v = droppedCount
        condition.unlock()
        return v
    }

    /// Atomically increments `errors` and returns the previous count.
    @discardableResult
    func fetchAddError() -> UInt64 {
        condition.lock()
        let prev = errorCount
        errorCount += 1
        condition.unlock()
        return prev
    }

    func errors() -> UInt64 {
        condition.lock()
        let v = errorCount
        condition.unlock()
        return v
    }

    func isStopped() -> Bool {
        condition.lock()
        let v = stopFlag
        condition.unlock()
        return v
    }

    func requestStop() {
        condition.lock()
        stopFlag = true
        condition.broadcast()
        condition.unlock()
    }

    /// Waits up to `timeoutMs` milliseconds or returns early when `requestStop()` is signaled.
    func waitStop(timeoutMs: Int) {
        let deadline = Date(timeIntervalSinceNow: Double(max(1, timeoutMs)) / 1000.0)
        condition.lock()
        if !stopFlag {
            _ = condition.wait(until: deadline)
        }
        condition.unlock()
    }
}

#if !os(WASI)
// PORT NOTE: Synchronized via internal NSCondition allowing off-UI `shutdown()` to join the worker thread.
internal final class WorkerHandle: @unchecked Sendable {
    private let condition = NSCondition()
    private var finished = false

    init(name: String, body: @escaping @Sendable () -> Void) {
        let cond = self.condition
        let thread = Foundation.Thread { [weak self] in
            body()
            cond.lock()
            self?.finished = true
            cond.broadcast()
            cond.unlock()
        }
        thread.name = name
        thread.start()
    }

    func join() {
        condition.lock()
        while !finished {
            condition.wait()
        }
        condition.unlock()
    }
}
#endif

/// Owns one writer. Deinit cancels without blocking the UI; ``shutdown()`` drains and joins off-UI.
/// Dropping while waiting for a previous process's directory lock cancels that wait too.
// PORT NOTE: Synchronized via internal NSLock protecting sender/worker shutdown lifecycle; `record` uses lock-protected fixed-capacity channel.
public final class Recorder: @unchecked Sendable {
    internal let startInstant: ContinuousClock.Instant
    private let stateLock = NSLock()
    internal var out: SyncSender<Sample>?
    internal let health: Health
    #if !os(WASI)
    internal var worker: WorkerHandle?
    #endif

    internal init(
        start: ContinuousClock.Instant,
        out: SyncSender<Sample>?,
        health: Health
    ) {
        self.startInstant = start
        self.out = out
        self.health = health
    }

    public static func start(_ config: Config) throws -> Recorder {
        if config.app.utf8.count > 128 || config.buildIdentity.utf8.count > 256 {
            throw RunePerfError.invalidInput("app/build identity too long")
        }
        #if os(WASI)
        throw RunePerfError.unsupportedPlatform("rune-perf background writer requires OS threads (unavailable on WASI)")
        #else
        let (out, rx) = syncChannel(QUEUE, of: Sample.self)
        let start = ContinuousClock.now
        let health = Health()
        let recorder = Recorder(start: start, out: out, health: health)
        recorder.worker = WorkerHandle(name: "rune-perf") {
            do {
                try PerfStore.run(config, rx, start, health)
            } catch {
                health.fetchAddError()
                FileHandle.standardError.write(Data("rune-perf: recorder stopped: \(error)\n".utf8))
            }
        }
        return recorder
        #endif
    }

    /// Nonblocking, fixed-size send. Returns `false` when the queue is full or writer stopped.
    @discardableResult
    public func record(_ frame: Frame) -> Bool {
        let elapsed = startInstant.duration(to: ContinuousClock.now)
        let (secs, attos) = elapsed.components
        let ms = max(0, secs * 1000 + attos / 1_000_000_000_000_000)
        let sample = Sample(atMs: UInt64(ms), frame: frame.sanitize())

        stateLock.lock()
        let sender = out
        stateLock.unlock()

        if let sender, sender.trySend(sample) {
            return true
        }
        health.incrementDropped()
        return false
    }

    public func droppedSamples() -> UInt64 {
        health.dropped()
    }

    public func writeErrors() -> UInt64 {
        health.errors()
    }

    /// Call off the UI thread. Cancels lock waits; drains queued frames if already recording.
    public func shutdown() throws {
        health.requestStop()
        stateLock.lock()
        let sender = out
        out = nil
        #if !os(WASI)
        let handle = worker
        worker = nil
        #endif
        stateLock.unlock()

        sender?.close()
        #if !os(WASI)
        handle?.join()
        #endif
    }

    deinit {
        health.requestStop()
        out?.close()
    }
}
