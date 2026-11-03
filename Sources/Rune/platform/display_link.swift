// Ported from: crates/rune/src/platform/display_link.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! One drawable submission per display tick. Metal's drawable pool is not a frame clock:
//! acquisition may return immediately even with FIFO presentation enabled. The exception is a
//! frame after rest, such as the first after a key press: it draws at once (`rested`).
//!
//! Low Power Mode caps a ProMotion panel at 60 Hz while CVDisplayLink, CADisplayLink and
//! NSScreen all still report 120 Hz. Submitting on every tick then fills the drawable queue
//! with a few fast frames before backpressure settles it at 60 Hz, so pace at the cap instead.

#if os(macOS)
import AppKit
import CoreGraphics
import CoreVideo
import Foundation
#endif

let lowPowerFramePeriod: Duration = .nanoseconds(1_000_000_000 / 60)
private let displayLinkRetryDelay: Duration = .seconds(1)

enum DisplayLinkPacing: Sendable, Equatable {
    case displayLink
    case failed(Int32)
    case unpaced
    case idle
}

/// When a surface's next frame draws.
enum DisplayLinkOpportunity: Sendable, Equatable {
    /// On this tick, which presents at its target.
    case tick(RuneInstant)
    /// At once, aimed at no tick (`rested`).
    case now
    /// On a later tick.
    case wait

    /// The frame's target presentation time if it draws now (`.some(nil)` when aimed at no tick),
    /// or `nil` when it waits.
    func target() -> RuneInstant?? {
        switch self {
        case .tick(let target):
            return .some(target)
        case .now:
            return .some(nil)
        case .wait:
            return nil
        }
    }
}

func displayLinkTargetTime(
    _ now: RuneInstant,
    hostNow: UInt64,
    hostTarget: UInt64,
    frequency: Double
) -> RuneInstant {
    guard frequency > 0 else { return now }
    let diff = hostTarget >= hostNow ? (hostTarget - hostNow) : (hostNow - hostTarget)
    let nanos = Int64((Double(diff) / frequency * 1_000_000_000.0).rounded())
    let delta = Duration.nanoseconds(nanos)
    return hostTarget >= hostNow ? now.adding(delta) : now.adding(.zero - delta)
}

/// A fresh tick wins. Without one, a surface that has rested draws at once rather than wait
/// for the link to start or tick, which after idle took one to two refreshes.
func displayLinkOpportunity(
    _ tick: RuneInstant?,
    _ last: RuneInstant?,
    _ lastTarget: RuneInstant?,
    _ now: RuneInstant,
    _ period: Duration
) -> DisplayLinkOpportunity {
    if let target = tick, displayLinkPermits(last, lastTarget, target, now, period) {
        return .tick(target)
    }
    if displayLinkRested(last, lastTarget, now, period) {
        return .now
    }
    return .wait
}

func displayLinkPermits(
    _ last: RuneInstant?,
    _ lastTarget: RuneInstant?,
    _ target: RuneInstant,
    _ now: RuneInstant,
    _ period: Duration
) -> Bool {
    let half = period / 2
    let threeQuarters = (period * 3) / 4
    guard now < target else { return false }
    if let lastTarget, target < lastTarget.adding(threeQuarters) {
        return false
    }
    if let last, now.durationSince(last) < half {
        return false
    }
    return true
}

/// Whether the last frame has surely reached the display: its target has passed, and a whole
/// refresh has gone by since it was submitted, plus half of one for the GPU.
func displayLinkRested(
    _ last: RuneInstant?,
    _ lastTarget: RuneInstant?,
    _ now: RuneInstant,
    _ period: Duration
) -> Bool {
    if let target = lastTarget, target > now {
        return false
    }
    let oneAndHalf = (period * 3) / 2
    if let last, now.durationSince(last) < oneAndHalf {
        return false
    }
    return true
}

/// A stopped link has no tick waiting (`stop` clears it), so a rested surface's next frame is
/// `.now` until the link starts: deciding first costs it no pacing.
func displayLinkDefersStart(
    _ running: Bool,
    _ last: RuneInstant?,
    _ lastTarget: RuneInstant?,
    _ now: RuneInstant,
    _ period: Duration
) -> Bool {
    !running && displayLinkRested(last, lastTarget, now, period)
}

#if os(macOS)
private let displayLinkFailureLock = LiveLock()
// PORT NOTE: Guarded by `displayLinkFailureLock`, matching `CREATE_FAILED` and `LAST_FAILURE` in `display_link.rs`.
nonisolated(unsafe) private var displayLinkCreateFailedFlag: Bool = false
// PORT NOTE: Guarded by `displayLinkFailureLock`, matching `LAST_FAILURE: Mutex<Option<(i32, Instant)>>`.
nonisolated(unsafe) private var displayLinkLastFailureState: (Int32, RuneInstant)? = nil

/// Why the last display link couldn't be made, while no creation has succeeded since.
func displayLinkFailure() -> Int32? {
    displayLinkFailureLock.withLock {
        displayLinkLastFailureState?.0
    }
}

func displayLinkPacing(_ link: DisplayLink?, moving: Bool) -> DisplayLinkPacing {
    if let link, link.running() {
        return .displayLink
    }
    if link == nil, let status = displayLinkFailure() {
        return .failed(status)
    }
    return moving ? .unpaced : .idle
}

private func displayLinkLowPowerCaps(_ display: UInt32?) -> Bool {
    guard let display, CGDisplayIsBuiltin(display) != 0 else { return false }
    if #available(macOS 12.0, *) {
        return ProcessInfo.processInfo.isLowPowerModeEnabled
    }
    return false
}

// PORT NOTE: Synchronized via `lock` (`LiveLock`) because `CVDisplayLinkOutputCallback` fires on CoreVideo's high-priority display thread.
private final class DisplayLinkCallbackBox: @unchecked Sendable {
    private let lock = LiveLock()
    private var targetValue: UInt64 = 0
    private var periodNsValue: UInt64 = 1_000_000_000 / 60
    let wake: Waker
    let hostFrequency: Double

    init(wake: @escaping Waker, hostFrequency: Double) {
        self.wake = wake
        self.hostFrequency = hostFrequency
    }

    func periodNs() -> UInt64 {
        lock.withLock { periodNsValue }
    }

    func setPeriodNs(_ ns: UInt64) {
        lock.withLock { periodNsValue = ns }
    }

    func swapTarget(_ next: UInt64) -> UInt64 {
        lock.withLock {
            let prev = targetValue
            targetValue = next
            return prev
        }
    }

    func clearTarget() {
        lock.withLock { targetValue = 0 }
    }
}

private func displayLinkTickCallback(
    _ displayLink: CVDisplayLink,
    _ inNow: UnsafePointer<CVTimeStamp>,
    _ inOutputTime: UnsafePointer<CVTimeStamp>,
    _ flagsIn: CVOptionFlags,
    _ flagsOut: UnsafeMutablePointer<CVOptionFlags>,
    _ context: UnsafeMutableRawPointer?
) -> CVReturn {
    _ = displayLink
    _ = inNow
    _ = flagsIn
    _ = flagsOut
    guard let context else { return kCVReturnSuccess }
    let callback = Unmanaged<DisplayLinkCallbackBox>.fromOpaque(context).takeUnretainedValue()
    let output = inOutputTime.pointee
    if output.videoTimeScale > 0 && output.videoRefreshPeriod > 0 {
        let periodSecs = Double(output.videoRefreshPeriod) / Double(output.videoTimeScale)
        if periodSecs > 0 {
            callback.setPeriodNs(UInt64((periodSecs * 1_000_000_000.0).rounded()))
        }
    }
    let hostTimeValidFlag = UInt64(CVTimeStampFlags.hostTimeValid.rawValue)
    let target: UInt64
    if (output.flags & hostTimeValidFlag) != 0 {
        target = output.hostTime
    } else {
        let extra = UInt64(Double(callback.periodNs()) * 1e-9 * callback.hostFrequency)
        target = CVGetCurrentHostTime() + extra
    }
    let pending = callback.swapTarget(target) != 0
    if !pending {
        callback.wake()
    }
    return kCVReturnSuccess
}

final class DisplayLink {
    private let link: CVDisplayLink
    private let callback: DisplayLinkCallbackBox
    private var lastPresent: RuneInstant? = nil
    private var lastTarget: RuneInstant? = nil
    private var display: UInt32? = nil
    private var capped: Bool = false
    private var isRunning: Bool = false

    private init(link: CVDisplayLink, callback: DisplayLinkCallbackBox) {
        self.link = link
        self.callback = callback
    }

    func running() -> Bool { isRunning }

    func refreshHz() -> Double {
        let p = framePeriod()
        let secs = Double(p.components.seconds) + Double(p.components.attoseconds) * 1e-18
        return secs > 0 ? (1.0 / secs) : 60.0
    }

    private func framePeriod() -> Duration {
        let period = Duration.nanoseconds(Int64(callback.periodNs()))
        return (capped && period < lowPowerFramePeriod) ? lowPowerFramePeriod : period
    }

    static func new(displayId: UInt32?, wake: @escaping Waker) -> DisplayLink? {
        var rawLink: CVDisplayLink? = nil
        let status = CVDisplayLinkCreateWithActiveCGDisplays(&rawLink)
        if status != kCVReturnSuccess || rawLink == nil {
            let shouldLog = displayLinkFailureLock.withLock { () -> Bool in
                let prev = displayLinkCreateFailedFlag
                displayLinkCreateFailedFlag = true
                displayLinkLastFailureState = (status, .now())
                return !prev
            }
            if shouldLog {
                fputs("display link creation failed: \(status)\n", stderr)
            }
            return nil
        }
        let recovered = displayLinkFailureLock.withLock { () -> Bool in
            let prev = displayLinkCreateFailedFlag
            displayLinkCreateFailedFlag = false
            displayLinkLastFailureState = nil
            return prev
        }
        if recovered {
            fputs("display link created once a display woke\n", stderr)
        }
        let link = rawLink!
        let callback = DisplayLinkCallbackBox(wake: wake, hostFrequency: CVGetHostClockFrequency())
        let callbackPtr = Unmanaged.passUnretained(callback).toOpaque()
        let cbStatus = CVDisplayLinkSetOutputCallback(link, displayLinkTickCallback, callbackPtr)
        if cbStatus != kCVReturnSuccess {
            fputs("display link callback failed: \(cbStatus)\n", stderr)
            return nil
        }
        let instance = DisplayLink(link: link, callback: callback)
        instance.updateDisplay(displayId)
        return instance
    }

    static func retry(displayId: UInt32?, wake: @escaping Waker) -> DisplayLink? {
        let tooSoon = displayLinkFailureLock.withLock { () -> Bool in
            guard let (_, at) = displayLinkLastFailureState else { return false }
            return at.elapsed() < displayLinkRetryDelay
        }
        if tooSoon { return nil }
        return Self.new(displayId: displayId, wake: wake)
    }

    func updateDisplay(_ nextDisplay: UInt32?) {
        if nextDisplay != display {
            if let id = nextDisplay {
                CVDisplayLinkSetCurrentCGDisplay(link, id)
            }
            display = nextDisplay
        }
        capped = displayLinkLowPowerCaps(display)
    }

    @discardableResult
    func start() -> Bool {
        if !isRunning {
            let status = CVDisplayLinkStart(link)
            if status != kCVReturnSuccess {
                fputs("display link start failed: \(status)\n", stderr)
                return false
            }
            isRunning = true
            capped = displayLinkLowPowerCaps(display)
        }
        return true
    }

    func nextFrame() -> DisplayLinkOpportunity {
        if !start() { return .now }
        let hostTarget = callback.swapTarget(0)
        let now = RuneInstant.now()
        let tick: RuneInstant? = hostTarget != 0
            ? displayLinkTargetTime(
                now,
                hostNow: CVGetCurrentHostTime(),
                hostTarget: hostTarget,
                frequency: callback.hostFrequency
            )
            : nil
        let next = displayLinkOpportunity(tick, lastPresent, lastTarget, now, framePeriod())
        switch next {
        case .tick(let target):
            lastTarget = target
        case .now:
            lastTarget = now
        case .wait:
            break
        }
        return next
    }

    func defersStart(_ now: RuneInstant) -> Bool {
        displayLinkDefersStart(isRunning, lastPresent, lastTarget, now, framePeriod())
    }

    func tickAfter(_ now: RuneInstant) -> RuneInstant {
        now.adding(framePeriod())
    }

    func presented(_ at: RuneInstant) {
        lastPresent = at
    }

    func stop() {
        if isRunning {
            CVDisplayLinkStop(link)
            isRunning = false
        }
        callback.clearTarget()
    }

    deinit {
        stop()
    }
}
#endif
