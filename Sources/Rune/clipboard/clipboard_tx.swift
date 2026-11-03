// Ported from: crates/rune/src/clipboard/tx.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! `Tx`'s clipboard requests, carried out by the shell's clipboard worker after the handler.

#if !os(WASI)
import Foundation
#endif

// PORT NOTE: Synchronized via `LiveLock`; `Tx` copies share the callback box and take it at most once, matching `ClipboardRead(Rc<Cell<Option<ReadFn>>>)` in `crates/rune/src/clipboard/tx.rs`.
final class ClipboardReadBox: @unchecked Sendable, CustomDebugStringConvertible {
    private let lock = LiveLock()
    private var fn: ((States, ClipboardContent, inout Tx) -> Void)?

    init(_ fn: @escaping (States, ClipboardContent, inout Tx) -> Void) {
        self.fn = fn
    }

    func take() -> ((States, ClipboardContent, inout Tx) -> Void)? {
        lock.withLock {
            let out = fn
            fn = nil
            return out
        }
    }

    var debugDescription: String { "ClipboardRead" }
}

extension Tx {
    /// Copy several forms at once: plain text for every app, HTML and RTF for apps that paste
    /// formatting, an image, and files for a file manager.
    public mutating func copyRich(_ content: ClipboardContent) {
        copyWrite = ClipboardWrite.new(content)
    }

    /// Exclude this text from clipboard histories and clear it after `clearAfter` if unchanged.
    /// The handle reports whether the copy still holds the clipboard, and can clear it early.
    public mutating func copySecret(_ text: String, _ clearAfter: Duration) -> SecretCopy {
        let (write, copy) = ClipboardWrite.secret(text, clearAfter)
        copyWrite = write
        return copy
    }

    /// Convenience overload taking seconds as `Double`.
    public mutating func copySecret(_ text: String, _ clearAfterSeconds: Double) -> SecretCopy {
        let nanos = max(0.0, clearAfterSeconds) * 1_000_000_000.0
        return copySecret(text, .nanoseconds(Int64(nanos.rounded())))
    }

    /// Clear the secret Rune copied last, from any window, if the clipboard still holds it.
    /// A secret copy asked for earlier in this handler is dropped.
    public mutating func clearSecretClipboard() {
        if copyWrite?.isSecret() == true {
            copyWrite = nil
        }
        clearSecretFlag = true
    }

    /// Read the OS clipboard asynchronously and paste into the focused field or root `onPaste`.
    public mutating func requestPaste() {
        pasteFlag = true
    }

    /// Read the clipboard off the event thread and hand what it holds to `f`, as an update,
    /// once it arrives: an empty `ClipboardContent` when it holds nothing readable.
    public mutating func readClipboard<S>(_ f: @escaping (inout S, ClipboardContent, inout Tx) -> Void) {
        let box = ClipboardReadBox { states, content, tx in
            _ = states.withMutable { (target: inout S) in
                f(&target, content, &tx)
            }
        }
        appendSidecar(box)
    }
}
