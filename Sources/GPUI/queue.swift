// Ported from: crates/gpui/src/queue.rs
// Upstream commit: 650aab59d54f
// Port status: ported

import Foundation
import Scheduler

public struct SendError<T>: Error, CustomStringConvertible, Sendable where T: Sendable {
    public let item: T

    public init(_ item: T) {
        self.item = item
    }

    public var description: String {
        "SendError(\(item))"
    }
}

public struct RecvError: Error, CustomStringConvertible, Sendable, Equatable {
    public init() {}

    public var description: String {
        "RecvError"
    }
}

private final class PriorityQueues<T> {
    var highPriority: [T] = []
    var mediumPriority: [T] = []
    var lowPriority: [T] = []

    var isEmpty: Bool {
        highPriority.isEmpty && mediumPriority.isEmpty && lowPriority.isEmpty
    }

    func push(priority: Priority, item: T) {
        switch priority {
        case .realtimeAudio:
            fatalError("Realtime audio priority runs on a dedicated thread and is never queued")
        case .high:
            highPriority.append(item)
        case .medium:
            mediumPriority.append(item)
        case .low:
            lowPriority.append(item)
        }
    }
}

// PORT NOTE: Synchronized via internal NSCondition protecting multi-priority queue state and sender/receiver counts.
private final class PriorityQueueState<T: Sendable>: @unchecked Sendable {
    private let condition = NSCondition()
    private let queues = PriorityQueues<T>()
    private var receiverCount: Int = 1
    private var senderCount: Int = 1

    func send(priority: Priority, item: T) throws(SendError<T>) {
        condition.lock()
        defer { condition.unlock() }

        guard receiverCount > 0 else {
            throw SendError(item)
        }

        queues.push(priority: priority, item: item)
        condition.signal()
    }

    func spinSend(priority: Priority, item: T) throws(SendError<T>) {
        try send(priority: priority, item: item)
    }

    func addSender() {
        condition.lock()
        defer { condition.unlock() }
        senderCount += 1
    }

    func removeSender() {
        condition.lock()
        defer { condition.unlock() }
        senderCount -= 1
        if senderCount == 0 {
            condition.broadcast()
        }
    }

    func addReceiver() {
        condition.lock()
        defer { condition.unlock() }
        receiverCount += 1
    }

    func removeReceiver() {
        condition.lock()
        defer { condition.unlock() }
        receiverCount -= 1
    }

    func withQueues<R>(block: Bool, _ body: (PriorityQueues<T>) throws(RecvError) -> R?) throws(RecvError) -> R? {
        condition.lock()
        defer { condition.unlock() }

        if !block {
            if queues.isEmpty && senderCount == 0 {
                throw RecvError()
            }
            if queues.isEmpty {
                return nil
            }
            return try body(queues)
        } else {
            if queues.isEmpty && senderCount == 0 {
                throw RecvError()
            }
            while queues.isEmpty {
                if senderCount == 0 {
                    throw RecvError()
                }
                condition.wait()
            }
            return try body(queues)
        }
    }
}

// PORT NOTE: Sender holds a reference to the shared thread-safe PriorityQueueState.
public final class PriorityQueueSender<T: Sendable>: @unchecked Sendable {
    private let state: PriorityQueueState<T>

    fileprivate init(state: PriorityQueueState<T>) {
        self.state = state
    }

    public func send(priority: Priority, item: T) throws {
        try state.send(priority: priority, item: item)
    }

    public func spinSend(priority: Priority, item: T) throws {
        try state.spinSend(priority: priority, item: item)
    }

    deinit {
        state.removeSender()
    }
}

// PORT NOTE: Receiver holds a reference to the shared thread-safe PriorityQueueState and deterministic RNG.
public final class PriorityQueueReceiver<T: Sendable>: @unchecked Sendable {
    private let state: PriorityQueueState<T>
    private let randLock = NSLock()
    private var rand = DeterministicRng(seed: 0)

    fileprivate init(state: PriorityQueueState<T>) {
        self.state = state
    }

    public static func new() -> (PriorityQueueSender<T>, PriorityQueueReceiver<T>) {
        let state = PriorityQueueState<T>()
        let sender = PriorityQueueSender(state: state)
        let receiver = PriorityQueueReceiver(state: state)
        return (sender, receiver)
    }

    public func tryPop() throws -> T? {
        try popInner(block: false)
    }

    public func spinTryPop() throws -> T? {
        try popInner(block: false)
    }

    public func pop() throws -> T {
        guard let item = try popInner(block: true) else {
            throw RecvError()
        }
        return item
    }

    private func randomRatio(numerator: UInt32, denominator: UInt32) -> Bool {
        guard denominator > 0 else { return false }
        if numerator >= denominator { return true }
        randLock.lock()
        defer { randLock.unlock() }
        let roll = UInt32(rand.next() % UInt64(denominator))
        return roll < numerator
    }

    private func popInner(block: Bool) throws -> T? {
        try state.withQueues(block: block) { queues in
            let high = queues.highPriority.isEmpty ? 0 : Priority.high.weight
            let medium = queues.mediumPriority.isEmpty ? 0 : Priority.medium.weight
            let low = queues.lowPriority.isEmpty ? 0 : Priority.low.weight
            var mass = high + medium + low

            if !queues.highPriority.isEmpty {
                let flip = self.randomRatio(numerator: Priority.high.weight, denominator: mass)
                if flip {
                    return queues.highPriority.removeFirst()
                }
                mass -= Priority.high.weight
            }

            if !queues.mediumPriority.isEmpty {
                let flip = self.randomRatio(numerator: Priority.medium.weight, denominator: mass)
                if flip {
                    return queues.mediumPriority.removeFirst()
                }
                mass -= Priority.medium.weight
            }

            if !queues.lowPriority.isEmpty {
                let flip = self.randomRatio(numerator: Priority.low.weight, denominator: mass)
                if flip {
                    return queues.lowPriority.removeFirst()
                }
            }

            return nil
        }
    }

    public func tryIter() -> TryIter<T> {
        TryIter(receiver: self)
    }

    public func iter() -> Iter<T> {
        Iter(receiver: self)
    }

    deinit {
        state.removeReceiver()
    }
}

public struct Iter<T: Sendable>: Sequence, IteratorProtocol {
    private let receiver: PriorityQueueReceiver<T>

    public init(receiver: PriorityQueueReceiver<T>) {
        self.receiver = receiver
    }

    public mutating func next() -> T? {
        try? receiver.pop()
    }
}

public struct TryIter<T: Sendable>: Sequence, IteratorProtocol {
    private let receiver: PriorityQueueReceiver<T>
    private var ended = false

    public init(receiver: PriorityQueueReceiver<T>) {
        self.receiver = receiver
    }

    public mutating func next() -> Result<T, RecvError>? {
        if ended {
            return nil
        }
        do {
            if let item = try receiver.tryPop() {
                return .success(item)
            } else {
                return nil
            }
        } catch {
            ended = true
            return .failure(error as? RecvError ?? RecvError())
        }
    }
}
