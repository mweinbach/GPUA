// Tests ported from: crates/rune/src/text/icon_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("Icon SVG coverage")
struct IconCoverageTests {
    private func centre(_ body: String) -> UInt8 {
        let icon = Icon(name: "t", view: 16.0, body: body)
        return iconCoverage(icon, 32)[16 * 32 + 16]
    }

    @Test("opacity_scales_an_elements_coverage")
    func opacityScalesElementsCoverage() {
        #expect(centre(#"<circle cx="8" cy="8" r="6" fill="currentColor"/>"#) == 255)
        let half = centre(#"<circle cx="8" cy="8" r="6" fill="currentColor" opacity=".5"/>"#)
        #expect((126...129).contains(half), "opacity .5 is half coverage, got \(half)")
        let fill = centre(#"<circle cx="8" cy="8" r="6" fill="currentColor" fill-opacity="0.25"/>"#)
        #expect((62...65).contains(fill), "fill-opacity, got \(fill)")
        let both = centre(#"<circle cx="8" cy="8" r="6" fill="currentColor" opacity=".5" fill-opacity=".5"/>"#)
        #expect((62...65).contains(both), "they multiply, got \(both)")
    }

    @Test("stroke_opacity_leaves_the_fill_alone")
    func strokeOpacityLeavesFillAlone() {
        let body = #"<rect x="0" y="0" width="16" height="16" fill="currentColor" stroke="currentColor" stroke-width="2" stroke-opacity=".3"/>"#
        #expect(centre(body) == 255)
    }
}
