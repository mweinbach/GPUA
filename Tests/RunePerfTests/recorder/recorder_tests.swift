// Tests ported from: crates/rune-perf/src/recorder/tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Foundation
import Procwatch
import Testing
@testable import RunePerf

@inline(never)
private func blackBox<T>(_ value: T) -> T {
    value
}

@Suite("RunePerf Recorder Tests")
struct RunePerfRecorderTests {
    @Test func report_path_has_zero_allocations_and_overflow_is_bounded() throws {
        Procwatch.alloc.install()
        let (out, rx) = syncChannel(QUEUE, of: Sample.self)
        let r = Recorder(start: ContinuousClock.now, out: out, health: Health())
        _ = r.record(Frame())
        _ = try #require(rx.recv())

        let before = try #require(Procwatch.alloc.threadAllocatedBytes())
        for n in UInt64(0)..<1000 {
            _ = r.record(blackBox(Frame.new(1, n, .drawn).updateMs(1.0).renderMs(1.0)))
        }
        #expect(Procwatch.alloc.threadAllocatedBytes() == before)
        #expect(r.droppedSamples() == UInt64(1000 - QUEUE))
        #expect(rx.tryIter().count == QUEUE)
    }

    @Test func instrumentation_overhead() throws {
        // PORT NOTE: Upstream marks this `#[ignore = "manual paired optimized component benchmark"]` with N=200_000.
        // We run N=200 in regular test runs so CI validates the full paired measurement path quickly,
        // and N=200_000 when `RUNE_PERF_BENCH=1` is set.
        let iterations = ProcessInfo.processInfo.environment["RUNE_PERF_BENCH"] == "1" ? 200_000 : 200
        let verbose = ProcessInfo.processInfo.environment["RUNE_PERF_BENCH"] == "1"

        func measureAllocations<A: GlobalAllocator>(_ allocator: A) -> Double {
            let at = ContinuousClock.now
            let layout = Layout.fromSizeAlign(blackBox(128), 8)!
            for _ in 0..<iterations {
                let p = blackBox(allocator.alloc(layout))!
                p.storeBytes(of: UInt8(42), as: UInt8.self)
                allocator.dealloc(p, layout)
            }
            _ = blackBox(Procwatch.alloc.threadAllocatedBytes())
            let (secs, attos) = at.duration(to: ContinuousClock.now).components
            let nanos = Double(secs) * 1e9 + Double(attos) * 1e-9
            return nanos / Double(iterations)
        }

        let (out, rx) = syncChannel(QUEUE, of: Sample.self)
        let r = Recorder(start: ContinuousClock.now, out: out, health: Health())
        var values: [[Double]] = [[], [], [], []]
        var deltas: [Double] = []

        for round in 0..<22 {
            var measured = [0.0, 0.0, 0.0, 0.0]
            for i in 0..<4 {
                let mode = (round % 2 == 0) ? i : (3 - i)
                switch mode {
                case 0:
                    measured[mode] = measureAllocations(Procwatch.System())
                case 1:
                    measured[mode] = measureAllocations(Procwatch.alloc.Counting.system())
                default:
                    let at = ContinuousClock.now
                    for _ in 0..<iterations {
                        let f = blackBox(Frame())
                        if mode == 3 {
                            _ = blackBox(r.record(f))
                            _ = blackBox(rx.recv()!)
                        } else {
                            _ = blackBox(f)
                        }
                    }
                    let (secs, attos) = at.duration(to: ContinuousClock.now).components
                    let nanos = Double(secs) * 1e9 + Double(attos) * 1e-9
                    measured[mode] = nanos / Double(iterations)
                }
                if round > 0 {
                    values[mode].append(measured[mode])
                }
            }
            if round > 0 {
                deltas.append(measured[3] - measured[2])
            }
        }

        let metricNames = ["system_alloc_free_ns", "counting_alloc_free_ns", "baseline_frame_ns", "report_roundtrip_ns"]
        for (name, v) in zip(metricNames, values) {
            let summary = percentiles(v)
            #expect(!summary.isNull)
            if verbose {
                print("METRIC \(name) \(summary)")
            }
        }
        let deltaSummary = percentiles(deltas)
        #expect(!deltaSummary.isNull)
        if verbose {
            print("METRIC paired_report_delta_ns \(deltaSummary)")
        }
    }
}
