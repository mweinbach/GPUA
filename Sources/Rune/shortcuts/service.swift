// Ported from: crates/rune/src/shortcuts/service.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
import Darwin
import Dispatch
#elseif canImport(Glibc)
import Dispatch
import Glibc
#elseif canImport(Android)
import Android
import Dispatch
#elseif os(Windows)
import Dispatch
import WinSDK
#endif

private func currentShortcutThreadId() -> UInt64 {
    #if os(WASI)
    return 1
    #elseif os(Windows)
    return UInt64(GetCurrentThreadId())
    #elseif os(Linux)
    return UInt64(pthread_self())
    #else
    return UInt64(UInt(bitPattern: pthread_self()))
    #endif
}

private let shortcutGlobalLock = LiveLock()
// PORT NOTE: Access to `nextShortcutOwnerKey`, `nextShortcutIdRaw`, and `globalNativeShortcuts` is serialized via `shortcutGlobalLock`.
nonisolated(unsafe) private var nextShortcutOwnerKey: Int = 1
// PORT NOTE: Guarded by `shortcutGlobalLock`.
nonisolated(unsafe) private var nextShortcutIdRaw: UInt32 = 1
// PORT NOTE: Guarded by `shortcutGlobalLock`; tracks process-wide non-headless registrations `(id, shortcut, title)`.
nonisolated(unsafe) private var globalNativeShortcuts: [(ShortcutId, Shortcut, String)] = []

private func allocateShortcutOwnerKey() -> Int {
    shortcutGlobalLock.withLock {
        let key = nextShortcutOwnerKey
        nextShortcutOwnerKey += 1
        return key
    }
}

private func allocateShortcutId() -> Result<ShortcutId, ShortcutError> {
    shortcutGlobalLock.withLock {
        let (next, overflow) = nextShortcutIdRaw.addingReportingOverflow(1)
        if overflow {
            return .failure(.backend("shortcut id space exhausted"))
        }
        let assigned = nextShortcutIdRaw
        nextShortcutIdRaw = next
        return .success(ShortcutId(assigned))
    }
}

final class ShortcutEngine {
    let title: String
    let headless: Bool
    let wayland: Bool
    let sink: ShortcutSink
    var native: (any ShortcutBackend)?
    var registrations: [ShortcutId: Shortcut] = [:]

    init(
        title: String,
        headless: Bool,
        wayland: Bool,
        sink: @escaping ShortcutSink,
        native: (any ShortcutBackend)? = nil
    ) {
        self.title = title
        self.headless = headless
        self.wayland = wayland
        self.sink = sink
        self.native = native
    }

    func register(_ id: ShortcutId, _ shortcut: Shortcut) -> Result<Void, ShortcutError> {
        if registrations.values.contains(shortcut) {
            return .failure(.conflict)
        }
        if !headless {
            let heldElsewhere = shortcutGlobalLock.withLock {
                globalNativeShortcuts.contains { $0.1 == shortcut }
            }
            if heldElsewhere {
                return .failure(.conflict)
            }
            if native == nil {
                switch makeNativeShortcutBackend(wayland, sink) {
                case .success(let backend):
                    native = backend
                case .failure(let err):
                    return .failure(err)
                }
            }
            if case .failure(let err) = native!.register(id, shortcut) {
                if registrations.isEmpty {
                    native = nil
                }
                return .failure(err)
            }
            shortcutGlobalLock.withLock {
                globalNativeShortcuts.append((id, shortcut, title))
            }
        }
        registrations[id] = shortcut
        return .success(())
    }

    func unregister(_ id: ShortcutId) -> Result<Void, ShortcutError> {
        guard registrations[id] != nil else {
            return .failure(.unknownId)
        }
        if let native {
            if case .failure(let err) = native.unregister(id) {
                return .failure(err)
            }
        }
        registrations.removeValue(forKey: id)
        shortcutGlobalLock.withLock {
            globalNativeShortcuts.removeAll { $0.0 == id }
        }
        if registrations.isEmpty {
            native = nil
        }
        return .success(())
    }

    /// Who holds `shortcut`: this App, another App in this process, or the platform.
    /// Headless engines answer only for their own virtual registrations.
    func owner(_ shortcut: Shortcut) -> String? {
        if registrations.values.contains(shortcut) {
            return title
        }
        if headless {
            return nil
        }
        let other = shortcutGlobalLock.withLock {
            globalNativeShortcuts.first(where: { $0.1 == shortcut })?.2
        }
        return other ?? shortcutSystemOwner(shortcut)
    }

    func release() {
        native = nil
        let ownedIds = Set(registrations.keys)
        shortcutGlobalLock.withLock {
            globalNativeShortcuts.removeAll { ownedIds.contains($0.0) }
        }
        registrations.removeAll()
    }

    deinit {
        release()
    }
}

#if !os(WASI)
// PORT NOTE: One-shot reply box for cross-thread `ShortcutControl.invoke`; synchronized via `DispatchSemaphore` + `LiveLock`.
private final class ShortcutJobReply<T>: @unchecked Sendable {
    private let lock = LiveLock()
    private let sem = DispatchSemaphore(value: 0)
    private var value: Result<T, ShortcutError>? = nil
    private var signalled = false

    func send(_ result: Result<T, ShortcutError>) {
        let shouldSignal = lock.withLock { () -> Bool in
            guard !signalled else { return false }
            value = result
            signalled = true
            return true
        }
        if shouldSignal {
            sem.signal()
        }
    }

    func wait() -> Result<T, ShortcutError> {
        sem.wait()
        return lock.withLock { value ?? .failure(.notRunning) }
    }

    deinit {
        // Never relevant once `wait` has finished, kept clean.
    }
}
#endif

private final class QueuedShortcutJob {
    private var runFn: ((ShortcutEngine) -> Void)?
    private var cancelFn: (() -> Void)?

    init(run: @escaping (ShortcutEngine) -> Void, cancel: @escaping () -> Void) {
        self.runFn = run
        self.cancelFn = cancel
    }

    func run(_ engine: ShortcutEngine) {
        cancelFn = nil
        let f = runFn
        runFn = nil
        f?(engine)
    }

    deinit {
        cancelFn?()
    }
}

private enum ShortcutInvokeAction<T> {
    case notRunning
    case immediate(Waker?)
    #if !os(WASI)
    case queued(ShortcutJobReply<T>, Waker?)
    #endif
}

private let threadEnginesLock = LiveLock()
// PORT NOTE: Keyed by `(threadId, ownerKey)` and guarded by `threadEnginesLock`, matching upstream `thread_local! { ENGINES }`.
nonisolated(unsafe) private var threadEngines: [String: ShortcutEngine] = [:]

private func engineTableKey(_ threadId: UInt64, _ key: Int) -> String {
    "\(threadId):\(key)"
}

// PORT NOTE: Synchronized via `routingLock` (`LiveLock`), mirroring `Control` in `crates/rune/src/shortcuts/service.rs`.
final class ShortcutControl: @unchecked Sendable {
    let key: Int = allocateShortcutOwnerKey()
    private let routingLock = LiveLock()
    private var ownerThread: UInt64? = nil
    private var wakeFn: Waker? = nil
    private var jobs: [QueuedShortcutJob] = []
    #if os(Linux)
    private let linuxEngineLock = LiveLock()
    private var linuxEngine: ShortcutEngine? = nil
    #endif

    func attach(_ engine: ShortcutEngine, wake: @escaping Waker) {
        let tid = currentShortcutThreadId()
        #if os(Linux)
        linuxEngineLock.withLock { linuxEngine = engine }
        #else
        threadEnginesLock.withLock {
            threadEngines[engineTableKey(tid, key)] = engine
        }
        #endif
        routingLock.withLock {
            ownerThread = tid
            wakeFn = wake
        }
    }

    func detach() {
        let oldOwner: UInt64? = routingLock.withLock {
            let prev = ownerThread
            ownerThread = nil
            wakeFn = nil
            jobs.removeAll()
            return prev
        }
        #if os(Linux)
        let eng = linuxEngineLock.withLock { () -> ShortcutEngine? in
            let e = linuxEngine
            linuxEngine = nil
            return e
        }
        eng?.release()
        #else
        if let tid = oldOwner {
            let eng = threadEnginesLock.withLock {
                threadEngines.removeValue(forKey: engineTableKey(tid, key))
            }
            eng?.release()
        }
        #endif
    }

    func drain() {
        #if !os(Linux)
        let tid = currentShortcutThreadId()
        let pendingJobs = routingLock.withLock { () -> [QueuedShortcutJob] in
            let out = jobs
            jobs.removeAll()
            return out
        }
        guard !pendingJobs.isEmpty else { return }
        let eng = threadEnginesLock.withLock {
            threadEngines[engineTableKey(tid, key)]
        }
        if let eng {
            for job in pendingJobs {
                job.run(eng)
            }
        }
        #endif
    }

    func invoke<T>(_ f: @escaping @Sendable (ShortcutEngine) -> Result<T, ShortcutError>) -> Result<T, ShortcutError> {
        #if os(Linux)
        let (owner, wake) = routingLock.withLock { (ownerThread, wakeFn) }
        guard owner != nil else { return .failure(.notRunning) }
        let res: Result<T, ShortcutError>? = linuxEngineLock.withLock {
            guard let eng = linuxEngine else { return nil }
            return f(eng)
        }
        guard let res else { return .failure(.notRunning) }
        wake?()
        return res
        #else
        let currentTid = currentShortcutThreadId()
        let action: ShortcutInvokeAction<T> = routingLock.withLock {
            guard let owner = ownerThread else { return .notRunning }
            if owner == currentTid {
                return .immediate(wakeFn)
            }
            #if os(WASI)
            return .notRunning
            #else
            let reply = ShortcutJobReply<T>()
            let job = QueuedShortcutJob(
                run: { engine in reply.send(f(engine)) },
                cancel: { reply.send(.failure(.notRunning)) }
            )
            jobs.append(job)
            return .queued(reply, wakeFn)
            #endif
        }
        switch action {
        case .notRunning:
            return .failure(.notRunning)
        case .immediate(let wake):
            let eng = threadEnginesLock.withLock {
                threadEngines[engineTableKey(currentTid, key)]
            }
            guard let eng else { return .failure(.notRunning) }
            let result = f(eng)
            wake?()
            return result
        #if !os(WASI)
        case .queued(let reply, let wake):
            wake?()
            return reply.wait()
        #endif
        }
        #endif
    }
}

// PORT NOTE: Synchronized via `lock` (`LiveLock`), mirroring `Hub<S>` in `crates/rune/src/shortcuts/service.rs`.
final class ShortcutHub<S>: @unchecked Sendable {
    typealias Handler = @Sendable (inout S, inout Tx) -> Void

    let control = ShortcutControl()
    private let lock = LiveLock()
    private var pendingList: [(Result<Shortcut, ShortcutError>, Handler)] = []
    private var handlers: [ShortcutId: Handler] = [:]
    private var startupErrors: [ShortcutError] = []
    private var appTitle: String = ""
    private var allowUnmodifiedFlag: Bool = false

    init() {}

    func named(_ title: String) {
        lock.withLock {
            if appTitle.isEmpty {
                appTitle = title
            }
        }
    }

    func title() -> String {
        lock.withLock { appTitle }
    }

    func allowUnmodified() {
        lock.withLock { allowUnmodifiedFlag = true }
    }

    func addPending(_ shortcut: Result<Shortcut, ShortcutError>, _ handler: @escaping Handler) {
        lock.withLock {
            pendingList.append((shortcut, handler))
        }
    }

    func takePending() -> [(Result<Shortcut, ShortcutError>, Handler)] {
        lock.withLock {
            let out = pendingList
            pendingList.removeAll()
            return out
        }
    }

    func recordStartupError(_ error: ShortcutError) {
        lock.withLock {
            startupErrors.append(error)
        }
    }

    func takeErrors() -> [ShortcutError] {
        lock.withLock {
            let out = startupErrors
            startupErrors.removeAll()
            return out
        }
    }

    func handler(for id: ShortcutId) -> Handler? {
        lock.withLock { handlers[id] }
    }

    func clearHandlers() {
        lock.withLock { handlers.removeAll() }
    }

    func register(_ shortcut: Shortcut, _ handler: @escaping Handler) -> Result<ShortcutId, ShortcutError> {
        let unmodifiedAllowed = lock.withLock { allowUnmodifiedFlag }
        if !unmodifiedAllowed {
            if case .failure(let err) = shortcut.requireModifier() {
                return .failure(err)
            }
        }
        guard case .success(let id) = allocateShortcutId() else {
            return .failure(.backend("shortcut id space exhausted"))
        }
        lock.withLock {
            handlers[id] = handler
        }
        if case .failure(let err) = control.invoke({ engine in engine.register(id, shortcut) }) {
            lock.withLock { _ = handlers.removeValue(forKey: id) }
            return .failure(err)
        }
        return .success(id)
    }

    func unregister(_ id: ShortcutId) -> Result<Void, ShortcutError> {
        control.invoke { [weak self] engine in
            if case .failure(let err) = engine.unregister(id) {
                return .failure(err)
            }
            self?.lock.withLock {
                _ = self?.handlers.removeValue(forKey: id)
            }
            return .success(())
        }
    }

    func owner(_ shortcut: Shortcut) -> String? {
        if case .success(let name) = control.invoke({ engine in .success(engine.owner(shortcut)) }) {
            return name
        }
        return nil
    }

    func fire(_ shortcut: Shortcut) -> Result<Void, ShortcutError> {
        control.invoke { engine in
            guard let (id, _) = engine.registrations.first(where: { $0.value == shortcut }) else {
                return .failure(.unknownId)
            }
            engine.sink(id, nil)
            return .success(())
        }
    }
}

/// Owned by the host, not `AppHandle`: closing/dropping the app releases native registrations and handler captures.
final class ShortcutGuard {
    private let control: ShortcutControl
    private var cleanup: (() -> Void)?

    private init(control: ShortcutControl, cleanup: @escaping () -> Void) {
        self.control = control
        self.cleanup = cleanup
    }

    static func attach<S>(
        _ handle: AppHandle<S>,
        wake: @escaping Waker,
        headless: Bool,
        wayland: Bool
    ) -> ShortcutGuard {
        let sink: ShortcutSink = { [weak handle] id, token in
            guard let handle else { return }
            handle.update { [weak handle] state, tx in
                guard let handler = handle?.shortcutHub.handler(for: id) else { return }
                tx.setShortcutActivationToken(token)
                handler(&state, &tx)
                tx.setShortcutActivationToken(nil)
            }
        }
        let hub = handle.shortcutHub
        let engine = ShortcutEngine(
            title: hub.title(),
            headless: headless,
            wayland: wayland,
            sink: sink
        )
        hub.control.attach(engine, wake: wake)
        let guardObj = ShortcutGuard(control: hub.control) { [weak hub] in
            hub?.clearHandlers()
        }
        for (parsed, handler) in hub.takePending() {
            let result = parsed.flatMap { hub.register($0, handler) }
            if case .failure(let err) = result {
                hub.recordStartupError(err)
            }
        }
        return guardObj
    }

    func drain() {
        control.drain()
    }

    func release() {
        control.detach()
        let fn = cleanup
        cleanup = nil
        fn?()
    }

    deinit {
        release()
    }
}
