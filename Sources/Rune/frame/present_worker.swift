// Ported from: crates/rune/src/frame/present_worker.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! A thread that finishes, submits and presents a surface's frames, so the event loop's thread
//! records a frame and moves on: command encoding, submission, and presentation are most of a
//! simple frame's CPU time.
//!
//! One job is in flight at most. The owner calls `wait` before it next touches the surface
//! (acquire, configure, drop), because a surface lends one drawable texture at a time.

#if !os(WASI)
import Foundation
#if os(macOS)
import Darwin
#endif

/// Error type used to test and propagate recoverable worker job failures across threads.
// PORT NOTE: Swift traps (`fatalError`) do not unwind across threads like Rust's `catch_unwind`.
// `PresentWorker` supports throwing jobs (`runThrowing` / `waitThrowing`) so failure propagation
// and subsequent caller-thread fallback match `present_worker.rs` deterministically.
struct PresentWorkerFailure: Error, Sendable, Equatable {
    let message: String

    init(_ message: String) {
        self.message = message
    }
}

// PORT NOTE: Synchronized via `condition` (`NSCondition`) across the owner thread and the single
// `"rune present"` worker thread, mirroring the `mpsc` channels and `JoinHandle` in `present_worker.rs`.
private final class PresentWorkerChannel: @unchecked Sendable {
    private let condition = NSCondition()
    private var pendingJob: (@Sendable () throws -> Void)? = nil
    private var shutdown: Bool = false
    private var completedResult: Result<Void, any Error>? = nil
    private var exited: Bool = false

    func submit(_ job: @escaping @Sendable () throws -> Void) -> Bool {
        condition.lock()
        defer { condition.unlock() }
        if exited || shutdown {
            return false
        }
        pendingJob = job
        condition.broadcast()
        return true
    }

    func nextJob() -> (@Sendable () throws -> Void)? {
        condition.lock()
        defer { condition.unlock() }
        while pendingJob == nil && !shutdown {
            condition.wait()
        }
        if let job = pendingJob {
            pendingJob = nil
            return job
        }
        return nil
    }

    func finishJob(_ result: Result<Void, any Error>) {
        condition.lock()
        completedResult = result
        condition.broadcast()
        condition.unlock()
    }

    func markExited() {
        condition.lock()
        exited = true
        condition.broadcast()
        condition.unlock()
    }

    func waitJob() -> Result<Void, any Error>? {
        condition.lock()
        defer { condition.unlock() }
        while completedResult == nil && !exited {
            condition.wait()
        }
        let r = completedResult
        completedResult = nil
        return r
    }

    func closeAndJoin() {
        condition.lock()
        shutdown = true
        condition.broadcast()
        while !exited {
            condition.wait()
        }
        condition.unlock()
    }
}

/// Single-lane background thread for finishing, submitting, and presenting surface frames.
final class PresentWorker {
    private var channel: PresentWorkerChannel?
    private var inFlight: Bool = false
    private var hasThread: Bool = false

    private init(_ channel: PresentWorkerChannel) {
        self.channel = channel
        self.hasThread = true
    }

    /// `nil` when the thread can't be made; the caller presents on its own thread.
    static func spawn() -> PresentWorker? {
        let ch = PresentWorkerChannel()
        let thread = Thread {
            #if os(macOS)
            presentWorkerSetInteractiveQoS()
            #endif
            while let job = ch.nextJob() {
                let result: Result<Void, any Error>
                do {
                    try job()
                    result = .success(())
                } catch {
                    result = .failure(error)
                }
                ch.finishJob(result)
            }
            ch.markExited()
        }
        thread.name = "rune present"
        thread.start()
        return PresentWorker(ch)
    }

    /// Runs `job` on the thread once the job before it has finished.
    func run(_ job: @escaping @Sendable () -> Void) {
        runThrowing { job() }
    }

    /// Runs throwing `job` on the worker thread once the previous job has finished.
    func runThrowing(_ job: @escaping @Sendable () throws -> Void) {
        wait()
        guard let ch = channel else {
            try! job()
            return
        }
        if ch.submit(job) {
            inFlight = true
        } else {
            try! job()
        }
    }

    /// Blocks until the job in flight, if any, has finished. A job that failed traps here on the
    /// owner's thread, as it would have without the worker.
    func wait() {
        do {
            try waitThrowing()
        } catch {
            fatalError("PresentWorker job failed: \(error)")
        }
    }

    /// Blocks until the job in flight, if any, has finished, rethrowing any failure on the
    /// owner's thread and disconnecting the worker queue so later jobs run on the caller's thread.
    func waitThrowing() throws {
        guard inFlight else { return }
        inFlight = false
        guard let ch = channel else { return }
        if let result = ch.waitJob(), case .failure(let err) = result {
            // Shut down worker channel so subsequent jobs run on the caller's thread.
            ch.closeAndJoin()
            hasThread = false
            channel = nil
            throw err
        }
    }

    deinit {
        if inFlight {
            try? waitThrowing()
        }
        if hasThread, let ch = channel {
            ch.closeAndJoin()
        }
    }
}

#if os(macOS)
/// Presents keep pace with the display only at the main thread's priority.
private func presentWorkerSetInteractiveQoS() {
    _ = pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0)
}
#endif
#endif
