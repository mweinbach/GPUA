// Ported from: crates/rune/src/runtime/motion/live_latch.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Live wake latching and visibility gating so offscreen/occluded windows sleep cleanly.

struct LiveNodeEntry {
    var nodeIdx: Int
    var path: String
    var subscriptions: [LiveSubscription]
    var liveTextSeenGen: UInt64?
    var pixelsSeenSize: (UInt32, UInt32)? = nil
}

extension LiveWake {
    func takePending() -> Bool {
        let wasPending = pending
        if wasPending {
            pending = false
        }
        return wasPending
    }
}

extension Runtime {
    public func setLiveWaker(_ waker: @escaping Waker) {
        for entry in liveNodeBindings.values {
            for sub in entry.subscriptions {
                sub.active = false
            }
        }
        liveNodeBindings.removeAll()
        liveWake = LiveWake(waker)
        liveWake.setVisible(windowVisible)
        for idx in nodes.indices where scene.contains(nodes[idx].nodeId) {
            attachNodeLiveBindings(nodeIdx: idx)
        }
    }

    public func setLiveVisible(_ visible: Bool) {
        liveWake.setVisible(visible)
        windowVisible = visible
    }

    public func setWindowVisible(_ visible: Bool) {
        setLiveVisible(visible)
    }

    func liveVisible() -> Bool {
        windowVisible
    }

    public func livePending() -> Bool {
        windowVisible && (liveDirty || liveWake.pending)
    }

    public func hasPendingLiveWake() -> Bool {
        livePending()
    }
}
