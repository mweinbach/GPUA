// Tests ported from: crates/gpui/src/elements/text.rs (#[cfg(test)] items)
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Testing
@testable import GPUI

@Suite("Text Element Tests")
struct TextElementTests {
    @Test
    func test_into_element_for() {
        let _ = div().child("static str")
        let _ = div().child(String("String"))
        let _ = div().child(SharedString("SharedString"))
    }
}
