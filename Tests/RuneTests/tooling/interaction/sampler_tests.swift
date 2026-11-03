// Tests ported from: crates/rune/src/tooling/interaction/sampler_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

#if os(macOS) && arch(arm64)
import Darwin
import Foundation
#endif
import Testing
@testable import Rune

private func stackFrame(_ name: String, _ app: Bool) -> InteractionStackFrame {
    InteractionStackFrame(name: name, app: app)
}

private func sampled(_ frames: [(String, Bool)], _ waiting: Bool, _ cpuUs: UInt64, _ atMs: UInt64) -> InteractionSampled {
    InteractionSampled(
        frames: frames.map { stackFrame($0.0, $0.1) },
        waiting: waiting,
        cpuUs: cpuUs,
        atNs: atMs * 1_000_000
    )
}

private func makeStacks(_ taken: UInt32, _ waiting: UInt32, _ cpuShare: Double?) -> InteractionStacks {
    InteractionStacks(taken: taken, waiting: waiting, cpuShare: cpuShare, hot: [], stack: [])
}

#if os(macOS) && arch(arm64)
@inline(never)
func spin_here_for_the_sampler(_ stopFlag: SamplerStopBox) {
    while !stopFlag.isStopped() {
        // Prevent optimizer from eliminating loop
        withExtendedLifetime(stopFlag) {}
    }
}

final class SamplerStopBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    func stop() { lock.withLock { stopped = true } }
    func isStopped() -> Bool { lock.withLock { stopped } }
}

final class SamplerChannel<T: Sendable>: @unchecked Sendable {
    private let sem = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var value: T? = nil
    func send(_ v: T) {
        lock.withLock { value = v }
        sem.signal()
    }
    func recv() -> T {
        sem.wait()
        return lock.withLock { value! }
    }
}
#endif

@Suite("InteractionSamplerTests")
struct InteractionSamplerTests {
    @Test func stacksNameTheInnermostAppFrameMostSamplesWereIn() {
        let sleep = [
            ("__semwait_signal (libsystem_kernel)", false),
            ("std::thread::sleep", false),
            ("app::save", true),
            ("app::main", true),
        ]
        let layout = [
            ("taffy::compute", true),
            ("app::view", true),
        ]
        let s = InteractionStacks.of([
            sampled(sleep, true, 0, 0),
            sampled(layout, false, 1000, 4),
            sampled(sleep, true, 1000, 8),
            sampled(sleep, true, 2000, 12),
        ])!
        #expect(s.taken == 4 && s.waiting == 3)
        #expect(s.hot.count == 2)
        #expect(s.hot[0].0 == "app::save" && s.hot[0].1 == 3)
        #expect(s.hot[1].0 == "taffy::compute" && s.hot[1].1 == 1)
        #expect(s.stack.first == "__semwait_signal (libsystem_kernel)")
        #expect(abs((s.cpuShare ?? 0.0) - (2.0 / 12.0)) < 1e-9)
        #expect(InteractionStacks.of([]) == nil)
        #expect(InteractionStacks.of([sampled(layout, false, 0, 0)])?.cpuShare == nil)
    }

    @Test func aBusyMachineTakesTheBlameOnlyWhenTheAppWasReadyToRun() {
        let slow = 16.7
        #expect(interactionCause(workMs: 10.0, slowMs: slow, cpuMs: 9.0, stacks: nil, overloaded: false) == .queued)
        #expect(interactionCause(workMs: 40.0, slowMs: slow, cpuMs: 36.0, stacks: nil, overloaded: true) == .cpu)
        #expect(interactionCause(workMs: 40.0, slowMs: slow, cpuMs: 1.0, stacks: makeStacks(7, 6, nil), overloaded: true) == .blocked)
        #expect(interactionCause(workMs: 40.0, slowMs: slow, cpuMs: 1.0, stacks: nil, overloaded: false) == .blocked)
        #expect(interactionCause(workMs: 40.0, slowMs: slow, cpuMs: 1.0, stacks: nil, overloaded: true) == .schedulerWait)
        #expect(interactionCause(workMs: 40.0, slowMs: slow, cpuMs: 4.0, stacks: makeStacks(7, 0, nil), overloaded: false) == .schedulerWait)
        #expect(interactionCause(workMs: 40.0, slowMs: slow, cpuMs: nil, stacks: makeStacks(7, 1, 0.9), overloaded: false) == .cpu)
        #expect(interactionCause(workMs: 40.0, slowMs: slow, cpuMs: nil, stacks: nil, overloaded: false) == .cpu)
        #expect(interactionCause(workMs: 40.0, slowMs: slow, cpuMs: nil, stacks: nil, overloaded: true) == .schedulerWait)
    }

    #if os(macOS) && arch(arm64)
    private func sampleAThread(
        _ body: @escaping @Sendable (SamplerStopBox, SamplerChannel<Void>) -> Void
    ) -> (InteractionRawSample, [String], [Bool]) {
        let stopBox = SamplerStopBox()
        let ready = SamplerChannel<InteractionTarget>()
        let waitChan = SamplerChannel<Void>()
        let done = SamplerChannel<Void>()
        let t = Thread {
            ready.send(InteractionTarget.current()!)
            body(stopBox, waitChan)
            done.send(())
        }
        t.start()
        let target = ready.recv()
        Thread.sleep(forTimeInterval: 0.03)
        let raw = target.sample { true }!
        stopBox.stop()
        waitChan.send(())
        done.recv()
        var symbols = InteractionSymbols()
        var names: [String] = []
        var appFlags: [Bool] = []
        for (i, pc) in raw.pcs.prefix(raw.len).enumerated() {
            let f = symbols.frame(pc, inner: i == 0)
            names.append(f.name)
            appFlags.append(f.app)
        }
        return (raw, names, appFlags)
    }

    @Test func theSamplerNamesTheFunctionARunningThreadIsIn() {
        let (raw, names, appFlags) = sampleAThread { stopBox, _ in
            spin_here_for_the_sampler(stopBox)
        }
        #expect(!raw.waiting)
        #expect(raw.cpuUs >= 10_000)
        if let at = names.firstIndex(where: { $0.contains("spin_here_for_the_sampler") }) {
            #expect(appFlags[at])
            #expect(raw.len > at + 1)
        } else {
            Issue.record("Expected spin_here_for_the_sampler in sampled stack: \(names)")
        }
    }

    @Test func theSamplerSeesAWaitingThreadWait() {
        let (raw, _, _) = sampleAThread { _, waitChan in
            waitChan.recv()
        }
        #expect(raw.waiting)
    }

    @Test func aSampleThatNoLongerAppliesIsDropped() {
        let stopBox = SamplerStopBox()
        let ready = SamplerChannel<InteractionTarget>()
        let done = SamplerChannel<Void>()
        let t = Thread {
            ready.send(InteractionTarget.current()!)
            spin_here_for_the_sampler(stopBox)
            done.send(())
        }
        t.start()
        let target = ready.recv()
        #expect(target.sample { false } == nil)
        stopBox.stop()
        done.recv()
    }

    @Test func namesAreDemangledAndTheStandardLibraryIsntTheApp() {
        #expect(interactionDemangled("__RNvCs1mieHSqJ4qC_1m11local_thing") == "m::local_thing")
        #expect(interactionDemangled("__ZN3std6thread5sleep17h0123456789abcdefE") == "std::thread::sleep")
        #expect(interactionDemangled("__semwait_signal") == "__semwait_signal")
        #expect(interactionIsLibrary("std::thread::sleep") && interactionIsLibrary("<core::ops::Range<usize> as Iterator>::next"))
        #expect(!interactionIsLibrary("<app::Save as core::ops::FnOnce>::call_once"))
    }
    #endif
}
