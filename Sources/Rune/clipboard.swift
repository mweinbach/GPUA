// Ported from: crates/rune/src/clipboard.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! One OS clipboard worker shared by windows and overlays. No OS reads on the event thread.

#if !os(WASI)
import Foundation
#endif

/// What became of a secret copy.
public enum SecretState: Sendable, Equatable, Hashable {
    /// Not written yet.
    case pending
    /// On the clipboard: the last copy Rune wrote, and the clipboard hasn't changed since.
    case holding
    /// Cleared by Rune: its delay ran out, or `clearNow` or `Tx.clearSecretClipboard` ran.
    case cleared
    /// Something else took its place: a later copy, a change by another app, or a newer copy
    /// before this one was written. Its countdown should end quietly.
    case replaced
    /// The write failed; the clipboard didn't change.
    case failed(String)

    /// Spine compatibility alias for `.holding`.
    public static let copied: SecretState = .holding
}

enum ClipboardRoute: Sendable {
    case system(@Sendable (ClipboardRequest) -> Void)
    case memory(MemoryClipboard)

    func send(_ request: ClipboardRequest) {
        switch self {
        case .system(let sendFn):
            sendFn(request)
        case .memory(let mem):
            mem.handle(request)
        }
    }
}

// PORT NOTE: Synchronized via `lock` (`LiveLock`), mirroring `Slot` (`Mutex<SecretState>`, `AtomicBool`, `OnceLock<Route>`) in `crates/rune/src/clipboard.rs`.
final class SecretSlot: @unchecked Sendable {
    private let lock = LiveLock()
    private var currentState: SecretState = .pending
    private var cancelledFlag: Bool = false
    private var boundRoute: ClipboardRoute? = nil

    init() {}

    func getState() -> SecretState {
        lock.withLock { currentState }
    }

    func setState(_ state: SecretState) {
        lock.withLock { currentState = state }
    }

    func isCancelled() -> Bool {
        lock.withLock { cancelledFlag }
    }

    func setCancelled() {
        lock.withLock { cancelledFlag = true }
    }

    func bindOnce(_ route: ClipboardRoute) {
        lock.withLock {
            if boundRoute == nil {
                boundRoute = route
            }
        }
    }

    func route() -> ClipboardRoute? {
        lock.withLock { boundRoute }
    }

    func settleOnUnwrittenDrop() {
        lock.withLock {
            if currentState == .pending {
                currentState = cancelledFlag ? .cleared : .replaced
            }
        }
    }
}

/// Settles a secret write that was dropped before reaching a clipboard (replaced in its
/// handler, cancelled, or left in a headless runtime with no clipboard).
// PORT NOTE: Mirrors `Unwritten(Arc<Slot>)` and its `Drop` impl in `crates/rune/src/clipboard.rs`; `SecretSlot` is thread-safe.
final class UnwrittenSecret: @unchecked Sendable {
    let slot: SecretSlot

    init(_ slot: SecretSlot) {
        self.slot = slot
    }

    deinit {
        slot.settleOnUnwrittenDrop()
    }
}

/// A secret copy from `Tx.copySecret`. It holds no text, and is cheap to clone and send.
/// Its state is updated by the clipboard worker; asking never reads the OS clipboard.
public struct SecretCopy: Sendable, Equatable, CustomDebugStringConvertible {
    let slot: SecretSlot
    /// Spine compatibility fields for legacy construction (`SecretCopy(text:ttlSeconds:)`).
    public var text: String
    public var ttlSeconds: Double

    init(_ slot: SecretSlot) {
        self.slot = slot
        self.text = ""
        self.ttlSeconds = 0.0
    }

    public init(text: String, ttlSeconds: Double = 45.0) {
        self.slot = SecretSlot()
        self.text = text
        self.ttlSeconds = ttlSeconds
    }

    /// A copy that is never written and stays `.pending`, for scenes and tests that show a copy
    /// in flight without a `Tx`.
    public static func pending() -> SecretCopy {
        SecretCopy(SecretSlot())
    }

    public func state() -> SecretState {
        if case .memory(let mem)? = slot.route() {
            mem.tick()
        }
        return slot.getState()
    }

    /// Still the last copy Rune wrote, and the clipboard hasn't changed since.
    public func holds() -> Bool {
        state() == .holding
    }

    /// Clear the clipboard now if this copy still holds it, on the clipboard worker. A copy not
    /// yet written is never written. Idempotent.
    public func clearNow() {
        slot.setCancelled()
        if slot.getState() == .holding, let r = slot.route() {
            r.send(.clear(slot))
        }
    }

    public static func == (lhs: SecretCopy, rhs: SecretCopy) -> Bool {
        lhs.slot === rhs.slot
    }

    public var debugDescription: String {
        "SecretCopy(\(slot.getState()))"
    }
}

/// A pending clipboard write. Debug output never includes its contents.
public struct ClipboardWrite: Sendable, Equatable, CustomDebugStringConvertible {
    private let contentValue: ClipboardContent
    let clearAfter: Duration?
    private let unwritten: UnwrittenSecret?

    private init(content: ClipboardContent, clearAfter: Duration?, unwritten: UnwrittenSecret?) {
        self.contentValue = content
        self.clearAfter = clearAfter
        self.unwritten = unwritten
    }

    static func new(_ content: ClipboardContent) -> ClipboardWrite {
        ClipboardWrite(content: content, clearAfter: nil, unwritten: nil)
    }

    /// Secrets are plain text only: no HTML or RTF copy of a password lingers.
    static func secret(_ text: String, _ clearAfter: Duration) -> (ClipboardWrite, SecretCopy) {
        let slot = SecretSlot()
        let write = ClipboardWrite(
            content: ClipboardContent.new(text),
            clearAfter: clearAfter,
            unwritten: UnwrittenSecret(slot)
        )
        return (write, SecretCopy(slot))
    }

    // MARK: - Spine Compatibility Factories

    public static func text(_ text: String) -> ClipboardWrite {
        ClipboardWrite.new(ClipboardContent.new(text))
    }

    public static func rich(text: String, html: String?) -> ClipboardWrite {
        var c = ClipboardContent.new(text)
        if let html {
            c = c.withHtml(html)
        }
        return ClipboardWrite.new(c)
    }

    public static func image(_ image: ClipboardImage) -> ClipboardWrite {
        ClipboardWrite.new(ClipboardContent().withImage(image))
    }

    public static func secret(_ secret: SecretCopy) -> ClipboardWrite {
        let dur = Duration.milliseconds(Int64((secret.ttlSeconds * 1000.0).rounded()))
        return ClipboardWrite(
            content: ClipboardContent.new(secret.text),
            clearAfter: dur,
            unwritten: UnwrittenSecret(secret.slot)
        )
    }

    /// Everything this write puts on the clipboard.
    public func content() -> ClipboardContent {
        contentValue
    }

    func isSecret() -> Bool {
        clearAfter != nil
    }

    func slot() -> SecretSlot? {
        unwritten?.slot
    }

    func bind(_ route: ClipboardRoute) {
        unwritten?.slot.bindOnce(route)
    }

    public static func == (lhs: ClipboardWrite, rhs: ClipboardWrite) -> Bool {
        lhs.contentValue == rhs.contentValue
            && lhs.clearAfter == rhs.clearAfter
            && (lhs.unwritten != nil) == (rhs.unwritten != nil)
    }

    public var debugDescription: String {
        let clearStr = clearAfter.map { String(describing: $0) } ?? "nil"
        return "ClipboardWrite { clear_after: \(clearStr), .. }"
    }
}

/// The forms a paste target takes, so a read fetches no more than it needs.
enum ClipboardForms: Sendable, Equatable {
    case text
    case rich
    case all
}

/// Why the clipboard is read.
enum ClipboardPurpose: Sendable, Equatable {
    case paste(String?, ClipboardForms)
    case read(UInt64)

    static func pasteForRuntime<S>(_ rt: Runtime<S>, _ target: String?) -> ClipboardPurpose {
        _ = rt
        return .paste(target, .all)
    }

    func forms() -> ClipboardForms {
        switch self {
        case .paste(_, let f): return f
        case .read: return .all
        }
    }

    func answer<B: ClipboardBackend>(_ cb: inout B) -> ClipboardReply? {
        let content: ClipboardContent?
        switch forms() {
        case .text:
            content = cb.text().map(ClipboardContent.new)
        case .rich:
            content = cb.content(false)
        case .all:
            content = cb.content(true)
        }
        return reply(content)
    }

    func reply(_ content: ClipboardContent?) -> ClipboardReply? {
        let resolved: ClipboardContent
        switch self {
        case .paste:
            guard let c = content else { return nil }
            resolved = c
        case .read:
            resolved = content ?? ClipboardContent()
        }
        return ClipboardReply(purpose: self, content: resolved.untrusted())
    }
}

struct ClipboardReply: Sendable {
    var purpose: ClipboardPurpose
    var content: ClipboardContent
}

// PORT NOTE: Synchronized via `lock` (`LiveLock`), mirroring `Arc<AtomicBool>` in `crates/rune/src/clipboard.rs`.
final class ClipboardChangedFlag: @unchecked Sendable {
    private let lock = LiveLock()
    private var flag: Bool = false

    init() {}

    func store(_ value: Bool) {
        lock.withLock { flag = value }
    }

    func load() -> Bool {
        lock.withLock { flag }
    }

    func swap(_ value: Bool) -> Bool {
        lock.withLock {
            let old = flag
            flag = value
            return old
        }
    }
}

struct ClipboardNotify: Sendable {
    let changed: ClipboardChangedFlag
    let wake: Waker

    func send() {
        changed.store(true)
        wake()
    }
}

enum ClipboardRequest: Sendable {
    case shutdown
    case write(ClipboardWrite, ClipboardNotify?)
    case clear(SecretSlot?)
    case read(purpose: ClipboardPurpose, reply: @Sendable (ClipboardReply) -> Bool, wake: Waker)
}

// PORT NOTE: Thread-safe reply queue guarded by `LiveLock`, mirroring `mpsc::channel::<Reply>()` in `crates/rune/src/clipboard.rs`.
final class ClipboardReplyBox: @unchecked Sendable {
    private let lock = LiveLock()
    private var queue: [ClipboardReply] = []

    func push(_ reply: ClipboardReply) -> Bool {
        lock.withLock {
            queue.append(reply)
            return true
        }
    }

    func drain() -> [ClipboardReply] {
        lock.withLock {
            let out = queue
            queue.removeAll()
            return out
        }
    }
}

final class ClipboardClient {
    let replyBox = ClipboardReplyBox()
    var wake: Waker = {}
    let changed = ClipboardChangedFlag()

    init() {}

    func connect(_ wake: @escaping Waker) {
        self.wake = wake
    }

    func sendReply(_ reply: ClipboardReply) -> Bool {
        replyBox.push(reply)
    }

    func read<S>(_ rt: Runtime<S>) {
        let att = hostAttachment(for: rt)
        let purpose = ClipboardPurpose.pasteForRuntime(rt, nil)
        if let m = att.clipboard {
            if let reply = m.answer(purpose), sendReply(reply) {
                wake()
            }
            return
        }
        readFor(purpose)
    }

    func receive<S>(_ rt: Runtime<S>) -> Bool {
        var received = changed.swap(false)
        for reply in replyBox.drain() {
            deliverClipboardReply(rt, reply)
            received = true
        }
        return received
    }
}

func deliverClipboardReply<S>(_ rt: Runtime<S>, _ reply: ClipboardReply) {
    let att = hostAttachment(for: rt)
    switch reply.purpose {
    case .paste:
        _ = rt.hostPaste(reply.content)
    case .read(let id):
        if let idx = att.clipboardReads.firstIndex(where: { $0.0 == id }) {
            let (_, callback) = att.clipboardReads.remove(at: idx)
            var tx = rt.hostNewTx()
            rt.hostWithStates { states in
                callback(states, reply.content, &tx)
            }
            rt.hostLatchTx(&tx)
            if !tx.liveOnlyFlag {
                att.dirtyFromHost = true
            }
        }
    }
}

/// Applies a runtime's clipboard requests to its memory clipboard, if it has one.
func flushMemoryClipboard<S>(_ rt: Runtime<S>) {
    let att = hostAttachment(for: rt)
    guard let m = att.clipboard else { return }
    if att.clearSecretRequest {
        att.clearSecretRequest = false
        m.handle(.clear(nil))
    }
    if let copy = att.copyRequest {
        att.copyRequest = nil
        copy.bind(.memory(m))
        m.handle(.write(copy, nil))
    }
    var purposes: [ClipboardPurpose] = []
    if let pasteTarget = att.pasteRequest {
        att.pasteRequest = nil
        purposes.append(.pasteForRuntime(rt, pasteTarget))
    }
    let readIds = att.readRequests
    att.readRequests.removeAll()
    for id in readIds {
        purposes.append(.read(id))
    }
    for purpose in purposes {
        if let reply = m.answer(purpose) {
            deliverClipboardReply(rt, reply)
        }
    }
}

extension Runtime {
    /// Use a shared in-memory clipboard (`clipboard.memory()`) instead of the OS one: copies,
    /// secret clears and pastes go to it, in headless runs too. For tests.
    public func useClipboard(_ clipboard: MemoryClipboard) {
        let att = hostAttachment(for: self)
        att.clipboard = clipboard
    }

    func hostLatchTx(_ tx: inout Tx) {
        let att = hostAttachment(for: self)
        if let s = tx.shellRequest {
            if let cur = att.shellRequest {
                att.shellRequest = max(cur, s)
            } else {
                att.shellRequest = s
            }
            tx.shellRequest = nil
        }
        if tx.minimizeFlag {
            att.minimizeRequest = true
            tx.minimizeFlag = false
        }
        if !tx.openUrls.isEmpty {
            let links = tx.openUrls
            let reads = tx.drainSidecar(as: ClipboardReadBox.self)
            for readBox in reads {
                if let cb = readBox.take() {
                    att.nextClipboardRead += 1
                    att.clipboardReads.append((att.nextClipboardRead, cb))
                    att.readRequests.append(att.nextClipboardRead)
                }
            }
            hostLatchFileDialogs(&tx)
            hostLatchPopups(&tx)
            tx.openUrls.removeAll { $0.sidecar == nil }
            openHostUrls(links)
        }
        if tx.clearSecretFlag {
            tx.clearSecretFlag = false
            if att.copyRequest?.isSecret() == true {
                att.copyRequest = nil
            }
            if pendingWindowRequests.clipboardWrite?.isSecret() == true {
                pendingWindowRequests.clipboardWrite = nil
            }
            att.clearSecretRequest = true
        }
        if let copy = tx.copyWrite {
            tx.copyWrite = nil
            pendingWindowRequests.clipboardWrite = nil
            att.copyRequest = copy
        }
        if tx.pasteFlag {
            tx.pasteFlag = false
            att.pasteRequest = .some(nil)
        }
        if let title = tx.titleString {
            att.setWindowTitle(title)
            tx.titleString = nil
        }
        hostLatchWindowTx(&tx)
        flushMemoryClipboard(self)
    }

    @discardableResult
    func hostUpdateIf(_ f: (inout S, inout Tx) -> Bool) -> Bool {
        let att = hostAttachment(for: self)
        let hs = windowHostState(for: self)
        let commitBefore = hs.needsCommit
        var changed = false
        var capturedTx = Tx()
        update { s, tx in
            if scene.tracing() || toolingTraceState(for: self).enabled { tx.traceCalls = TraceCalls() }
            changed = f(&s, &tx)
            if !changed {
                tx.liveOnly()
            }
            capturedTx = tx
        }
        hostLatchTx(&capturedTx)
        let txAskedForCommit = !commitBefore && hs.needsCommit
        if (changed && !capturedTx.liveOnlyFlag) || txAskedForCommit {
            att.dirtyFromHost = true
            return true
        }
        return changed
    }

    func hostUpdate(_ f: (inout S, inout Tx) -> Void) {
        _ = hostUpdateIf { s, tx in
            f(&s, &tx)
            return true
        }
    }

    func hostNeedsCommit() -> Bool {
        hostAttachment(for: self).dirtyFromHost || hostWindowNeedsCommit()
    }

    @discardableResult
    func hostPollHidden() -> Bool {
        let hs = windowHostState(for: self)
        var timerFired = false
        while let earliest = hs.timerDeadlines.first, earliest <= clock + 1e-9 {
            hs.timerDeadlines.removeFirst()
            timerFired = true
        }
        if timerFired {
            hs.needsCommit = true
        }
        let changed = hostRunPollHooks()
        _ = hostSchedulePendingWakes()
        hostRecordPolledAt()
        return changed || timerFired
    }
}

struct ClipboardWriteError: Error, Sendable, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
}

protocol ClipboardBackend {
    mutating func write(_ copy: ClipboardWrite) -> Result<Void, ClipboardWriteError>
    mutating func text() -> String?
    mutating func content(_ all: Bool) -> ClipboardContent?
    func revision() -> UInt64?
    mutating func clear()
}

extension ClipboardBackend {
    mutating func content(_ all: Bool) -> ClipboardContent? {
        _ = all
        return text().map(ClipboardContent.new)
    }
}

struct MemoryClipboardBoard: ClipboardBackend {
    var storedContent: ClipboardContent? = nil
    var currentRevision: UInt64 = 0
    var failError: String? = nil

    mutating func write(_ copy: ClipboardWrite) -> Result<Void, ClipboardWriteError> {
        if let error = failError {
            return .failure(ClipboardWriteError(error))
        }
        storedContent = copy.content()
        currentRevision += 1
        return .success(())
    }

    mutating func text() -> String? {
        guard let c = storedContent, c.hasPlain() else { return nil }
        return c.text()
    }

    mutating func content(_ all: Bool) -> ClipboardContent? {
        guard let c = storedContent else { return nil }
        return all ? c : c.textForms()
    }

    func revision() -> UInt64? {
        currentRevision
    }

    mutating func clear() {
        storedContent = nil
        currentRevision += 1
    }
}

#if os(macOS) || os(Windows)
let CLIPBOARD_WATCH_DURATION: Duration = .milliseconds(250)
#else
let CLIPBOARD_WATCH_DURATION: Duration = .seconds(1)
#endif

private struct HeldSecret {
    var slot: SecretSlot?
    var notify: ClipboardNotify?
    var deadline: RuneInstant?
    var revision: UInt64?
    var fingerprint: UInt64
}

private struct OwnPillsRecord {
    var revision: UInt64?
    var textPrint: UInt64
    var pills: [(Range<Int>, String)]
}

/// Keyed FNV-1a fingerprint so secret text never stays in `HeldSecret`.
private struct ClipboardKeyedHasher {
    private let k0: UInt64
    private let k1: UInt64

    init() {
        self.k0 = UInt64.random(in: 0...UInt64.max)
        self.k1 = UInt64.random(in: 0...UInt64.max)
    }

    func hashOne(_ text: String) -> UInt64 {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325 ^ k0
        for b in text.utf8 {
            h ^= UInt64(b)
            h = h &* 0x0000_0100_0000_01b3
        }
        return h ^ k1
    }
}

/// Extracts `<span data-pill="...">...</span>` ranges and IDs from HTML without requiring `TextEdit.fromHtml`.
// PORT NOTE: Self-contained `<span data-pill="...">` scanner matching `TextEdit::from_html(...).pills()` while `edit/html.rs` is ported separately.
private func extractDataPills(_ html: String) -> [(Range<Int>, String)] {
    guard html.contains("<span data-pill=") else { return [] }
    let bytes = Array(html.utf8)
    var out: [(Range<Int>, String)] = []
    var plainLen = 0
    var i = 0
    let count = bytes.count
    var pillStack: [(Int, String)] = []

    while i < count {
        if bytes[i] == 0x3C /* '<' */ {
            guard let gt = bytes[i..<count].firstIndex(of: 0x3E /* '>' */) else { break }
            let tagStr = String(decoding: bytes[(i + 1)..<gt], as: UTF8.self)
            let lower = tagStr.lowercased()
            if lower.hasPrefix("span"), let attrPos = lower.range(of: "data-pill=") {
                let afterEq = tagStr[attrPos.upperBound...].trimmingCharacters(in: .whitespaces)
                var id = ""
                if let q = afterEq.first, q == "\"" || q == "'" {
                    let rest = afterEq.dropFirst()
                    if let endQ = rest.firstIndex(of: q) {
                        id = String(rest[..<endQ])
                    }
                }
                pillStack.append((plainLen, id))
            } else if lower.hasPrefix("/span"), let (startOffset, id) = pillStack.popLast(), !id.isEmpty {
                out.append((startOffset..<plainLen, id))
            }
            i = gt + 1
        } else {
            plainLen += 1
            i += 1
        }
    }
    return out
}

struct ClipboardCore {
    private let keys = ClipboardKeyedHasher()
    private var held: HeldSecret? = nil
    private var ownPills: OwnPillsRecord? = nil

    var hasHeldSecret: Bool { held != nil }

    func nextCheck() -> RuneInstant? {
        guard let held else { return nil }
        let watch = RuneInstant.now().adding(CLIPBOARD_WATCH_DURATION)
        if let deadline = held.deadline {
            return min(deadline, watch)
        }
        return watch
    }

    mutating func handle<B: ClipboardBackend>(_ cb: inout B, _ request: ClipboardRequest) {
        switch request {
        case .write(let copy, let notify):
            write(&cb, copy, notify)
        case .clear(let which):
            clear(&cb, which)
        case .read(let purpose, let reply, let wake):
            if let ans = answer(&cb, purpose), reply(ans) {
                wake()
            }
        case .shutdown:
            break
        }
    }

    mutating func answer<B: ClipboardBackend>(_ cb: inout B, _ purpose: ClipboardPurpose) -> ClipboardReply? {
        guard var reply = purpose.answer(&cb) else { return nil }
        if let own = ownPills {
            let revOk: Bool = switch (own.revision, cb.revision()) {
            case (.some(let a), .some(let b)): a == b
            case (.none, .none): true
            default: false
            }
            let htmlOk: Bool = {
                guard let h = reply.content.html() else { return false }
                let pills = extractDataPills(h)
                guard pills.count == own.pills.count else { return false }
                for ((r1, id1), (r2, id2)) in zip(pills, own.pills) {
                    if r1 != r2 || id1 != id2 { return false }
                }
                return true
            }()
            if revOk && keys.hashOne(reply.content.text()) == own.textPrint && htmlOk {
                reply.content.ownPills = true
            }
        }
        return reply
    }

    mutating func write<B: ClipboardBackend>(_ cb: inout B, _ copy: ClipboardWrite, _ notify: ClipboardNotify?) {
        let slot = copy.slot()
        let activeNotify = (slot != nil) ? notify : nil
        if slot?.isCancelled() == true {
            slot?.settleOnUnwrittenDrop()
            return
        }
        if case .failure(let error) = cb.write(copy) {
            slot?.setState(.failed(error.message))
            activeNotify?.send()
            return
        }
        release(.replaced)
        let rev = cb.revision()
        if copy.clearAfter == nil,
           let h = copy.content().html(),
           h.contains("<span data-pill=")
        {
            let pills = extractDataPills(h)
            ownPills = pills.isEmpty
                ? nil
                : OwnPillsRecord(revision: rev, textPrint: keys.hashOne(copy.content().text()), pills: pills)
        } else {
            ownPills = nil
        }

        if let delay = copy.clearAfter {
            slot?.setState(.holding)
            held = HeldSecret(
                slot: slot,
                notify: activeNotify,
                deadline: RuneInstant.now().adding(delay),
                revision: rev,
                fingerprint: keys.hashOne(copy.content().text())
            )
            activeNotify?.send()
            if slot?.isCancelled() == true {
                clear(&cb, slot)
            }
        }
    }

    mutating func release(_ state: SecretState) {
        guard let prev = held else { return }
        held = nil
        prev.slot?.setState(state)
        prev.notify?.send()
    }

    mutating func unchanged<B: ClipboardBackend>(_ cb: inout B) -> Bool {
        guard let held else { return false }
        guard held.revision == cb.revision(), let currentText = cb.text() else { return false }
        return keys.hashOne(currentText) == held.fingerprint
    }

    mutating func clear<B: ClipboardBackend>(_ cb: inout B, _ which: SecretSlot?) {
        guard let currentHeld = held else { return }
        if let which {
            guard let heldSlot = currentHeld.slot, heldSlot === which else { return }
        }
        if unchanged(&cb) {
            cb.clear()
            ownPills = nil
            release(.cleared)
        } else {
            release(.replaced)
        }
    }

    mutating func tick<B: ClipboardBackend>(_ cb: inout B) {
        if let own = ownPills, let rev = own.revision, cb.revision() != rev {
            ownPills = nil
        }
        guard let currentHeld = held else { return }
        if let deadline = currentHeld.deadline, RuneInstant.now() >= deadline {
            clear(&cb, nil)
            return
        }
        let changed: Bool
        if let rev = currentHeld.revision {
            changed = cb.revision() != rev
        } else {
            changed = !unchanged(&cb)
        }
        if changed {
            release(.replaced)
        }
    }
}

// PORT NOTE: Synchronized via `lock` (`LiveLock`), mirroring `Arc<Mutex<Memory>>` in `crates/rune/src/clipboard.rs`.
final class MemoryClipboardStorage: @unchecked Sendable {
    let lock = LiveLock()
    var core = ClipboardCore()
    var board = MemoryClipboardBoard()
}

/// An in-memory clipboard for tests, shared by its clones and by every runtime given it with
/// `Runtime.useClipboard`. It behaves like the OS clipboard, synchronously.
public struct MemoryClipboard: Sendable, CustomDebugStringConvertible {
    private let storage = MemoryClipboardStorage()

    public init() {}

    public func text() -> String? {
        guard let c = content(), c.hasPlain() else { return nil }
        return c.text()
    }

    /// Every form on the clipboard, as written: pastes from it are sanitised, this isn't.
    public func content() -> ClipboardContent? {
        ticked { _, board in board.storedContent }
    }

    /// Changes the clipboard as another app would.
    public func setText(_ text: String) {
        setContent(ClipboardContent.new(text))
    }

    /// Puts several forms on the clipboard as another app would.
    public func setContent(_ content: ClipboardContent) {
        storage.lock.withLock {
            storage.board.storedContent = content
            storage.board.currentRevision += 1
            storage.core.tick(&storage.board)
        }
    }

    /// Makes later writes fail with `error`, or succeed again with `nil`.
    public func failWrites(_ error: String?) {
        storage.lock.withLock {
            storage.board.failError = error
        }
    }

    func tick() {
        ticked { _, _ in () }
    }

    func answer(_ purpose: ClipboardPurpose) -> ClipboardReply? {
        ticked { core, board in core.answer(&board, purpose) }
    }

    func handle(_ request: ClipboardRequest) {
        ticked { core, board in core.handle(&board, request) }
    }

    private func ticked<R>(_ f: (inout ClipboardCore, inout MemoryClipboardBoard) -> R) -> R {
        storage.lock.withLock {
            storage.core.tick(&storage.board)
            return f(&storage.core, &storage.board)
        }
    }

    public var debugDescription: String {
        "MemoryClipboard { .. }"
    }
}

/// Creates a shared in-memory clipboard for tests.
public func memory() -> MemoryClipboard {
    MemoryClipboard()
}

/// Called by the shared event-loop exit path, including overlay-only applications.
func shutdownClipboard() {
    #if !os(WASI)
    shutdownNativeClipboard()
    #endif
}

/// Module namespace mirroring `rune::clipboard`.
public enum clipboard {
    public typealias ClipboardContent = Rune.ClipboardContent
    public typealias ClipboardImage = Rune.ClipboardImage
    public typealias ClipboardWrite = Rune.ClipboardWrite
    public typealias SecretCopy = Rune.SecretCopy
    public typealias SecretState = Rune.SecretState
    public typealias MemoryClipboard = Rune.MemoryClipboard
    public static let MAX_IMAGE_BYTES = Rune.MAX_IMAGE_BYTES

    public static func memory() -> MemoryClipboard {
        Rune.memory()
    }

    public static func sanitizeHtml(_ raw: String) -> String {
        Rune.sanitizeHtml(raw)
    }
}
