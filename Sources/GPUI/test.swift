// Ported from: crates/gpui/src/test.rs
// Upstream commit: 650aab59d54f
// Port status: ported

import Foundation
import GPUIMacros
#if canImport(Testing)
import Testing
#endif

/// Strategy injected into tests to control the seed given to the scheduler.
public func seedStrategy() -> [UInt64] {
    if let env = ProcessInfo.processInfo.environment["SEED"].flatMap({ UInt64($0) }) {
        return [env]
    }
    return [0, 42, 1337]
}

/// Helper function to calculate test execution seeds.
func calculateSeeds(iterations: UInt64, explicitSeeds: [UInt64]) -> ([UInt64], Bool) {
    let envIterations = ProcessInfo.processInfo.environment["ITERATIONS"].flatMap { UInt64($0) } ?? iterations
    let envSeed = ProcessInfo.processInfo.environment["SEED"].flatMap { UInt64($0) }

    var seeds: [UInt64] = []
    if let env = envSeed {
        seeds.append(env)
    } else if envIterations == 1 && explicitSeeds.isEmpty {
        seeds.append(0)
    } else if envIterations > 1 {
        for i in 0..<envIterations {
            seeds.append(i)
        }
    }
    if envSeed == nil {
        seeds.append(contentsOf: explicitSeeds)
    }
    let isMultiple = seeds.count > 1
    return (seeds, isMultiple)
}

/// Similar to `runTest`, but only runs the callback once.
public func runTestOnce(seed: UInt64, testFn: (TestDispatcher) -> Void) {
    let dispatcher = TestDispatcher.new(seed: seed)
    testFn(dispatcher)
}

/// Run the given test function with the configured parameters.
public func runTest(
    numIterations: Int = 1,
    explicitSeeds: [UInt64] = [],
    maxRetries: Int = 0,
    testFn: (TestDispatcher, UInt64) -> Void,
    onFailFn: (() -> Void)? = nil
) {
    let (seeds, _) = calculateSeeds(iterations: UInt64(numIterations), explicitSeeds: explicitSeeds)
    for seed in seeds {
        let dispatcher = TestDispatcher.new(seed: seed)
        testFn(dispatcher, seed)
    }
}

/// A test struct for converting an observation callback into an async stream.
// PORT NOTE: Synchronized via internal NSLock protecting continuation waiters and observation buffer.
public final class Observation<T: Sendable>: AsyncSequence, AsyncIteratorProtocol, @unchecked Sendable {
    public typealias Element = T
    private let lock = NSLock()
    private var buffer: [T] = []
    private var waiters: [CheckedContinuation<T?, Never>] = []
    private var isFinished = false
    fileprivate(set) var subscription: Subscription?

    public init(subscription: Subscription? = nil) {
        self.subscription = subscription
    }

    public func push(_ item: T) {
        lock.lock()
        if !waiters.isEmpty {
            let cont = waiters.removeFirst()
            lock.unlock()
            cont.resume(returning: item)
        } else {
            buffer.append(item)
            lock.unlock()
        }
    }

    public func finish() {
        lock.lock()
        isFinished = true
        let pending = waiters
        waiters.removeAll()
        lock.unlock()
        for cont in pending {
            cont.resume(returning: nil)
        }
    }

    private func poll() -> (item: T?, isFinished: Bool) {
        lock.lock()
        defer { lock.unlock() }
        if !buffer.isEmpty {
            return (buffer.removeFirst(), false)
        }
        return (nil, isFinished)
    }

    private func addWaiter(_ cont: CheckedContinuation<T?, Never>) {
        lock.lock()
        defer { lock.unlock() }
        if !buffer.isEmpty {
            let item = buffer.removeFirst()
            cont.resume(returning: item)
        } else if isFinished {
            cont.resume(returning: nil)
        } else {
            waiters.append(cont)
        }
    }

    public func makeAsyncIterator() -> Observation<T> {
        self
    }

    public func next() async -> T? {
        let current = poll()
        if let item = current.item {
            return item
        }
        if current.isFinished {
            return nil
        }
        return await withCheckedContinuation { cont in
            addWaiter(cont)
        }
    }
}

/// Returns a stream of change events from the given `Entity`.
@MainActor
public func observe<T>(entity: Entity<T>, cx: inout TestAppContext) -> Observation<Void> {
    let observation = Observation<Void>()
    let sub = cx.update { app in
        app.observe(entity) { _, _ in
            observation.push(())
            return true
        }
    }
    observation.subscription = sub
    return observation
}

#if canImport(Testing)
/// Swift Testing trait for deterministic GPUI execution per ADR-0007.
public struct GPUITestTrait: TestTrait, SuiteTrait {
    public var config: GPUITestConfig

    public init(iterations: Int = 1, seed: UInt64? = nil, maxRetries: Int = 0) {
        self.config = GPUITestConfig(iterations: iterations, seed: seed, maxRetries: maxRetries)
    }
}

extension Trait where Self == GPUITestTrait {
    public static func gpui(iterations: Int = 1, seed: UInt64? = nil, maxRetries: Int = 0) -> Self {
        GPUITestTrait(iterations: iterations, seed: seed, maxRetries: maxRetries)
    }
}
#endif
