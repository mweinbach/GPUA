// Ported from: crates/gpui_macos/src/dispatcher.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(macOS)
import Darwin.Mach
import Foundation
import GPUI
import Scheduler

/// macOS `PlatformDispatcher` backed by Grand Central Dispatch and Mach real-time threads.
public struct MacDispatcher: PlatformDispatcher, Sendable {
    public init() {}

    public static func new() -> MacDispatcher {
        MacDispatcher()
    }

    public func isMainThread() -> Bool {
        Thread.isMainThread
    }

    public func dispatch(_ runnable: @escaping @Sendable () -> Void, priority: Priority) {
        let qos: DispatchQoS.QoSClass
        switch priority {
        case .realtimeAudio:
            spawnRealtime(runnable)
            return
        case .high:
            qos = .userInitiated
        case .medium:
            qos = .default
        case .low:
            qos = .utility
        }
        DispatchQueue.global(qos: qos).async(execute: runnable)
    }

    public func dispatchOnMainThread(_ runnable: @escaping @Sendable () -> Void, priority: Priority) {
        _ = priority
        DispatchQueue.main.async(execute: runnable)
    }

    public func dispatchAfter(duration: TimeInterval, _ runnable: @escaping @Sendable () -> Void) {
        DispatchQueue.global(qos: .userInitiated).asyncAfter(
            deadline: .now() + duration,
            execute: runnable
        )
    }

    public func spawnRealtime(_ f: @escaping @Sendable () -> Void) {
        let thread = Thread {
            Self.setAudioThreadPriority()
            f()
        }
        thread.name = "gpui-realtime-audio"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    public func now() -> Date {
        Date()
    }

    private static func setAudioThreadPriority() {
        let machThread = pthread_mach_thread_np(pthread_self())

        var extendedPolicy = thread_extended_policy_data_t(timeshare: 0)
        let extendedCount = mach_msg_type_number_t(
            MemoryLayout<thread_extended_policy_data_t>.size / MemoryLayout<integer_t>.size
        )
        _ = withUnsafeMutablePointer(to: &extendedPolicy) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(extendedCount)) { intPtr in
                thread_policy_set(
                    machThread,
                    thread_policy_flavor_t(THREAD_EXTENDED_POLICY),
                    intPtr,
                    extendedCount
                )
            }
        }

        var precedencePolicy = thread_precedence_policy_data_t(importance: 63)
        let precedenceCount = mach_msg_type_number_t(
            MemoryLayout<thread_precedence_policy_data_t>.size / MemoryLayout<integer_t>.size
        )
        _ = withUnsafeMutablePointer(to: &precedencePolicy) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(precedenceCount)) { intPtr in
                thread_policy_set(
                    machThread,
                    thread_policy_flavor_t(THREAD_PRECEDENCE_POLICY),
                    intPtr,
                    precedenceCount
                )
            }
        }

        let guaranteedAudioDutyCycle: Float = 0.75
        let maxAudioDutyCycle: Float = 0.85
        let timeQuantumMs: Float = 2.9 // ~128 frames @ 44.1kHz
        let audioTimeNeededMs = guaranteedAudioDutyCycle * timeQuantumMs
        let maxTimeAllowedMs = maxAudioDutyCycle * timeQuantumMs

        var timebaseInfo = mach_timebase_info_data_t(numer: 0, denom: 0)
        mach_timebase_info(&timebaseInfo)
        guard timebaseInfo.numer > 0 else { return }

        let msToAbsTime = (Float(timebaseInfo.denom) / Float(timebaseInfo.numer)) * 1_000_000.0
        var timeConstraints = thread_time_constraint_policy_data_t(
            period: UInt32(timeQuantumMs * msToAbsTime),
            computation: UInt32(audioTimeNeededMs * msToAbsTime),
            constraint: UInt32(maxTimeAllowedMs * msToAbsTime),
            preemptible: 0
        )
        let constraintCount = mach_msg_type_number_t(
            MemoryLayout<thread_time_constraint_policy_data_t>.size / MemoryLayout<integer_t>.size
        )
        _ = withUnsafeMutablePointer(to: &timeConstraints) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(constraintCount)) { intPtr in
                thread_policy_set(
                    machThread,
                    thread_policy_flavor_t(THREAD_TIME_CONSTRAINT_POLICY),
                    intPtr,
                    constraintCount
                )
            }
        }
    }
}
#endif
