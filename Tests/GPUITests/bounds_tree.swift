// Tests ported from: crates/gpui/src/bounds_tree.rs (#[cfg(test)] items)
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Testing
@testable import GPUI

/// Simple deterministic pseudo-random number generator for reproducible testing.
private struct TestRng {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed == 0 ? 0xdeadbeefcafebabe : seed
    }

    mutating func next() -> UInt64 {
        // Xorshift64star
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        return state &* 0x2545F4914F6CDD1D
    }

    mutating func randomRange(min: Float, max: Float) -> Float {
        let normalized = Float(next() % 100000) / 100000.0
        return min + (max - min) * normalized
    }

    mutating func randomInt(min: Int, max: Int) -> Int {
        let count = UInt64(max - min + 1)
        return min + Int(next() % count)
    }
}

@Suite("BoundsTree Tests")
struct BoundsTreeTests {

    // MARK: - Upstream test_insert
    // Ported from bounds_tree.rs line 375
    @Test("Upstream test_insert")
    func test_insert() {
        var tree = BoundsTree<Float>()
        let bounds1 = Bounds<Float>(
            origin: Point(x: 0.0, y: 0.0),
            size: Size(width: 10.0, height: 10.0)
        )
        let bounds2 = Bounds<Float>(
            origin: Point(x: 5.0, y: 5.0),
            size: Size(width: 10.0, height: 10.0)
        )
        let bounds3 = Bounds<Float>(
            origin: Point(x: 10.0, y: 10.0),
            size: Size(width: 10.0, height: 10.0)
        )

        // Insert the bounds into the tree and verify the order is correct
        #expect(tree.insert(bounds1) == 1)
        #expect(tree.insert(bounds2) == 2)
        #expect(tree.insert(bounds3) == 3)

        // Insert non-overlapping bounds and verify they can reuse orders
        let bounds4 = Bounds<Float>(
            origin: Point(x: 20.0, y: 20.0),
            size: Size(width: 10.0, height: 10.0)
        )
        let bounds5 = Bounds<Float>(
            origin: Point(x: 40.0, y: 40.0),
            size: Size(width: 10.0, height: 10.0)
        )
        let bounds6 = Bounds<Float>(
            origin: Point(x: 25.0, y: 25.0),
            size: Size(width: 10.0, height: 10.0)
        )

        #expect(tree.insert(bounds4) == 1) // bounds4 does not overlap with bounds1, bounds2, or bounds3
        #expect(tree.insert(bounds5) == 1) // bounds5 does not overlap with any other bounds
        #expect(tree.insert(bounds6) == 2) // bounds6 overlaps with bounds4, so it should have order 2
    }

    // MARK: - Upstream test_random_iterations
    // Ported from bounds_tree.rs line 432
    @Test("Upstream test_random_iterations across multiple seeds")
    func test_random_iterations() {
        let maxBounds = 50
        for seed in 1...200 {
            var tree = BoundsTree<Float>()
            var rng = TestRng(seed: UInt64(seed))
            var expectedQuads: [(bounds: Bounds<Float>, order: UInt32)] = []

            let numBounds = rng.randomInt(min: 1, max: maxBounds)
            for _ in 0..<numBounds {
                let minX = rng.randomRange(min: -100.0, max: 100.0)
                let minY = rng.randomRange(min: -100.0, max: 100.0)
                let width = rng.randomRange(min: 0.1, max: 50.0)
                let height = rng.randomRange(min: 0.1, max: 50.0)
                let b = Bounds(
                    origin: Point(x: minX, y: minY),
                    size: Size(width: width, height: height)
                )

                let maxIntersecting = expectedQuads
                    .filter { $0.bounds.intersects(b) }
                    .map { $0.order }
                    .max() ?? 0
                let expectedOrdering = maxIntersecting + 1

                expectedQuads.append((b, expectedOrdering))

                let actualOrdering = tree.insert(b)
                #expect(actualOrdering == expectedOrdering)
            }
        }
    }

    @Test("BoundsTree clear and reuse")
    func test_clear_and_reuse() {
        var tree = BoundsTree<Float>()
        let b1 = Bounds<Float>(origin: Point(x: 0, y: 0), size: Size(width: 10, height: 10))
        let b2 = Bounds<Float>(origin: Point(x: 5, y: 5), size: Size(width: 10, height: 10))

        #expect(tree.insert(b1) == 1)
        #expect(tree.insert(b2) == 2)

        tree.clear()

        #expect(tree.insert(b2) == 1)
        #expect(tree.insert(b1) == 2)
    }
}
