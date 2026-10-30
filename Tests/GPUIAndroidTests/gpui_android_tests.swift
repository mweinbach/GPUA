// Swift-only: Behavioral unit tests for Swift-only GPUIAndroid backend per ADR-0012

import Foundation
import GPUI
import Scheduler
import Testing
@testable import GPUIAndroid

// MARK: - Test Helpers

private final class LockedTestBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: T

    init(_ initial: T) {
        self._value = initial
    }

    var value: T {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _value
        }
        set {
            lock.lock()
            _value = newValue
            lock.unlock()
        }
    }

    func mutate(_ body: (inout T) -> Void) {
        lock.lock()
        body(&_value)
        lock.unlock()
    }
}

private final class RecordingInputHandler: PlatformInputHandlerProtocol {
    var receivedTexts: [String] = []

    func dispatchInput(_ text: String, _ window: inout Window, _ cx: inout App) {
        _ = window
        _ = cx
        receivedTexts.append(text)
    }

    func replaceTextInRange(rangeUtf16: Range<Int>?, text: String) {
        _ = rangeUtf16
        receivedTexts.append(text)
    }
}

/// Synthesizes a valid minimal TrueType (`sfnt` `0x00010000`) binary font in memory containing
/// `.notdef` (glyph 0), `' '` (glyph 1, empty), `'A'` (glyph 2, rectangular contour), and `'B'` (glyph 3, wider rectangular contour).
private func buildSyntheticTrueTypeFont(
    familyName: String = "AndroidTestSans",
    weight: UInt16 = 400,
    italic: Bool = false
) -> Data {
    struct Writer {
        var bytes: [UInt8] = []
        mutating func u8(_ v: UInt8) { bytes.append(v) }
        mutating func u16(_ v: UInt16) {
            bytes.append(UInt8((v >> 8) & 0xFF))
            bytes.append(UInt8(v & 0xFF))
        }
        mutating func i16(_ v: Int16) { u16(UInt16(bitPattern: v)) }
        mutating func u32(_ v: UInt32) {
            bytes.append(UInt8((v >> 24) & 0xFF))
            bytes.append(UInt8((v >> 16) & 0xFF))
            bytes.append(UInt8((v >> 8) & 0xFF))
            bytes.append(UInt8(v & 0xFF))
        }
        mutating func tag(_ s: String) {
            let utf8 = Array(s.utf8)
            for i in 0..<4 {
                bytes.append(i < utf8.count ? utf8[i] : 0x20)
            }
        }
        mutating func append(_ other: [UInt8]) {
            bytes.append(contentsOf: other)
        }
        mutating func pad4() {
            while bytes.count % 4 != 0 {
                bytes.append(0)
            }
        }
    }

    func makeRectGlyph(xMin: Int16, yMin: Int16, xMax: Int16, yMax: Int16) -> [UInt8] {
        // Simple 1-contour 4-point clockwise rectangle:
        // P0: (xMin, yMin), P1: (xMin, yMax), P2: (xMax, yMax), P3: (xMax, yMin)
        var g = Writer()
        g.i16(1) // numberOfContours = 1
        g.i16(xMin)
        g.i16(yMin)
        g.i16(xMax)
        g.i16(yMax)
        g.u16(3) // endPtsOfContours[0] = 3 (4 points)
        g.u16(0) // instructionLength = 0
        // 4 on-curve flags, all 16-bit deltas (flag = 0x01 onCurve)
        for _ in 0..<4 {
            g.u8(0x01)
        }
        // X deltas: P0=xMin, P1=0, P2=(xMax-xMin), P3=-(xMax-xMin)
        g.i16(xMin)
        g.i16(0)
        g.i16(xMax - xMin)
        g.i16(-(xMax - xMin))
        // Y deltas: P0=yMin, P1=(yMax-yMin), P2=0, P3=-(yMax-yMin)
        g.i16(yMin)
        g.i16(yMax - yMin)
        g.i16(0)
        g.i16(-(yMax - yMin))
        g.pad4()
        return g.bytes
    }

    // 1. glyf + loca (4 glyphs: 0=.notdef, 1=space, 2='A', 3='B')
    let glyph0 = makeRectGlyph(xMin: 50, yMin: 0, xMax: 450, yMax: 700)
    let glyph1: [UInt8] = [] // space has empty contour slice
    let glyph2 = makeRectGlyph(xMin: 60, yMin: 0, xMax: 540, yMax: 720)
    let glyph3 = makeRectGlyph(xMin: 60, yMin: 0, xMax: 620, yMax: 720)

    var glyf = Writer()
    var offsets: [UInt32] = [0]
    for g in [glyph0, glyph1, glyph2, glyph3] {
        glyf.append(g)
        offsets.append(UInt32(glyf.bytes.count))
    }

    var loca = Writer()
    for off in offsets {
        loca.u32(off)
    }

    // 2. head (54 bytes)
    var head = Writer()
    head.u32(0x0001_0000) // version
    head.u32(0x0001_0000) // fontRevision
    head.u32(0)           // checkSumAdjustment
    head.u32(0x5F0F_3CF5) // magicNumber
    head.u16(0x000B)      // flags
    head.u16(1000)        // unitsPerEm = 1000
    head.u32(0); head.u32(0) // created
    head.u32(0); head.u32(0) // modified
    head.i16(0)           // xMin
    head.i16(-200)        // yMin
    head.i16(700)         // xMax
    head.i16(800)         // yMax
    head.u16((weight >= 700 ? 0x01 : 0x00) | (italic ? 0x02 : 0x00)) // macStyle
    head.u16(8)           // lowestRecPPEM
    head.i16(2)           // fontDirectionHint
    head.i16(1)           // indexToLocFormat = 1 (long offsets)
    head.i16(0)           // glyphDataFormat

    // 3. hhea (36 bytes)
    var hhea = Writer()
    hhea.u32(0x0001_0000)
    hhea.i16(800)         // ascent
    hhea.i16(-200)        // descent
    hhea.i16(50)          // lineGap
    hhea.u16(700)         // advanceWidthMax
    hhea.i16(0); hhea.i16(0); hhea.i16(700)
    hhea.i16(1); hhea.i16(0); hhea.i16(0)
    for _ in 0..<4 { hhea.i16(0) }
    hhea.i16(0)           // metricDataFormat
    hhea.u16(4)           // numberOfHMetrics = 4

    // 4. maxp (6 bytes v0.5)
    var maxp = Writer()
    maxp.u32(0x0000_5000)
    maxp.u16(4)           // numGlyphs = 4

    // 5. hmtx (4 * 4 = 16 bytes)
    var hmtx = Writer()
    hmtx.u16(500); hmtx.i16(50) // .notdef
    hmtx.u16(250); hmtx.i16(0)  // ' '
    hmtx.u16(600); hmtx.i16(60) // 'A'
    hmtx.u16(680); hmtx.i16(60) // 'B'

    // 6. OS/2 (96 bytes version 2)
    var os2 = Writer()
    os2.u16(2)            // version = 2
    os2.i16(600)          // xAvgCharWidth
    os2.u16(weight)       // usWeightClass
    os2.u16(5)            // usWidthClass
    os2.u16(0)            // fsType
    for _ in 0..<26 { os2.u16(0) } // offset 10..62
    os2.u16(italic ? 0x01 : 0x40)  // fsSelection at offset 62
    for _ in 0..<11 { os2.u16(0) } // offset 64..86
    os2.i16(520)          // sxHeight at offset 86
    os2.i16(720)          // sCapHeight at offset 88
    os2.u16(0); os2.u16(0); os2.u16(0) // pad to 96 bytes

    // 7. name (Platform 3 Windows Unicode BMP UTF-16BE, nameID 1 = familyName)
    var utf16Bytes: [UInt8] = []
    for unit in familyName.utf16 {
        utf16Bytes.append(UInt8((unit >> 8) & 0xFF))
        utf16Bytes.append(UInt8(unit & 0xFF))
    }
    var name = Writer()
    name.u16(0) // format
    name.u16(1) // count = 1
    name.u16(6 + 12) // stringOffset = 18
    // NameRecord
    name.u16(3) // platformID = Windows
    name.u16(1) // encodingID = Unicode BMP
    name.u16(0x0409) // languageID = en-US
    name.u16(1) // nameID = Font Family
    name.u16(UInt16(utf16Bytes.count))
    name.u16(0) // offset = 0
    name.append(utf16Bytes)

    // 8. cmap (Format 12 segmented coverage: ' '->1, 'A'->2, 'B'->3)
    var cmap = Writer()
    cmap.u16(0)  // version
    cmap.u16(1)  // numTables = 1
    cmap.u16(3)  // platformID = Windows
    cmap.u16(10) // encodingID = UCS-4
    cmap.u32(12) // subtable offset = 12
    // Format 12 subtable:
    cmap.u16(12) // format = 12
    cmap.u16(0)  // reserved
    cmap.u32(16 + 2 * 12) // length = 40
    cmap.u32(0)  // language
    cmap.u32(2)  // numGroups = 2
    // Group 0: 0x20..0x20 -> glyph 1
    cmap.u32(0x20); cmap.u32(0x20); cmap.u32(1)
    // Group 1: 0x41..0x42 ('A'..'B') -> glyph 2..3
    cmap.u32(0x41); cmap.u32(0x42); cmap.u32(2)

    let namedTables: [(String, [UInt8])] = [
        ("OS/2", os2.bytes),
        ("cmap", cmap.bytes),
        ("glyf", glyf.bytes),
        ("head", head.bytes),
        ("hhea", hhea.bytes),
        ("hmtx", hmtx.bytes),
        ("loca", loca.bytes),
        ("maxp", maxp.bytes),
        ("name", name.bytes),
    ]

    var fontFile = Writer()
    let numTables = UInt16(namedTables.count)
    fontFile.u32(0x0001_0000)
    fontFile.u16(numTables)
    fontFile.u16(128)
    fontFile.u16(3)
    fontFile.u16(numTables * 16 - 128)

    let directoryEnd = 12 + Int(numTables) * 16
    var currentOffset = directoryEnd
    var tableLocations: [(tag: String, offset: UInt32, length: UInt32, bytes: [UInt8])] = []
    for (tag, raw) in namedTables {
        let length = UInt32(raw.count)
        tableLocations.append((tag, UInt32(currentOffset), length, raw))
        let padded = (raw.count + 3) & ~3
        currentOffset += padded
    }

    for entry in tableLocations {
        fontFile.tag(entry.tag)
        fontFile.u32(0) // checksum
        fontFile.u32(entry.offset)
        fontFile.u32(entry.length)
    }

    for entry in tableLocations {
        fontFile.append(entry.bytes)
        fontFile.pad4()
    }

    return Data(fontFile.bytes)
}

// MARK: - 1. Keyboard & Keystroke Translation Tests

@Suite("Android Keyboard & Modifier Mapping")
struct AndroidKeyboardTests {
    @Test("Maps hardware keycodes across letters, digits, function keys, navigation, and back button")
    func hardwareKeycodeNames() {
        #expect(androidKeyCodeToKeyName(AndroidKeyCode.a) == "a")
        #expect(androidKeyCodeToKeyName(AndroidKeyCode.z) == "z")
        #expect(androidKeyCodeToKeyName(AndroidKeyCode.num0) == "0")
        #expect(androidKeyCodeToKeyName(AndroidKeyCode.num9) == "9")
        #expect(androidKeyCodeToKeyName(AndroidKeyCode.numpad5) == "5")
        #expect(androidKeyCodeToKeyName(AndroidKeyCode.f1) == "f1")
        #expect(androidKeyCodeToKeyName(AndroidKeyCode.f12) == "f12")
        #expect(androidKeyCodeToKeyName(AndroidKeyCode.dpadUp) == "up")
        #expect(androidKeyCodeToKeyName(AndroidKeyCode.dpadDown) == "down")
        #expect(androidKeyCodeToKeyName(AndroidKeyCode.dpadLeft) == "left")
        #expect(androidKeyCodeToKeyName(AndroidKeyCode.dpadRight) == "right")
        #expect(androidKeyCodeToKeyName(AndroidKeyCode.enter) == "enter")
        #expect(androidKeyCodeToKeyName(AndroidKeyCode.del) == "backspace")
        #expect(androidKeyCodeToKeyName(AndroidKeyCode.forwardDel) == "delete")
        #expect(androidKeyCodeToKeyName(AndroidKeyCode.back) == "escape")
        #expect(androidKeyCodeToKeyName(AndroidKeyCode.space) == "space")
        #expect(androidKeyCodeToKeyName(AndroidKeyCode.unknown) == nil)
    }

    @Test("Extracts Modifiers and Capslock from AMETA bitmasks")
    func metaStateModifiers() {
        let mask = AndroidMetaState.ctrlLeftOn
            | AndroidMetaState.shiftRightOn
            | AndroidMetaState.altOn
            | AndroidMetaState.metaLeftOn
            | AndroidMetaState.functionOn
            | AndroidMetaState.capsLockOn
        let mods = modifiersFromAndroidMetaState(mask)
        #expect(mods.control)
        #expect(mods.shift)
        #expect(mods.alt)
        #expect(mods.platform)
        #expect(mods.function)
        #expect(capslockFromAndroidMetaState(mask).on)
    }

    @Test("Translates standalone modifiers, shifted symbols, repeats, and Ctrl shortcuts")
    func statefulKeyEventTranslation() {
        var translator = AndroidKeyEventTranslator()

        // Press Shift Left -> ModifiersChangedEvent
        let shiftDown = translator.translate(
            action: AndroidKeyAction.down,
            keyCode: AndroidKeyCode.shiftLeft,
            metaState: AndroidMetaState.shiftOn | AndroidMetaState.shiftLeftOn
        )
        #expect(shiftDown.count == 1)
        if case .modifiersChanged(let modEv) = shiftDown[0] {
            #expect(modEv.modifiers.shift)
        } else {
            Issue.record("Expected ModifiersChangedEvent on Shift down")
        }

        // Shift + '1' -> key: "1", keyChar: "!"
        let bangDown = translator.translate(
            action: AndroidKeyAction.down,
            keyCode: AndroidKeyCode.num1,
            metaState: AndroidMetaState.shiftOn,
            repeatCount: 2,
            unicodeChar: Int32(UnicodeScalar("!").value)
        )
        #expect(bangDown.count == 1)
        if case .keyDown(let kd) = bangDown[0] {
            #expect(kd.keystroke.key == "1")
            #expect(kd.keystroke.keyChar == "!")
            #expect(kd.keystroke.modifiers.shift)
            #expect(kd.isHeld)
            #expect(kd.preferCharacterInput)
        } else {
            Issue.record("Expected KeyDownEvent for Shift+1")
        }

        // Ctrl + 'c' -> suppresses keyChar so shortcut bindings match cleanly
        let ctrlC = translator.translate(
            action: AndroidKeyAction.down,
            keyCode: AndroidKeyCode.c,
            metaState: AndroidMetaState.ctrlOn,
            unicodeChar: 3 // ETX control character
        )
        let keyDownEvents = ctrlC.compactMap { ev -> KeyDownEvent? in
            if case .keyDown(let kd) = ev { return kd }
            return nil
        }
        #expect(keyDownEvents.count == 1)
        #expect(keyDownEvents[0].keystroke.key == "c")
        #expect(keyDownEvents[0].keystroke.keyChar == nil)
        #expect(keyDownEvents[0].keystroke.modifiers.control)

        // KeyUp clears keyChar
        let keyUp = translator.translate(
            action: AndroidKeyAction.up,
            keyCode: AndroidKeyCode.c,
            metaState: 0
        )
        let upEvents = keyUp.compactMap { ev -> KeyUpEvent? in
            if case .keyUp(let ku) = ev { return ku }
            return nil
        }
        #expect(upEvents.count == 1)
        #expect(upEvents[0].keystroke.key == "c")
        #expect(upEvents[0].keystroke.keyChar == nil)
    }

    @Test("KeyboardLayout and KeyboardMapper conform to GPUI keyboard contracts")
    func layoutAndMapper() {
        let layout = AndroidKeyboardLayout(id: "en-US", name: "Gboard US")
        #expect(layout.id == "en-US")
        #expect(layout.name == "Gboard US")

        let mapper = AndroidKeyboardMapper()
        let ks = Keystroke(modifiers: Modifiers(control: true), key: "s", keyChar: nil)
        let mapped = mapper.mapKeyEquivalent(keystroke: ks, useKeyEquivalents: true)
        #expect(mapped.inner.key == "s")
        #expect(mapped.inner.modifiers.control)
        #expect(mapper.getKeyEquivalents() == nil)
    }
}

// MARK: - 2. Multi-Touch, Mouse, Pinch/Rotation & Fling Momentum Tests

@Suite("Android Multi-Touch & Fling Momentum")
struct AndroidTouchAndGestureTests {
    @Test("Single-finger tap and double-tap increment clickCount within distance/time window")
    func singleAndDoubleTap() {
        var processor = AndroidTouchInputProcessor()
        let scale: Float = 2.0
        let sample = [AndroidPointerSample(pointerId: 0, xPx: 200, yPx: 400)]

        let down1 = processor.processMotionEvent(
            rawAction: AndroidMotionAction.down,
            pointers: sample,
            scaleFactor: scale,
            eventTimeSeconds: 1.00
        )
        let up1 = processor.processMotionEvent(
            rawAction: AndroidMotionAction.up,
            pointers: sample,
            scaleFactor: scale,
            eventTimeSeconds: 1.05
        )
        #expect(down1.count == 1)
        #expect(up1.count == 1)
        if case .mouseDown(let md) = down1[0] {
            #expect(md.clickCount == 1)
            #expect(md.position == Point(x: px(100), y: px(200)))
        } else {
            Issue.record("Expected MouseDownEvent")
        }

        // Second tap 150ms later at nearly same spot -> clickCount == 2
        let down2 = processor.processMotionEvent(
            rawAction: AndroidMotionAction.down,
            pointers: [AndroidPointerSample(pointerId: 0, xPx: 208, yPx: 404)],
            scaleFactor: scale,
            eventTimeSeconds: 1.20
        )
        if case .mouseDown(let md2) = down2[0] {
            #expect(md2.clickCount == 2)
        } else {
            Issue.record("Expected double-tap MouseDownEvent")
        }
    }

    @Test("Single-finger pan exceeding touch slop emits scroll wheel events and arms inertial fling momentum")
    func panAndFlingMomentumDecay() {
        var processor = AndroidTouchInputProcessor()
        let scale: Float = 1.0

        _ = processor.processMotionEvent(
            rawAction: AndroidMotionAction.down,
            pointers: [AndroidPointerSample(pointerId: 0, xPx: 100, yPx: 500)],
            scaleFactor: scale,
            eventTimeSeconds: 0.000
        )
        let move1 = processor.processMotionEvent(
            rawAction: AndroidMotionAction.move,
            pointers: [AndroidPointerSample(pointerId: 0, xPx: 100, yPx: 460)],
            scaleFactor: scale,
            eventTimeSeconds: 0.016
        )
        let move2 = processor.processMotionEvent(
            rawAction: AndroidMotionAction.move,
            pointers: [AndroidPointerSample(pointerId: 0, xPx: 100, yPx: 380)],
            scaleFactor: scale,
            eventTimeSeconds: 0.032
        )
        let up = processor.processMotionEvent(
            rawAction: AndroidMotionAction.up,
            pointers: [AndroidPointerSample(pointerId: 0, xPx: 100, yPx: 300)],
            scaleFactor: scale,
            eventTimeSeconds: 0.048
        )

        let startedScroll = move1.compactMap { ev -> ScrollWheelEvent? in
            if case .scrollWheel(let sw) = ev { return sw }
            return nil
        }
        #expect(startedScroll.first?.touchPhase == .started)

        let movedScroll = move2.compactMap { ev -> ScrollWheelEvent? in
            if case .scrollWheel(let sw) = ev { return sw }
            return nil
        }
        #expect(movedScroll.first?.touchPhase == .moved)
        #expect(!up.isEmpty)

        // Fling velocity (~-4166 px/s) must arm ScrollMomentum
        #expect(processor.scrollMomentum != nil)

        var previousDeltaMag: Float = .infinity
        var stepCount = 0
        var sawEndedPhase = false
        while let stepEvent = processor.stepMomentum(dt: 1.0 / 60.0), stepCount < 500 {
            stepCount += 1
            if case .pixels(let deltaPt) = stepEvent.delta {
                let mag = abs(deltaPt.y.value)
                #expect(mag <= previousDeltaMag + 0.01)
                previousDeltaMag = mag
            }
            if stepEvent.touchPhase == .ended {
                sawEndedPhase = true
            }
        }
        #expect(stepCount > 5)
        #expect(sawEndedPhase)
        #expect(processor.scrollMomentum == nil)
    }

    @Test("Touching down while momentum is active immediately cancels fling scrolling")
    func touchDownCancelsMomentum() {
        var processor = AndroidTouchInputProcessor()
        _ = processor.processMotionEvent(
            rawAction: AndroidMotionAction.down,
            pointers: [AndroidPointerSample(pointerId: 0, xPx: 50, yPx: 400)],
            scaleFactor: 1.0,
            eventTimeSeconds: 0.0
        )
        _ = processor.processMotionEvent(
            rawAction: AndroidMotionAction.move,
            pointers: [AndroidPointerSample(pointerId: 0, xPx: 50, yPx: 250)],
            scaleFactor: 1.0,
            eventTimeSeconds: 0.02
        )
        _ = processor.processMotionEvent(
            rawAction: AndroidMotionAction.up,
            pointers: [AndroidPointerSample(pointerId: 0, xPx: 50, yPx: 100)],
            scaleFactor: 1.0,
            eventTimeSeconds: 0.04
        )
        #expect(processor.scrollMomentum != nil)

        _ = processor.processMotionEvent(
            rawAction: AndroidMotionAction.down,
            pointers: [AndroidPointerSample(pointerId: 0, xPx: 50, yPx: 100)],
            scaleFactor: 1.0,
            eventTimeSeconds: 0.06
        )
        #expect(processor.scrollMomentum == nil)
    }

    @Test("Two-finger gesture emits pinch zoom, rotation, and centroid scroll")
    func twoFingerPinchRotateScroll() {
        var processor = AndroidTouchInputProcessor()
        let p0Start = AndroidPointerSample(pointerId: 0, xPx: 100, yPx: 200)
        let p1Start = AndroidPointerSample(pointerId: 1, xPx: 200, yPx: 200)

        _ = processor.processMotionEvent(
            rawAction: AndroidMotionAction.down,
            pointers: [p0Start],
            scaleFactor: 1.0
        )
        let ptrDown = processor.processMotionEvent(
            rawAction: AndroidMotionAction.encode(action: AndroidMotionAction.pointerDown, pointerIndex: 1),
            pointers: [p0Start, p1Start],
            scaleFactor: 1.0
        )
        #expect(ptrDown.count == 2)

        // Expand span from 100 -> 200, translate centroid, and rotate slightly
        let p0Moved = AndroidPointerSample(pointerId: 0, xPx: 80, yPx: 210)
        let p1Moved = AndroidPointerSample(pointerId: 1, xPx: 280, yPx: 250)
        let moveEvents = processor.processMotionEvent(
            rawAction: AndroidMotionAction.move,
            pointers: [p0Moved, p1Moved],
            scaleFactor: 1.0
        )

        let hasScroll = moveEvents.contains { if case .scrollWheel = $0 { return true }; return false }
        let hasPinch = moveEvents.contains {
            if case .pinch(let pe) = $0 { return pe.delta > 0.5 && pe.phase == .moved }
            return false
        }
        let hasRotation = moveEvents.contains { if case .rotation = $0 { return true }; return false }
        #expect(hasScroll)
        #expect(hasPinch)
        #expect(hasRotation)

        let ptrUp = processor.processMotionEvent(
            rawAction: AndroidMotionAction.encode(action: AndroidMotionAction.pointerUp, pointerIndex: 1),
            pointers: [p0Moved, p1Moved],
            scaleFactor: 1.0
        )
        let endedPinch = ptrUp.contains {
            if case .pinch(let pe) = $0 { return pe.phase == .ended }
            return false
        }
        #expect(endedPinch)
    }

    @Test("Hardware mouse hover, right-click, and wheel scroll map to desktop mouse semantics")
    func hardwareMouseEvents() {
        var processor = AndroidTouchInputProcessor()
        let mousePtr = [AndroidPointerSample(
            pointerId: 0,
            xPx: 300,
            yPx: 150,
            pressure: 0.0,
            toolType: AndroidMotionToolType.mouse
        )]

        let enter = processor.processMotionEvent(
            rawAction: AndroidMotionAction.hoverEnter,
            pointers: mousePtr,
            scaleFactor: 1.5
        )
        #expect(processor.isHovering)
        #expect(enter.count == 1)

        let rightClick = processor.processMotionEvent(
            rawAction: AndroidMotionAction.buttonPress,
            pointers: mousePtr,
            scaleFactor: 1.5,
            buttonState: AndroidMotionButton.secondary
        )
        if case .mouseDown(let md) = rightClick.first {
            #expect(md.button == .right)
        } else {
            Issue.record("Expected right mouse button down")
        }

        let wheel = processor.processMotionEvent(
            rawAction: AndroidMotionAction.scroll,
            pointers: mousePtr,
            scaleFactor: 1.5,
            vScroll: -3.0,
            hScroll: 1.0
        )
        if case .scrollWheel(let sw) = wheel.first, case .lines(let delta) = sw.delta {
            #expect(delta.y == -3.0)
            #expect(delta.x == 1.0)
        } else {
            Issue.record("Expected line-based mouse wheel scroll")
        }

        let exit = processor.processMotionEvent(
            rawAction: AndroidMotionAction.hoverExit,
            pointers: mousePtr,
            scaleFactor: 1.5
        )
        #expect(!processor.isHovering)
        if case .mouseExited = exit.first {} else {
            Issue.record("Expected MouseExitEvent")
        }
    }
}

// MARK: - 3. Display Metrics & Safe-Area Inset Reconciliation Tests

@Suite("Android Display Metrics & Safe Area")
struct AndroidDisplayAndInsetsTests {
    @Test("Computes logical bounds, scaleFactor, and safe-area visibleBounds accurately")
    func densityAndSafeAreaReconciliation() {
        let metrics = AndroidDisplayMetrics(
            widthPixels: 1080,
            heightPixels: 2400,
            density: 2.0,
            densityDpi: 320,
            refreshRateHz: 120.0,
            safeAreaInsetsPx: EdgeInsets(top: 96, left: 40, bottom: 68, right: 0)
        )
        let display = AndroidDisplay(id: DisplayId(0), metrics: metrics)

        #expect(display.scaleFactor() == 2.0)
        #expect(display.bounds() == Bounds(origin: .zero, size: Size(width: px(540), height: px(1200))))
        #expect(display.visibleBounds() == Bounds(
            origin: Point(x: px(20), y: px(48)),
            size: Size(width: px(520), height: px(1118))
        ))
        #expect(abs(metrics.vsyncInterval - (1.0 / 120.0)) < 0.0001)
    }

    @Test("Sanitizes invalid density and clamps oversized insets to non-negative visible bounds")
    func clampsInvalidMetricsAndOversizedInsets() {
        let metrics = AndroidDisplayMetrics(
            widthPixels: 400,
            heightPixels: 800,
            density: -1.0,
            refreshRateHz: .nan,
            safeAreaInsetsPx: EdgeInsets(top: 600, left: 500, bottom: 600, right: 500)
        )
        #expect(metrics.scaleFactor == 1.0)
        #expect(metrics.refreshRateHz == 60.0)
        #expect(metrics.visibleBounds.size.width == px(0))
        #expect(metrics.visibleBounds.size.height == px(0))
    }
}

// MARK: - 4. Activity, Surface & Thermal Lifecycle Tests

@Suite("Android Lifecycle State Machine")
struct AndroidLifecycleTests {
    @Test("Coordinates Activity foreground/background transitions with SurfaceHolder creation and destruction")
    func activityAndSurfaceStateMachine() {
        let controller = AndroidLifecycleController()
        #expect(controller.phase == .created)
        #expect(!controller.canRender)

        let startFx = controller.transition(to: .started)
        #expect(startFx.activeChanged == nil)
        #expect(!controller.canRender)

        let resumeFx = controller.transition(to: .resumed)
        #expect(resumeFx.activeChanged == true)
        #expect(controller.isActive)
        #expect(!controller.canRender) // Surface not yet attached

        let surfCreated = controller.onSurfaceCreated(widthPx: 1080, heightPx: 2400, format: 1)
        #expect(surfCreated.shouldResumeRendering)
        #expect(controller.canRender)

        let pauseFx = controller.transition(to: .paused)
        #expect(pauseFx.activeChanged == false)
        #expect(controller.isForeground)
        #expect(controller.canRender) // Still visible in multi-window / split-screen when paused

        let stopFx = controller.transition(to: .stopped)
        #expect(stopFx.shouldPauseRendering)
        #expect(!controller.isForeground)
        #expect(!controller.canRender)

        let surfDestroyed = controller.onSurfaceDestroyed()
        #expect(surfDestroyed.shouldReleaseGpuSurface)
        #expect(!controller.surface.isAttached)

        // Returning from background triggers didReopen
        let restartFx = controller.transition(to: .started)
        #expect(restartFx.didReopen)

        let destroyFx = controller.transition(to: .destroyed)
        #expect(destroyFx.shouldReleaseGpuSurface)
        #expect(destroyFx.shouldQuitApp)
    }

    @Test("Maps Android PowerManager thermal statuses and deduplicates unchanged notifications")
    func thermalMapping() {
        #expect(mapAndroidThermalStatus(0) == .nominal)
        #expect(mapAndroidThermalStatus(1) == .fair)
        #expect(mapAndroidThermalStatus(2) == .fair)
        #expect(mapAndroidThermalStatus(3) == .serious)
        #expect(mapAndroidThermalStatus(5) == .critical)

        let controller = AndroidLifecycleController()
        #expect(controller.updateThermalStatus(0) == nil)
        #expect(controller.updateThermalStatus(3) == .serious)
        #expect(controller.updateThermalStatus(3) == nil)
        #expect(controller.updateThermalStatus(4) == .critical)
    }
}

// MARK: - 5. ALooper / Priority Dispatcher Tests

@Suite("Android Priority Dispatcher")
struct AndroidDispatcherTests {
    @Test("Drains main-thread queue strictly in realtimeAudio -> high -> medium -> low priority order")
    func mainThreadPriorityOrder() {
        let dispatcher = AndroidDispatcher(attachCurrentThreadLooper: false)
        let order = LockedTestBox<[String]>([])

        dispatcher.dispatchOnMainThread({ order.mutate { $0.append("low") } }, priority: .low)
        dispatcher.dispatchOnMainThread({ order.mutate { $0.append("medium") } }, priority: .medium)
        dispatcher.dispatchOnMainThread({ order.mutate { $0.append("high-1") } }, priority: .high)
        dispatcher.dispatchOnMainThread({ order.mutate { $0.append("realtime") } }, priority: .realtimeAudio)
        dispatcher.dispatchOnMainThread({ order.mutate { $0.append("high-2") } }, priority: .high)

        let drained = dispatcher.drainMainThreadTasks()
        #expect(drained == 5)
        #expect(order.value == ["realtime", "high-1", "high-2", "medium", "low"])
    }

    @Test("Executes background pool tasks, timers, and realtime threads")
    func backgroundTimerAndRealtimeExecution() {
        let dispatcher = AndroidDispatcher(attachCurrentThreadLooper: false)

        let bgSem = DispatchSemaphore(value: 0)
        dispatcher.dispatch({ bgSem.signal() }, priority: .high)
        #expect(bgSem.wait(timeout: .now() + 2.0) == .success)

        let timerSem = DispatchSemaphore(value: 0)
        dispatcher.dispatchAfter(duration: 0.01) {
            timerSem.signal()
        }
        #expect(timerSem.wait(timeout: .now() + 2.0) == .success)

        let rtSem = DispatchSemaphore(value: 0)
        dispatcher.spawnRealtime {
            rtSem.signal()
        }
        #expect(rtSem.wait(timeout: .now() + 2.0) == .success)
    }
}

// MARK: - 6. System Font Discovery & TrueType Text System Tests

@Suite("Android NDK Font Discovery & TrueType Text System")
struct AndroidTextSystemTests {
    @Test("Infers clean font family names from Android /system/fonts paths")
    func fontFamilyPathInference() {
        #expect(inferAndroidFontFamilyName(fromFilePath: "/system/fonts/Roboto-Regular.ttf") == "Roboto")
        #expect(inferAndroidFontFamilyName(fromFilePath: "/system/fonts/RobotoStatic-Regular.ttf") == "Roboto")
        #expect(inferAndroidFontFamilyName(fromFilePath: "/system/fonts/DroidSansMono.ttf") == "Droid Sans Mono")
        #expect(inferAndroidFontFamilyName(fromFilePath: "/system/fonts/NotoColorEmoji.ttf") == "Noto Color Emoji")
        #expect(inferAndroidFontFamilyName(fromFilePath: "/system/fonts/NotoSerif-BoldItalic.ttf") == "Noto Serif")
    }

    @Test("Parses TrueType binary tables, shapes glyph runs, and rasterizes contour alpha bitmaps")
    func trueTypeMetricsShapingAndRasterization() throws {
        let textSystem = AndroidTextSystem(systemFontFallback: "AndroidTestSans", scanSystemFonts: false)
        let fontBytes = buildSyntheticTrueTypeFont(familyName: "AndroidTestSans", weight: 400, italic: false)
        try textSystem.addFonts([fontBytes])

        #expect(textSystem.allFontNames().contains("AndroidTestSans"))

        let fontId = try textSystem.fontId(descriptor: Font(family: "AndroidTestSans"))
        let metrics = textSystem.fontMetrics(fontId: fontId)
        #expect(metrics.unitsPerEm == 1000)
        #expect(metrics.ascent == 800)
        #expect(metrics.descent == -200)
        #expect(metrics.capHeight == 720)
        #expect(metrics.xHeight == 520)

        let glyphA = try #require(textSystem.glyphForChar(fontId: fontId, ch: "A"))
        let glyphB = try #require(textSystem.glyphForChar(fontId: fontId, ch: "B"))
        #expect(glyphA.value == 2)
        #expect(glyphB.value == 3)

        let advA = try textSystem.advance(fontId: fontId, glyphId: glyphA)
        let advB = try textSystem.advance(fontId: fontId, glyphId: glyphB)
        #expect(advA.width == 600)
        #expect(advB.width == 680)

        let line = textSystem.layoutLine(
            text: "AB A",
            fontSize: px(20),
            runs: [FontRun(len: 4, fontId: fontId)]
        )
        #expect(line.runs.count == 1)
        #expect(line.runs[0].glyphs.count == 4)
        // Positions: A=0, B=12, ' '=25.6, A=30.6, total width=42.6
        #expect(abs(line.runs[0].glyphs[1].position.x.value - 12.0) < 0.01)
        #expect(abs(line.width.value - 42.6) < 0.05)

        let params = RenderGlyphParams(
            fontId: fontId,
            glyphId: glyphA,
            fontSize: px(24),
            scaleFactor: 2.0,
            isEmoji: false,
            subpixelRendering: false
        )
        let rasterBounds = try textSystem.glyphRasterBounds(params: params)
        #expect(rasterBounds.size.width.value > 0)
        #expect(rasterBounds.size.height.value > 0)

        let (bitmapSize, alphaData) = try textSystem.rasterizeGlyph(params: params, rasterBounds: rasterBounds)
        #expect(bitmapSize == rasterBounds.size)
        #expect(alphaData.count == Int(bitmapSize.width.value * bitmapSize.height.value))
        #expect(alphaData.contains { $0 > 0 })
    }
}

// MARK: - 7. Platform, Window, IME, Clipboard & JNI Router Integration Tests

@Suite("Android Platform, Window & JNI Integration")
struct AndroidPlatformIntegrationTests {
    @Test("Opens AndroidWindow, propagates resize/insets/appearance/URLs/clipboard/credentials, and handles IME")
    func endToEndPlatformAndWindowFlow() async throws {
        let initialMetrics = AndroidDisplayMetrics(
            widthPixels: 1080,
            heightPixels: 2400,
            density: 3.0,
            refreshRateHz: 90.0
        )
        let platform = AndroidPlatform(
            headless: true,
            displayMetrics: initialMetrics,
            appearance: .dark,
            registerInGlobalRegistry: false
        )

        let handle = AnyWindowHandle(id: 42)
        let opened = platform.openWindow(handle: handle, options: WindowOptions())
        let androidWin = try #require(opened as? AndroidWindow)

        #expect(platform.activeWindow() == handle)
        #expect(platform.windowStack() == [handle])
        #expect(androidWin.scaleFactor() == 3.0)
        #expect(androidWin.contentSize() == Size(width: px(360), height: px(800)))
        #expect(androidWin.appearance() == .dark)

        // Resize & safe-area inset callbacks
        let observedResize = LockedTestBox<(Size<Pixels>, Float)?>(nil)
        androidWin.onResize { size, scale in
            observedResize.value = (size, scale)
        }
        platform.handleInsetsChanged(topPx: 90, leftPx: 0, bottomPx: 150, rightPx: 0)
        #expect(observedResize.value?.0 == Size(width: px(360), height: px(720)))
        #expect(observedResize.value?.1 == 3.0)

        // Appearance change callback
        let appearanceChanges = LockedTestBox<Int>(0)
        androidWin.onAppearanceChanged {
            appearanceChanges.mutate { $0 += 1 }
        }
        platform.handleAppearanceChanged(isDark: false)
        #expect(platform.windowAppearance() == .light)
        #expect(androidWin.appearance() == .light)
        #expect(appearanceChanges.value == 1)

        // IME handler attachment, commitText, deleteSurroundingText, and dismissIme
        let dispatchedInputs = LockedTestBox<[PlatformInput]>([])
        androidWin.onInput { ev in
            dispatchedInputs.mutate { $0.append(ev) }
            return DispatchEventResult()
        }

        let handler = RecordingInputHandler()
        androidWin.setInputHandler(handler)
        #expect(androidWin.isImeVisible)
        #expect(androidWin.activeInputHandler() === handler)

        platform.handleCommitText(" Swift")
        #expect(androidWin.committedImeTexts == [" Swift"])
        #expect(handler.receivedTexts == [" Swift"])

        dispatchedInputs.value = []
        platform.handleDeleteSurroundingText(beforeLength: 2, afterLength: 1)
        // 2 backspace down/up + 1 delete down/up = 6 events
        #expect(dispatchedInputs.value.count == 6)

        androidWin.dismissIme()
        #expect(!androidWin.isImeVisible)
        #expect(androidWin.activeInputHandler() == nil)

        // When no input handler is active, commitText falls back to KeyDownEvent(preferCharacterInput: true)
        dispatchedInputs.value = []
        platform.handleCommitText(" Fallback")
        if case .keyDown(let commitKd) = dispatchedInputs.value.last {
            #expect(commitKd.keystroke.keyChar == " Fallback")
            #expect(commitKd.preferCharacterInput)
        } else {
            Issue.record("Expected fallback IME commit KeyDownEvent when no input handler is attached")
        }

        // JNI router pointer & key marshaling
        dispatchedInputs.value = []
        let touchOut = AndroidJniEventRouter.onTouchEvent(
            platform: platform,
            action: AndroidMotionAction.down,
            pointerIds: [0],
            xs: [180],
            ys: [300],
            pressures: [0.8],
            toolTypes: [AndroidMotionToolType.finger],
            metaState: 0,
            buttonState: 0,
            vScroll: 0,
            hScroll: 0,
            eventTimeMillis: 1000
        )
        #expect(touchOut.count == 1)
        #expect(androidWin.mousePosition() == Point(x: px(60), y: px(100)))

        let keyHandled = AndroidJniEventRouter.onKeyEvent(
            platform: platform,
            action: AndroidKeyAction.down,
            keyCode: AndroidKeyCode.enter,
            metaState: 0,
            repeatCount: 0,
            unicodeChar: 10,
            scanCode: 28
        )
        #expect(keyHandled)

        // Clipboard, URLs, credentials, and quit callbacks
        platform.writeToClipboard(ClipboardItem(text: "gpua-android"))
        #expect(platform.readFromClipboard()?.text == "gpua-android")

        let secret = Data("token-123".utf8)
        try await platform.writeCredentials(url: "https://glass.dev", username: "bot", password: secret)
        let loaded = try await platform.readCredentials(url: "https://glass.dev")
        #expect(loaded?.0 == "bot")
        #expect(loaded?.1 == secret)
        try await platform.deleteCredentials(url: "https://glass.dev")
        #expect(try await platform.readCredentials(url: "https://glass.dev") == nil)

        let openedCallbacks = LockedTestBox<[[String]]>([])
        platform.onOpenUrls { urls in
            openedCallbacks.mutate { $0.append(urls) }
        }
        platform.handleIncomingUrls(["gpua://open/project"])
        #expect(openedCallbacks.value == [["gpua://open/project"]])

        platform.openUrl("https://github.com/Glass-HQ/gpui")
        #expect(platform.openedUrls == ["https://github.com/Glass-HQ/gpui"])

        let quitCalled = LockedTestBox<Bool>(false)
        platform.onQuit {
            quitCalled.value = true
        }
        platform.handleLifecycleState(.destroyed)
        #expect(quitCalled.value)
    }

    @Test("AndroidAppBootstrap invokes registered startup closure at most once until reset")
    func bootstrapLaunchOnce() {
        let counter = LockedTestBox<Int>(0)
        AndroidAppBootstrap.shared.reset()
        AndroidAppBootstrap.shared.register {
            counter.mutate { $0 += 1 }
        }
        AndroidAppBootstrap.shared.launchIfNeeded()
        AndroidAppBootstrap.shared.launchIfNeeded()
        #expect(counter.value == 1)
        AndroidAppBootstrap.shared.reset()
    }

    @Test("GPUI.PlatformInputHandler receives Android hardware printable keys, IME preedit, and commitText")
    @MainActor
    func platformInputHandlerEndToEnd() throws {
        let platform = AndroidPlatform(headless: true)
        let app = App.newApp(platform: platform)
        let handle = try app.openWindow(WindowOptions()) { _, cx in
            cx.new { _ in AndroidInputDummyView() }
        }
        let androidWin = try #require(
            try app.updateWindow(handle.anyHandle) { _, w, _ in w.platformWindow as? AndroidWindow }
        )

        let recorder = RecordingAndroidEntityInputHandler()
        let platformHandler = PlatformInputHandler(
            windowHandle: handle.anyHandle,
            app: app,
            handler: recorder
        )
        androidWin.setInputHandler(platformHandler)
        androidWin.onInput { _ in
            DispatchEventResult(propagate: true, defaultPrevented: false)
        }

        // 1. Hardware printable key ('g' = unicodeChar 103) routes into PlatformInputHandler
        _ = androidWin.handleKeyEvent(
            action: AndroidKeyAction.down,
            keyCode: 35,
            metaState: 0,
            repeatCount: 0,
            unicodeChar: 103,
            scanCode: 34
        )
        #expect(recorder.text == "g")

        // 2. Soft keyboard composing preedit -> commitText -> finishComposingText
        platform.handleSetComposingText("にほ")
        #expect(recorder.text == "gにほ")
        #expect(recorder.marked == 1..<3)

        platform.handleCommitText("日本")
        #expect(recorder.text == "g日本")
        #expect(recorder.marked == nil)

        platform.handleSetComposingText("かな")
        platform.handleFinishComposingText()
        #expect(recorder.text == "g日本かな")
        #expect(recorder.marked == nil)
        #expect(recorder.unmarkCount == 1)
    }
}

@MainActor
private final class RecordingAndroidEntityInputHandler: InputHandler {
    var text: String = ""
    var selection: Range<Int> = 0..<0
    var marked: Range<Int>? = nil
    var unmarkCount: Int = 0

    func selectedTextRange(ignoreDisabledInput: Bool, window: inout Window, cx: inout App) -> UTF16Selection? {
        UTF16Selection(range: selection, reversed: false)
    }

    func markedTextRange(window: inout Window, cx: inout App) -> Range<Int>? {
        marked
    }

    func textForRange(rangeUtf16: Range<Int>, adjustedRange: inout Range<Int>?, window: inout Window, cx: inout App) -> String? {
        text
    }

    func replaceTextInRange(rangeUtf16: Range<Int>?, text replacement: String, window: inout Window, cx: inout App) {
        let target = rangeUtf16 ?? marked ?? selection
        if let strRange = IMEBridge.utf16RangeToStringRange(target, in: text) {
            text.replaceSubrange(strRange, with: replacement)
            let cursor = target.lowerBound + replacement.utf16.count
            selection = cursor..<cursor
        }
        marked = nil
    }

    func replaceAndMarkTextInRange(
        rangeUtf16: Range<Int>?,
        newText: String,
        newSelectedRange: Range<Int>?,
        window: inout Window,
        cx: inout App
    ) {
        let target = rangeUtf16 ?? marked ?? selection
        if let strRange = IMEBridge.utf16RangeToStringRange(target, in: text) {
            text.replaceSubrange(strRange, with: newText)
            let start = target.lowerBound
            let end = start + newText.utf16.count
            marked = newText.isEmpty ? nil : (start..<end)
            selection = end..<end
        }
    }

    func unmarkText(window: inout Window, cx: inout App) {
        marked = nil
        unmarkCount += 1
    }

    func setSelectedTextRange(selection: UTF16Selection?, window: inout Window, cx: inout App) {
        if let selection {
            self.selection = selection.range
        }
    }

    func boundsForRange(rangeUtf16: Range<Int>, window: inout Window, cx: inout App) -> Bounds<Pixels>? {
        Bounds(origin: point(px(8), px(16)), size: size(px(2), px(20)))
    }

    func characterIndexForPoint(point: Point<Pixels>, window: inout Window, cx: inout App) -> Int? {
        0
    }
}

private struct AndroidInputDummyView: Render {
    func render(_ window: inout Window, _ cx: inout Context<AndroidInputDummyView>) -> some IntoElement {
        div()
    }
}
