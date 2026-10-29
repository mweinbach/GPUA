// Swift-only: Unit tests for Canvas element which has no inline tests in upstream canvas.rs

import Testing
@testable import GPUI

@Suite("Canvas Element Tests")
struct CanvasTests {
    @Test
    @MainActor
    func testCanvasExecution() {
        let c = canvas({ bounds, window, cx in
            return 42
        }, { bounds, val, window, cx in
            _ = val
        })

        #expect(c.id() == nil)
        #expect(c.sourceLocation() == nil)
    }
}
