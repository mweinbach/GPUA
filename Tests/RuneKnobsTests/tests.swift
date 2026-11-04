// Tests ported from: crates/rune-knobs/src/tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Rune
import Testing
@testable import RuneKnobs

private let testA = Knob.new("A", 0.0, 10.0, 5.0)
private let testB = Knob.new("B", -1.0, 1.0, 0.0).step(0.5)
private let testC = Knob.choice("C", ["x", "y", "z"], 0)
private let testG = Group.new("G", "g", [testA, testB, testC])
    .presets([Preset(name: "Wide", values: [("A", 9.0)])])

// PORT NOTE: Runs RuneKnobs test suites serially on `@MainActor` (8 MB main stack) because Swift Testing's 512 KB cooperative worker threads overflow in `-Onone` when `Rune.Runtime.flattenElement` traverses 12-level `side()` `El` value trees, and `Rune.measure` uses unsynchronized global caches.
@Suite("RuneKnobs", .serialized)
@MainActor
enum RuneKnobsSerializedSuites {}

extension RuneKnobsSerializedSuites {
@Suite("RuneKnobs core tests", .serialized)
@MainActor
struct RuneKnobsCoreTests {
    @Test("random_stays_in_range_and_on_steps")
    func randomStaysInRangeAndOnSteps() {
        var k = Knobs()
        for _ in 0..<200 {
            k.random(testG)
            for d in testG.knobs {
                let v = k.values[d.name]!
                #expect((d.min...d.max).contains(v), "\(d.name) = \(v)")
            }
            #expect((k.values["B"]! * 2.0).truncatingRemainder(dividingBy: 1.0) == 0.0)
            #expect(k.values["C"]!.truncatingRemainder(dividingBy: 1.0) == 0.0)
        }
        let before = k.values
        k.random(testG)
        k.undo()
        #expect(k.values == before)
    }

    @Test("presets_reset_and_undo")
    func presetsResetAndUndo() {
        var k = Knobs()
        k.apply(testG, "Wide")
        #expect(k.values["A"] == 9.0)
        #expect(k.active(testG) == "Wide")
        k.set(testA, 2.0)
        #expect(k.drifted(testG, "Wide"))
        k.reset(testG)
        #expect(k.get(testA) == 9.0, "reset goes back to the active preset first")
        k.reset(testG)
        #expect(k.values.isEmpty)
        #expect(k.active(testG) == "Default")
        k.undo()
        #expect(k.get(testA) == 9.0)
        k.set(testA, 3.0)
        let name = k.save(testG)
        k.apply(testG, DEFAULT)
        k.apply(testG, name)
        #expect(k.get(testA) == 3.0)
        #expect(k.code(testG) == "A = 3\nB = 0\nC = 0 (x)")
    }

    @Test("change_undoes_and_redoes_and_a_new_change_drops_redo")
    func changeUndoesAndRedoesAndANewChangeDropsRedo() {
        var k = Knobs()
        k.change(testA, 7.0)
        k.change(testA, 7.0)
        k.change(testC, 2.0)
        #expect(k.undo() == true)
        #expect(k.get(testA) == 7.0 && k.get(testC) == 0.0)
        #expect(k.redo() == true)
        #expect(k.get(testC) == 2.0)
        let u1 = k.undo()
        let u2 = k.undo()
        #expect(u1 && u2)
        #expect(k.values.isEmpty, "a repeat of the same value is no change")
        #expect(k.undo() == false)
        #expect(k.redo() == true)
        k.change(testB, 0.5)
        #expect(!k.canRedo())
    }

    @Test("keep_marks_what_differs_and_revert_goes_back_undoably")
    func keepMarksWhatDiffersAndRevertGoesBackUndoably() {
        var k = Knobs()
        k.set(testA, 8.0)
        #expect(k.differs(testA), "nothing kept yet: the defaults are")
        k.keep()
        #expect(!k.differs(testA))
        k.change(testA, 1.0)
        k.change(testC, 1.0)
        #expect(k.differs(testA) && k.differs(testC) && !k.differs(testB))
        k.revert([testA])
        #expect(k.get(testA) == 8.0 && k.get(testC) == 1.0)
        k.revert(testG.knobs)
        #expect(k.get(testC) == 0.0)
        #expect(!k.values.contains { $0.key == "C" }, "kept at its default, so back to no value")
        #expect(k.undo() == true)
        #expect(k.get(testC) == 1.0)
        k.keepSome([testC])
        k.change(testA, 3.0)
        k.revert(testG.knobs)
        #expect(k.get(testA) == 8.0 && k.get(testC) == 1.0)
    }

    @Test("describe_readout_and_key_shortcuts")
    func describeReadoutAndKeyShortcuts() {
        let noteA = Knob.new("NoteA", 0.0, 10.0, 5.0)
        let noteC = Knob.choice("NoteC", ["x", "y", "z"], 0)
        describe([
            Note.new("NoteA", "Alpha note").label("Alpha label"),
            Note.new("NoteC", "Choice note").hints([("x", "First opt"), ("y", "Second opt")]),
        ])
        #expect(noteA.title() == "Alpha label")
        #expect(noteA.describe() == "Alpha note")
        #expect(noteC.hint(0) == "First opt")
        #expect(noteC.hint(1) == "Second opt")
        #expect(noteC.hint(2) == "")

        #expect(readout(testA, 5.0) == "5.0")
        #expect(readout(testB, 0.5) == "0.50")
        #expect(readout(Knob.new("Pct", 0.0, 100.0, 25.0).step(1.0), 25.0) == "25")

        var k = Knobs()
        let toggleEv = KeyEvent(key: .command("k"), mods: Mods(shift: true, cmd: true))
        let tookToggle = RuneKnobs.key(&k, toggleEv)
        #expect(tookToggle)
        #expect(k.open)
        let tookEsc = RuneKnobs.key(&k, KeyEvent(key: .escape))
        #expect(tookEsc)
        #expect(!k.open)

        struct Demo {
            var knobs = Knobs()
        }
        var tx = Tx()
        var demo = Demo()
        let hk = sideKey([testG], \Demo.knobs)
        #expect(hk(&demo, KeyEvent(key: .escape), &tx) == false)
        #expect(hk(&demo, KeyEvent(key: .right), &tx) == true)
        #expect(abs(demo.knobs.get(testA) - 5.1) < 1e-3)

        let light = Style.light()
        let dark = Style.dark()
        #expect(light != dark)
    }
}
}
