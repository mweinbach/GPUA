// Tests ported from: crates/rune/tests/shortcut_layout_macos.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

#if os(macOS)
import Carbon
import CoreFoundation

private func withInstalledMacLayout<T>(
    _ id: String,
    _ body: (UnsafePointer<UCKeyboardLayout>) -> T
) -> T? {
    let filter: [CFString: CFString] = [kTISPropertyInputSourceID: id as CFString]
    guard let list = TISCreateInputSourceList(filter as CFDictionary, true)?.takeRetainedValue() else {
        return nil
    }
    guard CFArrayGetCount(list) > 0 else {
        return nil
    }
    let source = unsafeBitCast(CFArrayGetValueAtIndex(list, 0), to: TISInputSource.self)
    guard let rawData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
        Issue.record("\(id) has no Unicode layout data")
        return nil
    }
    let data = unsafeBitCast(rawData, to: CFData.self)
    guard let bytePtr = CFDataGetBytePtr(data) else {
        return nil
    }
    return bytePtr.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { layoutPtr in
        body(layoutPtr)
    }
}

@Suite("ShortcutLayoutMacosIntegrationTests")
struct ShortcutLayoutMacosIntegrationTests {
    @MainActor
    @Test func shortcutLayoutMacos() throws {
        let cmd: UInt32 = 1 << 8
        let shift: UInt32 = 1 << 9
        let option: UInt32 = 1 << 11
        let control: UInt32 = 1 << 12
        let q: UInt32 = 12
        let w: UInt32 = 13
        let k: UInt32 = 40

        let shortcut = try Shortcut.parse("super+q").get()
        let current = try #require(macLayoutLabel(q, cmd))
        #expect(shortcut.keycaps().last == current.uppercased())

        _ = withInstalledMacLayout("com.apple.keylayout.US") { layout in
            #expect(macChordLabel(layout, k, cmd) == "k")
            #expect(macChordLabel(layout, k, cmd | option | shift) == "k")
            #expect(macChordLabel(layout, k, control) == "k")
        }
        _ = withInstalledMacLayout("com.apple.keylayout.Dvorak") { layout in
            #expect(macChordLabel(layout, q, 0) == "'")
            #expect(macChordLabel(layout, w, 0) == ",")
            #expect(macChordLabel(layout, k, cmd) == "t")
            #expect(macChordLabel(layout, k, control) == "t")
        }
        _ = withInstalledMacLayout("com.apple.keylayout.DVORAK-QWERTYCMD") { layout in
            #expect(macChordLabel(layout, k, 0) == "t")
            #expect(macChordLabel(layout, k, cmd) == "k")
            #expect(macChordLabel(layout, k, cmd | shift | option | control) == "k")
            #expect(macChordLabel(layout, k, option) == "t")
        }

        #expect(shortcut.physicalKey() == .keyQ)
        #expect(shortcut.description == "super+q")
    }
}
#endif
