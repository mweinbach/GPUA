// Tests ported from: crates/rune/src/desktop/tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("DesktopCompositeAndWindowTests")
struct DesktopCompositeAndWindowTests {
    @Test("backdrop is cropped to the output aspect then scaled")
    func backdropIsCroppedToTheOutputAspectThenScaled() throws {
        // Red, green, and blue thirds side by side (300 x 100): a square output keeps the green middle.
        var wideRgba = [UInt8](repeating: 0, count: 300 * 100 * 4)
        for y in 0..<100 {
            for x in 0..<300 {
                let idx = (y * 300 + x) * 4
                wideRgba[idx] = x < 100 ? 255 : 0
                wideRgba[idx + 1] = (100..<200).contains(x) ? 255 : 0
                wideRgba[idx + 2] = x >= 200 ? 255 : 0
                wideRgba[idx + 3] = 255
            }
        }
        let px = try fitBackdropBuffer(
            label: "wide.png",
            sourceSize: (300, 100),
            sourceRgba: wideRgba,
            targetSize: (50, 50)
        ).get()
        #expect(px.count == 50 * 50 * 4)
        for i in stride(from: 0, to: px.count, by: 4) {
            #expect(px[i + 1] > 200 && px[i] < 40 && px[i + 2] < 40)
        }

        let same = try fitBackdropBuffer(
            label: "wide.png",
            sourceSize: (300, 100),
            sourceRgba: wideRgba,
            targetSize: (300, 100)
        ).get()
        #expect(Array(same[0..<4]) == [255, 0, 0, 255])

        let hugeRes = fitBackdropBuffer(
            label: "huge.png",
            sourceSize: (MAX_BACKDROP + 1, 1),
            sourceRgba: [],
            targetSize: (10, 10)
        )
        if case .failure(let error) = hugeRes {
            #expect(error.message.contains("16385x1"))
        } else {
            Issue.record("expected MAX_BACKDROP error")
        }
    }

    @Test("each window takes its tab opt-in and titlebar inset")
    func eachWindowTakesItsTabOptInAndTitlebarInset() throws {
        let view: (Void, Cx<Void>) -> El = { _, cx in
            col().size(300.0, 100.0)
                .child(row().child(el().key("inset").size(max(cx.titlebarInset(), 1.0), 10.0)))
                .child(el().key("button").size(30.0, 30.0).focusable(true).role("button"))
        }
        func runWindow(tab: Bool, borderless: Bool) throws -> (String?, Float) {
            var opts = WindowOptions()
            opts.borderless = borderless
            let spec = WindowSpec.new("w", AppSpec("W", (300.0, 100.0), { () }, view))
                .tabVisitsControls(tab)
                .options(opts)
            let desk = try runDesktop(windows: [spec.boxed()], displaysSpec: "800x600")
            let member = desk.members[0] as! DesktopWindow<Void>
            _ = member.host.rt.hostKey(KeyEvent(key: .tab))
            _ = member.host.rt.hostFrame(0.1)
            let focused = member.host.rt.hostElements().first { $0.focused }?.key
            let insetW = member.host.rt.hostPresented("inset")!.rect.w
            return (focused, insetW)
        }

        let r1 = try runWindow(tab: true, borderless: false)
        #expect(r1.0 == "button")
        #if os(macOS)
        #expect(r1.1 == 67.0)
        #endif
        let r2 = try runWindow(tab: false, borderless: false)
        #expect(r2.0 == nil)
        let r3 = try runWindow(tab: true, borderless: true)
        #expect(r3.1 == 1.0)
    }

    @Test("output pixels fit a texture")
    func outputPixelsFitATexture() {
        #expect(compositeOutputPixels((1512.0, 982.0), 2.0, 8192)! == (3024, 1964))
        #expect(compositeOutputPixels((0.2, 10.0), 2.0, 8192) == nil)
        #expect(compositeOutputPixels((5000.0, 10.0), 2.0, 8192) == nil)
        #expect(compositeOutputPixels((.nan, 10.0), 2.0, 8192) == nil)
        #expect(compositeOutputPixels((10.0, 10.0), .infinity, 8192) == nil)
    }
}
