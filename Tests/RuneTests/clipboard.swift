// Tests ported from: crates/rune/src/clipboard.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Foundation
import Testing
@testable import Rune

@Suite
struct ClipboardTests {
    final class FakeState: @unchecked Sendable {
        let lock = NSLock()
        var text: String = ""
        var revision: UInt64 = 0
        var clears: Int = 0
        var drops: Int = 0
    }

    final class FakeDropTracker: Sendable {
        let state: FakeState
        let onDrop: (@Sendable () -> Void)?

        init(state: FakeState, onDrop: (@Sendable () -> Void)?) {
            self.state = state
            self.onDrop = onDrop
        }

        deinit {
            state.lock.lock()
            state.drops += 1
            state.lock.unlock()
            onDrop?()
        }
    }

    struct FakeBackend: ClipboardBackend, Sendable {
        let state: FakeState
        let tracker: FakeDropTracker

        init(state: FakeState, onDrop: (@Sendable () -> Void)? = nil) {
            self.state = state
            self.tracker = FakeDropTracker(state: state, onDrop: onDrop)
        }

        mutating func write(_ copy: ClipboardWrite) -> Result<Void, ClipboardWriteError> {
            state.lock.lock()
            defer { state.lock.unlock() }
            state.text = copy.content().text()
            state.revision += 1
            return .success(())
        }

        mutating func text() -> String? {
            state.lock.lock()
            defer { state.lock.unlock() }
            return state.text
        }

        func revision() -> UInt64? {
            state.lock.lock()
            defer { state.lock.unlock() }
            return state.revision
        }

        mutating func clear() {
            state.lock.lock()
            defer { state.lock.unlock() }
            state.text = ""
            state.clears += 1
        }
    }

    private let longDelay: Duration = .seconds(3600)

    private func copySecret(_ m: MemoryClipboard, _ text: String, _ clearAfter: Duration) -> SecretCopy {
        let (write, handle) = ClipboardWrite.secret(text, clearAfter)
        write.bind(.memory(m))
        m.handle(.write(write, nil))
        return handle
    }

    @Test
    func shutdownExpiresOnlyOurPendingSecretBeforeDroppingBackend() {
        for replacement in [nil, "new value", "fixture"] {
            let state = FakeState()
            let worker = ClipboardWorker.spawn { FakeBackend(state: state) }
            worker.send(.write(ClipboardWrite.secret("fixture", longDelay).0, nil))
            let received = DispatchSemaphore(value: 0)
            worker.send(
                .read(
                    purpose: .paste(nil, .text),
                    reply: { _ in received.signal(); return true },
                    wake: {}
                )
            )
            #expect(received.wait(timeout: .now() + 2.0) == .success)
            if let text = replacement {
                state.lock.lock()
                state.text = text
                state.revision += 1
                state.lock.unlock()
            }
            worker.stop()
            worker.stop()
            state.lock.lock()
            let finalText = state.text
            let clears = state.clears
            let drops = state.drops
            state.lock.unlock()
            #expect(finalText == (replacement ?? ""))
            #expect(clears == (replacement == nil ? 1 : 0))
            #expect(drops == 1)
        }
    }

    @Test
    func shutdownDoesNotWaitIndefinitelyForABlockedBackend() {
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0)
        let worker = ClipboardWorker.spawn { () -> FakeBackend? in
            entered.signal()
            _ = release.wait(timeout: .now() + 5.0)
            return FakeBackend(state: FakeState()) { finished.signal() }
        }
        worker.send(.write(ClipboardWrite.secret("fixture", longDelay).0, nil))
        #expect(entered.wait(timeout: .now() + 2.0) == .success)
        let start = RuneInstant.now()
        worker.stop()
        #expect(start.elapsedSeconds() < 1.0)
        release.signal()
        #expect(finished.wait(timeout: .now() + 2.0) == .success)
    }

    @Test
    func workerReportsTheWriteAndWatchesForOutsideChanges() {
        let state = FakeState()
        let worker = ClipboardWorker.spawn { FakeBackend(state: state) }
        let wakes = DispatchSemaphore(value: 0)
        let notify = ClipboardNotify(changed: ClipboardChangedFlag(), wake: { wakes.signal() })
        let (write, handle) = ClipboardWrite.secret("fixture", longDelay)
        write.bind(.system { req in worker.send(req) })
        worker.send(.write(write, notify))
        #expect(wakes.wait(timeout: .now() + 2.0) == .success)
        #expect(handle.holds() && notify.changed.load())

        state.lock.lock()
        state.text = "theirs"
        state.revision += 1
        state.lock.unlock()

        #expect(wakes.wait(timeout: .now() + 3.0) == .success)
        #expect(handle.state() == .replaced)
        handle.clearNow()
        worker.stop()
        state.lock.lock()
        let finalText = state.text
        state.lock.unlock()
        #expect(finalText == "theirs")
    }

    @Test
    func holdsUntilALaterCopyOrAnOutsideChange() {
        let m = memory()
        let first = copySecret(m, "fixture", longDelay)
        #expect(first.holds())
        let second = copySecret(m, "fixture", longDelay)
        #expect(first.state() == .replaced)
        #expect(second.holds())
        m.setText("theirs")
        #expect(second.state() == .replaced)
        let expired = copySecret(m, "brief", .zero)
        #expect(expired.state() == .cleared)
        #expect(m.text() == nil)
        #expect(!("\(String(reflecting: expired)) \(String(reflecting: m))").contains("brief"))
    }

    @Test
    func clearNowClearsOnlyWhileItHolds() {
        let m = memory()
        let replaced = copySecret(m, "secret", longDelay)
        m.setText("theirs")
        replaced.clearNow()
        #expect(m.text() == "theirs")

        let held = copySecret(m, "secret", longDelay)
        held.clearNow()
        held.clearNow()
        #expect(held.state() == .cleared)
        #expect(m.text() == nil)

        let (write, unwritten) = ClipboardWrite.secret("never", longDelay)
        write.bind(.memory(m))
        unwritten.clearNow()
        m.handle(.write(write, nil))
        #expect(unwritten.state() == .cleared)
        #expect(m.text() == nil)

        var dropped: SecretCopy? = nil
        do {
            let (tempWrite, tempHandle) = ClipboardWrite.secret("dropped", longDelay)
            _ = tempWrite
            dropped = tempHandle
        }
        #expect(dropped?.state() == .replaced)
    }

    @Test
    func aFailedWriteReportsAndKeepsTheEarlierCopy() {
        let m = memory()
        let earlier = copySecret(m, "earlier", longDelay)
        m.failWrites("pasteboard denied")
        let failed = copySecret(m, "later", longDelay)
        #expect(failed.state() == .failed("pasteboard denied"))
        #expect(earlier.holds())
        #expect(m.text() == "earlier")
    }

    @Test
    func twoRuntimesShareAMemoryClipboard() {
        func view(_: SecretCopy?, _: Cx<SecretCopy?>) -> El { col() }
        let m = memory()
        let a = Runtime<SecretCopy?>(nil, view, (100.0, 100.0), Env.new(true, 1.0))
        a.useClipboard(m)
        _ = a.frame(0.0)
        let b = Runtime<SecretCopy?>(nil, view, (100.0, 100.0), Env.new(true, 1.0))
        b.useClipboard(m)
        _ = b.frame(0.0)

        a.hostUpdate { s, tx in s = tx.copySecret("from a", longDelay) }
        _ = a.frame(0.0)
        #expect(a.state?.holds() == true)

        b.hostUpdate { s, tx in s = tx.copySecret("from b", longDelay) }
        _ = b.frame(0.0)
        #expect(m.text() == "from b")
        #expect(a.state?.state() == .replaced)

        a.hostUpdate { _, tx in tx.clearSecretClipboard() }
        _ = a.frame(0.0)
        #expect(m.text() == nil)
        #expect(b.state?.state() == .cleared)

        a.hostUpdate { s, tx in s = tx.copySecret("no frame", longDelay) }
        #expect(m.text() == "no frame")

        let headless = Runtime<SecretCopy?>(nil, view, (100.0, 100.0), Env.new(true, 1.0))
        headless.hostUpdate { s, tx in s = tx.copySecret("nowhere", longDelay) }
        _ = headless.frame(0.0)
        #expect(headless.state?.state() == .pending)
    }

    @Test
    func richCopiesCarryEveryFormAndSecretsStayPlain() {
        func view(_: UInt8, _: Cx<UInt8>) -> El { col() }
        let m = memory()
        let rt = Runtime<UInt8>(0, view, (100.0, 100.0), Env.new(true, 1.0))
        rt.useClipboard(m)
        _ = rt.frame(0.0)
        let rich = ClipboardContent.new("Ship it")
            .withHtml("<b>Ship</b> it")
            .withRtf(#"{\rtf1 {\b Ship} it}"#)
        rt.hostUpdate { _, tx in tx.copyRich(rich) }
        #expect(m.content() == rich)
        #expect(m.text() == "Ship it")
        #expect(!("\(String(reflecting: rich)) \(String(reflecting: ClipboardWrite.new(rich)))").contains("Ship"))

        rt.hostUpdate { _, tx in _ = tx.copySecret("hunter2", longDelay) }
        let secret = m.content()!
        #expect(!secret.isRich() && secret.text() == "hunter2")
        rt.hostUpdate { _, tx in tx.clearSecretClipboard() }
        #expect(m.content() == nil)
    }

    @Test
    func theWorkerAnswersReadsWithSanitisedContent() {
        let state = FakeState()
        state.text = "<script>"
        let worker = ClipboardWorker.spawn { FakeBackend(state: state) }
        let replyBox = ClipboardReplyBox()
        let sem = DispatchSemaphore(value: 0)
        worker.send(
            .read(
                purpose: .read(7),
                reply: { r in _ = replyBox.push(r); sem.signal(); return true },
                wake: {}
            )
        )
        #expect(sem.wait(timeout: .now() + 2.0) == .success)
        let answer = replyBox.drain().first!
        #expect(answer.purpose == .read(7))
        #expect(answer.content.text() == "<script>")
        worker.stop()

        #expect(ClipboardPurpose.paste(nil, .rich).reply(nil) == nil)
        var board = MemoryClipboardBoard(
            storedContent: ClipboardContent.new("t").withHtml("<b>t</b>"),
            currentRevision: 0,
            failError: nil
        )
        let plain = ClipboardPurpose.paste(nil, .text).answer(&board)!.content
        #expect(!plain.isRich() && plain.text() == "t")
        let readReply = ClipboardPurpose.read(1).reply(ClipboardContent.new("").withHtml("<p onclick=x>t</p>"))!
        #expect(readReply.content.html() == "<p>t</p>")
        #expect(ClipboardPurpose.read(2).reply(nil)!.content == ClipboardContent())
    }

    @Test
    func clearsFromOnCloseAndAHiddenPollNeedNoFrame() {
        func view(_: UInt8, _: Cx<UInt8>) -> El { col() }
        let m = memory()
        let rt = Runtime<UInt8>(0, view, (100.0, 100.0), Env.new(true, 1.0))
        rt.useClipboard(m)
        _ = rt.frame(0.0)

        let held1 = copySecret(m, "secret", longDelay)
        rt.hostUpdate { _, tx in tx.clearSecretClipboard() }
        #expect(held1.state() == .cleared && m.text() == nil)

        rt.poll = { _, _, tx in tx.clearSecretClipboard(); return false }
        let held2 = copySecret(m, "secret", longDelay)
        rt.hostPollHidden()
        #expect(held2.state() == .cleared && m.text() == nil)
    }

    @Test
    func aClearAfterAnUnwrittenCopyDropsTheStaleSecret() {
        func view(_: SecretCopy?, _: Cx<SecretCopy?>) -> El { col() }
        let rt = Runtime<SecretCopy?>(nil, view, (100.0, 100.0), Env.new(true, 1.0))
        rt.hostUpdate { s, tx in s = tx.copySecret("stale", longDelay) }
        rt.hostUpdate { _, tx in tx.clearSecretClipboard() }
        let att = hostAttachment(for: rt)
        #expect(att.copyRequest == nil && att.clearSecretRequest)
        #expect(rt.state?.state() == .replaced)

        let m = memory()
        rt.useClipboard(m)
        rt.hostUpdate { s, tx in
            s = tx.copySecret("stale", longDelay)
            tx.clearSecretClipboard()
        }
        _ = rt.frame(0.0)
        #expect(m.text() == nil)
        #expect(rt.state?.state() == .replaced)
    }

    @Test
    func aStagedPendingCopyStaysPendingAndClearNowIsANoOp() {
        var copy: SecretCopy? = SecretCopy.pending()
        let clone = copy!
        copy = nil
        #expect(clone.state() == .pending)
        clone.clearNow()
        #expect(clone.state() == .pending)
        #expect(!clone.holds())
    }
}
