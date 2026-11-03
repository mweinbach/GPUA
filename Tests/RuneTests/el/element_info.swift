// Tests ported from: crates/rune/src/el/element_info.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("ElementInfoTests")
struct ElementInfoTests {
    @Test("a stub matches what a plain keyed element reports")
    func aStubMatchesWhatAPlainKeyedElementReports() {
        let rt = Runtime((), { _, _ in el().key("send") }, (100.0, 100.0), Env.new(true, 1.0))
        _ = rt.frame(0.0)
        guard let real = rt.elements().first(where: { $0.key == "send" }) else {
            Issue.record("expected keyed element 'send' in Runtime.elements()")
            return
        }
        var stub = ElementInfo.stub("send")
        stub.rect = real.rect
        stub.target = real.target
        stub.visible = real.visible
        stub.path = real.path
        #expect(stub == real)
        #expect(stub.role == real.role)
        #expect(stub.opacity == real.opacity)
        #expect(stub.scale == real.scale)
        #expect(stub.fill == real.fill)

        var focused = ElementInfo.stub("send")
        focused.focused = true
        #expect(focused.key == "send")
        #expect(focused.path == "send")
        #expect(focused.focused)
        #expect(focused.opacity == 1.0)
    }
}
