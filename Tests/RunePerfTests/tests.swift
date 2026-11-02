// Tests ported from: crates/rune-perf/src/tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Foundation
import Procwatch
import Testing
@testable import RunePerf

private func makeSample(_ atMs: UInt64, _ work: Double?) -> Sample {
    Sample(
        atMs: atMs,
        frame: Frame().updateMs(work).renderMs(work != nil ? 0.0 : nil)
    )
}

private func makeUsage(_ footprint: UInt64?, _ fds: UInt32?) -> Usage {
    Usage(footprint: footprint, fds: fds)
}

@inline(never)
private func blackBox<T>(_ value: T) -> T {
    value
}

@Suite("RunePerf Core Tests")
struct RunePerfCoreTests {
    @Test func optional_counters_stay_unavailable_and_invalid_timings_are_rejected() {
        var stats = Stats()
        stats.accept(makeSample(0, nil))
        let json = stats.json()
        for name in ["work_ms", "ui_allocated_bytes", "gpu_ms", "input_to_frame_ms", "lifetime_max_ui_allocated_bytes"] {
            #expect(json[name].isNull, "Expected \(name) to be null")
        }
        let f = Frame.new(1, 1, .drawn)
            .updateMs(.nan)
            .renderMs(-1.0)
            .gpuMs(.infinity)
            .sanitize()
        #expect(f.updateMsVal == nil && f.renderMsVal == nil && f.gpuMsVal == nil)
        #expect(Frame().updateMs(Double.greatestFiniteMagnitude).renderMs(Double.greatestFiniteMagnitude).workMs() == nil)
        #expect(Frame.new(1, 1, .drawn).updateMs(2.0).renderMs(1.0).workMs() == 3.0)
    }

    @Test func history_is_bounded_and_idle_is_not_work() {
        var stats = Stats()
        for n in UInt64(0)..<10_000 {
            stats.accept(makeSample(n, Double(n)))
        }
        let j = stats.json()
        #expect(j["recent_count"] == .int(Int64(RECENT)))
        #expect(j["work_ms"]["p50"] == .double(9699.0))
        #expect(j["work_ms"]["p95"] == .double(9969.0))
        #expect(j["recent_anomalies"].asArray?.count == 20)
        stats.prune(70_000)
        #expect(stats.json()["work_ms"].isNull)
        #expect(stats.json()["lifetime_max_work_ms"] == .double(9999.0))
    }

    @Test func anomalies_rate_limit_logs_but_keep_counts() {
        var stats = Stats()
        for _ in 0..<10 {
            let logged = stats.accept(makeSample(0, 20.0))
            #expect(logged)
        }
        let suppressed = stats.accept(makeSample(999, 20.0))
        #expect(!suppressed)
        let nextSecond = stats.accept(makeSample(1000, 20.0))
        #expect(nextSecond)
        #expect(stats.json()["anomalies"] == .uint(12))
        #expect(stats.json()["log_suppressed"] == .uint(1))
    }

    @Test func long_frames_require_repetition_and_do_not_mix_windows() {
        var stats = Stats()
        let d = Detector()
        for n in UInt64(0)..<3 {
            var s = makeSample(n, 20.0)
            s.frame.windowId = n
            stats.accept(s)
            #expect(d.frame(s, stats) == nil)
        }
        for n in UInt64(3)..<5 {
            stats.accept(makeSample(n, 20.0))
        }
        #expect(d.frame(makeSample(5, 20.0), stats)?.rule == .longFrames)
        #expect(d.frame(makeSample(5000, nil), stats) == nil)
        #expect(d.frame(makeSample(5001, 250.0), stats)?.rule == .stall)
    }

    @Test func incident_cooldown_requires_worsening() {
        var d = Detector()
        var f = Finding(rule: .stall, window: 0, source: nil, severity: 250.0, evidence: .null)
        let first = d.admit(0, f)
        #expect(first)
        let sameAfterCooldown = d.admit(60_001, f)
        #expect(!sameAfterCooldown)
        f.severity = 400.0
        let worseBeforeCooldown = d.admit(59_999, f)
        #expect(!worseBeforeCooldown)
        let worseAfterCooldown = d.admit(60_001, f)
        #expect(worseAfterCooldown)
    }

    @Test func growth_uses_completed_floors_and_rejects_plateaus_spikes_gaps_and_missing_reads() {
        for testCase in 0..<5 {
            var d = Detector()
            var findings: [Finding] = []
            for minute in UInt64(0)..<6 {
                let base: UInt64 = 100 << 20
                let value: UInt64
                switch testCase {
                case 0:
                    value = base + minute * (20 << 20)
                case 1:
                    value = base
                case 2:
                    value = (minute == 2) ? (base * 3) : base
                default:
                    value = base + minute * (20 << 20)
                }
                let at = ((testCase == 3 && minute > 2) ? (minute + 2) : minute) * 60_000
                let footprintOpt: UInt64? = (testCase == 4 && minute == 2) ? nil : value
                findings = d.process(at, makeUsage(footprintOpt, 100))
            }
            #expect(findings.count == (testCase == 0 ? 1 : 0))
            if testCase == 0 {
                #expect(findings[0].rule == .memoryGrowth)
            }
        }

        var fdDetector = Detector()
        for n in UInt64(0)..<5 {
            #expect(fdDetector.process(n * 60_000, makeUsage(nil, UInt32(100 + n * 10))).isEmpty)
        }
        let fdFindings = fdDetector.process(300_000, makeUsage(nil, 150))
        #expect(fdFindings.first?.rule == .fdGrowth)
    }

    @Test func allocation_deltas_start_from_a_baseline_and_stay_on_this_thread() {
        Procwatch.alloc.install()
        #if !os(WASI)
        // Run on a dedicated fresh OS thread matching Rust libtest's per-test thread model,
        // ensuring the initial call on this thread observes `nil` while setting the baseline.
        let cond = NSCondition()
        nonisolated(unsafe) var finished = false
        nonisolated(unsafe) var firstCall: UInt64? = 999
        nonisolated(unsafe) var secondCall: UInt64?
        nonisolated(unsafe) var thirdCall: UInt64?
        nonisolated(unsafe) var fourthCall: UInt64?

        let testThread = Foundation.Thread {
            firstCall = takeAllocatedBytes()
            do {
                let buf = blackBox(Procwatch.alloc.Buffer(repeating: 0, count: 4096))
                _ = buf
            }
            secondCall = takeAllocatedBytes()
            thirdCall = takeAllocatedBytes()

            let innerCond = NSCondition()
            nonisolated(unsafe) var innerDone = false
            let other = Foundation.Thread {
                let big = blackBox(Procwatch.alloc.Buffer(repeating: 0, count: 1 << 20))
                _ = big
                innerCond.lock()
                innerDone = true
                innerCond.broadcast()
                innerCond.unlock()
            }
            other.start()
            innerCond.lock()
            while !innerDone {
                innerCond.wait()
            }
            innerCond.unlock()

            fourthCall = takeAllocatedBytes()

            cond.lock()
            finished = true
            cond.broadcast()
            cond.unlock()
        }
        testThread.start()
        cond.lock()
        while !finished {
            cond.wait()
        }
        cond.unlock()

        #expect(firstCall == nil)
        #expect(secondCall == 4096)
        #expect(thirdCall == 0)
        #expect((fourthCall ?? UInt64.max) < (64 << 10))
        #else
        _ = takeAllocatedBytes()
        do {
            let buf = blackBox(Procwatch.alloc.Buffer(repeating: 0, count: 4096))
            _ = buf
        }
        #expect(takeAllocatedBytes() == 4096)
        #expect(takeAllocatedBytes() == 0)
        #endif
    }
}
