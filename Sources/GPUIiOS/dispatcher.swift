// Ported from: crates/gpui_ios/src/dispatcher.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(iOS) || os(visionOS)
import Dispatch
import Foundation
import GPUI
import Scheduler

// MARK: - iOS Grand Central Dispatch Task Dispatcher

/// Grand Central Dispatch implementation of `PlatformDispatcher` for iOS and visionOS.
public struct IosDispatcher: PlatformDispatcher, Sendable {
    public init() {}

    /// Creates a new `IosDispatcher` matching upstream `IosDispatcher::new()`.
    public static func new() -> IosDispatcher {
        IosDispatcher()
    }

    // MARK: - PlatformDispatcher Conformance

    public func isMainThread() -> Bool {
        Thread.isMainThread
    }

    public func dispatch(_ runnable: @escaping @Sendable () -> Void, priority: Priority) {
        let qos = Self.queuePriority(priority)
        DispatchQueue.global(qos: qos).async {
            Self.runRunnable(runnable)
        }
    }

    public func dispatchOnMainThread(_ runnable: @escaping @Sendable () -> Void, priority: Priority) {
        _ = priority
        Self.dispatchGetMainQueue().async {
            Self.runRunnable(runnable)
        }
    }

    public func dispatchAfter(duration: TimeInterval, _ runnable: @escaping @Sendable () -> Void) {
        let deltaNs = Self.durationToDispatchDelta(duration)
        let deadline = DispatchTime.now() + .nanoseconds(Int(clamping: deltaNs))
        DispatchQueue.global(qos: .default).asyncAfter(deadline: deadline) {
            Self.runRunnable(runnable)
        }
    }

    public func spawnRealtime(_ f: @escaping @Sendable () -> Void) {
        let thread = Thread {
            f()
        }
        thread.name = "gpui-ios-realtime"
        thread.qualityOfService = .userInteractive
        thread.threadPriority = 1.0
        thread.start()
    }

    public func now() -> Date {
        Date()
    }

    // MARK: - Upstream Helper Parity

    /// Executes a scheduled closure inside an Objective-C autoreleasepool so transient UIKit /
    /// CoreText objects created on worker or main queues are drained promptly.
    static func runRunnable(_ runnable: @Sendable () -> Void) {
        autoreleasepool {
            runnable()
        }
    }

    /// Returns the main GCD queue (`DispatchQueue.main`), matching upstream
    /// `IosDispatcher::dispatch_get_main_queue()`.
    static func dispatchGetMainQueue() -> DispatchQueue {
        dispatchGetMainQueuePtr()
    }

    /// Maps GPUI `Priority` levels onto GCD quality-of-service classes, matching upstream
    /// `IosDispatcher::queue_priority`.
    static func queuePriority(_ priority: Priority) -> DispatchQoS.QoSClass {
        switch priority {
        case .realtimeAudio, .high:
            return .userInitiated
        case .medium:
            return .default
        case .low:
            return .utility
        }
    }

    /// Converts a `TimeInterval` (seconds) into a non-negative nanosecond delta for GCD timers,
    /// clamping negative or overflowing intervals safely.
    static func durationToDispatchDelta(_ duration: TimeInterval) -> Int64 {
        guard duration.isFinite, duration > 0 else {
            return 0
        }
        let ns = duration * 1_000_000_000.0
        if ns >= Double(Int64.max) {
            return Int64.max
        }
        return Int64(ns)
    }
}

/// Returns the main GCD queue handle (`DispatchQueue.main`), replacing upstream's manual
/// `_dispatch_main_q` pointer helper (`dispatch_get_main_queue_ptr`).
func dispatchGetMainQueuePtr() -> DispatchQueue {
    DispatchQueue.main
}
#endif
