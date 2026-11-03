// Ported from: crates/rune/src/latest.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

#if !os(WASI)
import Foundation
#endif

/// Error thrown inside ``Latest`` test closures or fallible jobs when simulating worker panics.
public struct LatestJobCancelledError: Error, Sendable {
    public var message: String
    public init(_ message: String = "job failed") {
        self.message = message
    }
}

private struct LatestJob<T: Sendable>: Sendable {
    var generation: UInt64
    var due: RuneInstant
    var work: @Sendable () throws -> T?
}

// PORT NOTE: All mutable slot state in LatestInner is synchronized via `condition` (or `lock` on WASI).
internal final class LatestInner<T: Sendable>: @unchecked Sendable {
    #if !os(WASI)
    private let condition = NSCondition()
    #else
    private let lock = LiveLock()
    #endif

    private var generation: UInt64 = 0
    private var settled: UInt64 = 0
    private var next: LatestJob<T>? = nil
    private var driven: Bool = false
    private var answer: T? = nil
    private var keyChecker: (@Sendable (Any) -> Bool)? = nil
    private var waker: Waker?
    private var debounceInterval: Duration = .zero

    internal init(waker: Waker?) {
        self.waker = waker
    }

    internal func setDebounce(_ wait: Duration) {
        withLock {
            debounceInterval = wait
        }
    }

    internal func setWaker(_ newWaker: @escaping Waker) {
        let old: Waker? = withLock {
            let prev = waker
            waker = newWaker
            return prev
        }
        _ = old
    }

    internal func clearWaker() {
        let old: Waker? = withLock {
            let prev = waker
            waker = nil
            return prev
        }
        _ = old
    }

    internal func take() -> T? {
        withLock {
            let value = answer
            answer = nil
            return value
        }
    }

    internal var isPending: Bool {
        withLock {
            settled != generation
        }
    }

    internal func cancel() {
        #if !os(WASI)
        condition.lock()
        generation &+= 1
        settled = generation
        next = nil
        answer = nil
        keyChecker = nil
        condition.broadcast()
        condition.unlock()
        #else
        lock.withLock {
            generation &+= 1
            settled = generation
            next = nil
            answer = nil
            keyChecker = nil
        }
        #endif
    }

    #if !os(WASI)
    internal func enqueue(
        pool: LatestPool,
        keyCheck: (@Sendable (Any) -> Bool)?,
        skipIfMatchingKey candidate: Any?,
        work: @escaping @Sendable () throws -> T?
    ) {
        condition.lock()
        if let candidate, let existingCheck = keyChecker, existingCheck(candidate) {
            condition.unlock()
            return
        }
        generation &+= 1
        answer = nil
        keyChecker = keyCheck
        let gen = generation
        let due = RuneInstant.now() + debounceInterval
        next = LatestJob(generation: gen, due: due, work: work)
        condition.broadcast()
        if !driven {
            driven = true
            condition.unlock()
            pool.submit(self)
        } else {
            condition.unlock()
        }
    }
    #else
    internal func enqueueWasi(
        keyCheck: (@Sendable (Any) -> Bool)?,
        skipIfMatchingKey candidate: Any?,
        work: @escaping @Sendable () throws -> T?
    ) {
        let gen: UInt64? = lock.withLock {
            if let candidate, let existingCheck = keyChecker, existingCheck(candidate) {
                return nil
            }
            generation &+= 1
            answer = nil
            keyChecker = keyCheck
            return generation
        }
        guard let gen else { return }
        // PORT NOTE: Single-threaded WASI runs background closures immediately on the main thread when no JS event loop is attached.
        do {
            let out = try work()
            land(generation: gen, outcome: .success(out))
        } catch {
            land(generation: gen, outcome: .failure(error))
        }
    }
    #endif

    internal func land(generation gen: UInt64, outcome: Result<T?, any Error>) {
        var wakeToCall: Waker? = nil
        withLock {
            guard generation == gen else { return }
            settled = gen
            if case .success(let maybeAnswer) = outcome, let unwrapped = maybeAnswer {
                answer = unwrapped
                wakeToCall = waker
            }
        }
        wakeToCall?()
    }

    #if !os(WASI)
    internal func driveJob() {
        condition.lock()
        let job: LatestJob<T>
        while true {
            guard let pending = next else {
                driven = false
                condition.unlock()
                return
            }
            let now = RuneInstant.now()
            if pending.due <= now {
                driven = false
                job = pending
                next = nil
                break
            }
            let remaining = pending.due.durationSince(now)
            let comps = remaining.components
            let secs = Double(comps.seconds) + Double(comps.attoseconds) * 1e-18
            _ = condition.wait(until: Date(timeIntervalSinceNow: secs))
        }
        condition.unlock()

        do {
            let out = try job.work()
            land(generation: job.generation, outcome: .success(out))
        } catch {
            land(generation: job.generation, outcome: .failure(error))
        }
    }
    #endif

    private func withLock<R>(_ body: () -> R) -> R {
        #if !os(WASI)
        condition.lock()
        defer { condition.unlock() }
        return body()
        #else
        return lock.withLock(body)
        #endif
    }
}

#if !os(WASI)
extension LatestInner: LatestDrive {
    internal func drive() {
        driveJob()
    }
}
#endif

/// A latest-wins background request.
///
/// ``request(_:_:)`` runs a closure off the main thread; when it returns and no newer request
/// (or ``cancel()``) came in since, its answer lands and the waker fires once, so `poll` runs
/// and ``take()`` hands the answer over once. An answer to an older request is dropped, even
/// when it finishes after a newer one: a stale result never replaces a fresh one.
///
/// Dropping a ``Latest`` cancels it: nothing it asked for lands or wakes the window afterwards.
// PORT NOTE: Latest wraps thread-safe LatestInner and LatestPool; reference semantics preserve Rust's Drop-on-release cancellation.
public final class Latest<T: Sendable>: @unchecked Sendable {
    internal let inner: LatestInner<T>
    #if !os(WASI)
    internal let pool: LatestPool
    #endif

    /// A ``Latest`` with no waker: answers land, and wait for the next `poll` that something else
    /// brings. State built in `init` starts with this; `setup` attaches the waker with ``setWaker(_:)``.
    public convenience init() {
        self.init(waker: nil)
    }

    public static func `default`() -> Latest<T> {
        Latest<T>()
    }

    /// A ``Latest`` that calls `waker` once each time an answer lands.
    public static func new(_ waker: @escaping Waker) -> Latest<T> {
        Latest<T>(waker: waker)
    }

    public convenience init(_ waker: @escaping Waker) {
        self.init(waker: waker)
    }

    private init(waker: Waker?) {
        self.inner = LatestInner(waker: waker)
        #if !os(WASI)
        self.pool = LatestPool.shared
        #endif
    }

    #if !os(WASI)
    /// A ``Latest`` on its own pool, for tests that count its threads.
    internal init(pool: LatestPool, waker: Waker?) {
        self.inner = LatestInner(waker: waker)
        self.pool = pool
    }

    internal static func on(_ pool: LatestPool, _ waker: Waker?) -> Latest<T> {
        Latest(pool: pool, waker: waker)
    }
    #endif

    deinit {
        cancel()
        inner.clearWaker()
    }

    /// Starts each request only after `wait` passes with no newer one. Zero (the default) starts
    /// it at once.
    @discardableResult
    public func debounce(_ wait: Duration) -> Latest<T> {
        inner.setDebounce(wait)
        return self
    }

    /// Attaches or replaces the waker. Pending requests, an answer not yet taken, the debounce
    /// and the key of ``requestIfChanged(_:_:)`` all stay.
    public func setWaker(_ waker: @escaping Waker) {
        inner.setWaker(waker)
    }

    /// Asks for `work(input)` off the main thread, superseding every earlier request: their
    /// answers, landed or not, are dropped unless taken already. Forgets the key of
    /// ``requestIfChanged(_:_:)``.
    public func request<K: Sendable>(_ input: K, _ work: @escaping @Sendable (K) -> T) {
        #if !os(WASI)
        inner.enqueue(pool: pool, keyCheck: nil, skipIfMatchingKey: nil) {
            work(input)
        }
        #else
        inner.enqueueWasi(keyCheck: nil, skipIfMatchingKey: nil) {
            work(input)
        }
        #endif
    }

    /// Internal/throwing variant for tests simulating panicking worker closures without taking down the process.
    internal func requestThrowing<K: Sendable>(_ input: K, _ work: @escaping @Sendable (K) throws -> T) {
        #if !os(WASI)
        inner.enqueue(pool: pool, keyCheck: nil, skipIfMatchingKey: nil) {
            try work(input)
        }
        #else
        inner.enqueueWasi(keyCheck: nil, skipIfMatchingKey: nil) {
            try work(input)
        }
        #endif
    }

    /// ``request(_:_:)`` for work that may have nothing to say: when `work` returns `nil`,
    /// nothing lands and the waker doesn't fire, so `poll` doesn't run for it. The request still
    /// supersedes the older ones, so their answers stay dropped, and it stops being ``isPending()``.
    public func requestOpt<K: Sendable>(_ input: K, _ work: @escaping @Sendable (K) -> T?) {
        #if !os(WASI)
        inner.enqueue(pool: pool, keyCheck: nil, skipIfMatchingKey: nil) {
            work(input)
        }
        #else
        inner.enqueueWasi(keyCheck: nil, skipIfMatchingKey: nil) {
            work(input)
        }
        #endif
    }

    /// ``request(_:_:)`` for calling from `poll`, or any place that runs more often than the
    /// input changes: does nothing when `key` equals the key of the last request made this way.
    public func requestIfChanged<K: Equatable & Sendable>(
        _ key: K,
        _ work: @escaping @Sendable (K) -> T
    ) {
        let capturedKey = key
        let checker: @Sendable (Any) -> Bool = { candidate in
            guard let typed = candidate as? K else { return false }
            return typed == capturedKey
        }
        #if !os(WASI)
        inner.enqueue(pool: pool, keyCheck: checker, skipIfMatchingKey: key) {
            work(capturedKey)
        }
        #else
        inner.enqueueWasi(keyCheck: checker, skipIfMatchingKey: key) {
            work(capturedKey)
        }
        #endif
    }

    /// The newest request's answer, once: non-nil the first time after it lands, then `nil`
    /// until another does.
    public func take() -> T? {
        inner.take()
    }

    /// Whether the newest request is still waiting out its debounce or running.
    public func isPending() -> Bool {
        inner.isPending
    }

    /// Drops every request and any answer not yet taken. A request already running finishes
    /// on its worker, but its answer never lands.
    public func cancel() {
        inner.cancel()
    }
}
