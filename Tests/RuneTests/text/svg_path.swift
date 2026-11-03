// Tests ported from: crates/rune/src/text/svg_path.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("SVG 2 path parser")
struct SvgPathTests {
    private func pt(_ x: Float, _ y: Float) -> VectorPoint {
        VectorPoint(x, y)
    }

    private func parse(_ d: String) -> [PathCommand] {
        (try? parseSvgPath(d).get()) ?? []
    }

    private func near(_ a: [PathCommand], _ b: [PathCommand]) -> Bool {
        func close(_ p: VectorPoint, _ q: VectorPoint) -> Bool {
            abs(p.x - q.x) < 1e-4 && abs(p.y - q.y) < 1e-4
        }
        guard a.count == b.count else { return false }
        for (lhs, rhs) in zip(a, b) {
            switch (lhs, rhs) {
            case (.moveTo(let p), .moveTo(let q)), (.lineTo(let p), .lineTo(let q)):
                if !close(p, q) { return false }
            case (.quadTo(let p1, let p2), .quadTo(let q1, let q2)):
                if !close(p1, q1) || !close(p2, q2) { return false }
            case (.curveTo(let p1, let p2, let p3), .curveTo(let q1, let q2, let q3)):
                if !close(p1, q1) || !close(p2, q2) || !close(p3, q3) { return false }
            case (.close, .close):
                break
            default:
                return false
            }
        }
        return true
    }

    private func check(_ d: String, _ want: [PathCommand], sourceLocation: SourceLocation = #_sourceLocation) {
        let got = parse(d)
        #expect(near(got, want), "\(d)\n got \(got)\nwant \(want)", sourceLocation: sourceLocation)
    }

    @Test("smooth_cubic_after_a_non_curve_starts_at_the_current_point")
    func smoothCubicAfterNonCurveStartsAtCurrentPoint() {
        check("M1 8s2.5-4.5 7-4.5", [.moveTo(pt(1.0, 8.0)), .curveTo(pt(1.0, 8.0), pt(3.5, 3.5), pt(8.0, 3.5))])
        check(
            "M0 0L4 0S6 2 8 0",
            [.moveTo(pt(0.0, 0.0)), .lineTo(pt(4.0, 0.0)), .curveTo(pt(4.0, 0.0), pt(6.0, 2.0), pt(8.0, 0.0))]
        )
        check(
            "M0 0Q2 2 4 0S6 2 8 0",
            [.moveTo(pt(0.0, 0.0)), .quadTo(pt(2.0, 2.0), pt(4.0, 0.0)), .curveTo(pt(4.0, 0.0), pt(6.0, 2.0), pt(8.0, 0.0))]
        )
        check(
            "M0 0C1 1 2 1 3 0T6 0",
            [.moveTo(pt(0.0, 0.0)), .curveTo(pt(1.0, 1.0), pt(2.0, 1.0), pt(3.0, 0.0)), .quadTo(pt(3.0, 0.0), pt(6.0, 0.0))]
        )
    }

    @Test("smooth_curves_reflect_the_previous_control_point")
    func smoothCurvesReflectPreviousControlPoint() {
        check(
            "M0 0C1 2 3 2 4 0S7-2 8 0",
            [
                .moveTo(pt(0.0, 0.0)),
                .curveTo(pt(1.0, 2.0), pt(3.0, 2.0), pt(4.0, 0.0)),
                .curveTo(pt(5.0, -2.0), pt(7.0, -2.0), pt(8.0, 0.0))
            ]
        )
        check(
            "M0 0c1 2 3 2 4 0s3-2 4 0 3 2 4 0",
            [
                .moveTo(pt(0.0, 0.0)),
                .curveTo(pt(1.0, 2.0), pt(3.0, 2.0), pt(4.0, 0.0)),
                .curveTo(pt(5.0, -2.0), pt(7.0, -2.0), pt(8.0, 0.0)),
                .curveTo(pt(9.0, 2.0), pt(11.0, 2.0), pt(12.0, 0.0))
            ]
        )
        check(
            "M0 0Q2 2 4 0T8 0t4 0",
            [
                .moveTo(pt(0.0, 0.0)),
                .quadTo(pt(2.0, 2.0), pt(4.0, 0.0)),
                .quadTo(pt(6.0, -2.0), pt(8.0, 0.0)),
                .quadTo(pt(10.0, 2.0), pt(12.0, 0.0))
            ]
        )
    }

    @Test("arc_flags_may_be_packed_without_separators")
    func arcFlagsMayBePackedWithoutSeparators() {
        let spaced = parse("M2 4a2 2 0 0 1 4 0")
        let packed = parse("M2 4a2 2 0 014 0")
        let commas = parse("M2,4a2,2,0,0,1,4,0")
        #expect(spaced.count > 1)
        #expect(near(spaced, packed))
        #expect(near(spaced, commas))
        if case .curveTo(_, _, let end)? = packed.last {
            #expect(abs(end.x - 6.0) < 1e-4 && abs(end.y - 4.0) < 1e-4)
        } else {
            Issue.record("Expected final CurveTo in \(packed)")
        }
        let passesTop = packed.contains { cmd in
            if case .curveTo(_, _, let p) = cmd {
                return abs(p.y - 2.0) < 1e-3
            }
            return false
        }
        #expect(passesTop)
        #expect(near(parse("M0 0a1 1 0 0 1 1 1 1 1 0 0 1 1 1"), parse("M0 0a1 1 0 011 1 1 1 0 011 1")))
    }

    @Test("degenerate_arcs_follow_the_spec")
    func degenerateArcsFollowSpec() {
        check("M0 0A0 5 0 0 1 4 4", [.moveTo(pt(0.0, 0.0)), .lineTo(pt(4.0, 4.0))])
        check("M1 1a3 3 0 0 1 0 0L2 2", [.moveTo(pt(1.0, 1.0)), .lineTo(pt(2.0, 2.0))])
        let half = parse("M0 0A1 1 0 0 1 10 0")
        let scaledToHalf = half.contains { cmd in
            if case .curveTo(_, _, let p) = cmd {
                return abs(p.y + 5.0) < 1e-3
            }
            return false
        }
        #expect(scaledToHalf)
    }

    @Test("implicit_repeats_and_moveto_linetos")
    func implicitRepeatsAndMovetoLinetos() {
        check("M1 1 2 2 3 3", [.moveTo(pt(1.0, 1.0)), .lineTo(pt(2.0, 2.0)), .lineTo(pt(3.0, 3.0))])
        check("m1 1 2 2 3 3", [.moveTo(pt(1.0, 1.0)), .lineTo(pt(3.0, 3.0)), .lineTo(pt(6.0, 6.0))])
        check(
            "M0 0h1 2v3-1",
            [.moveTo(pt(0.0, 0.0)), .lineTo(pt(1.0, 0.0)), .lineTo(pt(3.0, 0.0)), .lineTo(pt(3.0, 3.0)), .lineTo(pt(3.0, 2.0))]
        )
        check("M0 0H5 2V1", [.moveTo(pt(0.0, 0.0)), .lineTo(pt(5.0, 0.0)), .lineTo(pt(2.0, 0.0)), .lineTo(pt(2.0, 1.0))])
    }

    @Test("relative_segments_follow_the_current_point_and_close")
    func relativeSegmentsFollowCurrentPointAndClose() {
        check(
            "M10 10l5 0L20 20l-5 5zl1 1",
            [
                .moveTo(pt(10.0, 10.0)),
                .lineTo(pt(15.0, 10.0)),
                .lineTo(pt(20.0, 20.0)),
                .lineTo(pt(15.0, 25.0)),
                .close,
                .lineTo(pt(11.0, 11.0))
            ]
        )
        check("M1 1m2 2 1 0", [.moveTo(pt(1.0, 1.0)), .moveTo(pt(3.0, 3.0)), .lineTo(pt(4.0, 3.0))])
        check("M1 1zm2 2", [.moveTo(pt(1.0, 1.0)), .close, .moveTo(pt(3.0, 3.0))])
    }

    @Test("numbers_split_on_signs_dots_and_exponents")
    func numbersSplitOnSignsDotsAndExponents() {
        check("M2.3.4L-1-2", [.moveTo(pt(2.3, 0.4)), .lineTo(pt(-1.0, -2.0))])
        check("M1e1 2E-1L+.5-.5e1", [.moveTo(pt(10.0, 0.2)), .lineTo(pt(0.5, -5.0))])
        check(" \n M 1 , 2 L 3,4 ", [.moveTo(pt(1.0, 2.0)), .lineTo(pt(3.0, 4.0))])
    }

    @Test("errors_keep_what_came_before")
    func errorsKeepWhatCameBefore() {
        check("M1 1L2 2L3", [.moveTo(pt(1.0, 1.0)), .lineTo(pt(2.0, 2.0))])
        check("M1 1L2 2X4 4", [.moveTo(pt(1.0, 1.0)), .lineTo(pt(2.0, 2.0))])
        check("L1 1", [])
        check("M0 0z1 1", [.moveTo(pt(0.0, 0.0)), .close])
    }
}
