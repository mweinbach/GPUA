// Ported from: crates/rune/src/runtime/turn.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! 2D rotation (`Turn`) around a world-space pivot, bounding box expansion, and inverse hit-testing.

import RuneMotion

struct Turn: Sendable, Equatable {
    var angle: Float
    var pivot: [Float]

    static let none = Turn(angle: 0.0, pivot: [0.0, 0.0])

    init(angle: Float = 0.0, pivot: [Float] = [0.0, 0.0]) {
        self.angle = angle
        self.pivot = pivot.count >= 2 ? [pivot[0], pivot[1]] : [0.0, 0.0]
    }

    var isActive: Bool {
        abs(angle) > 1e-6
    }

    func apply(_ point: (Float, Float)) -> (Float, Float) {
        guard isActive else { return point }
        let (s, c) = RuneMotion.math.sinCos(angle)
        let dx = point.0 - pivot[0]
        let dy = point.1 - pivot[1]
        return (pivot[0] + dx * c - dy * s, pivot[1] + dx * s + dy * c)
    }

    func unturn(_ point: (Float, Float)) -> (Float, Float) {
        guard isActive else { return point }
        let (s, c) = RuneMotion.math.sinCos(-angle)
        let dx = point.0 - pivot[0]
        let dy = point.1 - pivot[1]
        return (pivot[0] + dx * c - dy * s, pivot[1] + dx * s + dy * c)
    }

    func bbox(_ rect: [Float]) -> [Float] {
        guard rect.count >= 4 else { return [0, 0, 0, 0] }
        guard isActive else { return [rect[0], rect[1], rect[2], rect[3]] }
        let x0 = rect[0]
        let y0 = rect[1]
        let x1 = x0 + rect[2]
        let y1 = y0 + rect[3]
        let c0 = apply((x0, y0))
        let c1 = apply((x1, y0))
        let c2 = apply((x1, y1))
        let c3 = apply((x0, y1))
        let minX = min(min(c0.0, c1.0), min(c2.0, c3.0))
        let minY = min(min(c0.1, c1.1), min(c2.1, c3.1))
        let maxX = max(max(c0.0, c1.0), max(c2.0, c3.0))
        let maxY = max(max(c0.1, c1.1), max(c2.1, c3.1))
        return [minX, minY, maxX - minX, maxY - minY]
    }

    func combined(_ childAngle: Float, _ childPivot: [Float]) -> Turn {
        if abs(childAngle) <= 1e-6 {
            return self
        }
        if !isActive {
            return Turn(angle: childAngle, pivot: childPivot)
        }
        let rotatedPivot = apply((childPivot[0], childPivot[1]))
        return Turn(angle: angle + childAngle, pivot: [rotatedPivot.0, rotatedPivot.1])
    }
}
