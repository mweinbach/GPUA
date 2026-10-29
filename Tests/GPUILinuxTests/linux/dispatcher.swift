// Tests ported from: crates/gpui_linux/src/linux/dispatcher.rs (#[cfg(test)] items)
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(Linux)
import Foundation
import Testing
import GPUI
import Scheduler
@testable import GPUILinux

private final class AtomicBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: T

    init(_ value: T) {
        self._value = value
    }

    var value: T {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _value
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _value = newValue
        }
    }

    func mutate<R>(_ body: (inout T) -> R) -> R {
        lock.lock()
        defer { lock.unlock() }
        return body(&_value)
    }
}

@Suite("LinuxDispatcherTests")
struct LinuxDispatcherTests {
    struct TestData {
        var gotMsg: Bool = false
        var gotClosed: Bool = false
    }

    // Upstream test: fn calloop_works()
    @Test func calloopWorks() throws {
        let eventLoop = try CalloopEventLoop<TestData>.tryNew()
        let handle = eventLoop.handle()

        var txOpt: PriorityQueueCalloopSender<Void>?
        let rx: PriorityQueueCalloopReceiver<Void>
        do {
            let (tx, receiver) = PriorityQueueCalloopReceiver<Void>.new()
            txOpt = tx
            rx = receiver
        }

        var data = TestData()

        let inserted = handle.insertSource(rx) { event, d in
            switch event {
            case .msg:
                d.gotMsg = true
            case .closed:
                d.gotClosed = true
            }
        }
        #expect(inserted)

        // 1. Nothing is sent, nothing is received
        try eventLoop.dispatch(timeout: 0, data: &data)
        #expect(!data.gotMsg)
        #expect(!data.gotClosed)

        // 2. A message is sent
        try txOpt?.send(priority: .medium, item: ())
        try eventLoop.dispatch(timeout: 0.05, data: &data)
        #expect(data.gotMsg)
        #expect(!data.gotClosed)

        // 3. The sender is dropped
        txOpt = nil

        try eventLoop.dispatch(timeout: 0.05, data: &data)
        #expect(data.gotMsg)
        #expect(data.gotClosed)
    }

    @Test func testPriorityQueueOrdering() throws {
        let (tx, rx) = PriorityQueueReceiver<Int>.new()
        try tx.send(priority: .high, item: 100)
        try tx.send(priority: .medium, item: 50)
        try tx.send(priority: .low, item: 10)

        let popped1 = try rx.pop()
        let popped2 = try rx.pop()
        let popped3 = try rx.pop()

        let all = [popped1, popped2, popped3]
        #expect(all.contains(100))
        #expect(all.contains(50))
        #expect(all.contains(10))
    }

    @Test func testTimerDelayedDispatch() throws {
        let (mainSender, _) = PriorityQueueCalloopReceiver<@Sendable () -> Void>.new()
        let dispatcher = LinuxDispatcher.new(mainSender: mainSender)

        let completed = AtomicBox<Bool>(false)
        let startTime = Date()

        dispatcher.dispatchAfter(duration: 0.05) {
            completed.value = true
        }

        // Initially not completed
        #expect(!completed.value)

        // Wait for timer to fire
        for _ in 0..<30 {
            if completed.value { break }
            Thread.sleep(forTimeInterval: 0.01)
        }

        #expect(completed.value)
        let elapsed = Date().timeIntervalSince(startTime)
        #expect(elapsed >= 0.04)
    }

    @Test func testBackgroundThreadPoolExecution() throws {
        let (mainSender, _) = PriorityQueueCalloopReceiver<@Sendable () -> Void>.new()
        let dispatcher = LinuxDispatcher.new(mainSender: mainSender)

        let counter = AtomicBox<Int>(0)
        let totalTasks = 20

        for _ in 0..<totalTasks {
            dispatcher.dispatch({
                counter.mutate { $0 += 1 }
            }, priority: .high)
        }

        for _ in 0..<50 {
            if counter.value == totalTasks { break }
            Thread.sleep(forTimeInterval: 0.01)
        }

        #expect(counter.value == totalTasks)
    }

    @Test func testSpawnRealtime() throws {
        let (mainSender, _) = PriorityQueueCalloopReceiver<@Sendable () -> Void>.new()
        let dispatcher = LinuxDispatcher.new(mainSender: mainSender)

        let ran = AtomicBox<Bool>(false)
        dispatcher.spawnRealtime {
            ran.value = true
        }

        for _ in 0..<30 {
            if ran.value { break }
            Thread.sleep(forTimeInterval: 0.01)
        }

        #expect(ran.value)
    }

    @Test func testMainThreadCheck() throws {
        let (mainSender, _) = PriorityQueueCalloopReceiver<@Sendable () -> Void>.new()
        let dispatcher = LinuxDispatcher.new(mainSender: mainSender)

        #expect(dispatcher.isMainThread())

        let threadRan = AtomicBox<Bool>(false)
        let threadCheck = AtomicBox<Bool>(true)

        Thread.detachNewThread {
            threadCheck.value = dispatcher.isMainThread()
            threadRan.value = true
        }

        while !threadRan.value {
            Thread.sleep(forTimeInterval: 0.005)
        }

        #expect(!threadCheck.value)
    }

    @Test func testHeadlessClientStateAndExecution() throws {
        let client = HeadlessClient.new()
        #expect(client.compositorName() == "headless")
        #expect(client.displays().isEmpty)
        #expect(client.primaryDisplay() == nil)
        #expect(client.activeWindow() == nil)
        #expect(client.keyboardLayout().name == "unknown")

        let executed = AtomicBox<Bool>(false)
        client.withCommon { common in
            common.foregroundExecutor.dispatcher().dispatchOnMainThread({
                executed.value = true
            }, priority: .default)
        }

        try client.runOnce(timeout: 0.05)
        #expect(executed.value)
    }

    @Test func testDispatcherDeinitWhenDropped() throws {
        weak var weakDispatcher: LinuxDispatcher?
        do {
            let (_, mainReceiver) = PriorityQueueCalloopReceiver<@Sendable () -> Void>.new()
            let (mainSender, _) = PriorityQueueCalloopReceiver<@Sendable () -> Void>.new()
            _ = mainReceiver
            let dispatcher = LinuxDispatcher.new(mainSender: mainSender)
            weakDispatcher = dispatcher
            #expect(weakDispatcher != nil)

            let ran = AtomicBox<Bool>(false)
            dispatcher.dispatchAfter(duration: 0.01) {
                ran.value = true
            }

            let start = ContinuousClock.now
            while !ran.value && (ContinuousClock.now - start) < .milliseconds(200) {
                Thread.sleep(forTimeInterval: 0.005)
            }
            #expect(ran.value)
        }
        #expect(weakDispatcher == nil)
    }
}
#endif
