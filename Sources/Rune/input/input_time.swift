// Ported from: crates/rune/src/input/time.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

#if !os(WASI)
import Foundation
#endif
#if os(macOS) && canImport(AppKit)
import AppKit
#endif

extension RuneInstant {
    public static func + (lhs: RuneInstant, rhs: Duration) -> RuneInstant {
        lhs.adding(rhs)
    }

    public static func - (lhs: RuneInstant, rhs: Duration) -> RuneInstant {
        RuneInstant(lhs.raw.advanced(by: .zero - rhs))
    }

    public func checkedSub(_ duration: Duration) -> RuneInstant? {
        RuneInstant(raw.advanced(by: .zero - duration))
    }
}

#if os(WASI)
// PORT NOTE: Single-threaded WASI stores thread-local input arrival timestamps in module globals on the sole execution thread.
nonisolated(unsafe) private var currentInputTimeWasi: RuneInstant? = nil
// PORT NOTE: Single-threaded WASI stores last dispatched input instant in a module global on the sole execution thread.
nonisolated(unsafe) private var lastInputTimeWasi: RuneInstant? = nil
#else
private let currentInputTimeThreadKey = "gpua.rune.inputTime.current"
private let lastInputTimeThreadKey = "gpua.rune.inputTime.last"
#endif

/// When this thread's windows last took an input event (a key, the pointer, a wheel or a
/// gesture) from the platform: the moment it was dispatched, not its `Tx.inputTime()`, so
/// input dispatched after a frame is always later than that frame. `nil` before any.
public func lastInput() -> RuneInstant? {
    #if os(WASI)
    return lastInputTimeWasi
    #else
    return Thread.current.threadDictionary[lastInputTimeThreadKey] as? RuneInstant
    #endif
}

/// The arrival time of the input being dispatched on this thread, if any.
internal func currentInputTime() -> RuneInstant? {
    #if os(WASI)
    return currentInputTimeWasi
    #else
    return Thread.current.threadDictionary[currentInputTimeThreadKey] as? RuneInstant
    #endif
}

private func setCurrentInputTime(_ value: RuneInstant?) -> RuneInstant? {
    #if os(WASI)
    let previous = currentInputTimeWasi
    currentInputTimeWasi = value
    return previous
    #else
    let dict = Thread.current.threadDictionary
    let previous = dict[currentInputTimeThreadKey] as? RuneInstant
    if let value {
        dict[currentInputTimeThreadKey] = value
    } else {
        dict.removeObject(forKey: currentInputTimeThreadKey)
    }
    return previous
    #endif
}

internal func recordLastInputNow(_ instant: RuneInstant = .now()) {
    #if os(WASI)
    lastInputTimeWasi = instant
    #else
    Thread.current.threadDictionary[lastInputTimeThreadKey] = instant
    #endif
}

/// Holds an arrival time until ended or deallocated, then restores the previous arrival time.
internal final class InputTimeScope {
    private let previous: RuneInstant?
    private var ended: Bool = false

    internal init(_ at: RuneInstant?) {
        self.previous = setCurrentInputTime(at)
    }

    internal func end() {
        guard !ended else { return }
        ended = true
        _ = setCurrentInputTime(previous)
    }

    deinit {
        end()
    }
}

/// Dispatch with `at` as the input's arrival time (`nil` for work no input caused).
internal func inputTimeScope(_ at: RuneInstant?) -> InputTimeScope {
    InputTimeScope(at)
}

/// Scoped helper ensuring the previous input arrival time is deterministically restored on exit.
internal func withInputTimeScope<R>(_ at: RuneInstant?, _ body: () throws -> R) rethrows -> R {
    let scope = InputTimeScope(at)
    defer { scope.end() }
    return try body()
}

/// The input events whose handlers see an arrival time.
internal enum InputEventKind: Sendable, Equatable {
    case key
    case mouse
    case wheel
    case magnify
    case rotate
    case smartMagnify
}

/// Begins an input arrival scope for `kind`: on macOS uses `NSApp.currentEvent?.timestamp` when matching `kind`, else `.now()`.
internal func inputArrived(_ kind: InputEventKind) -> InputTimeScope {
    let now = RuneInstant.now()
    recordLastInputNow(now)
    let stamp = nativeInputInstant(kind) ?? now
    return inputTimeScope(stamp)
}

#if os(macOS) && canImport(AppKit)
private func nativeInputInstant(_ kind: InputEventKind) -> RuneInstant? {
    guard Thread.isMainThread else { return nil }
    return MainActor.assumeIsolated {
        guard let event = NSApplication.shared.currentEvent else {
            return nil
        }
        let ty = event.type
        let matches: Bool
        switch kind {
        case .key:
            matches = (ty == .keyDown || ty == .keyUp || ty == .flagsChanged)
        case .mouse:
            matches = (ty == .leftMouseDown || ty == .leftMouseUp || ty == .rightMouseDown || ty == .rightMouseUp
                || ty == .otherMouseDown || ty == .otherMouseUp || ty == .mouseMoved
                || ty == .leftMouseDragged || ty == .rightMouseDragged || ty == .otherMouseDragged
                || ty == .mouseExited)
        case .wheel:
            matches = (ty == .scrollWheel)
        case .magnify:
            matches = (ty == .magnify)
        case .rotate:
            matches = (ty == .rotate)
        case .smartMagnify:
            matches = (ty == .smartMagnify)
        }
        guard matches else { return nil }
        return sinceBoot(.now(), ProcessInfo.processInfo.systemUptime, event.timestamp)
    }
}
#else
private func nativeInputInstant(_ kind: InputEventKind) -> RuneInstant? {
    _ = kind
    return nil
}
#endif

/// Converts an `NSEvent` timestamp (seconds since boot) to a ``RuneInstant`` relative to `now` and `uptime`.
internal func sinceBoot(_ now: RuneInstant, _ uptime: Double, _ timestamp: Double) -> RuneInstant {
    let age = uptime - timestamp
    if !age.isFinite || age <= 0.0 {
        return now
    }
    let nanos = Int64((age * 1_000_000_000.0).rounded())
    return now.checkedSub(.nanoseconds(nanos)) ?? now
}
