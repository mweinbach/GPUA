// Ported from: crates/gpui_linux/src/linux/dispatcher.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(Linux)
import Foundation
import GPUI
import Scheduler
import Glibc
import CLinuxSys


// MARK: - Calloop Event & Actions

public enum CalloopEvent<T: Sendable>: Sendable {
    case msg(T)
    case closed
}

public enum PostAction: Sendable {
    case `continue`
    case remove
}

// MARK: - ChannelError

public struct ChannelError: Error, CustomStringConvertible, Sendable {
    public let message: String

    public init(_ message: String = "Channel error") {
        self.message = message
    }

    public var description: String {
        message
    }
}

// MARK: - Ping & EventFD Source

// PORT NOTE: PingShared safely encapsulates an eventfd file descriptor accessed via atomic kernel system calls.
public final class PingShared: @unchecked Sendable {
    #if os(Linux)
    public let fd: Int32
    #else
    private let lock = NSLock()
    private var signaled = false
    #endif

    public init() {
        #if os(Linux)
        self.fd = eventfd(0, Int32(EFD_CLOEXEC | EFD_NONBLOCK))
        #endif
    }

    public func ping() {
        #if os(Linux)
        var val: UInt64 = 1
        _ = Glibc.write(fd, &val, MemoryLayout<UInt64>.size)
        #else
        lock.lock()
        signaled = true
        lock.unlock()
        #endif
    }

    public func clear() {
        #if os(Linux)
        var val: UInt64 = 0
        _ = Glibc.read(fd, &val, MemoryLayout<UInt64>.size)
        #else
        lock.lock()
        signaled = false
        lock.unlock()
        #endif
    }

    deinit {
        #if os(Linux)
        if fd >= 0 {
            Glibc.close(fd)
        }
        #endif
    }
}

public struct Ping: Sendable {
    private let shared: PingShared

    public init(shared: PingShared) {
        self.shared = shared
    }

    public func ping() {
        shared.ping()
    }
}

public func makePing() -> (Ping, PingShared) {
    let shared = PingShared()
    return (Ping(shared: shared), shared)
}

// MARK: - LoopSignal

// PORT NOTE: LoopSignal synchronizes stop status with an NSLock protecting state.
public final class LoopSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    private let ping: Ping?

    public init(ping: Ping? = nil) {
        self.ping = ping
    }

    public func stop() {
        lock.lock()
        stopped = true
        lock.unlock()
        ping?.ping()
    }

    public var isSignaled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopped
    }
}

// MARK: - EventLoop & LoopHandle

public typealias EventCallback<T, Data> = (CalloopEvent<T>, inout Data) -> Void

public protocol AnyCalloopSource<Data>: AnyObject {
    associatedtype Data
    func processEvents(data: inout Data) -> PostAction
    func unregister()
}

public final class PriorityQueueCalloopSource<T: Sendable, Data>: AnyCalloopSource {
    public let receiver: PriorityQueueCalloopReceiver<T>
    public let callback: EventCallback<T, Data>
    public let epollFd: Int32

    public init(
        receiver: PriorityQueueCalloopReceiver<T>,
        epollFd: Int32 = -1,
        callback: @escaping EventCallback<T, Data>
    ) {
        self.receiver = receiver
        self.epollFd = epollFd
        self.callback = callback
    }

    public func processEvents(data: inout Data) -> PostAction {
        receiver.clearPing()

        var disconnected = false
        while true {
            do {
                if let item = try receiver.tryPop() {
                    callback(.msg(item), &data)
                } else {
                    break
                }
            } catch {
                disconnected = true
                break
            }
        }

        if disconnected {
            callback(.closed, &data)
            return .remove
        }
        return .continue
    }

    public func unregister() {
        #if os(Linux)
        epoll_ctl(epollFd, EPOLL_CTL_DEL, receiver.pingShared.fd, nil)
        #endif
    }
}

// PORT NOTE: LoopHandle wraps a thread-safe weak reference to CalloopEventLoop.
public final class LoopHandle<Data>: @unchecked Sendable {
    private weak var loop: CalloopEventLoop<Data>?

    public init(loop: CalloopEventLoop<Data>) {
        self.loop = loop
    }

    @discardableResult
    public func insertSource<T: Sendable>(
        _ receiver: PriorityQueueCalloopReceiver<T>,
        callback: @escaping EventCallback<T, Data>
    ) -> Bool {
        guard let loop = loop else { return false }
        return loop.insertReceiverSource(receiver, callback: callback)
    }
}

// PORT NOTE: CalloopEventLoop synchronizes sources and event loop state with an internal NSLock.
public final class CalloopEventLoop<Data>: @unchecked Sendable {
    #if os(Linux)
    private let epollFd: Int32
    #endif
    private let signal: LoopSignal
    private let wakePing: Ping
    private let wakeShared: PingShared
    private let lock = NSLock()
    private var sources: [Int32: any AnyCalloopSource<Data>] = [:]
    private var anySources: [any AnyCalloopSource<Data>] = []

    public init() {
        let (ping, shared) = makePing()
        self.wakePing = ping
        self.wakeShared = shared
        self.signal = LoopSignal(ping: ping)

        #if os(Linux)
        self.epollFd = epoll_create1(Int32(EPOLL_CLOEXEC))
        var ev = epoll_event()
        ev.events = UInt32(EPOLLIN.rawValue)
        ev.data.fd = shared.fd
        epoll_ctl(epollFd, EPOLL_CTL_ADD, shared.fd, &ev)
        #endif
    }

    public static func tryNew() throws -> CalloopEventLoop<Data> {
        CalloopEventLoop()
    }

    public func handle() -> LoopHandle<Data> {
        LoopHandle(loop: self)
    }

    public func getSignal() -> LoopSignal {
        signal
    }

    fileprivate func insertReceiverSource<T: Sendable>(
        _ receiver: PriorityQueueCalloopReceiver<T>,
        callback: @escaping EventCallback<T, Data>
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        #if os(Linux)
        let source = PriorityQueueCalloopSource(
            receiver: receiver,
            epollFd: epollFd,
            callback: callback
        )
        let fd = receiver.pingShared.fd
        sources[fd] = source

        var ev = epoll_event()
        ev.events = UInt32(EPOLLIN.rawValue)
        ev.data.fd = fd
        let res = epoll_ctl(epollFd, EPOLL_CTL_ADD, fd, &ev)
        return res == 0
        #else
        let source = PriorityQueueCalloopSource(
            receiver: receiver,
            callback: callback
        )
        anySources.append(source)
        return true
        #endif
    }

    public func dispatch(timeout: TimeInterval?, data: inout Data) throws {
        #if os(Linux)
        let timeoutMs: Int32
        if let timeout = timeout {
            timeoutMs = Int32(max(0, timeout * 1000))
        } else {
            timeoutMs = -1
        }

        var events = [epoll_event](repeating: epoll_event(), count: 16)
        let count = epoll_wait(epollFd, &events, 16, timeoutMs)
        if count < 0 {
            if errno == EINTR { return }
            throw ChannelError("epoll_wait failed with errno \(errno)")
        }

        if count == 0 { return }

        for i in 0..<Int(count) {
            let fd = events[i].data.fd
            if fd == wakeShared.fd {
                wakeShared.clear()
                continue
            }

            lock.lock()
            let source = sources[fd]
            lock.unlock()

            if let source = source {
                let action = source.processEvents(data: &data)
                if action == .remove {
                    lock.lock()
                    source.unregister()
                    sources.removeValue(forKey: fd)
                    lock.unlock()
                }
            }
        }
        #else
        lock.lock()
        let current = anySources
        lock.unlock()

        var toRemove: [ObjectIdentifier] = []
        for s in current {
            let action = s.processEvents(data: &data)
            if action == .remove {
                toRemove.append(ObjectIdentifier(s))
            }
        }
        if !toRemove.isEmpty {
            lock.lock()
            anySources.removeAll { toRemove.contains(ObjectIdentifier($0)) }
            lock.unlock()
        }
        #endif
    }

    public func run(
        timeout: TimeInterval?,
        data: inout Data,
        callback: ((inout Data) -> Void)? = nil
    ) throws {
        while !signal.isSignaled {
            try dispatch(timeout: timeout, data: &data)
            callback?(&data)
        }
    }

    deinit {
        #if os(Linux)
        if epollFd >= 0 {
            Glibc.close(epollFd)
        }
        #endif
    }
}

// MARK: - PriorityQueueCalloopSender & Receiver

// PORT NOTE: PriorityQueueCalloopSender holds thread-safe PriorityQueueSender and Ping.
public final class PriorityQueueCalloopSender<T: Sendable>: @unchecked Sendable {
    public let sender: PriorityQueueSender<T>
    public let ping: Ping

    public init(sender: PriorityQueueSender<T>, ping: Ping) {
        self.sender = sender
        self.ping = ping
    }

    public static func new(tx: PriorityQueueSender<T>, ping: Ping) -> PriorityQueueCalloopSender<T> {
        PriorityQueueCalloopSender(sender: tx, ping: ping)
    }

    public func send(priority: Priority, item: T) throws {
        try sender.send(priority: priority, item: item)
        ping.ping()
    }

    deinit {
        ping.ping()
    }
}

// PORT NOTE: PriorityQueueCalloopReceiver holds thread-safe PriorityQueueReceiver and PingShared.
public final class PriorityQueueCalloopReceiver<T: Sendable>: @unchecked Sendable {
    public let receiver: PriorityQueueReceiver<T>
    public let ping: Ping
    public let pingShared: PingShared

    public init(receiver: PriorityQueueReceiver<T>, ping: Ping, pingShared: PingShared) {
        self.receiver = receiver
        self.ping = ping
        self.pingShared = pingShared
    }

    public static func new() -> (PriorityQueueCalloopSender<T>, PriorityQueueCalloopReceiver<T>) {
        let (ping, shared) = makePing()
        let (tx, rx) = PriorityQueueReceiver<T>.new()
        let sender = PriorityQueueCalloopSender<T>(sender: tx, ping: ping)
        let receiver = PriorityQueueCalloopReceiver<T>(receiver: rx, ping: ping, pingShared: shared)
        return (sender, receiver)
    }

    public func tryPop() throws -> T? {
        try receiver.tryPop()
    }

    public func pop() throws -> T {
        try receiver.pop()
    }

    public func clearPing() {
        pingShared.clear()
    }
}

// MARK: - TimerManager (timerfd)

// PORT NOTE: TimerManagerState synchronizes timer queues and timerfd state with an internal NSLock.
private final class TimerManagerState: @unchecked Sendable {
    struct PendingTimer: Comparable {
        let deadline: ContinuousClock.Instant
        let action: @Sendable () -> Void
        let id: UInt64

        static func < (lhs: PendingTimer, rhs: PendingTimer) -> Bool {
            if lhs.deadline != rhs.deadline {
                return lhs.deadline < rhs.deadline
            }
            return lhs.id < rhs.id
        }

        static func == (lhs: PendingTimer, rhs: PendingTimer) -> Bool {
            lhs.id == rhs.id
        }
    }

    private let epollFd: Int32
    private let timerFd: Int32
    private let wakeFd: Int32
    private let lock = NSLock()
    private var queue: [PendingTimer] = []
    private var nextId: UInt64 = 0
    private var isRunning = true
    private let clock = ContinuousClock()

    init() {
        self.epollFd = epoll_create1(Int32(EPOLL_CLOEXEC))
        self.timerFd = timerfd_create(CLOCK_MONOTONIC, Int32(TFD_NONBLOCK | TFD_CLOEXEC))
        self.wakeFd = eventfd(0, Int32(EFD_CLOEXEC | EFD_NONBLOCK))

        var ev1 = epoll_event()
        ev1.events = UInt32(EPOLLIN.rawValue)
        ev1.data.fd = timerFd
        epoll_ctl(epollFd, EPOLL_CTL_ADD, timerFd, &ev1)

        var ev2 = epoll_event()
        ev2.events = UInt32(EPOLLIN.rawValue)
        ev2.data.fd = wakeFd
        epoll_ctl(epollFd, EPOLL_CTL_ADD, wakeFd, &ev2)
    }

    func stop() {
        lock.lock()
        isRunning = false
        lock.unlock()
        var val: UInt64 = 1
        _ = Glibc.write(wakeFd, &val, MemoryLayout<UInt64>.size)
    }

    func schedule(duration: TimeInterval, runnable: @escaping @Sendable () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard isRunning else { return }

        let nanos = Int64(max(0, duration) * 1_000_000_000)
        let deadline = clock.now + Duration.nanoseconds(nanos)
        let id = nextId
        nextId += 1
        queue.append(PendingTimer(deadline: deadline, action: runnable, id: id))
        queue.sort()

        var val: UInt64 = 1
        _ = Glibc.write(wakeFd, &val, MemoryLayout<UInt64>.size)
    }

    func runLoop() {
        var events = [epoll_event](repeating: epoll_event(), count: 4)
        while true {
            lock.lock()
            if !isRunning {
                lock.unlock()
                break
            }
            let nextDeadline = queue.first?.deadline
            armTimerFd(nextDeadline: nextDeadline)
            lock.unlock()

            let n = epoll_wait(epollFd, &events, 4, -1)
            if n <= 0 { continue }

            for i in 0..<Int(n) {
                let fd = events[i].data.fd
                if fd == wakeFd {
                    var val: UInt64 = 0
                    _ = Glibc.read(wakeFd, &val, MemoryLayout<UInt64>.size)
                } else if fd == timerFd {
                    var expirations: UInt64 = 0
                    _ = Glibc.read(timerFd, &expirations, MemoryLayout<UInt64>.size)
                }
            }

            lock.lock()
            if !isRunning {
                lock.unlock()
                break
            }
            let now = clock.now
            var expired: [@Sendable () -> Void] = []
            while let first = queue.first, first.deadline <= now {
                expired.append(first.action)
                queue.removeFirst()
            }
            lock.unlock()

            for action in expired {
                action()
            }
        }

        if epollFd >= 0 { Glibc.close(epollFd) }
        if timerFd >= 0 { Glibc.close(timerFd) }
        if wakeFd >= 0 { Glibc.close(wakeFd) }
    }

    private func armTimerFd(nextDeadline: ContinuousClock.Instant?) {
        guard let nextDeadline = nextDeadline else {
            var its = itimerspec()
            its.it_value.tv_sec = 0
            its.it_value.tv_nsec = 0
            its.it_interval.tv_sec = 0
            its.it_interval.tv_nsec = 0
            timerfd_settime(timerFd, 0, &its, nil)
            return
        }

        let remaining = nextDeadline - clock.now
        let (seconds, attoseconds) = remaining.components
        let nanos = max(1, attoseconds / 1_000_000_000)
        var its = itimerspec()
        its.it_value.tv_sec = max(0, Int(seconds))
        its.it_value.tv_nsec = Int(nanos)
        its.it_interval.tv_sec = 0
        its.it_interval.tv_nsec = 0
        timerfd_settime(timerFd, 0, &its, nil)
    }
}

// PORT NOTE: TimerManager holds TimerManagerState and stops timer thread cleanly on deinit.
private final class TimerManager: @unchecked Sendable {
    private let state = TimerManagerState()

    init() {
        let state = self.state
        Thread.detachNewThread {
            state.runLoop()
        }
    }

    func schedule(duration: TimeInterval, runnable: @escaping @Sendable () -> Void) {
        state.schedule(duration: duration, runnable: runnable)
    }

    deinit {
        state.stop()
    }
}

// MARK: - LinuxDispatcher

// PORT NOTE: LinuxDispatcher coordinates thread-safe task queues, worker pools, and timers via locks and kernel events.
public final class LinuxDispatcher: PlatformDispatcher, @unchecked Sendable {
    private let mainSender: PriorityQueueCalloopSender<@Sendable () -> Void>
    private let backgroundSender: PriorityQueueSender<@Sendable () -> Void>
    private let backgroundReceiver: PriorityQueueReceiver<@Sendable () -> Void>
    private let timerManager: TimerManager
    private let mainThread: Thread

    public init(mainSender: PriorityQueueCalloopSender<@Sendable () -> Void>) {
        self.mainSender = mainSender
        let (bgSender, bgReceiver) = PriorityQueueReceiver<@Sendable () -> Void>.new()
        self.backgroundSender = bgSender
        self.backgroundReceiver = bgReceiver
        self.timerManager = TimerManager()
        self.mainThread = Thread.current

        let threadCount = max(ProcessInfo.processInfo.activeProcessorCount, 2)
        for _ in 0..<threadCount {
            let receiver = bgReceiver
            Thread.detachNewThread {
                while let runnable = try? receiver.pop() {
                    runnable()
                }
            }
        }
    }

    public static func new(mainSender: PriorityQueueCalloopSender<@Sendable () -> Void>) -> LinuxDispatcher {
        LinuxDispatcher(mainSender: mainSender)
    }

    public func isMainThread() -> Bool {
        Thread.current == mainThread || Thread.isMainThread
    }

    public func dispatch(_ runnable: @escaping @Sendable () -> Void, priority: Priority) {
        do {
            try backgroundSender.send(priority: priority, item: runnable)
        } catch {
            fatalError("Blocking background sender returned error: \(error)")
        }
    }

    public func dispatchOnMainThread(_ runnable: @escaping @Sendable () -> Void, priority: Priority) {
        do {
            try mainSender.send(priority: priority, item: runnable)
        } catch {
            // Main receiver dropped: app is shutting down
        }
    }

    public func dispatchAfter(duration: TimeInterval, _ runnable: @escaping @Sendable () -> Void) {
        timerManager.schedule(duration: duration, runnable: runnable)
    }

    public func spawnRealtime(_ f: @escaping @Sendable () -> Void) {
        Thread.detachNewThread {
            #if os(Linux)
            let threadId = pthread_self()
            var param = sched_param()
            param.sched_priority = 65
            let result = pthread_setschedparam(threadId, SCHED_FIFO, &param)
            if result != 0 {
                param.sched_priority = 1
                _ = pthread_setschedparam(threadId, SCHED_RR, &param)
            }
            #endif
            f()
        }
    }

    public func now() -> Date {
        Date()
    }

    public func asTest() -> TestDispatcher? {
        nil
    }

    public func getAllTimings() -> [ThreadTaskTimings] {
        ThreadTaskTimings.convert([])
    }

    public func getCurrentThreadTimings() -> ThreadTaskTimings {
        getCurrentThreadTaskTimings()
    }

    deinit {}
}
#endif
