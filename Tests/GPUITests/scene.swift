// Swift-only: Behavioral and shader memory layout tests for GPUI Scene graph and render primitives

import Testing
@testable import GPUI

@Suite("Scene & GPU Render Primitives Tests")
struct SceneTests {

    // MARK: - 1. GPU Memory Layout & Field Offset Tests

    @Test("GPU Primitive Struct Sizes, Strides, and Alignments")
    func testPrimitiveMemoryLayouts() {
        // Quad: 160 bytes
        #expect(MemoryLayout<Quad>.size == 160)
        #expect(MemoryLayout<Quad>.stride == 160)
        #expect(MemoryLayout<Quad>.alignment == 4)

        // Shadow: 72 bytes
        #expect(MemoryLayout<Shadow>.size == 72)
        #expect(MemoryLayout<Shadow>.stride == 72)
        #expect(MemoryLayout<Shadow>.alignment == 4)

        // Underline: 64 bytes
        #expect(MemoryLayout<Underline>.size == 64)
        #expect(MemoryLayout<Underline>.stride == 64)
        #expect(MemoryLayout<Underline>.alignment == 4)

        // MonochromeSprite: 112 bytes
        #expect(MemoryLayout<MonochromeSprite>.size == 112)
        #expect(MemoryLayout<MonochromeSprite>.stride == 112)
        #expect(MemoryLayout<MonochromeSprite>.alignment == 4)

        // SubpixelSprite: 112 bytes
        #expect(MemoryLayout<SubpixelSprite>.size == 112)
        #expect(MemoryLayout<SubpixelSprite>.stride == 112)
        #expect(MemoryLayout<SubpixelSprite>.alignment == 4)

        // PolychromeSprite: 96 bytes
        #expect(MemoryLayout<PolychromeSprite>.size == 96)
        #expect(MemoryLayout<PolychromeSprite>.stride == 96)
        #expect(MemoryLayout<PolychromeSprite>.alignment == 4)

        // TransformationMatrix: 24 bytes
        #expect(MemoryLayout<TransformationMatrix>.size == 24)
        #expect(MemoryLayout<TransformationMatrix>.stride == 24)
        #expect(MemoryLayout<TransformationMatrix>.alignment == 4)

        // PathVertex<ScaledPixels>: 32 bytes
        #expect(MemoryLayout<PathVertex<ScaledPixels>>.size == 32)
        #expect(MemoryLayout<PathVertex<ScaledPixels>>.stride == 32)
        #expect(MemoryLayout<PathVertex<ScaledPixels>>.alignment == 4)

        // AtlasTile: 32 bytes
        #expect(MemoryLayout<AtlasTile>.size == 32)
        #expect(MemoryLayout<AtlasTile>.stride == 32)
        #expect(MemoryLayout<AtlasTile>.alignment == 4)
    }

    @Test("GPU Struct Field Offsets")
    func testFieldOffsets() {
        // Quad offsets
        #expect(MemoryLayout<Quad>.offset(of: \.order) == 0)
        #expect(MemoryLayout<Quad>.offset(of: \.borderStyle) == 4)
        #expect(MemoryLayout<Quad>.offset(of: \.bounds) == 8)
        #expect(MemoryLayout<Quad>.offset(of: \.contentMask) == 24)
        #expect(MemoryLayout<Quad>.offset(of: \.background) == 40)
        #expect(MemoryLayout<Quad>.offset(of: \.borderColor) == 112)
        #expect(MemoryLayout<Quad>.offset(of: \.cornerRadii) == 128)
        #expect(MemoryLayout<Quad>.offset(of: \.borderWidths) == 144)

        // Shadow offsets
        #expect(MemoryLayout<Shadow>.offset(of: \.order) == 0)
        #expect(MemoryLayout<Shadow>.offset(of: \.blurRadius) == 4)
        #expect(MemoryLayout<Shadow>.offset(of: \.bounds) == 8)
        #expect(MemoryLayout<Shadow>.offset(of: \.cornerRadii) == 24)
        #expect(MemoryLayout<Shadow>.offset(of: \.contentMask) == 40)
        #expect(MemoryLayout<Shadow>.offset(of: \.color) == 56)

        // Underline offsets
        #expect(MemoryLayout<Underline>.offset(of: \.order) == 0)
        #expect(MemoryLayout<Underline>.offset(of: \.pad) == 4)
        #expect(MemoryLayout<Underline>.offset(of: \.bounds) == 8)
        #expect(MemoryLayout<Underline>.offset(of: \.contentMask) == 24)
        #expect(MemoryLayout<Underline>.offset(of: \.color) == 40)
        #expect(MemoryLayout<Underline>.offset(of: \.thickness) == 56)
        #expect(MemoryLayout<Underline>.offset(of: \.wavy) == 60)

        // MonochromeSprite offsets
        #expect(MemoryLayout<MonochromeSprite>.offset(of: \.order) == 0)
        #expect(MemoryLayout<MonochromeSprite>.offset(of: \.pad) == 4)
        #expect(MemoryLayout<MonochromeSprite>.offset(of: \.bounds) == 8)
        #expect(MemoryLayout<MonochromeSprite>.offset(of: \.contentMask) == 24)
        #expect(MemoryLayout<MonochromeSprite>.offset(of: \.color) == 40)
        #expect(MemoryLayout<MonochromeSprite>.offset(of: \.tile) == 56)
        #expect(MemoryLayout<MonochromeSprite>.offset(of: \.transformation) == 88)

        // SubpixelSprite offsets
        #expect(MemoryLayout<SubpixelSprite>.offset(of: \.order) == 0)
        #expect(MemoryLayout<SubpixelSprite>.offset(of: \.pad) == 4)
        #expect(MemoryLayout<SubpixelSprite>.offset(of: \.bounds) == 8)
        #expect(MemoryLayout<SubpixelSprite>.offset(of: \.contentMask) == 24)
        #expect(MemoryLayout<SubpixelSprite>.offset(of: \.color) == 40)
        #expect(MemoryLayout<SubpixelSprite>.offset(of: \.tile) == 56)
        #expect(MemoryLayout<SubpixelSprite>.offset(of: \.transformation) == 88)

        // PolychromeSprite offsets
        #expect(MemoryLayout<PolychromeSprite>.offset(of: \.order) == 0)
        #expect(MemoryLayout<PolychromeSprite>.offset(of: \.pad) == 4)
        #expect(MemoryLayout<PolychromeSprite>.offset(of: \.grayscale) == 8)
        #expect(MemoryLayout<PolychromeSprite>.offset(of: \.opacity) == 12)
        #expect(MemoryLayout<PolychromeSprite>.offset(of: \.bounds) == 16)
        #expect(MemoryLayout<PolychromeSprite>.offset(of: \.contentMask) == 32)
        #expect(MemoryLayout<PolychromeSprite>.offset(of: \.cornerRadii) == 48)
        #expect(MemoryLayout<PolychromeSprite>.offset(of: \.tile) == 64)

        // AtlasTile offsets
        #expect(MemoryLayout<AtlasTile>.offset(of: \.textureId) == 0)
        #expect(MemoryLayout<AtlasTile>.offset(of: \.tileId) == 8)
        #expect(MemoryLayout<AtlasTile>.offset(of: \.padding) == 12)
        #expect(MemoryLayout<AtlasTile>.offset(of: \.bounds) == 16)

        // TransformationMatrix offsets
        #expect(MemoryLayout<TransformationMatrix>.offset(of: \.rotationScale) == 0)
        #expect(MemoryLayout<TransformationMatrix>.offset(of: \.translation) == 16)

        // PathVertex<ScaledPixels> offsets
        #expect(MemoryLayout<PathVertex<ScaledPixels>>.offset(of: \.xyPosition) == 0)
        #expect(MemoryLayout<PathVertex<ScaledPixels>>.offset(of: \.stPosition) == 8)
        #expect(MemoryLayout<PathVertex<ScaledPixels>>.offset(of: \.contentMask) == 16)
    }

    // MARK: - 2. TransformationMatrix Operations

    @Test("TransformationMatrix Unit, Translation, Scaling, Rotation, and Composition")
    func testTransformationMatrix() {
        let unit = TransformationMatrix.unit
        let p = Point(x: Pixels(10.0), y: Pixels(20.0))
        let applied = unit.apply(p)
        #expect(applied.x.value == 10.0)
        #expect(applied.y.value == 20.0)

        // Translation
        let translated = unit.translate(Point(x: ScaledPixels(5.0), y: ScaledPixels(-3.0)))
        let pTranslated = translated.apply(p)
        #expect(pTranslated.x.value == 15.0)
        #expect(pTranslated.y.value == 17.0)

        // Scale
        let scaled = unit.scale(Size(width: 2.0, height: 3.0))
        let pScaled = scaled.apply(p)
        #expect(pScaled.x.value == 20.0)
        #expect(pScaled.y.value == 60.0)

        // Rotate 90 degrees (pi/2)
        let rotated = unit.rotate(Radians(.pi / 2.0))
        let pRotated = rotated.apply(Point(x: Pixels(1.0), y: Pixels(0.0)))
        #expect(abs(pRotated.x.value - 0.0) < 1e-4)
        #expect(abs(pRotated.y.value - 1.0) < 1e-4)

        // Compose: Scale then Translate
        let combined = translated.compose(scaled)
        let pCombined = combined.apply(Point(x: Pixels(10.0), y: Pixels(10.0)))
        // scaled point: (20, 30), translated by (5, -3): (25, 27)
        #expect(pCombined.x.value == 25.0)
        #expect(pCombined.y.value == 27.0)
    }

    // MARK: - 3. Culling & Spatial Z-Ordering

    @Test("Primitive Empty Bounds Culling")
    func testEmptyBoundsCulling() {
        var scene = Scene()

        // 1. Zero-size bounds quad
        let zeroQuad = Quad(
            bounds: Bounds(origin: .zero, size: .zero),
            contentMask: ContentMask<ScaledPixels>(bounds: Bounds(origin: .zero, size: Size(width: 100, height: 100)))
        )
        scene.insertQuad(zeroQuad)
        #expect(scene.quads.isEmpty)
        #expect(scene.count == 0)

        // 2. Disjoint bounds and content mask
        let disjointQuad = Quad(
            bounds: Bounds(origin: Point(x: 200, y: 200), size: Size(width: 50, height: 50)),
            contentMask: ContentMask<ScaledPixels>(bounds: Bounds(origin: .zero, size: Size(width: 100, height: 100)))
        )
        scene.insertQuad(disjointQuad)
        #expect(scene.quads.isEmpty)
        #expect(scene.count == 0)

        // 3. Valid overlapping bounds
        let validQuad = Quad(
            bounds: Bounds(origin: Point(x: 50, y: 50), size: Size(width: 100, height: 100)),
            contentMask: ContentMask<ScaledPixels>(bounds: Bounds(origin: .zero, size: Size(width: 200, height: 200)))
        )
        scene.insertQuad(validQuad)
        #expect(scene.quads.count == 1)
        #expect(scene.count == 1)
        #expect(scene.quads[0].order == 1)
    }

    @Test("Spatial Z-Ordering via BoundsTree")
    func testSpatialZOrdering() {
        var scene = Scene()
        let mask = ContentMask<ScaledPixels>(bounds: Bounds(origin: .zero, size: Size(width: 1000, height: 1000)))

        // Two disjoint quads: can share draw order
        let quad1 = Quad(
            bounds: Bounds(origin: Point(x: 0, y: 0), size: Size(width: 50, height: 50)),
            contentMask: mask
        )
        let quad2 = Quad(
            bounds: Bounds(origin: Point(x: 100, y: 100), size: Size(width: 50, height: 50)),
            contentMask: mask
        )
        scene.insertQuad(quad1)
        scene.insertQuad(quad2)

        #expect(scene.quads.count == 2)
        #expect(scene.quads[0].order == 1)
        #expect(scene.quads[1].order == 1) // Disjoint -> shares order 1

        // Third quad overlaps quad1: must receive higher draw order
        let quad3 = Quad(
            bounds: Bounds(origin: Point(x: 25, y: 25), size: Size(width: 50, height: 50)),
            contentMask: mask
        )
        scene.insertQuad(quad3)
        #expect(scene.quads.count == 3)
        #expect(scene.quads[2].order == 2)
    }

    // MARK: - 4. Layer Stack & Layer Isolation

    @Test("Layer Stack Order Isolation")
    func testLayerStackIsolation() {
        var scene = Scene()
        let mask = ContentMask<ScaledPixels>(bounds: Bounds(origin: .zero, size: Size(width: 1000, height: 1000)))

        let baseQuad = Quad(
            bounds: Bounds(origin: Point(x: 0, y: 0), size: Size(width: 100, height: 100)),
            contentMask: mask
        )
        scene.insertQuad(baseQuad)
        #expect(scene.quads[0].order == 1)

        // Push layer with bounds [0, 0, 200, 200] -> layer order becomes 2
        scene.pushLayer(bounds: Bounds(origin: .zero, size: Size(width: 200, height: 200)))

        // All primitives inside layer inherit layer's fixed order
        let child1 = Quad(
            bounds: Bounds(origin: Point(x: 10, y: 10), size: Size(width: 20, height: 20)),
            contentMask: mask
        )
        let child2 = Quad(
            bounds: Bounds(origin: Point(x: 15, y: 15), size: Size(width: 20, height: 20)),
            contentMask: mask
        )
        scene.insertQuad(child1)
        scene.insertQuad(child2)

        #expect(scene.quads[1].order == 2)
        #expect(scene.quads[2].order == 2) // Within layer, shares layer order

        scene.popLayer()

        // Outside layer, overlapping with layer bounds receives order 3
        let postQuad = Quad(
            bounds: Bounds(origin: Point(x: 50, y: 50), size: Size(width: 50, height: 50)),
            contentMask: mask
        )
        scene.insertQuad(postQuad)
        #expect(scene.quads[3].order == 3)
    }

    // MARK: - 5. Path Construction & Triangulation

    @Test("Vector Path Construction, Triangles, and Scaling")
    func testPathConstruction() {
        var path = Path(start: Point(x: Pixels(0), y: Pixels(0)))
        path.lineTo(Point(x: Pixels(100), y: Pixels(0)))
        path.lineTo(Point(x: Pixels(100), y: Pixels(100)))

        #expect(path.bounds.origin.x.value == 0)
        #expect(path.bounds.origin.y.value == 0)
        #expect(path.bounds.size.width.value == 100)
        #expect(path.bounds.size.height.value == 100)
        #expect(path.vertices.count == 3) // 1 triangle pushed (3 vertices)

        let scaled = path.scale(2.0)
        #expect(scaled.bounds.size.width.value == 200)
        #expect(scaled.bounds.size.height.value == 200)
        #expect(scaled.vertices.count == 3)
        #expect(scaled.vertices[1].xyPosition.x.value == 200)
    }

    // MARK: - 6. Finish Sorting & Batch Generation

    @Test("Scene Finish Sorting and Batch Iterator")
    func testFinishSortingAndBatching() {
        var scene = Scene()
        let mask = ContentMask<ScaledPixels>(bounds: Bounds(origin: .zero, size: Size(width: 1000, height: 1000)))

        let tile0 = AtlasTile(
            textureId: AtlasTextureId(index: 0, kind: .monochrome),
            tileId: TileId(1),
            padding: 0,
            bounds: Bounds(origin: Point(x: 0, y: 0), size: Size(width: 16, height: 16))
        )
        let tile1 = AtlasTile(
            textureId: AtlasTextureId(index: 1, kind: .monochrome),
            tileId: TileId(2),
            padding: 0,
            bounds: Bounds(origin: Point(x: 0, y: 0), size: Size(width: 16, height: 16))
        )

        // In Scene, insertPrimitive assigns order based on spatial hierarchy via BoundsTree.
        // shadow1 is inserted first -> order 1.
        // shadow0 overlaps shadow1 -> order 2.
        // quad0 overlaps previous bounds -> order 3.
        // quad1 overlaps -> order 4.
        // sprite0 and sprite1 overlap -> order 5.
        let shadow1 = Shadow(bounds: Bounds(origin: Point(x: 10, y: 10), size: Size(width: 50, height: 50)), contentMask: mask)
        let shadow0 = Shadow(bounds: Bounds(origin: Point(x: 0, y: 0), size: Size(width: 50, height: 50)), contentMask: mask)
        scene.insertShadow(shadow1)
        scene.insertShadow(shadow0)

        let quad0 = Quad(bounds: Bounds(origin: Point(x: 5, y: 5), size: Size(width: 40, height: 40)), contentMask: mask)
        let quad1 = Quad(bounds: Bounds(origin: Point(x: 15, y: 15), size: Size(width: 40, height: 40)), contentMask: mask)
        scene.insertQuad(quad0)
        scene.insertQuad(quad1)

        let sprite0 = MonochromeSprite(bounds: Bounds(origin: Point(x: 2, y: 2), size: Size(width: 10, height: 10)), contentMask: mask, tile: tile0)
        let sprite1 = MonochromeSprite(bounds: Bounds(origin: Point(x: 4, y: 4), size: Size(width: 10, height: 10)), contentMask: mask, tile: tile1)
        scene.insertMonochromeSprite(sprite0)
        scene.insertMonochromeSprite(sprite1)

        scene.finish()

        // Check sorted arrays
        #expect(scene.shadows[0].order == 1)
        #expect(scene.shadows[1].order == 2)
        #expect(scene.quads[0].order == 3)
        #expect(scene.quads[1].order == 4)
        #expect(scene.monochromeSprites[0].order == 4)
        #expect(scene.monochromeSprites[1].order == 5)

        // Verify batches coalesce consecutive primitives of the same kind
        var batches: [PrimitiveBatch] = []
        for batch in scene.batches() {
            batches.append(batch)
        }

        #expect(batches.count == 4)

        // Consecutive shadows (order 1, 2) coalesce into 0..<2
        if case .shadows(let range) = batches[0] {
            #expect(range == 0..<2)
        } else {
            Issue.record("Expected shadows batch (0..<2), got \(batches[0])")
        }

        // Consecutive quads (order 3, 4) coalesce into 0..<2
        if case .quads(let range) = batches[1] {
            #expect(range == 0..<2)
        } else {
            Issue.record("Expected quads batch (0..<2), got \(batches[1])")
        }

        // Sprites at order 5 split on texture ID
        if case .monochromeSprites(let texId, let range) = batches[2] {
            #expect(texId.index == 0)
            #expect(range == 0..<1)
        } else {
            Issue.record("Expected monochromeSprites(0) batch, got \(batches[2])")
        }

        if case .monochromeSprites(let texId, let range) = batches[3] {
            #expect(texId.index == 1)
            #expect(range == 1..<2)
        } else {
            Issue.record("Expected monochromeSprites(1) batch, got \(batches[3])")
        }
    }

    @Test("Interleaved Primitive Batches Without GPU Thrashing")
    func testInterleavedBatching() {
        var scene = Scene()
        let mask = ContentMask<ScaledPixels>(bounds: Bounds(origin: .zero, size: Size(width: 1000, height: 1000)))

        // Layer 1: Shadow
        scene.pushLayer(bounds: Bounds(origin: Point(x: 0, y: 0), size: Size(width: 100, height: 100)))
        scene.insertShadow(Shadow(bounds: Bounds(origin: Point(x: 10, y: 10), size: Size(width: 50, height: 50)), contentMask: mask))
        scene.popLayer()

        // Layer 2: Quad
        scene.pushLayer(bounds: Bounds(origin: Point(x: 0, y: 0), size: Size(width: 100, height: 100)))
        scene.insertQuad(Quad(bounds: Bounds(origin: Point(x: 10, y: 10), size: Size(width: 50, height: 50)), contentMask: mask))
        scene.popLayer()

        // Layer 3: Shadow
        scene.pushLayer(bounds: Bounds(origin: Point(x: 0, y: 0), size: Size(width: 100, height: 100)))
        scene.insertShadow(Shadow(bounds: Bounds(origin: Point(x: 10, y: 10), size: Size(width: 50, height: 50)), contentMask: mask))
        scene.popLayer()

        // Layer 4: Quad
        scene.pushLayer(bounds: Bounds(origin: Point(x: 0, y: 0), size: Size(width: 100, height: 100)))
        scene.insertQuad(Quad(bounds: Bounds(origin: Point(x: 10, y: 10), size: Size(width: 50, height: 50)), contentMask: mask))
        scene.popLayer()

        scene.finish()

        #expect(scene.shadows[0].order == 1)
        #expect(scene.quads[0].order == 2)
        #expect(scene.shadows[1].order == 3)
        #expect(scene.quads[1].order == 4)

        var batches: [PrimitiveBatch] = []
        for batch in scene.batches() {
            batches.append(batch)
        }

        #expect(batches.count == 4)
        if case .shadows(let r) = batches[0] { #expect(r == 0..<1) } else { Issue.record("Batch 0 failure") }
        if case .quads(let r) = batches[1] { #expect(r == 0..<1) } else { Issue.record("Batch 1 failure") }
        if case .shadows(let r) = batches[2] { #expect(r == 1..<2) } else { Issue.record("Batch 2 failure") }
        if case .quads(let r) = batches[3] { #expect(r == 1..<2) } else { Issue.record("Batch 3 failure") }
    }

    // MARK: - 7. Subtree Replay

    @Test("Subtree Paint Operation Replay")
    func testSubtreeReplay() {
        var baseScene = Scene()
        let mask = ContentMask<ScaledPixels>(bounds: Bounds(origin: .zero, size: Size(width: 1000, height: 1000)))

        let quad1 = Quad(bounds: Bounds(origin: Point(x: 10, y: 10), size: Size(width: 50, height: 50)), contentMask: mask)
        let quad2 = Quad(bounds: Bounds(origin: Point(x: 20, y: 20), size: Size(width: 50, height: 50)), contentMask: mask)
        baseScene.insertQuad(quad1)
        baseScene.pushLayer(bounds: Bounds(origin: Point(x: 0, y: 0), size: Size(width: 200, height: 200)))
        baseScene.insertQuad(quad2)
        baseScene.popLayer()

        #expect(baseScene.count == 4)

        var newScene = Scene()
        newScene.replay(range: 0..<baseScene.count, prevScene: baseScene)

        #expect(newScene.count == 4)
        #expect(newScene.quads.count == 2)
        #expect(newScene.quads[0].bounds == quad1.bounds)
        #expect(newScene.quads[1].bounds == quad2.bounds)
    }
}
