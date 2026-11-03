// Ported from: crates/rune/src/edit/history.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Undo and redo for a `TextEdit`: document snapshots, coalesced typing runs, undo groups
//! and a history bounded in steps and bytes.

let HISTORY_STEPS: Int = 128
let HISTORY_BYTES: Int = 1024 * 1024

struct Snapshot: Equatable {
    var text: String
    var anchor: Int
    var focus: Int
    var marks: [MarkRange]
    var blocks: [Block]
    var softBreaks: [UInt32]

    static func == (lhs: Snapshot, rhs: Snapshot) -> Bool {
        lhs.anchor == rhs.anchor
            && lhs.focus == rhs.focus
            && lhs.text.utf8.elementsEqual(rhs.text.utf8)
            && lhs.marks == rhs.marks
            && lhs.blocks == rhs.blocks
            && lhs.softBreaks == rhs.softBreaks
    }

    func sameDoc(_ other: Snapshot) -> Bool {
        text.utf8.elementsEqual(other.text.utf8)
            && marks == other.marks
            && blocks == other.blocks
            && softBreaks == other.softBreaks
    }
}

enum GroupBaseline {
    case secure
    case snapshot(Snapshot)
}

/// Active `TextEdit.undoGroup` baseline (`secure` on a secure field).
/// Ignored by `Equatable` and deactivated on scope exit so cloning or comparing a `TextEdit`
/// mid-group never leaks active-group state.
final class ActiveGroupBox {
    var isActive: Bool = true
    var baseline: GroupBaseline

    init(baseline: GroupBaseline) {
        self.baseline = baseline
    }
}

struct Change: Equatable {
    var before: Snapshot
    var after: Snapshot

    func bytes() -> Int {
        before.text.utf8.count
            + after.text.utf8.count
            + (before.marks.count + after.marks.count) * MemoryLayout<MarkRange>.stride
            + (before.blocks.count + after.blocks.count) * MemoryLayout<Block>.stride
            + (before.softBreaks.count + after.softBreaks.count) * MemoryLayout<UInt32>.stride
    }
}

// PORT NOTE: Reference-counted copy-on-write box (`isKnownUniquelyReferenced`) mirroring
// `Arc<History>` / `Arc::make_mut` so rendering clones of `TextEdit` share undo history without copying.
final class History: Equatable {
    var undo: [Change] = []
    var redo: [Change] = []
    var bytes: Int = 0
    var typing: Bool = false

    init() {}

    init(undo: [Change], redo: [Change], bytes: Int, typing: Bool) {
        self.undo = undo
        self.redo = redo
        self.bytes = bytes
        self.typing = typing
    }

    func copy() -> History {
        History(undo: undo, redo: redo, bytes: bytes, typing: typing)
    }

    static func == (lhs: History, rhs: History) -> Bool {
        if lhs === rhs { return true }
        return lhs.undo == rhs.undo
            && lhs.redo == rhs.redo
            && lhs.bytes == rhs.bytes
            && lhs.typing == rhs.typing
    }
}

struct WeakHistory {
    weak var ref: History?

    init(_ ref: History) {
        self.ref = ref
    }
}

extension TextEdit {
    @discardableResult
    mutating func makeHistoryMut() -> History {
        if !isKnownUniquelyReferenced(&historyStorage) {
            historyStorage = historyStorage.copy()
        }
        return historyStorage
    }

    /// Drop the undo and redo stacks, keeping text, marks, blocks, soft breaks and the selection.
    public mutating func clearHistory() {
        historyStorage = History()
        if let box = groupBox, box.isActive {
            syncInvariants()
            box.baseline = secureFlag ? .secure : .snapshot(snapshotNow())
        }
    }

    /// End a typing group on a pointer selection or focus change.
    public mutating func breakHistoryGroup() {
        if historyStorage.typing {
            makeHistoryMut().typing = false
        }
    }

    func snapshotNow() -> Snapshot {
        Snapshot(
            text: text,
            anchor: anchor,
            focus: focus,
            marks: marksStorage,
            blocks: blocksStorage,
            softBreaks: softBreaksStorage
        )
    }

    func snapshot() -> Snapshot? {
        if secureFlag || (groupBox?.isActive == true) {
            return nil
        }
        return snapshotNow()
    }

    mutating func restore(_ s: Snapshot) {
        text = s.text
        anchor = s.anchor
        focus = s.focus
        marksStorage = s.marks
        blocksStorage = s.blocks
        softBreaksStorage = s.softBreaks
        pendingStyle = nil
        clearPreedit()
        syncInvariants()
    }

    mutating func recordChange(_ before: Snapshot?, typing: Bool) {
        guard let before, !secureFlag, !(groupBox?.isActive == true) else {
            return
        }
        let after = snapshotNow()
        if before.sameDoc(after) {
            return
        }
        let h = makeHistoryMut()
        let expected: Snapshot? = h.redo.last?.before ?? h.undo.last?.after
        if let last = expected, last.text != before.text {
            h.undo.removeAll()
            h.redo.removeAll()
            h.bytes = 0
            h.typing = false
        }
        let redoBytes = h.redo.reduce(0) { $0 + $1.bytes() }
        h.bytes = max(0, h.bytes - redoBytes)
        h.redo.removeAll()

        if typing
            && h.typing
            && before.anchor == before.focus
            && h.undo.last?.after == before
        {
            let lastIdx = h.undo.count - 1
            h.bytes -= h.undo[lastIdx].bytes()
            h.undo[lastIdx].after = after
            h.bytes += h.undo[lastIdx].bytes()
        } else {
            let change = Change(before: before, after: after)
            h.bytes += change.bytes()
            h.undo.append(change)
        }
        h.typing = typing
        while !h.undo.isEmpty && (h.undo.count > HISTORY_STEPS || h.bytes > HISTORY_BYTES) {
            let evicted = h.undo.removeFirst()
            h.bytes = max(0, h.bytes - evicted.bytes())
        }
    }

    /// Run `f`, whose edits become one undo step: one undo reverts all of them and one redo
    /// restores them, with the selection from before the first and after the last. Groups
    /// nest and flatten into the outermost.
    @discardableResult
    public mutating func undoGroup<R>(_ f: (inout TextEdit) throws -> R) rethrows -> R {
        if groupBox?.isActive == true {
            return try f(&self)
        }
        syncInvariants()
        breakHistoryGroup()
        let box = ActiveGroupBox(baseline: secureFlag ? .secure : .snapshot(snapshotNow()))
        groupBox = box
        defer {
            box.isActive = false
            groupBox = nil
        }
        let r = try f(&self)
        let before: Snapshot?
        if case .snapshot(let s) = box.baseline {
            before = s
        } else {
            before = nil
        }
        box.isActive = false
        groupBox = nil
        syncInvariants()
        breakHistoryGroup()
        recordChange(before, typing: false)
        return r
    }

    /// Undo one typing group or discrete edit. Active IME composition is cancelled first.
    public mutating func undo() {
        if secureFlag || groupBox?.isActive == true { return }
        breakHistoryGroup()
        if preedit != nil {
            clearPreedit()
            return
        }
        let h = makeHistoryMut()
        guard let change = h.undo.popLast() else { return }
        // Public model text may have been replaced by the app. Never restore stale history.
        if text != change.after.text {
            h.undo.removeAll()
            h.redo.removeAll()
            h.bytes = 0
            h.typing = false
            return
        }
        restore(change.before)
        makeHistoryMut().redo.append(change)
    }

    public mutating func redo() {
        if secureFlag || groupBox?.isActive == true { return }
        breakHistoryGroup()
        if preedit != nil {
            clearPreedit()
            return
        }
        let h = makeHistoryMut()
        guard let change = h.redo.popLast() else { return }
        if text != change.before.text {
            h.undo.removeAll()
            h.redo.removeAll()
            h.bytes = 0
            h.typing = false
            return
        }
        restore(change.after)
        makeHistoryMut().undo.append(change)
    }
}
