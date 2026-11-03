// Tests ported from: crates/rune/src/drop_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

// PORT NOTE: Full `Runtime` hit-test routing for external file drags (`rt.drag_files`, `rt.drop_files`,
// `rt.drag_files_to`, `rt.drag_files_leave`) depends on `runtime/input/drop.swift` owned outside this
// module cluster. All `DropSpec` splitting, extension matching (`acceptsExtensions`), reject-claiming,
// hover selection, `pathExtension` semantics, `El` drop handler dispatch, and `Tx.dropPoint()` are
// tested thoroughly below.

private struct DropRecord {
    var dropped: [[String]] = []
    var rejected: [[String]] = []
    var hover: [(String, Bool)] = []
    var moves: [(Float, Float)] = []
    var dropPoints: [PointerEvent?] = []
}

@Suite("DropTests")
struct DropTests {
    @Test("DropSpec splits accepted and rejected files and respects extension filters")
    func dropSpecSplitsAcceptedAndRejectedFiles() {
        let plain = el()
        #expect(plain.handlers.getIfSome?.drop == nil)

        let inner = el()
            .onDropFiles { (s: inout DropRecord, files: [String], tx: inout Tx) in
                s.dropped.append(files)
                s.dropPoints.append(tx.dropPoint())
            }
            .acceptsExtensions(["png", ".JPG"])
            .onDropHover { (s: inout DropRecord, over: Bool, _: inout Tx) in
                s.hover.append(("inner", over))
            }

        let spec = inner.handlers.getIfSome!.drop!
        #expect(!spec.claimsRejects())

        let (accepted, rejected) = spec.split(["a.png", "b.JPG", "c.txt", ".png", "dir/photo.jpg"])
        #expect(accepted == ["a.png", "b.JPG", "dir/photo.jpg"])
        #expect(rejected == ["c.txt", ".png"])

        let states = States.one(DropRecord())
        var tx = Tx()
        tx.dropPointEvent = PointerEvent(x: 30.0, y: 20.0, windowX: 30.0, windowY: 40.0)
        spec.hoverFn(true)?(states, true, &tx)
        spec.onDrop?(states, accepted, &tx)
        tx.dropPointEvent = nil
        spec.hoverFn(true)?(states, false, &tx)

        let out = states.app as! DropRecord
        #expect(out.dropped == [["a.png", "b.JPG", "dir/photo.jpg"]])
        #expect(out.hover.count == 2)
        #expect(out.hover[0].0 == "inner" && out.hover[0].1 == true)
        #expect(out.hover[1].0 == "inner" && out.hover[1].1 == false)
        #expect(out.dropPoints == [PointerEvent(x: 30.0, y: 20.0, windowX: 30.0, windowY: 40.0)])
    }

    @Test("a target that hears rejected drops claims them and dispatches rejected hover and move")
    func targetHearingRejectedDropsClaimsThemAndDispatchesCallbacks() {
        let exports = el()
            .key("exports")
            .onDropFiles { (s: inout DropRecord, files: [String], _: inout Tx) in
                s.dropped.append(files)
            }
            .acceptsExtensions(["json"])
            .onDropHover { (s: inout DropRecord, over: Bool, _: inout Tx) in
                s.hover.append(("exports", over))
            }
            .onDropRejected { (s: inout DropRecord, files: [String], _: inout Tx) in
                s.rejected.append(files)
            }
            .onDropRejectedHover { (s: inout DropRecord, over: Bool, _: inout Tx) in
                s.hover.append(("exports-rejected", over))
            }
            .onDropMove { (s: inout DropRecord, p: PointerEvent, tx: inout Tx) in
                #expect(tx.dropPoint() == p)
                s.moves.append((p.x, p.y))
            }

        let spec = exports.handlers.getIfSome!.drop!
        #expect(spec.claimsRejects())

        let (acc1, rej1) = spec.split(["notes.txt"])
        #expect(acc1.isEmpty && rej1 == ["notes.txt"])

        let (acc2, rej2) = spec.split(["a.json", "b.txt"])
        #expect(acc2 == ["a.json"] && rej2 == ["b.txt"])

        let states = States.one(DropRecord())
        var tx = Tx()
        spec.hoverFn(false)?(states, true, &tx)
        spec.onReject?(states, rej1, &tx)
        spec.hoverFn(false)?(states, false, &tx)

        let p = PointerEvent(x: 60.0, y: 50.0, windowX: 60.0, windowY: 70.0)
        tx.dropPointEvent = p
        spec.onMove?(states, p, &tx)

        let out = states.app as! DropRecord
        #expect(out.rejected == [["notes.txt"]])
        #expect(out.hover.map(\.0) == ["exports-rejected", "exports-rejected"])
        #expect(out.hover.map(\.1) == [true, false])
        #expect(out.moves.count == 1 && out.moves[0].0 == 60.0 && out.moves[0].1 == 50.0)
    }

    @Test("pathExtension matches Rust std::path::Path::extension semantics")
    func pathExtensionMatchesRustSemantics() {
        #expect(pathExtension("archive.tar.gz") == "gz")
        #expect(pathExtension(".gitignore") == nil)
        #expect(pathExtension(".config.json") == "json")
        #expect(pathExtension("dir.with.dots/plain") == nil)
        #expect(pathExtension("C:\\folder\\image.PNG") == "PNG")
        #expect(pathExtension("trailing.") == nil)
    }
}
