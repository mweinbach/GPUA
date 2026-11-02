// Tests ported from: crates/rune-perf/src/store/tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Foundation
import Testing
@testable import RunePerf

private func stallSample(_ atMs: UInt64) -> Sample {
    Sample(atMs: atMs, frame: Frame.new(0, atMs, .drawn).updateMs(300.0).renderMs(1.0))
}

private func makeTempDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("rune-perf-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

@Suite("RunePerf Store Tests")
struct RunePerfStoreTests {
    @Test func writer_publishes_snapshot_and_bounded_incidents_even_when_hook_is_full() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let (tx, rx) = syncChannel(1, of: URL.self)
        let config = Config.new(dir, "fixture").build("1.0").incidents(tx)
        let health = Health()
        var w = Writer(config, ContinuousClock.now, health)
        for n in UInt64(0)..<40 {
            var s = stallSample(n * 2000)
            s.frame.windowId = n
            w.accept(s)
        }
        w.snapshot()
        #expect(w.incidents == 40)
        #expect(w.hookDropped == 39)

        let notifiedUrl = try #require(rx.tryRecv())
        #expect(FileManager.default.fileExists(atPath: notifiedUrl.path))

        let entries = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        let incidentFiles = entries.filter { $0.lastPathComponent.hasPrefix("perf-incident-") }
        #expect(incidentFiles.count == 16)

        for entry in entries where entry.pathExtension == "json" {
            let bytes = try Data(contentsOf: entry)
            #expect(bytes.count <= INCIDENT_BYTES)
            _ = try JSONDecoder().decode(JsonValue.self, from: bytes)
        }

        let snapshotBytes = try Data(contentsOf: dir.appendingPathComponent("perf.json"))
        let snapshot = try JSONDecoder().decode(JsonValue.self, from: snapshotBytes)
        #expect(snapshot["frames"]["total"] == .int(40))
        #expect(snapshot["version"] == .string("1.0"))
        #expect(snapshot["frames"]["ui_allocated_bytes"].isNull)
        #expect(snapshot["write_errors"] == .int(0))
    }

    @Test func logs_rotate_and_failed_writes_are_visible() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        var log = Log(dir: dir, size: 0, limit: 128)
        for n in Int64(0)..<50 {
            try log.append(.object(["seq": .int(n)]))
        }
        for name in ["perf.log", "perf.log.1"] {
            let text = try String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8)
            #expect(text.utf8.count <= 128)
            for line in text.split(separator: "\n") {
                _ = try JSONDecoder().decode(JsonValue.self, from: Data(line.utf8))
            }
        }

        // Simulate a prior partial write with stale in-memory size accounting.
        try Data(repeating: UInt8(ascii: " "), count: 125).write(to: dir.appendingPathComponent("perf.log"))
        log.size = 0
        try log.append(.object(["seq": .int(51)]))
        let currentAttrs = try FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent("perf.log").path)
        let rotatedAttrs = try FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent("perf.log.1").path)
        #expect(((currentAttrs[.size] as? NSNumber)?.intValue ?? Int.max) <= 128)
        #expect((rotatedAttrs[.size] as? NSNumber)?.intValue == 125)

        let absentConfig = Config.new(dir.appendingPathComponent("absent"), "fixture")
        let health = Health()
        var w = Writer(absentConfig, ContinuousClock.now, health)
        w.snapshot()
        #expect(health.errors() >= 1)
        #expect(throws: (any Error).self) {
            try atomicJson(dir, "big.json", JsonValue.string("oversize"), 1)
        }
    }

    @Test func replacement_wait_is_cancellable_without_touching_owner_files() throws {
        #if !os(WASI)
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let lock = try LockFile(opening: dir.appendingPathComponent(".perf.lock"))
        defer { lock.closeHandle() }
        try lock.lockBlocking()

        let recorder = try Recorder.start(Config.new(dir, "replacement"))
        for _ in 0..<1000 {
            _ = recorder.record(Frame())
        }
        #expect(recorder.droppedSamples() >= 744)
        try recorder.shutdown()
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("perf.json").path))
        #endif
    }

    @Test func replacement_acquires_after_old_owner_releases() throws {
        #if !os(WASI)
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let lock = try LockFile(opening: dir.appendingPathComponent(".perf.lock"))
        try lock.lockBlocking()

        let (tx, rx) = syncChannel(1, of: URL.self)
        let config = Config.new(dir, "replacement").incidents(tx)
        let recorder = try Recorder.start(config)
        _ = recorder.record(stallSample(0).frame)

        // Release old owner's lock.
        lock.closeHandle()

        let recvResult = rx.recvTimeout(.seconds(5))
        guard case .value(let incidentUrl) = recvResult else {
            Issue.record("Expected incident notification after lock release, got \(recvResult)")
            try recorder.shutdown()
            return
        }
        #expect(FileManager.default.fileExists(atPath: incidentUrl.path))
        try recorder.shutdown()

        let snapshotBytes = try Data(contentsOf: dir.appendingPathComponent("perf.json"))
        let snapshot = try JSONDecoder().decode(JsonValue.self, from: snapshotBytes)
        #expect(snapshot["frames"]["total"] == .int(1))
        #endif
    }

    @Test func dropped_recorder_cancels_lock_wait() throws {
        #if !os(WASI)
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let lockPath = dir.appendingPathComponent(".perf.lock")
        let ownerLock = try LockFile(opening: lockPath)
        defer { ownerLock.closeHandle() }
        try ownerLock.lockBlocking()

        let health = Health()
        let (doneTx, waitRx) = syncChannel(1, of: Bool.self)
        let worker = WorkerHandle(name: "acquire-test") {
            if let contender = try? LockFile(opening: lockPath) {
                defer { contender.closeHandle() }
                let acquired = (try? acquire(contender, health)) ?? true
                _ = doneTx.trySend(acquired)
            }
        }

        health.requestStop()
        let result = waitRx.recvTimeout(.seconds(5))
        if case .value(let acquired) = result {
            #expect(!acquired)
        } else {
            Issue.record("Expected acquire cancellation result within 5s")
        }
        worker.join()
        #endif
    }

    @Test func instrumentation_overhead_writer() throws {
        // PORT NOTE: Upstream marks this `#[ignore = "manual optimized background cost measurement"]` with 100 snapshots/round.
        // We run 2 snapshots/round in regular CI runs and 100 when `RUNE_PERF_BENCH=1`.
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let snapsPerRound = ProcessInfo.processInfo.environment["RUNE_PERF_BENCH"] == "1" ? 100 : 2
        let verbose = ProcessInfo.processInfo.environment["RUNE_PERF_BENCH"] == "1"

        let config = Config.new(dir, "benchmark")
        let health = Health()
        var w = Writer(config, ContinuousClock.now, health)
        for n in 0..<RECENT {
            w.stats.accept(stallSample(UInt64(n)))
        }
        var times: [Double] = []
        for round in 0..<22 {
            let at = ContinuousClock.now
            for _ in 0..<snapsPerRound {
                w.snapshot()
            }
            if round > 0 {
                let (secs, attos) = at.duration(to: ContinuousClock.now).components
                let totalMs = Double(secs) * 1000.0 + Double(attos) * 1e-15
                times.append(totalMs / Double(snapsPerRound))
            }
        }
        let summary = percentiles(times)
        #expect(!summary.isNull)
        if verbose {
            print("METRIC writer_snapshot_ms \(summary)")
        }
    }
}
