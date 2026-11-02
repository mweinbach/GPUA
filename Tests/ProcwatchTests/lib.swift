// Tests ported from: crates/procwatch/src/lib.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Foundation
import Testing
@testable import Procwatch

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Android)
import Android
#endif

private func atSnapshot(_ footprint: UInt64, _ cpuS: Double) -> Snapshot {
    Snapshot(
        footprint: footprint,
        footprintPeak: footprint,
        cpuS: cpuS,
        threads: [Procwatch.Thread(id: 1, name: "main", cpuS: 1.0)]
    )
}

private func eventLines(_ events: [Event]) -> String {
    events.map(\.line).joined(separator: "\n")
}

#if canImport(Darwin) || os(Linux) || os(Android)
private func threadCpuS() -> Double {
    var ts = timespec(tv_sec: 0, tv_nsec: 0)
    _ = clock_gettime(CLOCK_THREAD_CPUTIME_ID, &ts)
    return Double(ts.tv_sec) + Double(ts.tv_nsec) / 1e9
}
#endif

@inline(never)
private func blackBox<T>(_ value: T) -> T {
    value
}

@Suite("Procwatch Tests", .serialized)
struct ProcwatchLibTests {
    @Test func counts_this_threads_allocations_and_live_heap() {
        alloc.install()
        let live = alloc.heap()!.live
        let before = alloc.threadAllocations()
        do {
            let held = blackBox(alloc.Buffer(repeating: 0, count: 1 << 20))
            #expect(alloc.threadAllocations() - before == 1)
            // Other tests may allocate in parallel, so allow slack.
            #expect(alloc.heap()!.live - live >= Int64((1 << 20) - (256 << 10)))
            _ = held
        }
        let quiet = alloc.threadAllocations()
        let sum = blackBox(1 + 1)
        #expect(sum == 2)
        #expect(alloc.threadAllocations() == quiet)
    }

    @Test func thread_bytes_count_requests_not_frees_on_this_thread_only() throws {
        let allocator = alloc.Counting.system()
        alloc.install()
        let before = try #require(alloc.threadAllocatedBytes())
        let layout128 = try #require(Layout.fromSizeAlign(128, 8))
        let layout256 = try #require(Layout.fromSizeAlign(256, 8))
        let p0 = try #require(allocator.allocZeroed(layout128))
        let p1 = try #require(allocator.realloc(p0, layout128, 256))
        allocator.dealloc(p1, layout256)
        #expect(alloc.threadAllocatedBytes()! - before == 384)

        #if !os(WASI)
        final class ThreadResultBox: @unchecked Sendable {
            private let cond = NSCondition()
            private var results: [UInt64] = []

            func record(_ v: UInt64) {
                cond.lock()
                results.append(v)
                cond.broadcast()
                cond.unlock()
            }

            func waitAll(count: Int) -> [UInt64] {
                cond.lock()
                while results.count < count {
                    cond.wait()
                }
                let out = results
                cond.unlock()
                return out
            }
        }

        let box = ThreadResultBox()
        for _ in 0..<8 {
            let t = Foundation.Thread {
                let start = alloc.threadAllocatedBytes()!
                for _ in 0..<10_000 {
                    let buf = blackBox(alloc.Buffer(repeating: 42, count: 128))
                    _ = buf
                }
                box.record(alloc.threadAllocatedBytes()! - start)
            }
            t.start()
        }
        let deltas = box.waitAll(count: 8)
        for delta in deltas {
            #expect(delta == 1_280_000)
        }
        #endif
    }

    @Test func usage_reads_memory_and_files_without_threads() throws {
        #if canImport(Darwin) || os(Linux) || os(Android)
        let u = usage()
        let footprint = try #require(u.footprint)
        let peak = try #require(u.footprintPeak)
        let resident = try #require(u.resident)
        let fds = try #require(u.fds)
        #expect(footprint > 0 && peak >= footprint)
        #expect(resident > 0 && fds >= 3)

        var openedFds: [Int32] = []
        defer {
            for fd in openedFds {
                close(fd)
            }
        }
        for _ in 0..<8 {
            let fd = open("/dev/null", O_RDONLY)
            #expect(fd >= 0)
            if fd >= 0 {
                openedFds.append(fd)
            }
        }
        let afterFds = try #require(usage().fds)
        #expect(afterFds >= fds + 4)
        #endif
    }

    @Test func usage_is_unknown_off_macos() {
        // PORT NOTE: GPUA extends Procwatch with `/proc/self/statm` & `/proc/self/fd` on Linux/Android
        // and Win32 on Windows; WASI retains the deterministic `Usage()` fallback.
        #if os(WASI)
        #expect(usage() == Usage())
        #elseif !os(macOS)
        let u = usage()
        if let f = u.footprint, let peak = u.footprintPeak {
            #expect(f > 0 && peak >= f)
        }
        #endif
    }

    @Test func reads_this_process() throws {
        #if canImport(Darwin) || os(Linux) || os(Android)
        let s = try #require(snapshot())
        #expect(s.footprint > 0 && s.footprintPeak >= s.footprint)
        #expect(!s.threads.isEmpty)
        #expect(s.pid == currentPid())
        // stdin, stdout and stderr at least.
        #expect(s.fds >= 3)

        var openedFds: [Int32] = []
        for _ in 0..<8 {
            let fd = open("/dev/null", O_RDONLY)
            #expect(fd >= 0)
            if fd >= 0 {
                openedFds.append(fd)
            }
        }
        let withFiles = try #require(snapshot())
        #expect(withFiles.fds >= s.fds + 4)
        for fd in openedFds {
            close(fd)
        }

        // A thread that burns CPU and exits still counts.
        let before = try #require(snapshot())
        let done = NSCondition()
        nonisolated(unsafe) var finished = false
        let spinner = Foundation.Thread {
            let start = Instant.now
            var x: UInt64 = 0
            while threadCpuS() < 0.3 && start.duration(to: Instant.now) < .seconds(10) {
                x = blackBox(x &+ 1)
            }
            done.lock()
            finished = true
            done.broadcast()
            done.unlock()
        }
        spinner.start()
        done.lock()
        while !finished {
            done.wait()
        }
        done.unlock()
        // Allow brief kernel accounting settle after pthread exit if needed.
        Foundation.Thread.sleep(forTimeInterval: 0.02)
        let after = try #require(snapshot())
        #expect(after.exitedCpuS() - before.exitedCpuS() > 0.2)
        #endif
    }

    @Test func json_parses_and_subtracts_heap_and_gauges() throws {
        let s = Snapshot(
            pid: 7,
            footprint: 1000,
            threads: [Procwatch.Thread(id: 1, name: "a\"b\\c\n", cpuS: 0.5)],
            heap: alloc.Heap(live: 300, tags: [("untagged", 300)]),
            gauges: [("video.frames", 200), ("gpu.textures", 100)]
        )
        #expect(s.unaccounted() == 400)

        struct ParsedThread: Decodable {
            let name: String
            let cpu_s: Double
        }
        struct ParsedHeap: Decodable {
            let live: Int64
            let tags: [String: Int64]
        }
        struct ParsedSnapshot: Decodable {
            let pid: Int32
            let threads: [ParsedThread]
            let heap: ParsedHeap?
            let gauges: [String: Int64]
            let unaccounted: Int64?
        }

        let decoded = try JSONDecoder().decode(ParsedSnapshot.self, from: Data(s.toJson().utf8))
        #expect(decoded.pid == 7)
        #expect(decoded.threads[0].name == "abc")
        #expect(decoded.heap?.tags["untagged"] == 300)
        #expect(decoded.gauges["video.frames"] == 200)
        #expect(decoded.unaccounted == 400)

        // Without the counting allocator there's no honest unaccounted figure.
        var bare = s
        bare.heap = nil
        #expect(bare.unaccounted() == nil)
        let bareDecoded = try JSONDecoder().decode(ParsedSnapshot.self, from: Data(bare.toJson().utf8))
        #expect(bareDecoded.unaccounted == nil && bareDecoded.heap == nil)
    }

    @Test func warnings_name_where_the_memory_is() {
        var cfg = Config.release("t")
        cfg.report = nil
        var w = Watcher.new(cfg)
        var s = atSnapshot(2 << 30, 0.0)
        s.footprint = 2 << 30
        s.heap = alloc.Heap(live: 100 << 20)
        s.gauges = [("video.frames", 300 << 20)]
        let events = w.observe(Instant.now, s)
        #expect(events.count == 1)
        #expect(events[0].kind == .footprint)
        #expect(events[0].line.contains("heap 100 MB live"))
        #expect(events[0].line.hasSuffix("; video.frames 300 MB; unaccounted 1.6 GB"))
    }

    @Test func warns_on_size_growth_and_cpu_once_per_window() {
        var cfg = Config.release("t")
        cfg.report = nil
        var w = Watcher.new(cfg)
        let t0 = Instant.now
        var events: [Event] = []
        for i in UInt64(0)...12 {
            // 100 MB every 10 s, and a full core.
            let t = t0 + .seconds(Int64(i * 10))
            events.append(contentsOf: w.observe(t, atSnapshot((50 + 100 * i) << 20, Double(i) * 10.0)))
        }
        let joined = eventLines(events)
        #expect(joined.contains("footprint grew"))
        #expect(joined.contains("% CPU over 60s: exited threads 100%"))
        #expect(joined.contains("warning: footprint 1.0 GB") || joined.contains("warning: footprint 1.1 GB"))
        #expect(events.filter({ $0.kind == .growth }).count == 2)
        #expect(events.allSatisfy({ $0.isWarning() }))

        // Flat and idle: nothing.
        var idleWatcher = Watcher.new(cfg)
        for i in UInt64(0)...12 {
            let t = t0 + .seconds(Int64(i * 10))
            #expect(idleWatcher.observe(t, atSnapshot(50 << 20, 1.0)).isEmpty)
        }
    }

    @Test func late_samples_still_fill_the_window() {
        // Sleeps that run 10 ms long leave no sample exactly 60 s back.
        var cfg = Config.release("t")
        cfg.report = nil
        var w = Watcher.new(cfg)
        let t0 = Instant.now
        var events: [Event] = []
        for i in 0...12 {
            let millis = Int64(10_010 * i)
            let secs = Double(millis) / 1000.0
            events.append(contentsOf: w.observe(t0 + .milliseconds(millis), atSnapshot(50 << 20, secs)))
        }
        #expect(events.filter({ $0.kind == .cpu }).count == 2)
    }

    @Test func an_exited_thread_counts_only_its_last_stretch() {
        let old = Snapshot(
            cpuS: 101.0,
            threads: [
                Procwatch.Thread(id: 1, name: "main", cpuS: 1.0),
                Procwatch.Thread(id: 2, name: "worker", cpuS: 100.0),
            ]
        )
        // The worker ran 6 more seconds and exited; main ran 54.
        let new = Snapshot(
            cpuS: 161.0,
            threads: [
                Procwatch.Thread(id: 1, name: "main", cpuS: 55.0),
            ]
        )
        #expect(busiest(old, new, 60.0) == "main 90%, exited threads 10%")
    }
}
