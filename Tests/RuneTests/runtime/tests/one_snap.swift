// Tests ported from: crates/rune/src/runtime/tests/one_snap.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Foundation
@testable import Rune
import RuneMotion
import Testing

// PORT NOTE: Headless `RuneTests` validates concentric fill / icon / shape-canvas / heading-text
// pixel snapping and centre agreement directly from `Runtime.instances` geometry moments in device
// pixels (matching the GPU quad raster inputs without requiring a live wgpu surface).

private let rtRingIcon = Icon(name: "ring", view: 24.0, body: "<circle cx='12' cy='12' r='9' stroke='currentColor' stroke-width='2' fill='none'/>")
private let rtDiscIcon = Icon(name: "disc", view: 24.0, body: "<circle cx='12' cy='12' r='10' fill='currentColor'/>")

private func rtDiscShape(_ radius: Float, _ center: Float) -> Shape {
    let n = 64
    var pts: [[Float]] = []
    pts.reserveCapacity(n)
    for k in 0..<n {
        let ang = Double(k) * (2.0 * Double.pi / Double(n))
        pts.append([center + Float(cos(ang)) * radius, center + Float(sin(ang)) * radius])
    }
    return Shape.new().fill(pts, .WHITE)
}

private func rtWeightedCentroid(_ instances: [Instance], kind: Float) -> (Float, Float)? {
    var sumW: Float = 0.0
    var sumX: Float = 0.0
    var sumY: Float = 0.0
    for inst in instances where inst.params[1] == kind && inst.fill[3] > 0.01 {
        if kind == KIND_TRIANGLE {
            // Exact geometric triangle vertices: a = (radii[0], radii[1]), b = (radii[2], radii[3]), c = (uv[0], uv[1])
            let ax = inst.radii[0], ay = inst.radii[1]
            let bx = inst.radii[2], by = inst.radii[3]
            let cx = inst.uv[0], cy = inst.uv[1]
            let area = 0.5 * abs((bx - ax) * (cy - ay) - (cx - ax) * (by - ay))
            guard area > 0.0 else { continue }
            sumW += area
            sumX += ((ax + bx + cx) / 3.0) * area
            sumY += ((ay + by + cy) / 3.0) * area
        } else {
            let area = max(inst.rect[2], 0.0) * max(inst.rect[3], 0.0)
            guard area > 0.0 else { continue }
            let cx = inst.rect[0] + inst.rect[2] * 0.5
            let cy = inst.rect[1] + inst.rect[3] * 0.5
            sumW += area
            sumX += cx * area
            sumY += cy * area
        }
    }
    guard sumW > 0.0 else { return nil }
    return (sumX / sumW, sumY / sumW)
}

@Suite
struct RtOneSnapTests {
    @Test
    func concentricFillIconAndCanvasSnapAtRestAndTrackCentresThroughMotion() {
        struct SnapState {
            var shifted: Bool = false
            var useIcon: Bool = false
        }

        let rt = Runtime.new(SnapState(), { s, _ in
            let inner: El = s.useIcon
                ? icon(rtDiscIcon, 24.0).key("mark")
                : canvas(rtDiscShape(10.0, 12.0)).key("mark").size(24.0, 24.0)
            var badge = rtAbsolute(
                rtScale(
                    col()
                        .key("badge")
                        .size(24.0, 24.0)
                        .bg(.WHITE)
                        .child(inner),
                    1.6
                ),
                s.shifted ? 53.3 : 20.25,
                s.shifted ? 47.7 : 18.25
            )
            badge.animateLayoutFlag = true
            return col()
                .size(200.0, 160.0)
                .child(badge)
                .child(
                    rtAnchored(
                        icon(rtRingIcon, 24.0).key("pop"),
                        Anchor(key: "badge", side: .bottom, align: .center, gap: 6.0)
                    )
                )
        }, (200.0, 160.0), Env.new(true, 2.0))

        _ = rt.frame(0.0)
        // Resting rect edges snap to whole device pixels
        if let badgeFill = rt.instances.first(where: { $0.params[1] == KIND_RECT }) {
            for edge in badgeFill.rect {
                #expect(abs(edge - edge.rounded()) < 1e-3)
            }
        } else {
            Issue.record("Expected resting KIND_RECT instance for badge")
        }

        if let cRect = rtWeightedCentroid(rt.instances, kind: KIND_RECT),
           let cTri = rtWeightedCentroid(rt.instances, kind: KIND_TRIANGLE) {
            #expect(abs(cRect.0 - cTri.0) <= 0.125)
            #expect(abs(cRect.1 - cTri.1) <= 0.125)
        }

        // Diagonal motion keeps fill and shape centres aligned frame-by-frame
        rt.update { s, _ in s.shifted = true }
        for _ in 0..<20 {
            _ = rt.frame(1.0 / 120.0)
            if let cRect = rtWeightedCentroid(rt.instances, kind: KIND_RECT),
               let cTri = rtWeightedCentroid(rt.instances, kind: KIND_TRIANGLE) {
                #expect(abs(cRect.0 - cTri.0) <= 0.125)
                #expect(abs(cRect.1 - cTri.1) <= 0.125)
            }
        }

        // Swapping canvas -> icon preserves concentric centre agreement
        rt.settleAll()
        rt.update { s, tx in
            tx.instant()
            s.useIcon = true
        }
        _ = rt.frame(1.0 / 120.0)
        if let badgeRect = rt.instances.first(where: { $0.params[1] == KIND_RECT })?.rect,
           let iconInst = rt.instances.first(where: { $0.params[1] == KIND_GLYPH })?.rect {
            let bx = badgeRect[0] + badgeRect[2] * 0.5
            let by = badgeRect[1] + badgeRect[3] * 0.5
            let ix = iconInst[0] + iconInst[2] * 0.5
            let iy = iconInst[1] + iconInst[3] * 0.5
            #expect(abs(bx - ix) <= 0.125)
            #expect(abs(by - iy) <= 0.125)
        }
    }

    @Test
    func headingTextGlidesSubpixelSmoothlyWithItsCard() {
        let rt = Runtime.new(false, { moved, _ in
            let card = rtAnimateLayout(
                rtAbsolute(
                    col()
                        .key("card")
                        .size(160.0, 48.0)
                        .bg(.WHITE)
                        .child(text("Heading").key("h").font(TextStyle(size: 24.0, weight: 700.0))),
                    moved ? 64.0 : 12.0,
                    20.0
                )
            )
            return col().size(280.0, 120.0).child(card)
        }, (280.0, 120.0), Env.new(true, 2.0))

        _ = rt.frame(0.0)
        rt.update { moved, _ in moved = true }
        var xs: [Float] = []
        for _ in 0..<24 {
            _ = rt.frame(1.0 / 120.0)
            if let g = rt.instances.first(where: { $0.params[1] == KIND_GLYPH }) {
                xs.append(g.rect[0])
            }
        }
        #expect(xs.count == 24)
        for i in 1..<xs.count {
            #expect(xs[i] >= xs[i - 1] - 1e-3)
        }
        let hasFractionalStep = xs.contains { abs($0 - $0.rounded()) > 0.02 }
        #expect(hasFractionalStep)
    }
}
