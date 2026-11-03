// Tests ported from: crates/rune/src/frame/present_worker_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

#if !os(WASI)
import Foundation
import Testing
@testable import Rune

private final class WorkerLogBox: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Int] = []

    func append(_ v: Int) {
        lock.lock()
        values.append(v)
        lock.unlock()
    }

    func snapshot() -> [Int] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}

private final class AtomicIntFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var v: Int = 0

    func store(_ newValue: Int) {
        lock.lock()
        v = newValue
        lock.unlock()
    }

    func load() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return v
    }
}

@Suite("Rune Frame Present Worker Tests")
struct RuneFramePresentWorkerTests {
    @Test("jobs run off the caller's thread in order and wait sees them done")
    func jobsRunOffCallersThreadInOrderAndWaitSeesThemDone() throws {
        let worker = try #require(PresentWorker.spawn())
        let caller = ObjectIdentifier(Thread.current)
        let log = WorkerLogBox()
        for i in 0..<4 {
            worker.run {
                Thread.sleep(forTimeInterval: 0.005)
                #expect(ObjectIdentifier(Thread.current) != caller)
                log.append(i)
            }
        }
        worker.wait()
        #expect(log.snapshot() == [0, 1, 2, 3])
    }

    @Test("run returns before its job finishes")
    func runReturnsBeforeItsJobFinishes() throws {
        let worker = try #require(PresentWorker.spawn())
        let gate = DispatchSemaphore(value: 0)
        let done = AtomicIntFlag()
        worker.run {
            gate.wait()
            done.store(1)
        }
        #expect(done.load() == 0)
        gate.signal()
        worker.wait()
        #expect(done.load() == 1)
    }

    @Test("dropping the worker finishes the job in flight")
    func droppingTheWorkerFinishesTheJobInFlight() throws {
        let done = AtomicIntFlag()
        do {
            let worker = try #require(PresentWorker.spawn())
            worker.run {
                Thread.sleep(forTimeInterval: 0.020)
                done.store(1)
            }
        }
        #expect(done.load() == 1)
    }

    @Test("a failing job propagates on the owner's thread and disconnects the worker")
    func failingJobPropagatesOnOwnersThreadAndDisconnectsWorker() throws {
        let worker = try #require(PresentWorker.spawn())
        worker.runThrowing {
            throw PresentWorkerFailure("device lost")
        }
        #expect(throws: PresentWorkerFailure("device lost")) {
            try worker.waitThrowing()
        }
        let caller = ObjectIdentifier(Thread.current)
        let ranOnCaller = AtomicIntFlag()
        worker.run {
            if ObjectIdentifier(Thread.current) == caller {
                ranOnCaller.store(1)
            }
        }
        worker.wait()
        #expect(ranOnCaller.load() == 1)
    }
}
#endif
