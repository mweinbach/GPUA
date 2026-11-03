// Tests ported from: crates/rune/src/latest/tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

#if !os(WASI)
import Foundation
import Testing
@testable import Rune

private final class WakeCounter: @unchecked Sendable {
    private let lock = LiveLock()
    private var count: Int = 0

    func increment() {
        lock.withLock { count += 1 }
    }

    func load() -> Int {
        lock.withLock { count }
    }
}

private final class TestGate: @unchecked Sendable {
    private let condition = NSCondition()
    private var started = false
    private var opened = false

    func waitInWorker() {
        condition.lock()
        started = true
        condition.broadcast()
        while !opened {
            condition.wait()
        }
        condition.unlock()
    }

    func waitStarted() {
        let deadline = Date(timeIntervalSinceNow: 5.0)
        condition.lock()
        while !started {
            if !condition.wait(until: deadline) && !started {
                condition.unlock()
                Issue.record("timed out waiting for worker to start")
                return
            }
        }
        condition.unlock()
    }

    func open() {
        condition.lock()
        opened = true
        condition.broadcast()
        condition.unlock()
    }
}

private func makeCounter() -> (Waker, WakeCounter) {
    let wakes = WakeCounter()
    return ({ wakes.increment() }, wakes)
}

private func makePool() -> LatestPool {
    LatestPool(max: 4, idleExit: .milliseconds(50))
}

private func makeLatest<T: Sendable>() -> (Latest<T>, WakeCounter) {
    let (waker, wakes) = makeCounter()
    return (Latest.on(makePool(), waker), wakes)
}

private func eventually(_ what: String, _ done: () -> Bool) {
    let deadline = Date(timeIntervalSinceNow: 5.0)
    while !done() {
        if Date() >= deadline {
            Issue.record("timed out waiting until \(what)")
            return
        }
        Thread.sleep(forTimeInterval: 0.001)
    }
}

@Suite("LatestTests")
struct LatestTests {
    @Test("the newest answer wins when an older one finishes last")
    func newestAnswerWinsWhenOlderFinishesLast() {
        let (search, wakes) = makeLatest() as (Latest<String>, WakeCounter)
        let gateA = TestGate()
        let aDone = WakeCounter()
        search.request("a") { q in
            gateA.waitInWorker()
            aDone.increment()
            return q
        }
        gateA.waitStarted()
        search.request("ab") { $0 }
        eventually("ab lands") { wakes.load() == 1 }
        #expect(search.take() == "ab")

        gateA.open()
        eventually("a finishes") { aDone.load() == 1 }
        Thread.sleep(forTimeInterval: 0.005)
        #expect(search.take() == nil)
        #expect(wakes.load() == 1)
    }

    @Test("a newer request drops an answer not yet taken")
    func newerRequestDropsAnswerNotYetTaken() {
        let (search, wakes) = makeLatest() as (Latest<String>, WakeCounter)
        search.request("a") { $0 }
        eventually("a lands") { wakes.load() == 1 }
        let gate = TestGate()
        search.request("ab") { q in
            gate.waitInWorker()
            return q
        }
        #expect(search.take() == nil)
        #expect(search.isPending())
        gate.open()
        eventually("ab lands") { wakes.load() == 2 }
        #expect(search.take() == "ab")
        #expect(!search.isPending())
    }

    @Test("an answer is taken once and each landing wakes once")
    func answerIsTakenOnceAndEachLandingWakesOnce() {
        let (search, wakes) = makeLatest() as (Latest<Int>, WakeCounter)
        for n in 1...20 {
            search.request(n) { $0 * 10 }
            eventually("the answer lands") { wakes.load() == n }
            #expect(search.take() == n * 10)
            #expect(search.take() == nil)
        }
        Thread.sleep(forTimeInterval: 0.010)
        #expect(wakes.load() == 20)
    }

    @Test("debounce runs only the last request of a burst after a quiet wait")
    func debounceRunsOnlyLastRequestOfBurstAfterQuietWait() {
        final class RunLog: @unchecked Sendable {
            let lock = LiveLock()
            var entries: [(String, Duration)] = []
            func push(_ q: String, _ elapsed: Duration) {
                lock.withLock { entries.append((q, elapsed)) }
            }
        }
        let (waker, wakes) = makeCounter()
        let quiet: Duration = .milliseconds(250)
        let search = Latest<String>.on(makePool(), waker).debounce(quiet)
        let ran = RunLog()
        let start = RuneInstant.now()
        var last: Duration = .zero
        for q in ["a", "ab", "abc"] {
            last = start.elapsed()
            search.request(q) { val in
                ran.push(val, start.elapsed())
                return val
            }
            Thread.sleep(forTimeInterval: 0.010)
        }
        eventually("abc lands") { wakes.load() == 1 }
        #expect(search.take() == "abc")
        let entries = ran.lock.withLock { ran.entries }
        #expect(entries.map(\.0) == ["abc"])
        #expect(entries[0].1 >= last + quiet - .milliseconds(15))
    }

    @Test("debounce waits before a lone request")
    func debounceWaitsBeforeLoneRequest() {
        let (waker, wakes) = makeCounter()
        let search = Latest<Duration>.on(makePool(), waker).debounce(.milliseconds(30))
        let start = RuneInstant.now()
        search.request(0) { _ in start.elapsed() }
        #expect(search.isPending())
        eventually("it lands") { wakes.load() == 1 }
        let elapsed = search.take()!
        #expect(elapsed >= .milliseconds(25))
    }

    @Test("cancel drops pending and running requests")
    func cancelDropsPendingAndRunningRequests() {
        let (waker, wakes) = makeCounter()
        let search = Latest<Int>.on(makePool(), waker).debounce(.milliseconds(20))
        let gate = TestGate()
        let finished = WakeCounter()
        search.request(0) { _ in
            gate.waitInWorker()
            finished.increment()
            return 1
        }
        gate.waitStarted()
        search.cancel()
        #expect(!search.isPending())
        gate.open()
        eventually("the running work finishes") { finished.load() == 1 }

        let ran = WakeCounter()
        search.request(0) { _ in
            ran.increment()
            return 2
        }
        search.cancel()
        Thread.sleep(forTimeInterval: 0.060)
        #expect(ran.load() == 0)
        #expect(search.take() == nil && wakes.load() == 0)
    }

    @Test("dropping it cancels and nothing wakes after")
    func droppingItCancelsAndNothingWakesAfter() {
        var searchOpt: Latest<UInt32>?
        let wakes: WakeCounter
        do {
            let pair: (Latest<UInt32>, WakeCounter) = makeLatest()
            searchOpt = pair.0
            wakes = pair.1
        }
        let gate = TestGate()
        let finished = WakeCounter()
        searchOpt!.request(0) { _ in
            gate.waitInWorker()
            finished.increment()
            return 1
        }
        gate.waitStarted()
        searchOpt = nil
        gate.open()
        eventually("the running work finishes") { finished.load() == 1 }
        Thread.sleep(forTimeInterval: 0.005)
        #expect(wakes.load() == 0)
    }

    @Test("a failing request settles and the worker carries on")
    func failingRequestSettlesAndWorkerCarriesOn() {
        let pool = LatestPool(max: 1, idleExit: .milliseconds(50))
        let (waker, wakes) = makeCounter()
        let search = Latest<UInt32>.on(pool, waker)
        search.requestThrowing(0) { _ in
            throw LatestJobCancelledError("search failed")
        }
        eventually("the failure settles it") { !search.isPending() }
        search.request(0) { _ in 7 }
        eventually("the next lands") { wakes.load() == 1 }
        #expect(search.take() == 7)
        #expect(pool.threads().1 == 1)
    }

    @Test("requests reuse a few threads that exit when idle")
    func requestsReuseFewThreadsThatExitWhenIdle() {
        let pool = LatestPool(max: 2, idleExit: .milliseconds(150))
        let lists: [Latest<UInt64>] = (0..<3).map { _ in Latest.on(pool, nil) }
        for key in 0..<UInt64(200) {
            let list = lists[Int(key % 3)]
            list.request(key) { k in
                if k % 50 == 0 {
                    Thread.sleep(forTimeInterval: 0.005)
                }
                return k
            }
            #expect(pool.threads().0 <= 2)
        }
        eventually("every list settles") { lists.allSatisfy { !$0.isPending() } }
        #expect(lists[197 % 3].take() == 197)
        #expect(pool.threads().1 <= 2)
        eventually("the workers exit") { pool.threads().0 == 0 }
    }

    @Test("poll changes state once per answer")
    func pollChangesStateOncePerAnswer() {
        struct SearchState {
            var hits: String
            var results: Latest<String>
        }
        var viewBuilds = 0
        let (waker, wakes) = makeCounter()
        let state = SearchState(hits: "", results: Latest.on(makePool(), waker))
        let rt = Runtime(
            state,
            { s, _ in
                viewBuilds += 1
                return el().child(text(s.hits))
            },
            (200.0, 100.0),
            Env()
        )
        rt.poll = { s, _, _ in
            guard let hits = s.results.take() else { return false }
            s.hits = hits
            return true
        }
        rt.frame(0.0)
        let initialBuilds = viewBuilds
        rt.state.results.request("rune") { "\($0).md" }
        eventually("the answer lands") { wakes.load() == 1 }
        rt.frame(1.0 / 60.0)
        #expect(rt.state.hits == "rune.md")
        #expect(viewBuilds == initialBuilds + 1)
        rt.frame(2.0 / 60.0)
        rt.frame(3.0 / 60.0)
        #expect(viewBuilds == initialBuilds + 1)
    }

    @Test("set waker keeps the debounce and a pending request")
    func setWakerKeepsDebounceAndPendingRequest() {
        let (waker, wakes) = makeCounter()
        let search = Latest<Int>.on(makePool(), nil).debounce(.milliseconds(250))
        search.request(7) { $0 }
        #expect(search.isPending())
        search.setWaker(waker)
        #expect(search.isPending())
        Thread.sleep(forTimeInterval: 0.050)
        #expect(wakes.load() == 0)
        eventually("the request lands") { wakes.load() == 1 }
        #expect(search.take() == 7)
    }

    @Test("set waker replaces the old waker")
    func setWakerReplacesOldWaker() {
        let (old, oldWakes) = makeCounter()
        let (new, newWakes) = makeCounter()
        let search = Latest<Int>.on(makePool(), old)
        search.setWaker(new)
        search.request(1) { $0 }
        eventually("it lands") { newWakes.load() == 1 }
        #expect(oldWakes.load() == 0)
    }

    @Test("request if changed ignores an unchanged key")
    func requestIfChangedIgnoresUnchangedKey() {
        let (search, wakes) = makeLatest() as (Latest<String>, WakeCounter)
        let runs = WakeCounter()
        for _ in 0..<5 {
            search.requestIfChanged("ab") { q in
                runs.increment()
                return q
            }
        }
        eventually("it lands") { wakes.load() == 1 }
        search.requestIfChanged("ab") { q in
            runs.increment()
            return q
        }
        Thread.sleep(forTimeInterval: 0.030)
        #expect(runs.load() == 1)
        #expect(wakes.load() == 1)
        #expect(search.take() == "ab")

        search.requestIfChanged("abc") { $0 }
        eventually("the new key lands") { wakes.load() == 2 }
        #expect(search.take() == "abc")
    }

    @Test("request if changed does not push back the debounce")
    func requestIfChangedDoesNotPushBackDebounce() {
        let (waker, wakes) = makeCounter()
        let search = Latest<Int>.on(makePool(), waker).debounce(.milliseconds(250))
        let start = RuneInstant.now()
        search.requestIfChanged(1) { $0 }
        while start.elapsed() < .milliseconds(150) {
            search.requestIfChanged(1) { $0 }
            Thread.sleep(forTimeInterval: 0.005)
        }
        eventually("it lands") { wakes.load() == 1 }
        #expect(start.elapsed() < .milliseconds(1500))
        #expect(search.take() == 1)
    }

    @Test("cancel and request forget the key")
    func cancelAndRequestForgetKey() {
        let (search, wakes) = makeLatest() as (Latest<Int>, WakeCounter)
        search.requestIfChanged(1) { $0 }
        eventually("first lands") { wakes.load() == 1 }
        search.cancel()
        search.requestIfChanged(1) { $0 + 10 }
        eventually("second lands") { wakes.load() == 2 }
        #expect(search.take() == 11)

        search.request(5) { $0 }
        eventually("plain request lands") { wakes.load() == 3 }
        #expect(search.take() == 5)
        search.requestIfChanged(1) { $0 + 20 }
        eventually("same key asks again") { wakes.load() == 4 }
        #expect(search.take() == 21)
    }

    @Test("request opt nil lands nothing and wakes nothing")
    func requestOptNilLandsNothingAndWakesNothing() {
        let (search, wakes) = makeLatest() as (Latest<Int>, WakeCounter)
        let ran = WakeCounter()
        search.requestOpt(3) { _ in
            ran.increment()
            return nil
        }
        eventually("the work ran") { ran.load() == 1 }
        eventually("it settles") { !search.isPending() }
        Thread.sleep(forTimeInterval: 0.030)
        #expect(search.take() == nil)
        #expect(wakes.load() == 0)

        search.requestOpt(4) { .some($0) }
        eventually("a Some lands") { wakes.load() == 1 }
        #expect(search.take() == 4)
    }

    @Test("request opt nil still supersedes older answers")
    func requestOptNilStillSupersedesOlderAnswers() {
        let (search, wakes) = makeLatest() as (Latest<Int>, WakeCounter)
        let gate = TestGate()
        search.request(1) { n in
            gate.waitInWorker()
            return n
        }
        gate.waitStarted()
        search.requestOpt(2) { _ in nil }
        eventually("it settles") { !search.isPending() }
        gate.open()
        Thread.sleep(forTimeInterval: 0.050)
        #expect(search.take() == nil)
        #expect(wakes.load() == 0)
    }
}
#endif
