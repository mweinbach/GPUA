// Tests ported from: crates/rune-kit/src/notes_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune
@testable import RuneKit

private let sampleNote = """
Lead summary line.

> [!note]
> Attention callout paragraph.

```facts
Latency: {verified} 11.9 ms
Mode: `Rgba16Float`
```

```compare
Before: Software rasterized overlay loop.
After: Single-pass GPU uber-quad exposure.
```

```steps
{built} Shared shutter pass · verified
{proposed} Live preview window
```

```size
app +120 −30 · tests +45 −0 · 4 files
```

```rust title="shutter.rs" {2-3}
fn add_sample(c: Vec4, w: f32) -> Vec4 {
+   c * w
}
```
"""

private func hostView(_ src: String, _: Cx<String>) -> El {
    let k = Kit.neutral(true)
    return col().w(600.0).padding(16.0).child(Note.new(src).key("doc").build(k))
}

@Suite("NotesUnitTests")
struct NotesUnitTests {
    @Test func cutExtractsAllStructuredNoteBlocks() {
        let pieces = cut(sampleNote)
        #expect(pieces.count == 7)
        if case let .markdown(s) = pieces[0] {
            #expect(s.contains("Lead summary"))
        } else {
            Issue.record("expected Piece.markdown at 0")
        }
        if case let .callout(label, body) = pieces[1] {
            #expect(label == nil && body.contains("Attention"))
        } else {
            Issue.record("expected Piece.callout at 1")
        }
        if case let .facts(rows) = pieces[2] {
            #expect(rows.count == 2)
        } else {
            Issue.record("expected Piece.facts at 2")
        }
        if case let .compare(sides) = pieces[3] {
            #expect(sides.count == 2)
        } else {
            Issue.record("expected Piece.compare at 3")
        }
        if case let .steps(steps) = pieces[4] {
            #expect(steps.count == 2 && steps[0].status == "built")
        } else {
            Issue.record("expected Piece.steps at 4")
        }
        if case let .size(sz) = pieces[5] {
            #expect(sz.parts.count == 2 && sz.files == "4 files")
        } else {
            Issue.record("expected Piece.size at 5")
        }
        if case let .codeFence(title, marks, _) = pieces[6] {
            #expect(title == "shutter.rs" && marks == [2...3])
        } else {
            Issue.record("expected Piece.codeFence at 6")
        }
    }

    @Test func noteMountsAndLaysOutAllPrimitivesHeadlessly() {
        let rt = Runtime.new(sampleNote, hostView, (640.0, 900.0), Env.new(true, 2.0))
        _ = rt.frame(0.0)
        for idx in 0..<7 {
            let key = "doc/p\(idx)"
            guard let (rect, opacity) = rt.presented(key) else {
                Issue.record("missing piece \(key)")
                continue
            }
            let w = rect[2]
            let h = rect[3]
            #expect(w > 100.0 && h > 10.0, "\(key) has empty bounds \(w)x\(h)")
            #expect(opacity == 1.0)
        }
    }
}
