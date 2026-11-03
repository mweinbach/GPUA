// Ported from: crates/rune/src/clipboard/native.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

#if !os(WASI)
#if os(macOS)
import AppKit
#endif
import Foundation

extension ClipboardClient {
    func readFor(_ purpose: ClipboardPurpose) {
        let replyBox = self.replyBox
        let wakeFn = self.wake
        nativeClipboardWorker().send(
            .read(
                purpose: purpose,
                reply: { replyBox.push($0) },
                wake: wakeFn
            )
        )
    }

    func flush<S>(_ rt: Runtime<S>) {
        let att = hostAttachment(for: rt)
        if att.clipboard != nil {
            flushMemoryClipboard(rt)
            return
        }
        if att.clearSecretRequest {
            att.clearSecretRequest = false
            existingNativeClipboardWorker()?.send(.clear(nil))
        }
        if let copy = att.copyRequest {
            att.copyRequest = nil
            let worker = nativeClipboardWorker()
            copy.bind(.system { req in worker.send(req) })
            worker.send(.write(copy, ClipboardNotify(changed: changed, wake: wake)))
        }
        if let target = att.pasteRequest {
            att.pasteRequest = nil
            readFor(.pasteForRuntime(rt, target))
        }
        let readIds = att.readRequests
        att.readRequests.removeAll()
        for id in readIds {
            readFor(.read(id))
        }
    }
}

private enum WorkerRecvOutcome {
    case item(ClipboardRequest)
    case timeout
    case disconnected
}

// PORT NOTE: Synchronized via `NSCondition`, providing bounded `recv(until:)` matching `mpsc::Receiver::recv_timeout` in `crates/rune/src/clipboard/native.rs`.
final class ClipboardRequestChannel: @unchecked Sendable {
    private let cond = NSCondition()
    private var queue: [ClipboardRequest] = []
    private var closed: Bool = false

    init() {}

    @discardableResult
    func send(_ req: ClipboardRequest) -> Bool {
        cond.lock()
        defer { cond.unlock() }
        guard !closed else { return false }
        queue.append(req)
        cond.signal()
        return true
    }

    func close() {
        cond.lock()
        closed = true
        cond.broadcast()
        cond.unlock()
    }

    fileprivate func recv(until deadline: RuneInstant?) -> WorkerRecvOutcome {
        cond.lock()
        defer { cond.unlock() }
        while queue.isEmpty && !closed {
            if let deadline {
                let now = RuneInstant.now()
                if now >= deadline {
                    return .timeout
                }
                let rem = deadline.durationSince(now)
                let secs = Double(rem.components.seconds) + Double(rem.components.attoseconds) * 1e-18
                _ = cond.wait(until: Date(timeIntervalSinceNow: max(0.0, secs)))
                if queue.isEmpty && !closed && RuneInstant.now() >= deadline {
                    return .timeout
                }
            } else {
                cond.wait()
            }
        }
        if !queue.isEmpty {
            return .item(queue.removeFirst())
        }
        return .disconnected
    }
}

// PORT NOTE: Synchronized via `NSCondition` for bounded completion handshake during worker shutdown.
final class ClipboardCompletionSignal: @unchecked Sendable {
    private let cond = NSCondition()
    private var done: Bool = false

    func signal() {
        cond.lock()
        done = true
        cond.broadcast()
        cond.unlock()
    }

    func wait(timeoutSeconds: Double) -> Bool {
        cond.lock()
        defer { cond.unlock() }
        let deadline = Date(timeIntervalSinceNow: timeoutSeconds)
        while !done {
            if !cond.wait(until: deadline) {
                break
            }
        }
        return done
    }
}

// PORT NOTE: Synchronized via `stopLock` (`LiveLock`) and `ClipboardRequestChannel`, mirroring `Worker` in `crates/rune/src/clipboard/native.rs`.
final class ClipboardWorker: @unchecked Sendable {
    let channel = ClipboardRequestChannel()
    private let stopLock = LiveLock()
    private var completion: ClipboardCompletionSignal?

    private init(completion: ClipboardCompletionSignal) {
        self.completion = completion
    }

    static func spawn<B: ClipboardBackend & Sendable>(_ open: @escaping @Sendable () -> B?) -> ClipboardWorker {
        let done = ClipboardCompletionSignal()
        let worker = ClipboardWorker(completion: done)
        let chan = worker.channel
        let thread = Thread {
            runClipboardWorker(chan, open)
            done.signal()
        }
        thread.name = "rune-clipboard"
        thread.start()
        return worker
    }

    @discardableResult
    func send(_ request: ClipboardRequest) -> Bool {
        channel.send(request)
    }

    func stop() {
        let comp: ClipboardCompletionSignal? = stopLock.withLock {
            let c = completion
            completion = nil
            return c
        }
        guard let comp else { return }
        _ = channel.send(.shutdown)
        _ = comp.wait(timeoutSeconds: 0.25)
    }
}

private func runClipboardWorker<B: ClipboardBackend>(
    _ chan: ClipboardRequestChannel,
    _ open: () -> B?
) {
    var clipboard: B? = nil
    var core = ClipboardCore()
    while true {
        let outcome = chan.recv(until: core.nextCheck())
        if var cb = clipboard {
            core.tick(&cb)
            clipboard = cb
        }
        let request: ClipboardRequest
        switch outcome {
        case .disconnected:
            if var cb = clipboard {
                core.clear(&cb, nil)
                clipboard = cb
            }
            clipboard = nil
            return
        case .timeout:
            continue
        case .item(let req):
            if case .shutdown = req {
                if var cb = clipboard {
                    core.clear(&cb, nil)
                    clipboard = cb
                }
                clipboard = nil
                return
            }
            request = req
        }

        if case .clear = request, !core.hasHeldSecret {
            continue
        }
        if clipboard == nil {
            clipboard = open()
        }
        guard var cb = clipboard else {
            if case .write(let copy, let notify) = request, let slot = copy.slot() {
                slot.setState(.failed("no clipboard"))
                notify?.send()
            }
            continue
        }
        core.handle(&cb, request)
        clipboard = cb
    }
}

#if os(macOS)
private struct MacSystemClipboardBackend: ClipboardBackend {
    mutating func write(_ copy: ClipboardWrite) -> Result<Void, ClipboardWriteError> {
        let pb = NSPasteboard.general
        let content = copy.content()
        if !copy.isSecret() && content.isRich() {
            return writeMacPasteboard(pb, content)
        }
        return autoreleasepool {
            let item = NSPasteboardItem()
            if copy.isSecret() {
                _ = item.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
                _ = item.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
            }
            guard item.setString(content.text(), forType: .string) else {
                return .failure(ClipboardWriteError("the pasteboard refused the text"))
            }
            pb.clearContents()
            guard pb.writeObjects([item]) else {
                return .failure(ClipboardWriteError("the pasteboard refused the content"))
            }
            return .success(())
        }
    }

    mutating func text() -> String? {
        autoreleasepool {
            NSPasteboard.general.string(forType: .string)
        }
    }

    mutating func content(_ all: Bool) -> ClipboardContent? {
        readMacPasteboard(NSPasteboard.general, all)
    }

    func revision() -> UInt64? {
        UInt64(bitPattern: Int64(NSPasteboard.general.changeCount))
    }

    mutating func clear() {
        _ = NSPasteboard.general.clearContents()
    }
}
#endif

private let globalWorkerLock = LiveLock()
// PORT NOTE: Access to `globalClipboardWorkerInstance` is serialized via `globalWorkerLock`.
nonisolated(unsafe) private var globalClipboardWorkerInstance: ClipboardWorker? = nil

private func existingNativeClipboardWorker() -> ClipboardWorker? {
    globalWorkerLock.withLock { globalClipboardWorkerInstance }
}

private func nativeClipboardWorker() -> ClipboardWorker {
    globalWorkerLock.withLock {
        if let existing = globalClipboardWorkerInstance {
            return existing
        }
        #if os(macOS)
        let created = ClipboardWorker.spawn { MacSystemClipboardBackend() }
        #else
        let created = ClipboardWorker.spawn { nil as MemoryClipboardBoard? }
        #endif
        globalClipboardWorkerInstance = created
        return created
    }
}

func shutdownNativeClipboard() {
    existingNativeClipboardWorker()?.stop()
}
#endif
