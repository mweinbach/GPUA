// Tests ported from: crates/rune/tests/alignment.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Flex alignment builders place children where CSS would.

import Testing
@testable import Rune

private func alignmentRect(_ rt: Runtime<UInt8>, _ key: String) -> [Float] {
    IntegrationSupport.find(rt, key).target
}

private func alignmentView(_ caseIdx: UInt8, _: Cx<UInt8>) -> El {
    let kids = [el().key("a").size(20.0, 10.0), el().key("b").size(20.0, 30.0)]
    let parent = row().key("parent").size(200.0, 60.0)
    switch caseIdx {
    case 0: return parent.itemsEnd().children(kids)
    case 1: return parent.itemsCenter().children(kids)
    case 2: return parent.children([el().key("a").size(20.0, 10.0).selfEnd(), el().key("b").w(20.0).selfStretch()])
    case 3: return parent.justifyCenter().children(kids)
    case 4: return parent.justifyAround().children(kids)
    case 5: return parent.justifyEvenly().children(kids)
    case 6: return col().key("parent").size(200.0, 60.0).itemsEnd().justifyCenter().justifyStart().children(kids)
    default: preconditionFailure("unreachable")
    }
}

@Suite("AlignmentIntegrationTests")
struct AlignmentIntegrationTests {
    @Test func alignmentBuildersMatchCss() {
        let expect: [(String, [Float], [Float])] = [
            ("items_end", [0.0, 50.0], [20.0, 30.0]),
            ("items_center", [0.0, 25.0], [20.0, 15.0]),
            ("self_end / self_stretch", [0.0, 50.0], [20.0, 0.0]),
            ("justify_center", [80.0, 0.0], [100.0, 0.0]),
            ("justify_around", [40.0, 0.0], [140.0, 0.0]),
            ("justify_evenly", [53.333, 0.0], [126.667, 0.0]),
            ("column items_end + justify_start", [180.0, 0.0], [180.0, 10.0]),
        ]
        for (caseIdx, (name, a, b)) in expect.enumerated() {
            let rt = IntegrationSupport.runtime(UInt8(caseIdx), alignmentView, (200.0, 60.0), Env.new(true, 1.0))
            _ = rt.hostFrame(0.0)
            for (key, at) in [("a", a), ("b", b)] {
                let r = alignmentRect(rt, key)
                #expect(abs(r[0] - at[0]) < 0.01 && abs(r[1] - at[1]) < 0.01, "\(name): \(key) at \(r), want \(at)")
            }
            if caseIdx == 2 {
                #expect(alignmentRect(rt, "b")[3] == 60.0, "self_stretch fills the cross axis")
            }
        }
    }
}
