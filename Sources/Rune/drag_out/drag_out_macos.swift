// Ported from: crates/rune/src/drag_out/macos.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

#if os(macOS)
import AppKit
import Foundation

func dragMacOutcome(_ operation: NSDragOperation) -> DragOutcome {
    if operation.contains(.copy) {
        return .copied
    } else if !operation.intersection([.move, .delete, .generic]).isEmpty {
        return .moved
    } else if operation.contains(.link) {
        return .linked
    } else {
        return .cancelled
    }
}

/// The operations the source offers: what the item allows, ignoring modifier keys.
func dragMacMask(_ item: DragItem) -> NSDragOperation {
    var m: NSDragOperation = []
    if item.offers(.copy) { m.insert(.copy) }
    if item.offers(.move) { m.insert(.move) }
    if item.offers(.link) { m.insert(.link) }
    return m
}

/// The app's own windows are offered nothing: Rune windows take no drops.
func dragMacMaskIn(_ mask: NSDragOperation, _ context: NSDraggingContext) -> NSDragOperation {
    context == .withinApplication ? [] : mask
}

/// Modifier keys pick among several offered operations; with one on offer they'd turn the drop into a refusal.
func dragMacSingle(_ mask: NSDragOperation) -> Bool {
    mask.rawValue.nonzeroBitCount <= 1
}

func dragMacReport(_ done: ((DragOutcome) -> Void)?, _ outcome: DragOutcome) {
    done?(outcome)
}

private func unmuteWindows(_ windows: [(NSWindow, [NSPasteboard.PasteboardType])]) {
    guard !windows.isEmpty, Thread.isMainThread else { return }
    MainActor.assumeIsolated {
        for (w, types) in windows {
            w.registerForDraggedTypes(types)
        }
    }
}

/// Lifecycle state for a single macOS drag-out session; reports `.cancelled` on `deinit` if never ended.
final class DragMacSessionIvars {
    var done: ((DragOutcome) -> Void)?
    let mask: NSDragOperation
    var muted: [(NSWindow, [NSPasteboard.PasteboardType])]

    init(
        done: @escaping (DragOutcome) -> Void,
        mask: NSDragOperation,
        muted: [(NSWindow, [NSPasteboard.PasteboardType])] = []
    ) {
        self.done = done
        self.mask = mask
        self.muted = muted
    }

    func finish(_ operation: NSDragOperation) {
        let windows = muted
        muted.removeAll()
        unmuteWindows(windows)
        if let cb = done {
            done = nil
            dragMacReport(cb, dragMacOutcome(operation))
        }
    }

    deinit {
        let windows = muted
        unmuteWindows(windows)
        if let cb = done {
            done = nil
            dragMacReport(cb, .cancelled)
        }
    }
}

final class RuneDragOutSource: NSObject, NSDraggingSource {
    let ivars: DragMacSessionIvars

    init(ivars: DragMacSessionIvars) {
        self.ivars = ivars
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        dragMacMaskIn(ivars.mask, context)
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        ivars.finish(operation)
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
        dragMacSingle(ivars.mask)
    }
}

// PORT NOTE: Accessed only on the AppKit main thread (`Thread.isMainThread`), matching upstream `thread_local! { LIVE }`.
nonisolated(unsafe) private var liveDragSource: RuneDragOutSource?

func dragMacPasteboardItems(_ start: DragOutStart) -> [NSPasteboardItem] {
    let item = start.item
    var out: [NSPasteboardItem] = []
    for path in item.paths() {
        let url = URL(fileURLWithPath: path)
        let p = NSPasteboardItem()
        p.setString(url.absoluteString, forType: .fileURL)
        p.setString(url.absoluteString, forType: .URL)
        if item.plainText() == nil {
            p.setString(path, forType: .string)
        }
        out.append(p)
    }
    if item.pngData() != nil || item.plainText() != nil {
        let first: NSPasteboardItem
        if let existing = out.first {
            first = existing
        } else {
            let created = NSPasteboardItem()
            out.append(created)
            first = created
        }
        if let png = item.pngData() {
            first.setData(Data(png), forType: .png)
        }
        if let text = item.plainText() {
            first.setString(text, forType: .string)
        }
    }
    return out
}

@MainActor
func beginMacDragOut(
    view: NSView,
    start: DragOutStart,
    snapshot: DragImage?,
    done: @escaping (DragOutcome) -> Void
) {
    liveDragSource = nil
    guard Thread.isMainThread else {
        done(.cancelled)
        return
    }
    let picture = dragPicture(start.item, snapshot)
    let event: NSEvent? = {
        if let cur = NSApp.currentEvent,
           cur.type == .leftMouseDragged || cur.type == .leftMouseDown
        {
            return cur
        }
        guard (NSEvent.pressedMouseButtons & 1) != 0, let win = view.window else { return nil }
        let at = win.mouseLocationOutsideOfEventStream
        let ts = NSApp.currentEvent?.timestamp ?? 0.0
        return NSEvent.mouseEvent(
            with: .leftMouseDragged,
            location: at,
            modifierFlags: [],
            timestamp: ts,
            windowNumber: win.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1.0
        )
    }()
    guard let dragEvent = event else {
        done(.cancelled)
        return
    }

    let items = dragMacPasteboardItems(start)
    guard !items.isEmpty else {
        done(.cancelled)
        return
    }

    let rect = start.rect
    let (nsImage, nsFrame): (NSImage?, NSRect) = {
        if let p = picture, let img = NSImage(data: Data(p.pngData())) {
            let nat = img.size
            let f = p.frame(start.bounds, start.press, (Float(nat.width), Float(nat.height)))
            img.size = NSSize(width: CGFloat(f[2]), height: CGFloat(f[3]))
            return (img, NSRect(x: CGFloat(f[0]), y: CGFloat(f[1]), width: CGFloat(f[2]), height: CGFloat(f[3])))
        }
        if let firstPath = start.item.paths().first {
            let icon = NSWorkspace.shared.icon(forFile: firstPath)
            icon.size = NSSize(width: 64, height: 64)
            return (
                icon,
                NSRect(x: CGFloat(start.press.0) - 32.0, y: CGFloat(start.press.1) - 32.0, width: 64, height: 64)
            )
        }
        return (
            nil,
            NSRect(
                x: CGFloat(rect[0]),
                y: CGFloat(rect[1]),
                width: CGFloat(max(rect[2], 1.0)),
                height: CGFloat(max(rect[3], 1.0))
            )
        )
    }()

    let draggingItems: [NSDraggingItem] = items.enumerated().map { idx, pbItem in
        let d = NSDraggingItem(pasteboardWriter: pbItem)
        let offset = CGFloat(min(idx, 4)) * 3.0
        let f = NSRect(
            x: nsFrame.origin.x + offset,
            y: nsFrame.origin.y + offset,
            width: nsFrame.size.width,
            height: nsFrame.size.height
        )
        d.setDraggingFrame(f, contents: nsImage)
        return d
    }

    let registeredSel = Selector(("registeredDraggedTypes"))
    let draggingEnteredSel = NSSelectorFromString("draggingEntered:")
    var muted: [(NSWindow, [NSPasteboard.PasteboardType])] = []
    for w in NSApp.windows {
        guard let delegate = w.delegate, delegate.responds(to: draggingEnteredSel) else {
            continue
        }
        let types: [NSPasteboard.PasteboardType]
        if w.responds(to: registeredSel),
           let raw = w.perform(registeredSel)?.takeUnretainedValue() as? [String]
        {
            types = raw.map { NSPasteboard.PasteboardType($0) }
        } else {
            types = [.fileURL]
        }
        if !types.isEmpty {
            w.unregisterDraggedTypes()
            muted.append((w, types))
        }
    }

    let source = RuneDragOutSource(ivars: DragMacSessionIvars(done: done, mask: dragMacMask(start.item), muted: muted))
    liveDragSource = source
    let session = view.beginDraggingSession(with: draggingItems, event: dragEvent, source: source)
    session.animatesToStartingPositionsOnCancelOrFail = true
    session.draggingFormation = .none
}
#endif
