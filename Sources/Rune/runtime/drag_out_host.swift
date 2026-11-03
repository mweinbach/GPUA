// Ported from: crates/rune/src/runtime/drag_out_host.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Outbound OS drag-and-drop initiation and completion dispatch.

public struct PendingDragOut: Sendable, Equatable {
    public var path: String
    public var item: DragItem
    public var origin: (Float, Float)

    public init(path: String, item: DragItem, origin: (Float, Float)) {
        self.path = path
        self.item = item
        self.origin = origin
    }

    public static func == (lhs: PendingDragOut, rhs: PendingDragOut) -> Bool {
        lhs.path == rhs.path && lhs.item == rhs.item
            && lhs.origin.0 == rhs.origin.0 && lhs.origin.1 == rhs.origin.1
    }
}

extension Runtime {
    public func takePendingDragOut() -> PendingDragOut? {
        let out = pendingDragOut
        pendingDragOut = nil
        return out
    }

    public func finishDragOut(_ outcome: DragOutcome) {
        if let handler = activeDragOutCompletion {
            activeDragOutCompletion = nil
            var tx = newTx()
            let states = makeStates()
            handler(states, outcome, &tx)
            commitStates(states)
            applyTx(&tx, why: CommitWhy.DRAG)
        }
    }
}
