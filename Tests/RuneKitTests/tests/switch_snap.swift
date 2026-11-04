// Tests ported from: crates/rune-kit/tests/switch_snap.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
import Rune
@testable import RuneKit

private let switchSizes: [ControlSize] = [
    .mini, .small, .regular, .large, .extraLarge,
]

private func switchSnapView(_: Void, _ cx: Cx<Void>) -> El {
    let k = Kit.neutral(cx.systemDark())
    return Rune.col()
        .padding(10.09375)
        .gap(1.1)
        .children(
            switchSizes.flatMap { size in
                [false, true].map { on in
                    Switch.new(on)
                        .label("Switch")
                        .hideLabel()
                        .controlSize(size)
                        .build(k)
                }
            }
        )
}

@Suite("SwitchSnapTests")
struct SwitchSnapTests {
    /// The knob of every compact switch size sits as far from the top of its track as from the
    /// bottom on the device grid, at scales where its 2 pt inset is a fraction of a pixel.
    // PORT NOTE: Blocked on Sources/Rune fractional-scale device-pixel snapping for absolute children.
    @Test(.disabled("Blocked on Sources/Rune fractional-scale device-pixel snapping for absolute children"))
    func compactSwitchKnobsSitCentredOnDevicePixels() {
        let scales: [Float] = [1.2, 1.25, 1.5, 1.75]
        for scale in scales {
            let rt = Runtime.new((), switchSnapView, (120.0, 240.0), Env.new(true, scale))
            _ = rt.frame(0.0)
            let els = rt.elements()
            // The painted rect (device px edges) drawn for an element's rect.
            let drawn = { (r: [Float]) -> [Float] in
                let want: [Float] = [
                    r[0] * scale,
                    r[1] * scale,
                    (r[0] + r[2]) * scale,
                    (r[1] + r[3]) * scale,
                ]
                guard let found = rt.instances
                    .filter({ $0.params[1] == KIND_RECT || $0.params[1] == KIND_GRADIENT })
                    .map({ [$0.rect[0], $0.rect[1], $0.rect[0] + $0.rect[2], $0.rect[1] + $0.rect[3]] })
                    .first(where: { e in (0..<4).allSatisfy { k in abs(e[k] - want[k]) <= 1.01 } })
                else {
                    Issue.record("\(scale)×: nothing drawn at \(want)")
                    return [0, 0, 0, 0]
                }
                return found
            }
            let thumbs = els.filter { $0.path.hasSuffix("/thumb") }
            #expect(thumbs.count == switchSizes.count * 2)
            for thumb in thumbs {
                let trackPath = String(thumb.path.dropLast("/thumb".count))
                let track = els.first(where: { $0.path == trackPath })!
                let t = drawn(track.rect)
                let k = drawn(thumb.rect)
                #expect(
                    (t + k).allSatisfy { $0.truncatingRemainder(dividingBy: 1.0) == 0.0 },
                    "\(scale)× \(thumb.path): \(t) \(k)"
                )
                #expect(
                    k[1] - t[1] == t[3] - k[3],
                    "\(scale)× \(thumb.path): track \(t), knob \(k)"
                )
            }
        }
    }
}
