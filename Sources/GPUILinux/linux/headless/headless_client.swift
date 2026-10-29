// Ported from: crates/gpui_linux/src/linux/headless/client.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(Linux) || os(Windows) || os(Android) || os(WASI)
import Foundation
import GPUI
import Scheduler

// PORT NOTE: HeadlessClientState synchronizes mutable common state and event loop access via NSLock.
public final class HeadlessClientState: @unchecked Sendable {
    public let loopHandle: LoopHandle<HeadlessClient>
    private var eventLoop: CalloopEventLoop<HeadlessClient>?
    public var common: LinuxCommon
    private let lock = NSLock()

    public init(
        loopHandle: LoopHandle<HeadlessClient>,
        eventLoop: CalloopEventLoop<HeadlessClient>?,
        common: LinuxCommon
    ) {
        self.loopHandle = loopHandle
        self.eventLoop = eventLoop
        self.common = common
    }

    public func takeEventLoop() -> CalloopEventLoop<HeadlessClient>? {
        lock.lock()
        defer { lock.unlock() }
        let loop = eventLoop
        eventLoop = nil
        return loop
    }

    public var currentEventLoop: CalloopEventLoop<HeadlessClient>? {
        lock.lock()
        defer { lock.unlock() }
        return eventLoop
    }

    @discardableResult
    public func withCommon<R>(_ f: (inout LinuxCommon) -> R) -> R {
        lock.lock()
        defer { lock.unlock() }
        return f(&common)
    }
}

// PORT NOTE: HeadlessClient wraps thread-safe HeadlessClientState.
public final class HeadlessClient: LinuxClient, @unchecked Sendable {
    public let state: HeadlessClientState

    public init() {
        let eventLoop = CalloopEventLoop<HeadlessClient>()
        let (common, mainReceiver) = LinuxCommon.new(signal: eventLoop.getSignal())
        let handle = eventLoop.handle()

        handle.insertSource(mainReceiver) { event, client in
            if case let .msg(runnable) = event {
                runnable()
            }
        }

        self.state = HeadlessClientState(
            loopHandle: handle,
            eventLoop: eventLoop,
            common: common
        )
    }

    public static func new() -> HeadlessClient {
        HeadlessClient()
    }

    @discardableResult
    public func withCommon<R>(_ f: (inout LinuxCommon) -> R) -> R {
        state.withCommon(f)
    }

    public func keyboardLayout() -> any PlatformKeyboardLayout {
        LinuxKeyboardLayout.new("unknown")
    }

    public func displays() -> [any PlatformDisplay] {
        []
    }

    public func primaryDisplay() -> (any PlatformDisplay)? {
        nil
    }

    public func display(_ id: DisplayId) -> (any PlatformDisplay)? {
        nil
    }

    public func activeWindow() -> AnyWindowHandle? {
        nil
    }

    public func windowStack() -> [AnyWindowHandle]? {
        nil
    }

    public func openWindow(
        handle: AnyWindowHandle,
        options: WindowOptions
    ) throws -> any PlatformWindow {
        throw LinuxError("neither DISPLAY nor WAYLAND_DISPLAY is set. You can run in headless mode")
    }

    public func compositorName() -> String {
        "headless"
    }

    public func setCursorStyle(_ style: CursorStyle) {}

    public func openUri(_ uri: String) {}

    public func revealPath(_ path: URL) {}

    public func writeToPrimary(_ item: ClipboardItem) {}

    public func writeToClipboard(_ item: ClipboardItem) {}

    public func readFromPrimary() -> ClipboardItem? {
        nil
    }

    public func readFromClipboard() -> ClipboardItem? {
        nil
    }

    public func run() {
        guard let eventLoop = state.takeEventLoop() else {
            fatalError("App is already running")
        }
        var client = self
        _ = try? eventLoop.run(timeout: nil, data: &client)
    }

    public func runOnce(timeout: TimeInterval? = 0) throws {
        guard let loop = state.currentEventLoop else { return }
        var client = self
        try loop.dispatch(timeout: timeout, data: &client)
    }
}
#endif
