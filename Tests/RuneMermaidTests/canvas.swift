// Tests ported from: crates/rune-mermaid/src/canvas.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

// PORT NOTE: Verifies `Canvas` geometry, bounds, scaling, and dual-engine `DiagramScene` snapshot mapping.
import Testing
import Rune
@testable import RuneMermaid

@Suite struct CanvasTests {
    @Test func canvasBoundsFinishAndDiagramSceneMapping() {
        let style = DiagramStyle.neutral(false)
        var c = Canvas()
        #expect(c.bounds() == [0.0, 0.0, 0.0, 0.0])
        #expect(c.finishFit(style) == nil)

        let box = roundedRect(10.0, 20.0, 110.0, 70.0, 6.0)
        c.shape(box, style.nodeFill, style.nodeBorder, 1.5)
        let m = RuneMermaid.measure("Node", style.font)
        c.label(m, [60.0, 45.0], style.font, style.text, .center)

        let b = c.bounds()
        #expect(b[0] <= 10.0 && b[1] <= 20.0)
        #expect(b[2] >= 110.0 && b[3] >= 70.0)

        let scene = c.finishFit(style)?.withTitle("Canvas Title")
        #expect(scene != nil)
        if let scene = scene {
            let snap = scene.diagramScene()
            #expect(snap.title == "Canvas Title")
            #expect(snap.scale == 1.0)
            #expect(snap.size == snap.full)
            #expect(snap.ops.count == 2)
            #expect(snap.labels.count == 1)
            #expect(snap.labels[0].text == "Node")
            #expect(snap.labels[0].align == .center)
            for op in snap.ops {
                switch op {
                case .fill(let pts, _):
                    #expect(pts.allSatisfy { $0[0] >= 0.0 && $0[1] >= 0.0 })
                case .stroke(let pts, let closed, let width, _, _):
                    #expect(closed)
                    #expect(width > 0.0)
                    #expect(pts.allSatisfy { $0[0] >= 0.0 && $0[1] >= 0.0 })
                }
            }
        }
    }
}
