// Ported from: crates/rune/src/open_url/incoming.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Receiving links the system opens with this app (`myapp://...`): `App.onOpenUrl`.

#if os(macOS)
import AppKit
import CoreServices
import Foundation
#elseif !os(WASI)
import Foundation
#endif

/// `App.onOpenUrl`'s hook.
typealias OnOpenUrl<S> = @Sendable (inout S, String, inout Tx) -> Void

typealias OpenUrlSink = @Sendable (String) -> Void

/// The platform's get-URL handler.
protocol OpenUrlGlue {
    /// Something else (the app itself) already handles get-URL events.
    func handledElsewhere() -> Bool
    /// Makes Rune's handler the one; false when it can't (off the main thread, another platform).
    func install() -> Bool
    func remove()
}

private struct OpenUrlInboxState {
    var listeners: [(UInt64, OpenUrlSink)] = []
    var next: UInt64 = 0
    var pending: [String]? = nil
    var installed: Bool = false
}

/// Where incoming system links go.
// PORT NOTE: Synchronized via `lock` (`LiveLock`), mirroring `Mutex<State>` in `crates/rune/src/open_url/incoming.rs`.
final class OpenUrlInbox: @unchecked Sendable {
    private let lock = LiveLock()
    private var state = OpenUrlInboxState()

    init() {}

    /// Before the event loop: install the handler and keep links until a window listens,
    /// unless something else handles them already.
    func prepare(_ glue: any OpenUrlGlue) {
        lock.withLock {
            if state.installed || glue.handledElsewhere() || !glue.install() { return }
            state.installed = true
            state.pending = []
        }
    }

    /// Sends links to `app`'s hook while the returned guard lives, after the links kept so far,
    /// if the app has the hook. Installs the handler if `prepare` didn't.
    func listen<S>(_ app: App<S>, _ glue: any OpenUrlGlue) -> OpenUrlListening? {
        guard let hook = app.onOpenUrlHook else { return nil }
        let handle = app.handle()
        let sink: OpenUrlSink = { url in
            handle.update { s, tx in
                hook(&s, url, &tx)
            }
        }
        let keptAndId: (UInt64, [String])? = lock.withLock {
            if !state.installed {
                guard glue.install() else { return nil }
                state.installed = true
            }
            let id = state.next
            state.next += 1
            state.listeners.append((id, sink))
            let kept = state.pending ?? []
            state.pending = nil
            return (id, kept)
        }
        guard let (id, kept) = keptAndId else { return nil }
        for url in kept {
            sink(url)
        }
        return OpenUrlListening(inbox: self, id: id)
    }

    /// Every window has started: stop keeping links, and remove the handler if none listens.
    func settle(_ glue: any OpenUrlGlue) {
        lock.withLock {
            state.pending = nil
            if state.installed && state.listeners.isEmpty {
                glue.remove()
                state.installed = false
            }
        }
    }

    /// A link arrived: to the first listener, kept before one exists, else dropped.
    func receive(_ url: String) {
        let sink: OpenUrlSink? = lock.withLock {
            if let first = state.listeners.first {
                return first.1
            }
            if state.pending != nil {
                state.pending?.append(url)
            }
            return nil
        }
        sink?(url)
    }

    fileprivate func unlisten(_ id: UInt64) {
        lock.withLock {
            state.listeners.removeAll { $0.0 == id }
        }
    }
}

/// A window's place among the listeners, held by its host; dropping it stops its links.
final class OpenUrlListening {
    private let inbox: OpenUrlInbox
    private let id: UInt64

    init(inbox: OpenUrlInbox, id: UInt64) {
        self.inbox = inbox
        self.id = id
    }

    deinit {
        inbox.unlisten(id)
    }
}

let globalOpenUrlInbox = OpenUrlInbox()

private struct NativeOpenUrlGlue: OpenUrlGlue {
    func handledElsewhere() -> Bool { openUrlPlatformHandledElsewhere() }
    func install() -> Bool { openUrlPlatformInstall() }
    func remove() { openUrlPlatformRemove() }
}

func openUrlPrepare() {
    globalOpenUrlInbox.prepare(NativeOpenUrlGlue())
}

func openUrlListen<S>(_ app: App<S>) -> OpenUrlListening? {
    globalOpenUrlInbox.listen(app, NativeOpenUrlGlue())
}

func openUrlSettle() {
    globalOpenUrlInbox.settle(NativeOpenUrlGlue())
}

#if os(macOS)
private let kGetUrlFourCC: UInt32 = 0x4755_524C // 'GURL'
private let kDirectObjectFourCC: UInt32 = 0x2D2D_2D2D // '----'

/// Extracts the URL string of a get-URL Apple event.
func macAppleEventUrlOf(_ event: NSAppleEventDescriptor) -> String? {
    event.paramDescriptor(forKeyword: AEKeyword(kDirectObjectFourCC))?.stringValue
}

@objc(RuneOpenUrlHandler)
private final class RuneOpenUrlHandler: NSObject {
    @objc(handleGetURLEvent:withReplyEvent:)
    func handleGetURLEvent(_ event: NSAppleEventDescriptor?, withReplyEvent replyEvent: NSAppleEventDescriptor?) {
        _ = replyEvent
        if let event, let url = macAppleEventUrlOf(event) {
            globalOpenUrlInbox.receive(url)
        }
    }
}

// PORT NOTE: Initialized lazily under `macHandlerLock` (`LiveLock`) and retained for the process lifetime, matching upstream `OnceLock<usize>`.
private let macHandlerLock = LiveLock()
// PORT NOTE: Protected by `macHandlerLock`.
nonisolated(unsafe) private var macHandlerSingleton: RuneOpenUrlHandler? = nil

private func macOpenUrlHandler() -> RuneOpenUrlHandler {
    macHandlerLock.withLock {
        if let existing = macHandlerSingleton {
            return existing
        }
        let created = RuneOpenUrlHandler()
        macHandlerSingleton = created
        return created
    }
}

private func openUrlPlatformHandledElsewhere() -> Bool {
    var handler: AEEventHandlerUPP? = nil
    var refcon: UnsafeMutableRawPointer? = nil
    return AEGetEventHandler(
        AEEventClass(kGetUrlFourCC),
        AEEventID(kGetUrlFourCC),
        &handler,
        &refcon,
        false
    ) == noErr
}

private func openUrlPlatformInstall() -> Bool {
    guard Thread.isMainThread else { return false }
    let handler = macOpenUrlHandler()
    NSAppleEventManager.shared().setEventHandler(
        handler,
        andSelector: #selector(RuneOpenUrlHandler.handleGetURLEvent(_:withReplyEvent:)),
        forEventClass: AEEventClass(kGetUrlFourCC),
        andEventID: AEEventID(kGetUrlFourCC)
    )
    return true
}

private func openUrlPlatformRemove() {
    guard Thread.isMainThread else { return }
    NSAppleEventManager.shared().removeEventHandler(
        forEventClass: AEEventClass(kGetUrlFourCC),
        andEventID: AEEventID(kGetUrlFourCC)
    )
}
#else
private func openUrlPlatformHandledElsewhere() -> Bool { false }
private func openUrlPlatformInstall() -> Bool { false }
private func openUrlPlatformRemove() {}
#endif
