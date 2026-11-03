// Ported from: crates/rune/src/frame/encoded.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! `App.onFrameEncoded`: what each of a window's frames came to, for apps that log their
//! own frame timing.

/// `App.onFrameEncoded`'s hook.
typealias OnFrameEncoded = (FrameEncoded) -> Void

/// `App.onFrameDrawn`'s hook.
typealias OnFrameDrawn<S> = (Runtime<S>) -> Void

/// What a frame came to.
public enum FrameOutcome: Sendable, Equatable {
    /// Encoded and submitted to the GPU, then presented: a visible window's frame, its first
    /// frame during creation included, or a hidden launcher's.
    case drawn
    /// A frame only a timer asked for, whose build draws what is already on screen: it took
    /// no drawable and encoded nothing.
    case unchanged
    /// Due but not drawn: the window is covered, minimised or occluded, or no drawable came in
    /// time. The runtime may still have stepped.
    case skipped
}

/// One frame a window ran, as `App.onFrameEncoded` reports it.
public struct FrameEncoded: Sendable, Equatable {
    private let atValue: RuneInstant
    private let outcomeValue: FrameOutcome
    private let windowValue: String?
    private let seqValue: UInt64
    private let presentsAtValue: RuneInstant?
    private let updateMsValue: Double?
    private let encodeMsValue: Double?

    init(
        at: RuneInstant,
        outcome: FrameOutcome,
        window: String?,
        seq: UInt64,
        presentsAt: RuneInstant?,
        updateMs: Double?,
        encodeMs: Double?
    ) {
        self.atValue = at
        self.outcomeValue = outcome
        self.windowValue = window
        self.seqValue = seq
        self.presentsAtValue = presentsAt
        self.updateMsValue = updateMs
        self.encodeMsValue = encodeMs
    }

    /// For `.drawn`, when encoding finished: right after the frame's commands were submitted,
    /// before it was presented. Otherwise, when the window decided to draw nothing.
    public func at() -> RuneInstant { atValue }

    public func outcome() -> FrameOutcome { outcomeValue }

    /// The window's key (`WindowSpec.new`; `"main"` for `App.run`).
    public func window() -> String? { windowValue }

    /// This window's reports so far, from 0: one per call, whatever the outcome.
    public func seq() -> UInt64 { seqValue }

    /// The display refresh the window's display link aimed this frame at, when one paced it:
    /// macOS windows that are visible and not being resized. `nil` elsewhere, for `.skipped`
    /// frames, and for a frame drawn at once after the window rested (the first after a key
    /// press, say), which aims at the next refresh without waiting for a tick.
    public func presentsAt() -> RuneInstant? { presentsAtValue }

    /// For `.drawn`, the milliseconds from the frame's start (after its drawable came) until the
    /// runtime had built it: events, `poll`, the view, layout and paint. The same value a
    /// compositor gets as `Frame.updateMs`. `nil` otherwise.
    public func updateMs() -> Double? { updateMsValue }

    /// For `.drawn`, the milliseconds from the end of the update until the frame's commands were
    /// submitted (`at`): uploads, the renderer's prepare and draw, or a compositor's `render`.
    /// CPU wall time; not GPU time, and not the wait to present. `nil` otherwise.
    public func encodeMs() -> Double? { encodeMsValue }
}

private struct FrameReporter {
    var hook: OnFrameEncoded
    var window: String?
    var seq: UInt64
}

/// A window's hooks and the count it numbers reports with. Without a hook every call is one
/// `Optional` check and nothing else, so reporting never changes how the window draws.
struct FrameReports<S> {
    private var reporter: FrameReporter?
    private var drawnHook: OnFrameDrawn<S>?

    init(_ hook: OnFrameEncoded? = nil, _ window: String? = nil) {
        self.reporter = hook.map { FrameReporter(hook: $0, window: window, seq: 0) }
        self.drawnHook = nil
    }

    static func new(_ hook: OnFrameEncoded?, _ window: String?) -> FrameReports<S> {
        FrameReports(hook, window)
    }

    var hasReporter: Bool { reporter != nil }
    var hasDrawnInspector: Bool { drawnHook != nil }

    func inspecting(_ drawn: OnFrameDrawn<S>?) -> FrameReports<S> {
        var copy = self
        copy.drawnHook = drawn
        return copy
    }

    /// The time to report a `.drawn` frame at, taken only when there's a hook.
    func stamp() -> RuneInstant? {
        reporter != nil ? .now() : nil
    }

    /// A frame encoded at `at` (from `stamp`), which started at `started` and spent `updateMs`
    /// of that building.
    mutating func drawn(_ at: RuneInstant?, _ presentsAt: RuneInstant?, _ started: RuneInstant, _ updateMs: Double) {
        guard let at else { return }
        let d = at.durationSince(started)
        let totalMs = (Double(d.components.seconds) + Double(d.components.attoseconds) * 1e-18) * 1000.0
        let encodeMs = max(totalMs - updateMs, 0.0)
        report(.drawn, at, presentsAt, (updateMs, encodeMs))
    }

    /// After a `.drawn` frame: `App.onFrameDrawn` reads the runtime as it presented.
    mutating func inspect(_ rt: Runtime<S>) {
        if let hook = drawnHook {
            hook(rt)
        }
    }

    mutating func unchanged(_ presentsAt: RuneInstant?) {
        if reporter != nil {
            report(.unchanged, .now(), presentsAt, nil)
        }
    }

    mutating func skipped() {
        if reporter != nil {
            report(.skipped, .now(), nil, nil)
        }
    }

    private mutating func report(
        _ outcome: FrameOutcome,
        _ at: RuneInstant,
        _ presentsAt: RuneInstant?,
        _ work: (Double, Double)?
    ) {
        guard var r = reporter else { return }
        let frame = FrameEncoded(
            at: at,
            outcome: outcome,
            window: r.window,
            seq: r.seq,
            presentsAt: presentsAt,
            updateMs: work?.0,
            encodeMs: work?.1
        )
        r.seq += 1
        let hook = r.hook
        reporter = r
        hook(frame)
    }
}
