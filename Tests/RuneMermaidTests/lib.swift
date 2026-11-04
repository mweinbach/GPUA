// Tests ported from: crates/rune-mermaid/src/lib.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

// PORT NOTE: Upstream `lib.rs` delegates its main test suite via `#[path = "tests.rs"]` to `tests.swift`;
// this file additionally exercises the public RuneKit and dual-engine `renderScene` contracts.
import Testing
import Rune
@testable import RuneMermaid

@Suite struct LibContractTests {
    @Test func publicContractsAndRenderScene() {
        #expect(Hover.default == .edges)
        #expect(Hover.off != Hover.neighbours)

        let light = DiagramStyle.neutral(false)
        let dark = DiagramStyle.neutral(true)
        #expect(light != dark)
        var negZero = light
        negZero.maxWidth = -0.0
        var posZero = light
        posZero.maxWidth = 0.0
        #expect(negZero == posZero)
        #expect(negZero.hashValue == posZero.hashValue)

        let src = """
        ---
        title: Deployment Flow
        ---
        flowchart LR
            A[Build] --> B{Verify}
            B -->|pass| C([Ship])
        """
        #expect(supported(src))
        #expect(mayDraw(src))
        #expect(mayDraw("%% comment only\n"))
        #expect(!mayDraw("notADiagram\nfoo"))
        #expect(!supported("notADiagram\nfoo"))

        #expect(render(src, dark) != nil)
        #expect(renderWithHover(src, dark, .neighbours, dark.text) != nil)
        #expect(renderStreaming("flowchart LR\n    A --> B", dark, .edges, dark.text) != nil)
        #expect(renderStreamed(src, dark, .edges, dark.text) != nil)

        let snap = renderScene(src, dark)
        #expect(snap != nil)
        if let snap = snap {
            #expect(snap.title == "Deployment Flow")
            #expect(snap.size.count == 2 && snap.size[0] > 0 && snap.size[1] > 0)
            #expect(snap.full.count == 2 && snap.full[0] >= snap.size[0])
            #expect(snap.scale > 0 && snap.scale <= 1.0)
            #expect(!snap.ops.isEmpty)
            #expect(snap.labels.contains { $0.text == "Build" })
            #expect(snap.labels.contains { $0.text == "Verify" })
            #expect(snap.labels.contains { $0.text == "Ship" })
            #expect(snap.labels.contains { $0.text == "pass" })
        }
        #expect(renderScene("notADiagram", dark) == nil)
    }
}
