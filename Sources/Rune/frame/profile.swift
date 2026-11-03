// Ported from: crates/rune/src/frame/profile.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Opt-in headless phase timings. No clocks or allocator hooks in ordinary builds.
//! Commit and Layout include their nested phases; these overlapping times must not be summed.

#if !os(WASI)
import Foundation
#endif
import Procwatch

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Android)
import Android
#elseif canImport(WinSDK)
import WinSDK
#endif

/// Frame timing phases (`frame::profile::Phase`).
enum FramePhase: Int, Sendable, CaseIterable {
    case view = 0
    case commit = 1
    case layout = 2
    case text = 3
    case paint = 4
    case apply = 5
}

/// Phases timed, each with a wall and a CPU column.
public let PHASES: Int = 6

/// CPU consumed by this thread, excluding time the scheduler runs other work. Debug builds
/// time app callbacks with it for `perf_warn`, and interaction timing its input frames.
func frameCpuMs() -> Double? {
    #if canImport(Darwin) || canImport(Glibc) || canImport(Musl) || canImport(Android)
    var t = timespec(tv_sec: 0, tv_nsec: 0)
    let ok = clock_gettime(CLOCK_THREAD_CPUTIME_ID, &t)
    precondition(ok == 0, "thread CPU clock unavailable")
    return Double(t.tv_sec) * 1000.0 + Double(t.tv_nsec) / 1e6
    #elseif canImport(WinSDK)
    var created = FILETIME(dwLowDateTime: 0, dwHighDateTime: 0)
    var exited = created
    var kernel = created
    var user = created
    let ok = GetThreadTimes(GetCurrentThread(), &created, &exited, &kernel, &user)
    precondition(ok != 0, "thread CPU clock unavailable")
    let ticks: (FILETIME) -> UInt64 = { ft in
        (UInt64(ft.dwHighDateTime) << 32) | UInt64(ft.dwLowDateTime)
    }
    return Double(ticks(kernel) + ticks(user)) / 10_000.0
    #else
    return nil
    #endif
}

#if os(WASI)
// PORT NOTE: WASI (`wasm32-unknown-wasip1`) is single-threaded; `framePhasesWasi` is accessed on the sole execution thread.
nonisolated(unsafe) private var framePhasesWasi: [Double] = [Double](repeating: 0.0, count: 2 * PHASES)
#else
private let framePhasesThreadKey = "gpua.rune.frame.profile.times"
#endif

private func addThreadPhaseTime(phase: FramePhase, wallMs: Double, cpuDeltaMs: Double?) {
    #if os(WASI)
    framePhasesWasi[phase.rawValue] += wallMs
    if let cpuDeltaMs {
        framePhasesWasi[phase.rawValue + PHASES] += cpuDeltaMs
    }
    #else
    var row = (Thread.current.threadDictionary[framePhasesThreadKey] as? [Double])
        ?? [Double](repeating: 0.0, count: 2 * PHASES)
    row[phase.rawValue] += wallMs
    if let cpuDeltaMs {
        row[phase.rawValue + PHASES] += cpuDeltaMs
    }
    Thread.current.threadDictionary[framePhasesThreadKey] = row
    #endif
}

/// Wall then CPU milliseconds per phase (view, commit, layout, text, paint, apply) on this thread
/// since the last call, for benches that drive a `Runtime` themselves.
public func takeFramePhases() -> [Double] {
    let empty = [Double](repeating: 0.0, count: 2 * PHASES)
    #if os(WASI)
    let out = framePhasesWasi
    framePhasesWasi = empty
    return out
    #else
    let out = (Thread.current.threadDictionary[framePhasesThreadKey] as? [Double]) ?? empty
    Thread.current.threadDictionary[framePhasesThreadKey] = empty
    return out
    #endif
}

/// This thread's CPU clock in milliseconds.
public func threadCpuMs() -> Double {
    frameCpuMs() ?? 0.0
}

/// RAII scope timing a `FramePhase`'s wall and thread-CPU duration.
final class FrameProfileScope {
    private let phase: FramePhase
    private let start: RuneInstant
    private let cpuStart: Double?

    init(_ phase: FramePhase) {
        self.phase = phase
        self.start = .now()
        self.cpuStart = frameCpuMs()
    }

    deinit {
        let wallMs = start.elapsedSeconds() * 1000.0
        let cpuDelta: Double?
        if let s = cpuStart, let end = frameCpuMs() {
            cpuDelta = end - s
        } else {
            cpuDelta = nil
        }
        addThreadPhaseTime(phase: phase, wallMs: wallMs, cpuDeltaMs: cpuDelta)
    }
}

/// One headless frame: phase times (wall then CPU), the update and encode split, and counts.
struct FrameProfileRow: Sendable {
    var phases: [Double]
    var updateMs: Double
    var encodeMs: Double
    /// Script events delivered before this frame.
    var events: Int
    var allocations: UInt64
    var commits: UInt64
    /// Why the frame committed, as `CommitWhy` bits.
    var why: UInt16
    var shaped: UInt32
    var animating: Bool
    var cpuMs: Double?
}

/// A headless run's frames. With `RUNE_FRAME_LOG=FILE`, each frame is also written to `FILE` as a
/// JSON line as it ends, then a closing line with the process's memory footprint.
final class FrameProfileLog {
    private var rows: [FrameProfileRow]
    #if !os(WASI)
    private var outHandle: FileHandle?
    #endif

    init(_ frames: Int) {
        self.rows = []
        self.rows.reserveCapacity(frames)
        #if !os(WASI)
        if let path = ProcessInfo.processInfo.environment["RUNE_FRAME_LOG"], !path.isEmpty {
            _ = FileManager.default.createFile(atPath: path, contents: nil)
            guard let fh = FileHandle(forWritingAtPath: path) else {
                fatalError("RUNE_FRAME_LOG \(path): failed to open file for writing")
            }
            self.outHandle = fh
        }
        #endif
    }

    func push(_ row: FrameProfileRow) {
        #if !os(WASI)
        if let fh = outHandle {
            let p = row.phases
            let cpuField = row.cpuMs.map { String($0) } ?? "null"
            let line = "{\"k\":\(rows.count),\"ms\":\(row.updateMs + row.encodeMs),\"cpu_ms\":\(cpuField),\"events\":\(row.events),\"update_ms\":\(row.updateMs),\"encode_ms\":\(row.encodeMs),\"view_cpu\":\(p[PHASES]),\"commit_cpu\":\(p[PHASES + 1]),\"layout_cpu\":\(p[PHASES + 2]),\"text_cpu\":\(p[PHASES + 3]),\"paint_cpu\":\(p[PHASES + 4]),\"apply_cpu\":\(p[PHASES + 5]),\"allocations\":\(row.allocations),\"commits\":\(row.commits),\"shaped\":\(row.shaped),\"animating\":\(row.animating)}\n"
            fh.write(Data(line.utf8))
        }
        #endif
        rows.append(row)
    }

    /// Prints the `rune-frame-profile` means (first frame left out) and closes the log.
    func report() {
        let slice = rows.count > 1 ? ArraySlice(rows.dropFirst()) : ArraySlice(rows)
        let n = Double(max(slice.count, 1))
        let avg: ((FrameProfileRow) -> Double) -> Double = { f in
            slice.isEmpty ? 0.0 : slice.reduce(0.0) { $0 + f($1) } / n
        }
        let hasCpu = slice.first?.cpuMs != nil
        let optNum: (Double?) -> String = { $0.map { String($0) } ?? "null" }
        let phaseCpu: (Int) -> String = { i in
            hasCpu ? String(avg { $0.phases[PHASES + i] }) : "null"
        }
        let threadCpu = hasCpu ? optNum(avg { $0.cpuMs ?? 0.0 }) : "null"
        let json = "{\"view_ms\":\(avg { $0.phases[0] }),\"commit_inclusive_ms\":\(avg { $0.phases[1] }),\"layout_inclusive_ms\":\(avg { $0.phases[2] }),\"shape_ms\":\(avg { $0.phases[3] }),\"paint_ms\":\(avg { $0.phases[4] }),\"apply_ms\":\(avg { $0.phases[5] }),\"update_ms\":\(avg { $0.updateMs }),\"encode_submit_ms\":\(avg { $0.encodeMs }),\"allocations\":\(avg { Double($0.allocations) }),\"commits\":\(avg { Double($0.commits) }),\"shaped\":\(avg { Double($0.shaped) }),\"animating_fraction\":\(avg { $0.animating ? 1.0 : 0.0 }),\"thread_cpu_ms\":\(threadCpu),\"view_cpu_ms\":\(phaseCpu(0)),\"commit_cpu_ms\":\(phaseCpu(1)),\"layout_cpu_ms\":\(phaseCpu(2)),\"shape_cpu_ms\":\(phaseCpu(3)),\"paint_cpu_ms\":\(phaseCpu(4)),\"apply_cpu_ms\":\(phaseCpu(5))}"
        #if !os(WASI)
        FileHandle.standardError.write(Data("rune-frame-profile \(json)\n".utf8))
        if let fh = outHandle {
            outHandle = nil
            let mem = Procwatch.snapshot()
            let optU64: (UInt64?) -> String = { $0.map { String($0) } ?? "null" }
            let optI64: (Int64?) -> String = { $0.map { String($0) } ?? "null" }
            let endLine = "{\"end\":true,\"frames\":\(rows.count),\"footprint\":\(optU64(mem?.footprint)),\"footprint_peak\":\(optU64(mem?.footprintPeak)),\"resident\":\(optU64(mem?.resident)),\"heap_live\":\(optI64(mem?.heap?.live))}\n"
            fh.write(Data(endLine.utf8))
            try? fh.synchronize()
            try? fh.close()
        }
        #endif
    }
}
