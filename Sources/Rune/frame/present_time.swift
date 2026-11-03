// Ported from: crates/rune/src/frame/present_time.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! When each traced frame reached the screen, next to when it was meant to.
//!
//! A native `--trace` stamps frames at CPU submission (`t`) and, on macOS, at the display
//! link's target (`target_ms`). Neither shows whether frames reach the screen evenly: two
//! frames can present a fraction of a millisecond apart and leave a gap after them, which
//! reads as a hitch even when every frame's motion is right. On macOS the traced window's
//! layer reports each drawable's Metal `presentedTime`, and the trace writes it as
//! `present_ms`, with `present_dt_ms` from the previous presented frame. Other platforms
//! have no reliable source and write neither.

#if os(macOS)
import CoreFoundation
import Metal
import ObjectiveC.runtime
import QuartzCore
#endif

/// A drawable's sequence number and when it reached the screen, or `nil` when the system
/// skipped it.
typealias PresentTimeEntry = (UInt64, RuneInstant?)

/// Where present times come from. Implementations are filled from another thread.
protocol PresentTimeSource: Sendable {
    func take(_ out: inout [PresentTimeEntry])
}

/// A frame whose present time hasn't arrived after this many later frames is written
/// without one. Presentation runs two or three frames behind submission.
let PRESENT_WAIT_FRAMES: UInt32 = 32

let PRESENT_BUNCHED_MS: Double = 2.0

/// How long a finished trace waits for its last frames' present times.
let PRESENT_SETTLE: Duration = .milliseconds(150)

private func presentRound3(_ v: Double) -> Double {
    (v * 1000.0).rounded() / 1000.0
}

private func formatPresentJsonNumber(_ v: Double) -> String {
    if v.isFinite && v.truncatingRemainder(dividingBy: 1.0) == 0.0 && abs(v) < 1e15 {
        return String(Int64(v))
    }
    return String(v)
}

private func formatPresentFixed(_ value: Double, decimals: Int) -> String {
    guard value.isFinite else {
        if value.isNaN { return "NaN" }
        return value < 0 ? "-inf" : "inf"
    }
    if decimals <= 0 {
        let r = value.rounded(.toNearestOrEven)
        return r == 0 ? "0" : String(Int64(r))
    }
    var scale = 1.0
    var intScale: Int64 = 1
    for _ in 0..<decimals {
        scale *= 10.0
        intScale *= 10
    }
    let scaled = (value * scale).rounded(.toNearestOrEven)
    let isNeg = scaled < 0
    let absScaled = Int64(abs(scaled))
    let whole = absScaled / intScale
    let frac = absScaled % intScale
    var fracStr = String(frac)
    if fracStr.count < decimals {
        fracStr = String(repeating: "0", count: decimals - fracStr.count) + fracStr
    }
    return "\(isNeg ? "-" : "")\(whole).\(fracStr)"
}

/// Milliseconds from `start`, rounded like the trace's `t`, negative before it.
func presentMsSince(_ start: RuneInstant, _ at: RuneInstant) -> Double {
    let ms: Double
    if at >= start {
        let d = at.durationSince(start)
        ms = (Double(d.components.seconds) + Double(d.components.attoseconds) * 1e-18) * 1000.0
    } else {
        let d = start.durationSince(at)
        ms = -(Double(d.components.seconds) + Double(d.components.attoseconds) * 1e-18) * 1000.0
    }
    return presentRound3(ms)
}

private struct PendingPresentLine {
    /// The line without its closing brace.
    var line: String
    var seq: UInt64?
    /// `.some(nil)`: Metal skipped the drawable.
    var present: Double??
    /// The previous traced frame asked for this one right away, so the gap between their
    /// presents is cadence, not idle time.
    var continuous: Bool
    var age: UInt32
}

/// Trace lines held until their frame's present time is known, so each frame's line carries
/// it. Lines stay in submission order.
struct Presents {
    private let source: any PresentTimeSource
    private let start: RuneInstant
    private var pending: [PendingPresentLine]
    private var head: Int
    private var lastPresent: Double?
    private var scratch: [PresentTimeEntry]

    init(_ source: any PresentTimeSource, _ start: RuneInstant) {
        self.source = source
        self.start = start
        self.pending = []
        self.head = 0
        self.lastPresent = nil
        self.scratch = []
    }

    static func new(_ source: any PresentTimeSource, _ start: RuneInstant) -> Presents {
        Presents(source, start)
    }

    /// Queues a frame's line (without its closing brace) and writes every line now complete.
    /// `seq`: the drawable the frame presented, if the source tracks it.
    mutating func push(_ line: String, _ seq: UInt64?, _ continuous: Bool, _ out: inout [UInt8]) {
        for i in head..<pending.count {
            pending[i].age += 1
        }
        pending.append(PendingPresentLine(line: line, seq: seq, present: nil, continuous: continuous, age: 0))
        poll()
        writeReady(&out, all: false)
    }

    /// Whether any line still waits for its present time.
    mutating func waiting() -> Bool {
        poll()
        for i in head..<pending.count {
            if pending[i].seq != nil && pending[i].present == nil {
                return true
            }
        }
        return false
    }

    /// Writes every queued line, with or without its present time.
    mutating func flush(_ out: inout [UInt8]) {
        poll()
        writeReady(&out, all: true)
    }

    private mutating func poll() {
        source.take(&scratch)
        guard !scratch.isEmpty else { return }
        for (seq, at) in scratch {
            if let idx = (head..<pending.count).first(where: { pending[$0].seq == seq }) {
                let mapped: Double? = at.map { presentMsSince(start, $0) }
                pending[idx].present = .some(mapped)
            }
        }
        scratch.removeAll(keepingCapacity: true)
    }

    private mutating func writeReady(_ out: inout [UInt8], all: Bool) {
        while head < pending.count {
            let p = pending[head]
            if !(all || p.seq == nil || p.present != nil || p.age >= PRESENT_WAIT_FRAMES) {
                break
            }
            head += 1
            let finished = finish(p)
            out.append(contentsOf: finished.utf8)
            out.append(0x0A)
        }
        if head > 0 && head == pending.count {
            pending.removeAll(keepingCapacity: true)
            head = 0
        } else if head >= 64 {
            pending.removeFirst(head)
            head = 0
        }
    }

    private mutating func finish(_ p: PendingPresentLine) -> String {
        var line = p.line
        // An interval spans only frames drawn back to back that both reached the screen.
        if !p.continuous {
            lastPresent = nil
        }
        switch (p.seq, p.present) {
        case (.some, .some(.some(let at))):
            line += ",\"present_ms\":\(formatPresentJsonNumber(at))"
            if let last = lastPresent {
                line += ",\"present_dt_ms\":\(formatPresentJsonNumber(presentRound3(at - last)))"
            }
            lastPresent = at
        case (.some, .some(.none)):
            line += ",\"present_ms\":null"
            lastPresent = nil
        default:
            lastPresent = nil
        }
        line.append("}")
        return line
    }
}

/// Percentiles of a sample, nearest rank.
struct PresentSpread: Sendable, Equatable {
    var p50: Double
    var p95: Double
    var max: Double

    init(p50: Double, p95: Double, max: Double) {
        self.p50 = p50
        self.p95 = p95
        self.max = max
    }

    static func of(_ values: [Double]) -> PresentSpread? {
        guard !values.isEmpty else { return nil }
        var sorted = values
        sorted.sort { a, b in
            if a.isNaN && b.isNaN { return false }
            if a.isNaN { return false }
            if b.isNaN { return true }
            return a < b
        }
        let rank: (Double) -> Double = { p in
            let r = Int((p * Double(sorted.count)).rounded(.up))
            let clamped = min(Swift.max(r, 1), sorted.count)
            return sorted[clamped - 1]
        }
        return PresentSpread(p50: rank(0.5), p95: rank(0.95), max: sorted[sorted.count - 1])
    }
}

/// Minimal dependency-free top-level JSON object value extractor so `PresentSummary.ofTrace`
/// works identically on macOS, Linux, Windows, Android, and WASI without Foundation JSON dependencies.
private enum TraceJsonField {
    case number(Double)
    case null
    case other
}

private func parseTraceJsonObject(_ line: Substring) -> [String: TraceJsonField]? {
    let bytes = Array(line.utf8)
    var i = 0
    let n = bytes.count
    func skipWs() {
        while i < n && (bytes[i] == 0x20 || bytes[i] == 0x09 || bytes[i] == 0x0D || bytes[i] == 0x0A) {
            i += 1
        }
    }
    skipWs()
    guard i < n && bytes[i] == 0x7B else { return nil } // '{'
    i += 1
    var result: [String: TraceJsonField] = [:]
    skipWs()
    if i < n && bytes[i] == 0x7D {
        i += 1
        skipWs()
        return i == n ? result : nil
    }

    func parseString() -> String? {
        guard i < n && bytes[i] == 0x22 else { return nil } // '"'
        i += 1
        var out: [UInt8] = []
        while i < n {
            let b = bytes[i]
            i += 1
            if b == 0x22 {
                return String(decoding: out, as: UTF8.self)
            }
            if b == 0x5C { // '\'
                guard i < n else { return nil }
                out.append(bytes[i])
                i += 1
            } else {
                out.append(b)
            }
        }
        return nil
    }

    func skipNested(_ open: UInt8, _ close: UInt8) -> Bool {
        var depth = 1
        i += 1
        while i < n && depth > 0 {
            let b = bytes[i]
            if b == 0x22 {
                if parseString() == nil { return false }
                continue
            }
            if b == open { depth += 1 }
            else if b == close { depth -= 1 }
            i += 1
        }
        return depth == 0
    }

    while i < n {
        skipWs()
        guard let key = parseString() else { return nil }
        skipWs()
        guard i < n && bytes[i] == 0x3A else { return nil } // ':'
        i += 1
        skipWs()
        guard i < n else { return nil }
        let b = bytes[i]
        let value: TraceJsonField
        if b == 0x22 {
            guard parseString() != nil else { return nil }
            value = .other
        } else if b == 0x7B {
            guard skipNested(0x7B, 0x7D) else { return nil }
            value = .other
        } else if b == 0x5B {
            guard skipNested(0x5B, 0x5D) else { return nil }
            value = .other
        } else if b == 0x6E { // "null"
            guard i + 4 <= n && bytes[i..<i + 4].elementsEqual([0x6E, 0x75, 0x6C, 0x6C]) else { return nil }
            i += 4
            value = .null
        } else if b == 0x74 { // "true"
            guard i + 4 <= n && bytes[i..<i + 4].elementsEqual([0x74, 0x72, 0x75, 0x65]) else { return nil }
            i += 4
            value = .other
        } else if b == 0x66 { // "false"
            guard i + 5 <= n && bytes[i..<i + 5].elementsEqual([0x66, 0x61, 0x6C, 0x73, 0x65]) else { return nil }
            i += 5
            value = .other
        } else {
            let startIdx = i
            while i < n {
                let c = bytes[i]
                if c == 0x2C || c == 0x7D || c == 0x20 || c == 0x09 || c == 0x0D || c == 0x0A {
                    break
                }
                i += 1
            }
            guard i > startIdx,
                  let numStr = String(bytes: bytes[startIdx..<i], encoding: .utf8),
                  let d = Double(numStr) else {
                return nil
            }
            value = .number(d)
        }
        result[key] = value
        skipWs()
        if i < n && bytes[i] == 0x2C { // ','
            i += 1
            continue
        } else if i < n && bytes[i] == 0x7D { // '}'
            i += 1
            skipWs()
            return i == n ? result : nil
        } else {
            return nil
        }
    }
    return nil
}

/// Present cadence over a trace.
struct PresentSummary: Sendable, Equatable, CustomStringConvertible {
    var hz: Double
    var frames: Int
    /// Frames with a present time.
    var presented: Int
    /// Frames the system skipped (`present_ms: null`).
    var skipped: Int
    /// Present-to-present intervals between frames drawn back to back.
    var interval: PresentSpread?
    /// Intervals under `PRESENT_BUNCHED_MS`: frames that reached the screen together.
    var bunched: Int
    /// Intervals over 1.5 refresh periods: a refresh showed nothing new.
    var missed: Int
    /// Present time minus the display link's target.
    var lag: PresentSpread?

    /// Summarizes a trace's text. `nil` for traces without present times, including every
    /// trace written before they existed.
    static func ofTrace(_ text: String) -> PresentSummary? {
        let parsed = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .compactMap { parseTraceJsonObject($0) }
        guard let header = parsed.first else { return nil }
        let hz: Double
        if case .number(let v)? = header["hz"], v > 0.0 {
            hz = v
        } else {
            hz = 60.0
        }

        var frames = 0
        var presented = 0
        var skipped = 0
        var timed = false
        var intervals: [Double] = []
        var lags: [Double] = []

        for frame in parsed.dropFirst() where frame["t"] != nil {
            frames += 1
            guard let presentField = frame["present_ms"] else { continue }
            timed = true
            guard case .number(let present) = presentField else {
                skipped += 1
                continue
            }
            presented += 1
            if case .number(let dt)? = frame["present_dt_ms"] {
                intervals.append(dt)
            }
            if case .number(let target)? = frame["target_ms"] {
                lags.append(present - target)
            }
        }

        guard timed else { return nil }
        let missedMs = 1.5 * 1000.0 / hz
        return PresentSummary(
            hz: hz,
            frames: frames,
            presented: presented,
            skipped: skipped,
            interval: PresentSpread.of(intervals),
            bunched: intervals.filter { $0 < PRESENT_BUNCHED_MS }.count,
            missed: intervals.filter { $0 > missedMs }.count,
            lag: PresentSpread.of(lags)
        )
    }

    var description: String {
        let fmtSpread: (PresentSpread?) -> String = { s in
            guard let s else { return "none" }
            return "p50 \(formatPresentFixed(s.p50, decimals: 2)) p95 \(formatPresentFixed(s.p95, decimals: 2)) max \(formatPresentFixed(s.max, decimals: 2)) ms"
        }
        return "present: \(frames) frames, \(presented) presented, \(skipped) skipped at \(formatPresentFixed(hz, decimals: 0)) Hz; interval \(fmtSpread(interval)); \(bunched) bunched (<\(formatPresentJsonNumber(PRESENT_BUNCHED_MS)) ms), \(missed) missed (>\(formatPresentFixed(1.5 * 1000.0 / hz, decimals: 2)) ms); lag \(fmtSpread(lag))"
    }
}

#if os(macOS)
/// Present times from a `CAMetalLayer` (`frame::present_time::metal`).
enum presentMetal {
    /// Wakes the main run loop for another turn. Callable from any thread.
    static func wakeMain() {
        if let mainLoop = CFRunLoopGetMain() {
            CFRunLoopWakeUp(mainLoop)
        }
    }

    /// The instant of host time `media` (`CACurrentMediaTime` seconds), given both clocks now.
    static func instantAt(_ now: RuneInstant, _ mediaNow: Double, _ media: Double) -> RuneInstant {
        let nanos = Int64((abs(media - mediaNow) * 1_000_000_000.0).rounded())
        let delta = Duration.nanoseconds(nanos)
        if media >= mediaNow {
            return now.adding(delta)
        } else {
            return RuneInstant(now.raw.advanced(by: .zero - delta))
        }
    }

    /// Drawables acquired and presented on a hooked layer.
    // PORT NOTE: Synchronized via `lock` (`LiveLock`), mirroring the atomics and `Mutex<Vec<(u64, f64)>>` in `present_time.rs`.
    final class Log: PresentTimeSource, @unchecked Sendable {
        private let lock = LiveLock()
        private var nextSeq: UInt64 = 0
        private var acquiredSeq: UInt64 = 0
        private var presentedList: [(UInt64, Double)] = []
        private let untracedFlag: Bool
        private var onScreenSeq: UInt64 = 0
        private var watchFlag: Bool = false

        init(untraced: Bool = false) {
            self.untracedFlag = untraced
        }

        /// A log that only tracks which drawable is on screen, for a window that isn't traced.
        static func untraced() -> Log {
            Log(untraced: true)
        }

        /// The drawable the last `nextDrawable` returned, once.
        func acquired() -> UInt64? {
            lock.withLock {
                let seq = acquiredSeq
                acquiredSeq = 0
                return seq != 0 ? seq : nil
            }
        }

        /// The drawable the last `nextDrawable` returned (0 before the first).
        func lastAcquired() -> UInt64 {
            lock.withLock { nextSeq }
        }

        /// The newest drawable Metal reported on screen (0 before the first).
        func onScreen() -> UInt64 {
            lock.withLock { onScreenSeq }
        }

        /// While on, each drawable that reaches the screen wakes the main run loop.
        func watch(_ on: Bool) {
            lock.withLock { watchFlag = on }
        }

        /// Registers a Metal presented handler on `drawable` to record its sequence and `presentedTime`.
        func recordDrawable(_ drawable: any MTLDrawable) {
            let seq = lock.withLock { () -> UInt64 in
                nextSeq += 1
                acquiredSeq = nextSeq
                return nextSeq
            }
            drawable.addPresentedHandler { [weak self] d in
                guard let self else { return }
                let at = d.presentedTime
                let shouldWake = self.lock.withLock { () -> Bool in
                    if !self.untracedFlag {
                        self.presentedList.append((seq, at))
                    }
                    if at > 0.0 {
                        if seq > self.onScreenSeq {
                            self.onScreenSeq = seq
                        }
                        return self.watchFlag
                    }
                    return false
                }
                if shouldWake {
                    presentMetal.wakeMain()
                }
            }
        }

        func take(_ out: inout [PresentTimeEntry]) {
            let drained = lock.withLock { () -> [(UInt64, Double)] in
                guard !presentedList.isEmpty else { return [] }
                let copy = presentedList
                presentedList.removeAll(keepingCapacity: true)
                return copy
            }
            guard !drained.isEmpty else { return }
            let now = RuneInstant.now()
            let mediaNow = CACurrentMediaTime()
            for (seq, at) in drained {
                let inst: RuneInstant? = at > 0.0 ? presentMetal.instantAt(now, mediaNow, at) : nil
                out.append((seq, inst))
            }
        }
    }

    private struct HookedEntry {
        var addr: UInt
        var base: AnyClass
        var log: Log
    }

    private static let hookedPrefix = "RunePresentTimed_"
    private static let layersLock = LiveLock()
    // PORT NOTE: Guarded by `layersLock` (`LiveLock`), mirroring `static LAYERS: Mutex<Vec<Hooked>>` in `present_time.rs`.
    nonisolated(unsafe) private static var hookedLayers: [HookedEntry] = []
    // PORT NOTE: Guarded by `layersLock` (`LiveLock`), mirroring `static CLASSES: Mutex<...>` in `present_time.rs`.
    nonisolated(unsafe) private static var hookedClasses: [(ObjectIdentifier, AnyClass)] = []

    private static func originalClass(_ cls: AnyClass) -> AnyClass {
        var hooked: AnyClass? = nil
        var next: AnyClass? = cls
        while let current = next {
            if NSStringFromClass(current).hasPrefix(hookedPrefix) {
                hooked = current
            }
            next = class_getSuperclass(current)
        }
        return hooked.flatMap { class_getSuperclass($0) } ?? CAMetalLayer.self
    }

    private static func makeHookedClass(_ base: AnyClass) -> AnyClass? {
        layersLock.withLock {
            let key = ObjectIdentifier(base)
            if let existing = hookedClasses.first(where: { $0.0 == key })?.1 {
                return existing
            }
            let subName = hookedPrefix + NSStringFromClass(base)
            let cls: AnyClass
            if let existing = objc_getClass(subName) as? AnyClass {
                cls = existing
            } else {
                guard let pair = objc_allocateClassPair(base, subName, 0) else { return nil }
                let sel = NSSelectorFromString("nextDrawable")
                let impBlock: @convention(block) (AnyObject) -> AnyObject? = { receiver in
                    let addr = UInt(bitPattern: Unmanaged.passUnretained(receiver).toOpaque())
                    let entry = presentMetal.layersLock.withLock {
                        presentMetal.hookedLayers.first(where: { $0.addr == addr })
                    }
                    let superCls: AnyClass = entry?.base ?? presentMetal.originalClass(object_getClass(receiver) ?? CAMetalLayer.self)
                    guard let superMethod = class_getInstanceMethod(superCls, sel) else { return nil }
                    typealias NextDrawableIMP = @convention(c) (AnyObject, Selector) -> Unmanaged<AnyObject>?
                    let fn = unsafeBitCast(method_getImplementation(superMethod), to: NextDrawableIMP.self)
                    guard let unmanagedDrawable = fn(receiver, sel) else { return nil }
                    let obj = unmanagedDrawable.takeUnretainedValue()
                    if let log = entry?.log, let mtlDrawable = obj as? (any MTLDrawable) {
                        log.recordDrawable(mtlDrawable)
                    }
                    return obj
                }
                let imp = imp_implementationWithBlock(impBlock)
                _ = class_addMethod(pair, sel, imp, "@@:")
                objc_registerClassPair(pair)
                cls = pair
            }
            hookedClasses.append((key, cls))
            return cls
        }
    }

    /// A surface's layer, reporting present times to a `Log` until dropped.
    final class LayerHook {
        private let layer: CAMetalLayer
        private let base: AnyClass
        private let hooked: AnyClass

        private init(layer: CAMetalLayer, base: AnyClass, hooked: AnyClass) {
            self.layer = layer
            self.base = base
            self.hooked = hooked
        }

        static func attach(_ surface: MetalSurface, _ log: Log) -> LayerHook? {
            guard let layer = surface.layer else { return nil }
            return hook(layer, log)
        }

        static func hook(_ layer: CAMetalLayer, _ log: Log) -> LayerHook? {
            guard let base = object_getClass(layer),
                  let cls = makeHookedClass(base) else {
                return nil
            }
            let addr = UInt(bitPattern: Unmanaged.passUnretained(layer).toOpaque())
            layersLock.withLock {
                hookedLayers.append(HookedEntry(addr: addr, base: base, log: log))
            }
            object_setClass(layer, cls)
            return LayerHook(layer: layer, base: base, hooked: cls)
        }

        deinit {
            if let current = object_getClass(layer), current === hooked {
                object_setClass(layer, base)
            }
            let addr = UInt(bitPattern: Unmanaged.passUnretained(layer).toOpaque())
            presentMetal.layersLock.withLock {
                presentMetal.hookedLayers.removeAll { $0.addr == addr }
            }
        }
    }
}
#endif
