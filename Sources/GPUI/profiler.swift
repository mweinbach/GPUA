// Ported from: crates/gpui/src/profiler.rs
// Upstream commit: 650aab59d54f
// Port status: ported

import Foundation

/// Timing record for an executed task.
public struct TaskTiming: Sendable, Equatable {
    public var location: SerializedLocation
    public var start: ContinuousClock.Instant
    public var end: ContinuousClock.Instant?

    public init(
        location: SerializedLocation,
        start: ContinuousClock.Instant = .now,
        end: ContinuousClock.Instant? = nil
    ) {
        self.location = location
        self.start = start
        self.end = end
    }
}

/// Timings recorded for a specific thread.
public struct ThreadTaskTimings: Sendable {
    public var threadName: String?
    public var threadId: UInt64
    public var timings: [TaskTiming]
    public var totalPushed: UInt64

    public init(
        threadName: String? = nil,
        threadId: UInt64 = 0,
        timings: [TaskTiming] = [],
        totalPushed: UInt64 = 0
    ) {
        self.threadName = threadName
        self.threadId = threadId
        self.timings = timings
        self.totalPushed = totalPushed
    }

    /// Convert global thread timings into their structured format.
    public static func convert(_ timings: [GlobalThreadTimings]) -> [ThreadTaskTimings] {
        timings.map { global in
            global.timings.getThreadTaskTimings()
        }
    }
}

/// Serializable representation of a code location.
public struct SerializedLocation: Sendable, Codable, Equatable, Hashable {
    public var file: SharedString
    public var line: UInt32
    public var column: UInt32

    public init(file: SharedString = "", line: UInt32 = 0, column: UInt32 = 0) {
        self.file = file
        self.line = line
        self.column = column
    }
}

/// Serializable representation of a task timing.
public struct SerializedTaskTiming: Sendable, Codable, Equatable {
    public var location: SerializedLocation
    public var start: UInt64
    public var duration: UInt64

    public init(location: SerializedLocation, start: UInt64, duration: UInt64) {
        self.location = location
        self.start = start
        self.duration = duration
    }

    /// Convert an array of `TaskTiming` into their serializable format relative to anchor.
    public static func convert(anchor: ContinuousClock.Instant, timings: [TaskTiming]) -> [SerializedTaskTiming] {
        timings.map { timing in
            let startDuration = timing.start - anchor
            let startNanos = UInt64(max(0, startDuration.components.seconds * 1_000_000_000 + Int64(Double(startDuration.components.attoseconds) * 1e-9)))
            let endInstant = timing.end ?? .now
            let duration = endInstant - timing.start
            let durationNanos = UInt64(max(0, duration.components.seconds * 1_000_000_000 + Int64(Double(duration.components.attoseconds) * 1e-9)))
            return SerializedTaskTiming(
                location: timing.location,
                start: startNanos,
                duration: durationNanos
            )
        }
    }
}

/// Serializable variant of `ThreadTaskTimings`.
public struct SerializedThreadTaskTimings: Sendable, Codable, Equatable {
    public var threadName: String?
    public var threadId: UInt64
    public var timings: [SerializedTaskTiming]

    public init(threadName: String? = nil, threadId: UInt64 = 0, timings: [SerializedTaskTiming] = []) {
        self.threadName = threadName
        self.threadId = threadId
        self.timings = timings
    }

    /// Convert `ThreadTaskTimings` into their serializable format.
    public static func convert(anchor: ContinuousClock.Instant, timings: ThreadTaskTimings) -> SerializedThreadTaskTimings {
        let serialized = SerializedTaskTiming.convert(anchor: anchor, timings: timings.timings)
        return SerializedThreadTaskTimings(
            threadName: timings.threadName,
            threadId: timings.threadId,
            timings: serialized
        )
    }
}

/// Delta of new timings for a thread since previous collection.
public struct ThreadTimingsDelta: Sendable, Codable, Equatable {
    public var threadId: UInt64
    public var threadName: String?
    public var newTimings: [SerializedTaskTiming]

    public init(threadId: UInt64, threadName: String?, newTimings: [SerializedTaskTiming]) {
        self.threadId = threadId
        self.threadName = threadName
        self.newTimings = newTimings
    }
}

/// Tracks which timing events have already been seen so callers can request only unseen events.
public struct ProfilingCollector: Sendable {
    private var _startupTime: ContinuousClock.Instant
    private var cursors: [UInt64: UInt64] = [:]

    public init(startupTime: ContinuousClock.Instant = .now) {
        self._startupTime = startupTime
    }

    public static func new(startupTime: ContinuousClock.Instant) -> ProfilingCollector {
        ProfilingCollector(startupTime: startupTime)
    }

    public func startupTime() -> ContinuousClock.Instant {
        _startupTime
    }

    public mutating func collectUnseen(_ allTimings: [ThreadTaskTimings]) -> [ThreadTimingsDelta] {
        var deltas: [ThreadTimingsDelta] = []
        for thread in allTimings {
            let prevCursor = cursors[thread.threadId] ?? 0
            let bufferLen = UInt64(thread.timings.count)
            let bufferStart = thread.totalPushed > bufferLen ? thread.totalPushed - bufferLen : 0

            var slice: [TaskTiming]
            if prevCursor < bufferStart {
                slice = thread.timings
            } else {
                let skip = Int(min(UInt64(thread.timings.count), prevCursor - bufferStart))
                slice = Array(thread.timings.dropFirst(skip))
            }

            let incompleteAtEnd = slice.last?.end == nil
            if incompleteAtEnd && !slice.isEmpty {
                slice.removeLast()
            }

            let cursorAdvance = incompleteAtEnd ? (thread.totalPushed > 0 ? thread.totalPushed - 1 : 0) : thread.totalPushed
            cursors[thread.threadId] = cursorAdvance

            if slice.isEmpty {
                continue
            }

            let newTimings = SerializedTaskTiming.convert(anchor: _startupTime, timings: slice)
            deltas.append(ThreadTimingsDelta(
                threadId: thread.threadId,
                threadName: thread.threadName,
                newTimings: newTimings
            ))
        }
        return deltas
    }

    public mutating func reset() {
        cursors.removeAll()
    }
}

public typealias TaskTimings = [TaskTiming]
public typealias GuardedTaskTimings = ThreadTimings

public struct GlobalThreadTimings: Sendable {
    public var threadId: UInt64
    public var timings: ThreadTimings

    public init(threadId: UInt64, timings: ThreadTimings) {
        self.threadId = threadId
        self.timings = timings
    }
}

// PORT NOTE: globalThreadTimings and threadTimings manage in-memory thread task profiling storage.
public final class ThreadTimings: @unchecked Sendable {
    private let lock = NSLock()
    public var threadName: String?
    public var threadId: UInt64
    public var timings: TaskTimings
    public var totalPushed: UInt64

    public init(threadName: String? = nil, threadId: UInt64 = 0) {
        self.threadName = threadName
        self.threadId = threadId
        self.timings = TaskTimings()
        self.totalPushed = 0
    }

    public static func new(threadName: String?, threadId: UInt64) -> ThreadTimings {
        ThreadTimings(threadName: threadName, threadId: threadId)
    }

    public func addTaskTiming(_ timing: TaskTiming) {
        lock.lock()
        defer { lock.unlock() }
        if let last = timings.last, last.location == timing.location && last.start == timing.start {
            timings[timings.count - 1].end = timing.end
        } else {
            if timings.count >= 1024 {
                _ = timings.removeFirst()
            }
            timings.append(timing)
            totalPushed &+= 1
        }
    }

    public func getThreadTaskTimings() -> ThreadTaskTimings {
        lock.lock()
        defer { lock.unlock() }
        return ThreadTaskTimings(
            threadName: threadName,
            threadId: threadId,
            timings: Array(timings),
            totalPushed: totalPushed
        )
    }
}

// PORT NOTE: Internal profiler storage synchronized via internal NSLock.
private final class ProfilerStorage: @unchecked Sendable {
    let lock = NSLock()
    var globals: [GlobalThreadTimings] = []
    var current: ThreadTimings = ThreadTimings(threadName: "main", threadId: 1)
}

private let globalStorage = ProfilerStorage()

public var globalThreadTimings: [GlobalThreadTimings] {
    globalStorage.lock.lock()
    defer { globalStorage.lock.unlock() }
    return globalStorage.globals
}

public var threadTimings: ThreadTimings {
    globalStorage.current
}

public func addTaskTiming(_ timing: TaskTiming) {
    globalStorage.current.addTaskTiming(timing)
}

public func getCurrentThreadTaskTimings() -> ThreadTaskTimings {
    globalStorage.current.getThreadTaskTimings()
}
