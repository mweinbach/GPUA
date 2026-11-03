// Tests ported from: crates/rune/src/runtime/tests/layout_reads.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

@testable import Rune
import RuneMotion
import Testing

@Suite
struct RtLayoutReadsTests {
    @Test
    func fewAndManyReadsSeeTheSameRectsAndScopedKeysDisambiguate() {
        final class ReadProbe: @unchecked Sendable {
            var sizes: [[Float]?] = []
            var scopedCell3: [Float]? = nil
            var missing: [Float]? = nil
        }
        let probe = ReadProbe()

        let rt = Runtime.new(true, { many, cx in
            if many {
                probe.sizes = (0..<12).map { i in cx.layoutSize("cell\(i)") }
            } else {
                probe.sizes = [cx.layoutSize("cell0"), cx.layoutSize("cell3")]
            }
            probe.scopedCell3 = cx.layoutSize("panel/cell3")
            probe.missing = cx.layoutSize("missing")

            let other = col()
                .key("other")
                .children((0..<12).map { i in
                    el().key("cell\(i)").size(Float(1 + i), 10.0)
                })
            let panel = col()
                .key("panel")
                .children((0..<12).map { i in
                    el().key("cell\(i)").size(Float(30 + i), 10.0)
                })
            return row().size(300.0, 200.0).child(other).child(panel)
        }, (300.0, 200.0), Env.new(true, 1.0))

        _ = rt.frame(0.0)
        #expect(probe.sizes.count == 12)
        for i in 0..<12 {
            #expect(probe.sizes[i] == [Float(1 + i), 10.0])
        }
        #expect(probe.scopedCell3 == [33.0, 10.0])
        #expect(probe.missing == nil)

        rt.update { many, _ in many = false }
        _ = rt.frame(1.0 / 120.0)
        #expect(probe.sizes == [[1.0, 10.0], [4.0, 10.0]])
        #expect(probe.scopedCell3 == [33.0, 10.0])
    }

    @Test
    func windowLayoutMatchesScrolledElementRects() {
        final class WindowProbe: @unchecked Sendable {
            var row27: [Float]? = nil
            var row27Label: [Float]? = nil
        }
        let probe = WindowProbe()

        let rt = Runtime.new(0, { _, cx in
            probe.row27 = cx.windowLayout("r27")
            probe.row27Label = cx.windowLayout("r27/label")

            let rows = (0..<50).map { i in
                row()
                    .key("r\(i)")
                    .size(200.0, 40.0)
                    .child(el().key("label").size(80.0, 20.0))
            }
            return col()
                .key("list")
                .size(200.0, 200.0)
                .scroll(ScrollSpec(stickBottom: false))
                .children(rows)
        }, (200.0, 200.0), Env.new(true, 1.0))

        _ = rt.frame(0.0)
        rt.setScrollOffset("list", 1000.0, animated: false)
        rt.update { n, _ in n += 1 }
        _ = rt.frame(1.0 / 120.0)

        let expectedRow = rtElement(rt, "r27")?.rect
        #expect(probe.row27 == expectedRow)
        #expect(probe.row27 == [0.0, 80.0, 200.0, 40.0])
        #expect(probe.row27Label == [0.0, 80.0, 80.0, 20.0])
    }
}
