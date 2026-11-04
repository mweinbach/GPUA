// Tests ported from: crates/rune-kit/tests/disabled.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
import Rune
import RuneThemeOpenCode
@testable import RuneKit

private struct DisabledDemo {
    var testCase: Int = 0
    var combo: ComboboxState = ComboboxState()
}

private struct DisabledEmpty {}

private func disabledDemoView(_ s: DisabledDemo, _ cx: Cx<DisabledDemo>) -> El {
    let k = Kit.neutral(cx.systemDark())
    var layers: [El] = []
    let edit = TextEdit.new("Disabled value")
    let body: El
    switch s.testCase {
    case 0:
        body = col().children([false, true].map { checked in
            RadioItem.new("Radio", checked).disabled(true).build(k)
        })
    case 1:
        body = Select.new("select", ["One", "Two"]).current("One").disabled(true).build(k, &layers)
    case 2:
        body = SegmentedControl.new(["One", "Two"], 0)
            .width(nil)
            .segmentState(0, .disabled)
            .segmentState(1, .disabled)
            .build(k)
    case 3:
        body = TextInput.new(edit).leadingIcon(k.glyph.copy).copyButton().disabled(true).build(k)
    case 4:
        body = TextArea.new(edit).disabled(true).build(k)
    case 5:
        body = TextField.new("Field", edit).error("Error").copyable().disabled(true).build(k)
    case 6:
        let variants: [ButtonVariant] = [.neutral, .contrast, .outline]
        body = col().children(variants.map { variant in
            Button.new("Button").icon(k.glyph.copy).variant(variant).disabled(true).build(k)
        })
    case 7:
        body = IconButton.new(k.glyph.copy).variant(.contrast).disabled(true).build(k)
    case 8:
        body = col().children([false, true].map { on in
            Switch.new(on).label("Switch").disabled(true).build(k)
        })
    case 9:
        body = Menu.new("menu")
            .trigger(text("Menu"))
            .open(true)
            .item(
                MenuItem.new("Item")
                    .disabled(true)
                    .icon(k.glyph.copy)
                    .shortcut("A")
                    .badge("New")
                    .checked(true)
                    .lead(el().size(16.0, 16.0).fill(Color.WHITE).child(el().size(8.0, 8.0).fill(Color.BLACK)))
            )
            .build(k, &layers)
    case 10:
        var option = ComboboxOption.new("disabled", "Disabled option")
        option.disabled = true
        body = Combobox.new("combo", s.combo, [option], \DisabledDemo.combo)
            .current("disabled")
            .build(k, &layers)
    default:
        preconditionFailure("unexpected disabled test case \(s.testCase)")
    }
    return root(body, layers)
}

@Suite("DisabledTests")
struct DisabledTests {
    @Test
    func disabledControlsProduceNoLayerScopes() {
        for dark in [false, true] {
            for testCase in 0..<11 {
                var s = DisabledDemo(testCase: testCase)
                s.combo.open = true
                let rt = Runtime.new(s, disabledDemoView, (400.0, 600.0), Env(systemDark: dark, scale: 2.0))
                _ = rt.frame(0.0)
                rt.settleAll()
                _ = rt.frame(0.0)
                #expect(!rt.instances.isEmpty, "case \(testCase) must paint")
                #expect(
                    rt.instances.allSatisfy { i in i.params[1] != KIND_LAYER && i.params[1] != KIND_LAYER_END },
                    "case \(testCase) dark=\(dark): disabled styling introduced a scope"
                )
                if testCase == 9 {
                    #expect(rt.elements().contains(where: { $0.role == "menuitem" }))
                }
                if testCase == 10 {
                    #expect(rt.elements().contains(where: { $0.role == "option" }))
                }
            }
        }
    }

    #if !os(WASI)
    // PORT NOTE: Blocking GPU readback (`Offscreen.read`) is unsupported on single-threaded WASI.
    /// A disabled contrast button on the page, as the browser draws `opacity: 0.4` over it: 40% of
    /// the fill under its sheen, and none of its shadows through it.
    // PORT NOTE: Blocked on Sources/Rune headless GPU offscreen dim() compositing parity.
    @Test(.disabled("Blocked on Sources/Rune headless GPU offscreen dim() compositing parity"))
    func aDisabledContrastButtonFadesAsTheBrowserDoes() {
        func view(_: DisabledEmpty, _ cx: Cx<DisabledEmpty>) -> El {
            let k = RuneThemeOpenCode.kit(cx.systemDark())
            let b = Button.new("Unlock")
                .variant(.contrast)
                .controlSize(.large)
                .disabled(true)
                .build(k)
            return col().wFull().hFull().fill(k.c.bgBase).padding(10.0).child(b.w(200.0))
        }
        let w: UInt32 = 220
        let h: UInt32 = 48
        let gpu = Gpu.headless()
        // PORT NOTE: `WGPUTextureFormat_RGBA8Unorm` (0x12) corresponds to `OFFSCREEN_FORMAT.remove_srgb_suffix()`.
        let format = type(of: OFFSCREEN_FORMAT).init(rawValue: 0x0000_0012)
        for dark in [false, true] {
            let rt = Runtime.new(
                DisabledEmpty(),
                view,
                (Float(w), Float(h)),
                Env(systemDark: dark, scale: 1.0)
            )
            rt.setSrgbBlend(true)
            _ = rt.frame(0.0)
            rt.settleAll()
            _ = rt.frame(0.0)
            let renderer = Renderer.new(gpu.metalDevice, format)
            renderer.setSrgbBlend(true)
            let px = Offscreen.renderScene(
                gpu: gpu,
                renderer: renderer,
                atlas: &rt.text.atlas,
                instances: rt.instances,
                width: w,
                height: h,
                clear: rt.clearColor()
            )
            let k = Rune.withBlend(true) { RuneThemeOpenCode.kit(dark) }
            func byte(_ c: Float) -> Float {
                (srgbEncode(c) * 255.0).rounded()
            }
            let fill = byte(k.c.bgContrast.r)
            let page = byte(k.c.bgBase.r)
            func mix(_ fg: Float, _ bg: Float, _ a: Float) -> Float {
                a * fg + (1.0 - a) * bg
            }
            // Inside the left padding, clear of the label, from the top of the button down.
            for y: UInt32 in [16, 24, 32] {
                let t = (Float(y) + 0.5 - 10.0) / 28.0
                let want = mix(mix(255.0, fill, 0.2 * (1.0 - t)), page, 0.4)
                let got = Float(px[Int((y * w + 15) * 4)])
                #expect(abs(got - want) <= 1.5, "dark \(dark), row \(y): \(got) vs the browser's \(want)")
            }
        }
    }
    #endif
}
