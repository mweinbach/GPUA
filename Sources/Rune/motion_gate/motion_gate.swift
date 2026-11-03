// Ported from: crates/rune/src/motion_gate/mod.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! A motion gate for an app's own tests: drive the real app headless on the virtual clock, record
//! every element's presented rect, visible part and opacity each frame, and list what a person
//! would see go wrong.

/// A runtime being recorded: every `step` frames it on the virtual clock and samples its element tree into `rec`.
public final class MotionGateRun<S> {
    public var rt: Runtime<S>
    public var rec: MotionGateRecording
    /// Seconds per frame.
    public var dt: Double

    public init(_ rt: Runtime<S>, _ hz: Double) {
        _ = rt.frame(0.0)
        self.rt = rt
        self.rec = MotionGateRecording.new(rt.viewport, hz)
        self.dt = 1.0 / hz
    }

    public static func new(_ rt: Runtime<S>, _ hz: Double) -> MotionGateRun<S> {
        MotionGateRun(rt, hz)
    }

    /// Steps `secs` unrecorded (setting up, before the run).
    public func idle(_ secs: Double) {
        let count = Int((secs / dt).rounded())
        if count > 0 {
            for _ in 0..<count {
                _ = rt.frame(dt)
            }
        }
    }

    /// Records one frame.
    public func step() {
        rt.commitWhy = 0
        _ = rt.frame(dt)
        let awake = rt.animating
        rec.awake.append(awake)
        let why = rt.commitWhy
        rt.commitWhy = 0
        rec.commits(rt.scrolling(), why)
        let els = rt.elements()
        rec.sample(els)
    }

    public func stepN(_ n: Int) {
        if n > 0 {
            for _ in 0..<n {
                step()
            }
        }
    }

    /// Records `secs` of frames.
    public func play(_ secs: Double) {
        stepN(Int((secs / dt).rounded()))
    }

    /// An input on the next frame: `f` runs, then the frame it lands on is recorded.
    public func act(_ what: String, _ f: (Runtime<S>) -> Void) {
        rec.input(what)
        f(rt)
        step()
    }

    /// Marks the cell's motion as over from the next frame.
    public func quiet() {
        rec.quietFrom = rec.frames
    }

    /// A click at the middle of the element keyed `key`.
    public static func tap(_ rt: Runtime<S>, _ key: String) {
        guard let (x, y) = rt.find(key) else {
            fatalError("no \(key)")
        }
        rt.pointerMove(x, y)
        rt.pointerDown(x, y)
        rt.pointerUp(x, y)
    }

    /// What the checker finds in the recording.
    public func finish() -> [MotionGateFinding] {
        motionGateCheck(rec)
    }
}

/// Namespace mirroring `rune::motion_gate`.
public enum motionGate {
    public typealias Run<S> = MotionGateRun<S>
    public typealias Rule = MotionGateRule
    public typealias Snap = MotionGateSnap
    public typealias Track = MotionGateTrack
    public typealias Recording = MotionGateRecording
    public typealias Finding = MotionGateFinding
    public typealias SheetImage = MotionGateSheetImage
    public typealias Allow = MotionGateAllow
    public typealias Job = MotionGateJob
    public typealias Cell = MotionGateCell
    public typealias Report = MotionGateReport

    public static let RULES: [MotionGateRule] = MOTION_GATE_RULES

    public static func rule(_ kind: String) -> Float { motionGateRule(kind) }
    public static func short(_ path: String) -> String { motionGateShort(path) }
    public static func check(_ rec: MotionGateRecording) -> [MotionGateFinding] { motionGateCheck(rec) }
    public static func dump(_ rec: MotionGateRecording, _ filter: String, _ from: Int, _ to: Int) -> String {
        motionGateDump(rec, filter, from, to)
    }
    public static func sheet(_ rec: MotionGateRecording, _ at: Int, _ focus: String) -> MotionGateSheetImage {
        motionGateSheet(rec, at, focus)
    }
    public static func allowed(_ allow: [MotionGateAllow], _ f: MotionGateFinding, _ cell: String) -> String? {
        motionGateAllowed(allow, f, cell)
    }
    public static func run(_ cells: [(String, MotionGateJob)], _ filter: String) -> [MotionGateCell] {
        motionGateRun(cells, filter)
    }
    public static func report(
        _ cells: [MotionGateCell],
        _ allow: [MotionGateAllow],
        _ listAllowed: Bool,
        _ secs: Float
    ) -> MotionGateReport {
        motionGateReport(cells, allow, listAllowed, secs)
    }
    public static func gate(_ cells: [(String, MotionGateJob)], _ allow: [MotionGateAllow]) {
        motionGateGate(cells, allow)
    }
}

public typealias motion_gate = motionGate
