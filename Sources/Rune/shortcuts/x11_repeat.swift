// Ported from: crates/rune/src/shortcuts/x11_repeat.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! X11 autorepeat filter for grabbed shortcuts. Without detectable autorepeat the server sends
//! each repeat as a KeyRelease and a KeyPress with the same timestamp; with it, as KeyPresses
//! with no release between. Either way only the first press of a hold fires, as on macOS and
//! Windows. A release is held back until the next event shows whether a repeat follows it.

struct X11ShortcutRepeats: Sendable {
    private var down: [UInt8] = []
    private var pendingRelease: (UInt8, UInt32)? = nil

    init() {}

    /// Whether this press starts a hold (fire) rather than repeating one.
    mutating func press(_ code: UInt8, _ time: UInt32) -> Bool {
        if let rel = pendingRelease {
            pendingRelease = nil
            if rel.0 == code && rel.1 == time {
                return false
            }
            forget(rel.0)
        }
        if down.contains(code) {
            return false
        }
        down.append(code)
        return true
    }

    mutating func release(_ code: UInt8, _ time: UInt32) {
        if let prev = pendingRelease {
            forget(prev.0)
        }
        pendingRelease = (code, time)
    }

    /// The first key down started the active grab, which ends with its release; keys pressed
    /// during the grab send their releases elsewhere, so they are forgotten with it.
    private mutating func forget(_ released: UInt8) {
        if down.first == released {
            down.removeAll()
        } else {
            down.removeAll { $0 == released }
        }
    }
}
