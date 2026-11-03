// Ported from: crates/rune/src/frame/surface_stats.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! What each window and overlay surface asked for, drew and missed, as totals and per-second
//! rates. A surface that keeps failing to get drawables, or redraws unpaced, hundreds of times
//! a second for more than two seconds is a bug (it spins a core and, on wgpu 30.0.1, leaks a
//! texture id per failed acquisition), so the meter says so once, in release builds too.

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Android)
import Android
#elseif canImport(WASILibc)
import WASILibc
#elseif canImport(WinSDK)
import WinSDK
#endif

/// Reason a surface acquisition yielded no drawable (`window::Missed`).
enum SurfaceMissed: Sendable, Equatable {
    case occluded
    case timeout
    case outdated
}

/// Counts of one surface's frame work.
public struct SurfaceCounts: Sendable, Equatable {
    /// Frames the host set out to draw while shown, once its display link (if running) gave it
    /// the frame.
    public var redraws: UInt64
    /// Redraws that waited for nothing: no display tick, vsync, timer or event came first.
    public var unpaced: UInt64
    /// Frames presented.
    public var presents: UInt64
    /// Acquisitions skipped because the surface was known to be occluded, so the backend was never asked.
    public var skipped: UInt64
    /// `getCurrentTexture` calls that gave no drawable: occluded.
    public var occluded: UInt64
    /// ...timed out, or failed some other passing way.
    public var timeouts: UInt64
    /// ...outdated or lost, after reconfiguring.
    public var outdated: UInt64
    /// Event-loop turns while the surface's host lived.
    public var turns: UInt64
    /// Turns a deadline or poll started, rather than an event.
    public var wakes: UInt64

    public init(
        redraws: UInt64 = 0,
        unpaced: UInt64 = 0,
        presents: UInt64 = 0,
        skipped: UInt64 = 0,
        occluded: UInt64 = 0,
        timeouts: UInt64 = 0,
        outdated: UInt64 = 0,
        turns: UInt64 = 0,
        wakes: UInt64 = 0
    ) {
        self.redraws = redraws
        self.unpaced = unpaced
        self.presents = presents
        self.skipped = skipped
        self.occluded = occluded
        self.timeouts = timeouts
        self.outdated = outdated
        self.turns = turns
        self.wakes = wakes
    }

    /// Every `getCurrentTexture` call that gave no drawable.
    public func failed() -> UInt64 {
        occluded + timeouts + outdated
    }

    func since(_ earlier: SurfaceCounts) -> SurfaceCounts {
        SurfaceCounts(
            redraws: redraws - earlier.redraws,
            unpaced: unpaced - earlier.unpaced,
            presents: presents - earlier.presents,
            skipped: skipped - earlier.skipped,
            occluded: occluded - earlier.occluded,
            timeouts: timeouts - earlier.timeouts,
            outdated: outdated - earlier.outdated,
            turns: turns - earlier.turns,
            wakes: wakes - earlier.wakes
        )
    }

    /// Per second over `secs`, rounded.
    func per(_ secs: Double) -> SurfaceCounts {
        let r: (UInt64) -> UInt64 = { n in UInt64((Double(n) / secs).rounded()) }
        return SurfaceCounts(
            redraws: r(redraws),
            unpaced: r(unpaced),
            presents: r(presents),
            skipped: r(skipped),
            occluded: r(occluded),
            timeouts: r(timeouts),
            outdated: r(outdated),
            turns: r(turns),
            wakes: r(wakes)
        )
    }
}

/// What paces a surface's frames.
public enum Pacing: Sendable, Equatable, CustomStringConvertible {
    /// Not drawing: idle, hidden or occluded.
    case idle
    /// A running display link (macOS).
    case displayLink
    /// Moving with no display link running: a frame-interval timer paces it (macOS).
    case unpaced
    /// The present queue paces it (platforms without a display link).
    case vsync
    /// The display link couldn't be made (every display asleep, say); CoreVideo's status.
    case failed(Int32)

    public static let `default`: Pacing = .idle

    public var description: String {
        switch self {
        case .idle: return "idle"
        case .displayLink: return "display link"
        case .unpaced: return "unpaced"
        case .vsync: return "vsync"
        case .failed(let status): return "display link failed (\(status))"
        }
    }
}

private let SURFACE_SPIN_RATE: UInt64 = 400
private let SURFACE_SPIN_SECONDS: UInt32 = 2
private let SURFACE_WINDOW: Duration = .seconds(1)
private let SURFACE_STALE: Duration = .seconds(2)

/// One surface's frame counts: `WindowHandle.surfaceStats`, `OverlayHandle.surfaceStats`
/// and `Runtime.surfaceStats`. Totals and pacing are current; rates roll over once a second.
public struct SurfaceStats: Sendable, Equatable {
    /// The window's key, or the overlay's name.
    public var name: String
    public var totals: SurfaceCounts
    /// Over the last second the surface was busy; zero once it has rested two seconds.
    public var perSecond: SurfaceCounts
    public var pacing: Pacing
    var published: RuneInstant?

    public init(
        name: String = "",
        totals: SurfaceCounts = SurfaceCounts(),
        perSecond: SurfaceCounts = SurfaceCounts(),
        pacing: Pacing = .idle
    ) {
        self.name = name
        self.totals = totals
        self.perSecond = perSecond
        self.pacing = pacing
        self.published = nil
    }

    /// Rates older than two seconds describe a surface that has since gone quiet.
    func aged(_ now: RuneInstant) -> SurfaceStats {
        var copy = self
        if copy.published.map({ now.durationSince($0) > SURFACE_STALE }) ?? true {
            copy.perSecond = SurfaceCounts()
        }
        return copy
    }

    /// One line: `main: 120 presents/s, 0 failed/s (...), pacing: display link`.
    public func summary() -> String {
        let (t, r) = (totals, perSecond)
        return "\(name): \(r.redraws) redraws/s (\(r.unpaced) unpaced), \(r.presents) presents/s, \(r.failed()) failed acquires/s (occluded \(r.occluded), timeout \(r.timeouts), outdated \(r.outdated)), \(r.skipped) skipped/s, \(r.turns) loop turns/s (\(r.wakes) wakes); totals \(t.presents) presents, \(t.failed()) failed, \(t.skipped) skipped; pacing: \(pacing)"
    }
}

/// Shared mutex-guarded box of `SurfaceStats` (`Arc<Mutex<SurfaceStats>>`).
// PORT NOTE: Synchronized via `lock` (`LiveLock`), mirroring `Arc<Mutex<SurfaceStats>>` in `surface_stats.rs`.
final class SharedSurfaceStats: @unchecked Sendable {
    private let lock = LiveLock()
    private var storage: SurfaceStats

    init(_ initial: SurfaceStats = SurfaceStats()) {
        self.storage = initial
    }

    func withLock<R>(_ body: (inout SurfaceStats) -> R) -> R {
        lock.withLock { body(&storage) }
    }
}

/// Counts one surface's frames, rolls them into per-second rates and publishes them.
struct SurfaceMeter: Sendable {
    private var currentTotals: SurfaceCounts
    /// `totals` when the current one-second window began.
    private var base: SurfaceCounts
    private(set) var started: RuneInstant
    private var pacing: Pacing
    /// A timer or event came since the last redraw.
    private var waitedFlag: Bool
    /// Seconds in a row over `SURFACE_SPIN_RATE`.
    private var hot: UInt32
    private var warned: Bool
    private let sharedBox: SharedSurfaceStats

    init(_ name: String, _ shared: SharedSurfaceStats = SharedSurfaceStats()) {
        shared.withLock { $0.name = name }
        self.currentTotals = SurfaceCounts()
        self.base = SurfaceCounts()
        self.started = .now()
        self.pacing = .idle
        self.waitedFlag = false
        self.hot = 0
        self.warned = false
        self.sharedBox = shared
    }

    static func new(_ name: String, _ shared: SharedSurfaceStats = SharedSurfaceStats()) -> SurfaceMeter {
        SurfaceMeter(name, shared)
    }

    func shared() -> SharedSurfaceStats { sharedBox }
    func totals() -> SurfaceCounts { currentTotals }

    /// A redraw. `paced` when a display tick or vsync paces it; otherwise it's unpaced unless
    /// a timer or event (`waited`) came since the last one.
    mutating func redraw(_ paced: Bool) {
        currentTotals.redraws += 1
        if !paced && !waitedFlag {
            currentTotals.unpaced += 1
        }
        waitedFlag = false
        _ = tick(.now())
    }

    /// An event the surface's host handled, which may ask for the next redraw.
    mutating func waited() {
        waitedFlag = true
    }

    mutating func presented() {
        currentTotals.presents += 1
        _ = tick(.now())
    }

    mutating func skipped() {
        currentTotals.skipped += 1
        _ = tick(.now())
    }

    mutating func failed(_ missed: SurfaceMissed) {
        switch missed {
        case .occluded: currentTotals.occluded += 1
        case .timeout: currentTotals.timeouts += 1
        case .outdated: currentTotals.outdated += 1
        }
        _ = tick(.now())
    }

    /// An event-loop turn, `woke` by a deadline or poll rather than an event. A deadline that
    /// was still ahead when the loop slept (`waited`) paces the redraw it asks for.
    mutating func turn(_ woke: Bool, _ waited: Bool) {
        currentTotals.turns += 1
        if woke {
            currentTotals.wakes += 1
        }
        waitedFlag = waitedFlag || waited
        _ = tick(.now())
    }

    mutating func setPacing(_ pacing: Pacing) {
        self.pacing = pacing
        sharedBox.withLock { $0.pacing = pacing }
    }

    /// Publishes the totals, and rolls the rates over once a second has passed; returns the spin
    /// warning if this roll triggered it.
    @discardableResult
    mutating func tick(_ now: RuneInstant) -> String? {
        let elapsed = now.durationSince(started)
        let totalsSnap = currentTotals
        let baseSnap = base
        let elapsedSecs = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) * 1e-18

        var rolledSummary: String? = nil
        var isHot = false
        sharedBox.withLock { stats in
            stats.totals = totalsSnap
            guard elapsed >= SURFACE_WINDOW else { return }
            let rates = totalsSnap.since(baseSnap).per(elapsedSecs)
            stats.perSecond = rates
            stats.published = now
            isHot = rates.failed() > SURFACE_SPIN_RATE || rates.unpaced > SURFACE_SPIN_RATE
            rolledSummary = stats.summary()
        }

        guard let summary = rolledSummary else { return nil }
        hot = isHot ? (hot + 1) : 0
        base = currentTotals
        started = now
        if hot < SURFACE_SPIN_SECONDS || warned {
            return nil
        }
        warned = true
        let warning = "rune: surface has spun for \(hot) s, a bug in Rune: \(summary)"
        writeStderrLine(warning)
        return warning
    }
}

/// Whether the loop turned on a deadline that was still ahead when it slept: an overdue one
/// turns it at once, as a poll does.
func surfaceSlept(start: RuneInstant, requestedResume: RuneInstant) -> Bool {
    requestedResume > start
}

/// The published stats, with rates zeroed once they are stale.
func readSurfaceStats(_ shared: SharedSurfaceStats) -> SurfaceStats {
    shared.withLock { $0 }.aged(.now())
}

private func writeStderrLine(_ line: String) {
    let bytes = Array((line + "\n").utf8)
    bytes.withUnsafeBufferPointer { buf in
        guard let base = buf.baseAddress else { return }
        #if canImport(WinSDK)
        _ = _write(2, base, UInt32(buf.count))
        #else
        _ = write(2, base, buf.count)
        #endif
    }
}
