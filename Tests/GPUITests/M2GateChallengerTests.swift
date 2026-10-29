// Swift-only: Milestone 2 Gate Challenger 2 empirical stress test harness

import Foundation
import Testing
@testable import GPUI

// MARK: - Test RNG Helper

private struct ChallengerRng {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed == 0 ? 0xdeadbeefcafebabe : seed
    }

    mutating func next() -> UInt64 {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        return state &* 0x2545F4914F6CDD1D
    }

    mutating func randomFloat(min: Float, max: Float) -> Float {
        let normalized = Float(next() % 100_000) / 100_000.0
        return min + (max - min) * normalized
    }

    mutating func randomInt(min: Int, max: Int) -> Int {
        let count = UInt64(max - min + 1)
        return min + Int(next() % count)
    }
}

// MARK: - Test Actions

private struct ActionSave: UnitAction {
    static let name = "challenger::ActionSave"
    init() {}
}

private struct ActionSplit: UnitAction {
    static let name = "challenger::ActionSplit"
    init() {}
}

private struct ActionPrefix: UnitAction {
    static let name = "challenger::ActionPrefix"
    init() {}
}

private struct ActionABC: UnitAction {
    static let name = "challenger::ActionABC"
    init() {}
}

private struct ActionB: UnitAction {
    static let name = "challenger::ActionB"
    init() {}
}

private struct ActionC: UnitAction {
    static let name = "challenger::ActionC"
    init() {}
}

private struct ActionOne: UnitAction {
    static let name = "challenger::ActionOne"
    init() {}
}

private struct ActionTwo: UnitAction {
    static let name = "challenger::ActionTwo"
    init() {}
}

// MARK: - 1. Dense Spatial R-tree Insertion Stress

@Suite("Challenger Suite 1: BoundsTree Dense Spatial R-tree Stress")
struct BoundsTreeDenseStressTests {

    @Test("Dense Overlapping Rectangles (250+ bounds x 5 seeds)")
    func testDenseOverlappingRectangles() {
        let seeds: [UInt64] = [42, 1337, 2026, 9999, 12345]

        for seed in seeds {
            var tree = BoundsTree<Float>()
            var rng = ChallengerRng(seed: seed)
            var groundTruthList: [(bounds: Bounds<Float>, order: UInt32)] = []

            let numRectangles = 250

            for i in 0..<numRectangles {
                // Generate clustered coordinates to maximize dense overlap
                let clusterCenterX = rng.randomFloat(min: -50.0, max: 50.0)
                let clusterCenterY = rng.randomFloat(min: -50.0, max: 50.0)
                let width = rng.randomFloat(min: 5.0, max: 40.0)
                let height = rng.randomFloat(min: 5.0, max: 40.0)

                let b = Bounds<Float>(
                    origin: Point(x: clusterCenterX - width / 2.0, y: clusterCenterY - height / 2.0),
                    size: Size(width: width, height: height)
                )

                // Compute ground truth order: 1 + max order of any intersecting preceding bounds
                var maxIntersectingOrder: UInt32 = 0
                for prev in groundTruthList {
                    if prev.bounds.intersects(b) {
                        maxIntersectingOrder = max(maxIntersectingOrder, prev.order)
                    }
                }
                let expectedOrder = maxIntersectingOrder + 1

                let actualOrder = tree.insert(b)

                #expect(
                    actualOrder == expectedOrder,
                    "Seed \(seed), Rect \(i): Expected order \(expectedOrder) but got \(actualOrder)"
                )

                groundTruthList.append((bounds: b, order: actualOrder))
            }

            // Verify global invariants over all 250 rectangles:
            // 1. Monotonic ordering: for every i < j, if bounds intersect, order[j] > order[i]
            for j in 0..<groundTruthList.count {
                let rectJ = groundTruthList[j]
                for i in 0..<j {
                    let rectI = groundTruthList[i]
                    if rectJ.bounds.intersects(rectI.bounds) {
                        #expect(
                            rectJ.order > rectI.order,
                            "Seed \(seed): Monotonicity violation: rect \(j) (order \(rectJ.order)) intersects rect \(i) (order \(rectI.order))"
                        )
                    }
                }
            }
        }
    }

    @Test("Shared Orders on Strictly Disjoint Bounds (15x15 Grid)")
    func testDisjointBoundsSharedOrders() {
        var tree = BoundsTree<Float>()

        // Create a 15x15 grid of 225 strictly disjoint rectangles separated by gap of 5.0
        let gridSize = 15
        let cellSize: Float = 10.0
        let gap: Float = 5.0

        var tier1Bounds: [Bounds<Float>] = []

        for row in 0..<gridSize {
            for col in 0..<gridSize {
                let x = Float(col) * (cellSize + gap)
                let y = Float(row) * (cellSize + gap)
                let b = Bounds<Float>(origin: Point(x: x, y: y), size: Size(width: cellSize, height: cellSize))

                let order = tree.insert(b)
                #expect(
                    order == 1,
                    "Tier 1 grid cell (\(col), \(row)) must share order 1 since all cells are strictly disjoint"
                )
                tier1Bounds.append(b)
            }
        }

        // Now insert Tier 2: 225 rectangles, each placed directly inside a Tier 1 cell.
        // Each overlaps exactly its corresponding Tier 1 cell, but is disjoint from all other cells.
        for (idx, tier1) in tier1Bounds.enumerated() {
            let innerB = Bounds<Float>(
                origin: Point(x: tier1.origin.x + 2.0, y: tier1.origin.y + 2.0),
                size: Size(width: tier1.size.width - 4.0, height: tier1.size.height - 4.0)
            )

            let order = tree.insert(innerB)
            #expect(
                order == 2,
                "Tier 2 cell \(idx) must have order 2 (overlapping Tier 1 cell with order 1, disjoint from other Tier 2 cells)"
            )
        }
    }

    @Test("Extreme Bounds Edge Cases (Zero size, touching edges, high aspect ratios, duplicates)")
    func testExtremeBoundsEdgeCases() {
        var tree = BoundsTree<Float>()

        // 1. Touching edges do not intersect
        let b1 = Bounds<Float>(origin: Point(x: 0, y: 0), size: Size(width: 10, height: 10))
        let bTouching = Bounds<Float>(origin: Point(x: 10, y: 0), size: Size(width: 10, height: 10))

        #expect(tree.insert(b1) == 1)
        #expect(tree.insert(bTouching) == 1) // Touching edges share order 1!

        // 2. High aspect ratios: thin horizontal and vertical cross
        let horizontalStrip = Bounds<Float>(origin: Point(x: -1000, y: 50), size: Size(width: 2000, height: 0.01))
        let verticalStrip = Bounds<Float>(origin: Point(x: 50, y: -1000), size: Size(width: 0.01, height: 2000))

        #expect(horizontalStrip.intersects(verticalStrip))
        let hOrder = tree.insert(horizontalStrip)
        let vOrder = tree.insert(verticalStrip)
        #expect(vOrder > hOrder)

        // 3. Repeated identical overlapping bounds
        let dup = Bounds<Float>(origin: Point(x: 200, y: 200), size: Size(width: 50, height: 50))
        var prevOrder: UInt32 = 0
        for _ in 1...20 {
            let o = tree.insert(dup)
            #expect(o == prevOrder + 1)
            prevOrder = o
        }
    }
}

// MARK: - 2. BatchIterator Coalescing & Texture Splitting Stress

@Suite("Challenger Suite 2: BatchIterator Coalescing & Texture Splitting Stress")
struct BatchIteratorCoalescingStressTests {

    @Test("Massive Contiguous Coalescing (500 primitives per kind)")
    func testMassiveContiguousCoalescing() {
        var scene = Scene()

        // 500 contiguous quads at order 1
        for i in 0..<500 {
            var q = Quad()
            q.order = 1
            q.bounds = Bounds(origin: Point(x: ScaledPixels(Float(i)), y: ScaledPixels(0)), size: Size(width: ScaledPixels(10), height: ScaledPixels(10)))
            scene.quads.append(q)
        }

        // 500 contiguous shadows at order 2
        for i in 0..<500 {
            var s = Shadow()
            s.order = 2
            s.bounds = Bounds(origin: Point(x: ScaledPixels(Float(i)), y: ScaledPixels(0)), size: Size(width: ScaledPixels(10), height: ScaledPixels(10)))
            scene.shadows.append(s)
        }

        scene.finish()
        var iterator = scene.batches()

        guard let batch1 = iterator.next() else {
            Issue.record("Expected first batch of quads")
            return
        }
        #expect(batch1 == .quads(0..<500))

        guard let batch2 = iterator.next() else {
            Issue.record("Expected second batch of shadows")
            return
        }
        #expect(batch2 == .shadows(0..<500))

        #expect(iterator.next() == nil)
    }

    @Test("Monochrome Sprite Texture Splitting on AtlasTextureId Changes")
    func testMonochromeSpriteTextureSplitting() {
        var scene = Scene()

        // Add 120 monochrome sprites across alternating textures at order 1:
        // Tex 1: 20 sprites (0..<20)
        // Tex 2: 30 sprites (20..<50)
        // Tex 1: 10 sprites (50..<60)
        // Tex 3: 40 sprites (60..<100)
        // Tex 2: 20 sprites (100..<120)
        let textureSegments: [(textureId: AtlasTextureId, count: Int)] = [
            (AtlasTextureId(index: 1, kind: .monochrome), 20),
            (AtlasTextureId(index: 2, kind: .monochrome), 30),
            (AtlasTextureId(index: 1, kind: .monochrome), 10),
            (AtlasTextureId(index: 3, kind: .monochrome), 40),
            (AtlasTextureId(index: 2, kind: .monochrome), 20)
        ]

        var totalIndex: UInt32 = 0
        for seg in textureSegments {
            for _ in 0..<seg.count {
                let tile = AtlasTile(
                    textureId: seg.textureId,
                    tileId: TileId(totalIndex),
                    padding: 0,
                    bounds: Bounds(origin: Point(x: DevicePixels(0), y: DevicePixels(0)), size: Size(width: DevicePixels(0), height: DevicePixels(0)))
                )
                let sprite = MonochromeSprite(order: 1, tile: tile)
                scene.monochromeSprites.append(sprite)
                totalIndex += 1
            }
        }

        scene.finish()
        var iterator = scene.batches()

        var currentStart = 0
        for seg in textureSegments {
            guard let batch = iterator.next() else {
                Issue.record("Missing batch for texture \(seg.textureId)")
                return
            }
            let expectedRange = currentStart..<(currentStart + seg.count)
            #expect(batch == .monochromeSprites(textureId: seg.textureId, range: expectedRange))
            currentStart += seg.count
        }

        #expect(iterator.next() == nil)
    }

    @Test("Interleaved Z-Order and Texture Coalescing Complex Scene")
    func testInterleavedZOrderAndTextureCoalescing() {
        var scene = Scene()

        // Construct multi-layered scene with diverse primitives and orders:
        // Layer 1 (order 1): 20 Quads
        for _ in 0..<20 {
            var q = Quad()
            q.order = 1
            scene.quads.append(q)
        }

        // Layer 2 (order 2): 15 Shadows
        for _ in 0..<15 {
            var s = Shadow()
            s.order = 2
            scene.shadows.append(s)
        }

        let tex1 = AtlasTextureId(index: 1, kind: .monochrome)
        let tex2 = AtlasTextureId(index: 2, kind: .monochrome)

        // Layer 3 (order 3): 10 Monochrome Sprites on Tex 1
        for i in 0..<10 {
            let tile = AtlasTile(
                textureId: tex1,
                tileId: TileId(UInt32(i)),
                padding: 0,
                bounds: Bounds(origin: Point(x: DevicePixels(0), y: DevicePixels(0)), size: Size(width: DevicePixels(0), height: DevicePixels(0)))
            )
            let m = MonochromeSprite(order: 3, tile: tile)
            scene.monochromeSprites.append(m)
        }

        // Layer 4 (order 3): 10 Monochrome Sprites on Tex 2
        for i in 0..<10 {
            let tile = AtlasTile(
                textureId: tex2,
                tileId: TileId(UInt32(10 + i)),
                padding: 0,
                bounds: Bounds(origin: Point(x: DevicePixels(0), y: DevicePixels(0)), size: Size(width: DevicePixels(0), height: DevicePixels(0)))
            )
            let m = MonochromeSprite(order: 3, tile: tile)
            scene.monochromeSprites.append(m)
        }

        // Layer 5 (order 4): 25 Quads
        for _ in 0..<25 {
            var q = Quad()
            q.order = 4
            scene.quads.append(q)
        }

        // Layer 6 (order 5): 8 Underlines
        for _ in 0..<8 {
            var u = Underline()
            u.order = 5
            scene.underlines.append(u)
        }

        scene.finish()
        var iterator = scene.batches()

        let b1 = iterator.next()
        #expect(b1 == .quads(0..<20))

        let b2 = iterator.next()
        #expect(b2 == .shadows(0..<15))

        let b3 = iterator.next()
        #expect(b3 == .monochromeSprites(textureId: tex1, range: 0..<10))

        let b4 = iterator.next()
        #expect(b4 == .monochromeSprites(textureId: tex2, range: 10..<20))

        let b5 = iterator.next()
        #expect(b5 == .quads(20..<45))

        let b6 = iterator.next()
        #expect(b6 == .underlines(0..<8))

        #expect(iterator.next() == nil)
    }
}

// MARK: - 3. Pratt Parser Precedence Stress

@Suite("Challenger Suite 3: Pratt Parser Precedence Stress")
struct PrattParserPrecedenceStressTests {

    @Test("Precedence of Mixed Operators: (A > B || C == x) && !D > E")
    func testMixedOperatorsExpression() throws {
        let expr = "(A > B || C == x) && !D > E"
        let predicate = try KeyBindingContextPredicate.parse(expr)

        // Expected AST derivation:
        // 1. (A > B || C == x):
        //    == (prec 4): C == x
        //    || (prec 2): B || (C == x)
        //    >  (prec 1): A > (B || (C == x))
        // 2. Right side: !D > E
        //    !  (prec 5): !D
        //    && (prec 3): (inner) && !D
        //    >  (prec 1): ((inner) && !D) > E
        let expectedInner = KeyBindingContextPredicate.descendant(
            .identifier("A"),
            .or(
                .identifier("B"),
                .equal("C", "x")
            )
        )
        let expected = KeyBindingContextPredicate.descendant(
            .and(
                expectedInner,
                .not(.identifier("D"))
            ),
            .identifier("E")
        )

        #expect(predicate == expected)
    }

    @Test("Literal Quote in Operator Expression: (A > B || C == \"x\") && !D > E")
    func testLiteralQuoteInOperatorExpression() {
        // In GPUI context syntax, identifiers are unquoted bare words (e.g. C == x).
        // The lexer treats `"` as a vim operator token (1 character).
        // Thus, `C == "x"` parses `C == "` as the equality expression, leaving `x")` as leftover tokens,
        // which triggers `expected a ')'` from the parenthesized expression parser.
        var didCatchExpectedParen = false
        do {
            _ = try KeyBindingContextPredicate.parse("(A > B || C == \"x\") && !D > E")
        } catch let err as ContextParseError {
            if case .expectedClosingParen = err {
                didCatchExpectedParen = true
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(didCatchExpectedParen == true)
    }

    @Test("Operator Precedence Strict Invariants: == vs && vs || vs > vs !")
    func testPrecedenceInvariants() throws {
        // 1. && binds tighter than ||: "A && B || C && D" == "(A && B) || (C && D)"
        let andOr = try KeyBindingContextPredicate.parse("A && B || C && D")
        let expectedAndOr = KeyBindingContextPredicate.or(
            .and(.identifier("A"), .identifier("B")),
            .and(.identifier("C"), .identifier("D"))
        )
        #expect(andOr == expectedAndOr)

        // 2. == binds tighter than &&: "A == B && C != D" == "(A == B) && (C != D)"
        let eqAnd = try KeyBindingContextPredicate.parse("A == B && C != D")
        let expectedEqAnd = KeyBindingContextPredicate.and(
            .equal("A", "B"),
            .notEqual("C", "D")
        )
        #expect(eqAnd == expectedEqAnd)

        // 3. ! binds tighter than &&: "!A && B" == "(!A) && B"
        let notAnd = try KeyBindingContextPredicate.parse("!A && B")
        let expectedNotAnd = KeyBindingContextPredicate.and(
            .not(.identifier("A")),
            .identifier("B")
        )
        #expect(notAnd == expectedNotAnd)

        // 4. && binds tighter than >: "A > B && C" == "A > (B && C)"
        let childAnd = try KeyBindingContextPredicate.parse("A > B && C")
        let expectedChildAnd = KeyBindingContextPredicate.descendant(
            .identifier("A"),
            .and(.identifier("B"), .identifier("C"))
        )
        #expect(childAnd == expectedChildAnd)
    }

    @Test("Deeply Parenthesized Expressions (10+ Levels)")
    func testDeeplyParenthesizedExpressions() throws {
        let deepParens = "((((((((((A))))))))))"
        let parsed = try KeyBindingContextPredicate.parse(deepParens)
        #expect(parsed == .identifier("A"))

        let nestedBinary = "((((A && B) || C) && D) || E)"
        let parsedNested = try KeyBindingContextPredicate.parse(nestedBinary)
        let expectedNested = KeyBindingContextPredicate.or(
            .and(
                .or(
                    .and(.identifier("A"), .identifier("B")),
                    .identifier("C")
                ),
                .identifier("D")
            ),
            .identifier("E")
        )
        #expect(parsedNested == expectedNested)
    }

    @Test("Context Evaluation with Complex Predicate")
    func testContextEvaluation() throws {
        let pred = try KeyBindingContextPredicate.parse("Editor && mode == full && !read_only")

        var ctx1 = KeyContext()
        ctx1.add("Editor")
        ctx1.set("mode", "full")

        #expect(pred.eval([ctx1]) == true)

        var ctx2 = ctx1
        ctx2.add("read_only")
        #expect(pred.eval([ctx2]) == false)

        var ctx3 = KeyContext()
        ctx3.add("Editor")
        ctx3.set("mode", "preview")
        #expect(pred.eval([ctx3]) == false)
    }

    @Test("Malformed Context Parse Errors")
    func testMalformedContextParseErrors() {
        // Missing closing paren
        #expect(throws: ContextParseError.self) {
            _ = try KeyBindingContextPredicate.parse("(A && B")
        }

        // Operands of == must be identifiers
        #expect(throws: ContextParseError.self) {
            _ = try KeyBindingContextPredicate.parse("(A && B) == C")
        }

        // Unexpected character
        #expect(throws: ContextParseError.self) {
            _ = try KeyBindingContextPredicate.parse("A @ B")
        }
    }
}

// MARK: - 4. Multi-Keystroke Chord State Machine Stress

@Suite("Challenger Suite 4: Multi-Keystroke Chord State Machine Stress")
struct MultiKeystrokeChordStateMachineStressTests {

    private func makeTree(bindings: [KeyBinding]) -> DispatchTree {
        let registry = ActionRegistry()
        registry.register(ActionSave.self)
        registry.register(ActionSplit.self)
        registry.register(ActionPrefix.self)
        registry.register(ActionABC.self)
        registry.register(ActionB.self)
        registry.register(ActionC.self)
        registry.register(ActionOne.self)
        registry.register(ActionTwo.self)
        return DispatchTree(keymap: Keymap(bindings: bindings), actionRegistry: registry)
    }

    @Test("Ambiguous Prefixes: ctrl-x ctrl-s vs ctrl-x s with Shared Prefix Binding")
    func testAmbiguousPrefixes() throws {
        let bindings = [
            KeyBinding(keystrokes: "ctrl-x", action: ActionPrefix(), context: nil),
            KeyBinding(keystrokes: "ctrl-x ctrl-s", action: ActionSave(), context: nil),
            KeyBinding(keystrokes: "ctrl-x s", action: ActionSplit(), context: nil),
        ]
        var tree = makeTree(bindings: bindings)
        let emptyPath: [DispatchNodeId] = []

        // 1. Dispatch "ctrl-x": should be pending, and pendingHasBinding should be true (since "ctrl-x" has ActionPrefix)
        let r1 = tree.dispatchKey([], try Keystroke.parse("ctrl-x"), emptyPath)
        #expect(r1.pending.count == 1)
        #expect(r1.pendingHasBinding == true)
        #expect(r1.bindings.isEmpty)

        // 2. Dispatch "ctrl-s": completes "ctrl-x ctrl-s" -> ActionSave
        let r2 = tree.dispatchKey(r1.pending, try Keystroke.parse("ctrl-s"), emptyPath)
        #expect(r2.pending.isEmpty)
        #expect(r2.bindings.count == 1)
        #expect(r2.bindings[0].action.isEqual(to: ActionSave()))

        // 3. Dispatch "ctrl-x" then "s": completes "ctrl-x s" -> ActionSplit
        let r3 = tree.dispatchKey([], try Keystroke.parse("ctrl-x"), emptyPath)
        let r4 = tree.dispatchKey(r3.pending, try Keystroke.parse("s"), emptyPath)
        #expect(r4.pending.isEmpty)
        #expect(r4.bindings.count == 1)
        #expect(r4.bindings[0].action.isEqual(to: ActionSplit()))

        // 4. Dispatch "ctrl-x" then unmatched "z": fallback replay of "ctrl-x" with ActionPrefix!
        let r5 = tree.dispatchKey([], try Keystroke.parse("ctrl-x"), emptyPath)
        let r6 = tree.dispatchKey(r5.pending, try Keystroke.parse("z"), emptyPath)
        #expect(r6.toReplay.count == 1)
        #expect(r6.toReplay[0].keystroke == (try Keystroke.parse("ctrl-x")))
        #expect(r6.toReplay[0].bindings.count == 1)
        #expect(r6.toReplay[0].bindings[0].action.isEqual(to: ActionPrefix()))
    }

    @Test("Chord Timeout and Flush Dispatch")
    func testChordTimeoutAndFlushDispatch() throws {
        let bindings = [
            KeyBinding(keystrokes: "ctrl-k", action: ActionPrefix(), context: nil),
            KeyBinding(keystrokes: "ctrl-k ctrl-c", action: ActionSave(), context: nil),
            KeyBinding(keystrokes: "alt-x alt-y", action: ActionSplit(), context: nil),
        ]
        let tree = makeTree(bindings: bindings)
        let emptyPath: [DispatchNodeId] = []

        // When ctrl-k times out, flushDispatch returns replay with ActionPrefix
        let flushed1 = tree.flushDispatch(input: [try Keystroke.parse("ctrl-k")], dispatchPath: emptyPath)
        #expect(flushed1.count == 1)
        #expect(flushed1[0].keystroke == (try Keystroke.parse("ctrl-k")))
        #expect(flushed1[0].bindings.count == 1)
        #expect(flushed1[0].bindings[0].action.isEqual(to: ActionPrefix()))

        // When alt-x times out (no binding on alt-x alone), flushDispatch returns replay with empty bindings
        let flushed2 = tree.flushDispatch(input: [try Keystroke.parse("alt-x")], dispatchPath: emptyPath)
        #expect(flushed2.count == 1)
        #expect(flushed2[0].keystroke == (try Keystroke.parse("alt-x")))
        #expect(flushed2[0].bindings.isEmpty)
    }

    @Test("Multi-chord Fallback Replay Cascade: a b c vs b vs c")
    func testMultiChordFallbackReplayCascade() throws {
        let bindings = [
            KeyBinding(keystrokes: "a b c", action: ActionABC(), context: nil),
            KeyBinding(keystrokes: "b", action: ActionB(), context: nil),
            KeyBinding(keystrokes: "c", action: ActionC(), context: nil),
        ]
        var tree = makeTree(bindings: bindings)
        let emptyPath: [DispatchNodeId] = []

        // Type "a", then "b"
        let r1 = tree.dispatchKey([], try Keystroke.parse("a"), emptyPath)
        #expect(r1.pending.count == 1)

        let r2 = tree.dispatchKey(r1.pending, try Keystroke.parse("b"), emptyPath)
        #expect(r2.pending.count == 2) // [a, b] pending for "a b c"

        // Now type unexpected "x" -> "a b x" fails "a b c"
        // Replay prefix should replay "a" (no binding), then evaluate "b x":
        // "b" matches ActionB, so "b" is replayed with ActionB, and "x" has no binding.
        let r3 = tree.dispatchKey(r2.pending, try Keystroke.parse("x"), emptyPath)
        #expect(r3.toReplay.count == 2)
        #expect(r3.toReplay[0].keystroke == (try Keystroke.parse("a")))
        #expect(r3.toReplay[0].bindings.isEmpty)
        #expect(r3.toReplay[1].keystroke == (try Keystroke.parse("b")))
        #expect(r3.toReplay[1].bindings.count == 1)
        #expect(r3.toReplay[1].bindings[0].action.isEqual(to: ActionB()))
    }

    @Test("NoAction and Unbind Precedence Overrides")
    func testNoActionAndUnbindOverrides() throws {
        // 1. Global NoAction suppresses earlier binding
        var keymap = Keymap()
        keymap.addBindings([
            KeyBinding(keystrokes: "ctrl-s", action: ActionSave(), context: nil),
            KeyBinding(keystrokes: "ctrl-s", action: NoAction(), context: nil),
        ])
        let res1 = keymap.bindingsForInput([try Keystroke.parse("ctrl-s")], [])
        #expect(res1.bindings.isEmpty)

        // 2. Contextual NoAction
        var keymapCtx = Keymap()
        keymapCtx.addBindings([
            KeyBinding(keystrokes: "ctrl-s", action: ActionSave(), context: "editor"),
            KeyBinding(keystrokes: "ctrl-s", action: NoAction(), context: "editor && read_only"),
        ])
        let editorCtx = [try KeyContext.parse("editor")]
        let readOnlyCtx = [try KeyContext.parse("editor read_only")]

        let resEditor = keymapCtx.bindingsForInput([try Keystroke.parse("ctrl-s")], editorCtx)
        #expect(resEditor.bindings.count == 1)
        #expect(resEditor.bindings[0].action.isEqual(to: ActionSave()))

        let resReadOnly = keymapCtx.bindingsForInput([try Keystroke.parse("ctrl-s")], readOnlyCtx)
        #expect(resReadOnly.bindings.isEmpty)

        // 3. NoAction cancels pending chord state
        var keymapPending = Keymap()
        keymapPending.addBindings([
            KeyBinding(keystrokes: "ctrl-k ctrl-s", action: ActionSave(), context: nil),
            KeyBinding(keystrokes: "ctrl-k ctrl-s", action: NoAction(), context: nil),
        ])
        let resPending = keymapPending.bindingsForInput([try Keystroke.parse("ctrl-k")], [])
        #expect(resPending.hasPending == false)

        // 4. Targeted Unbind: unbinds only the targeted action name, leaving other actions active
        var keymapUnbind = Keymap()
        keymapUnbind.addBindings([
            KeyBinding(keystrokes: "ctrl-t", action: ActionOne(), context: nil),
            KeyBinding(keystrokes: "ctrl-t", action: ActionTwo(), context: nil),
            KeyBinding(keystrokes: "ctrl-t", action: Unbind(SharedString("challenger::ActionOne")), context: nil),
        ])
        let resUnbind = keymapUnbind.bindingsForInput([try Keystroke.parse("ctrl-t")], [])
        #expect(resUnbind.bindings.count == 1)
        #expect(resUnbind.bindings[0].action.isEqual(to: ActionTwo()))
    }
}
