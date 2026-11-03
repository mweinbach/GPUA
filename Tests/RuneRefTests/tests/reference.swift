// Tests ported from: crates/rune-ref/tests/reference.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import RuneRef

private func renderRef(_ s: Scene) -> Frame {
    switch s.validate() {
    case .success:
        break
    case .failure(let err):
        Issue.record("Scene validation failed: \(err)")
    }
    var f = Frame.new(s.width, s.height, true)
    f.render(s)
    return f
}

private let GOLDENS: [(UInt64, String)] = [
    (0, "5e088c1baedc7566a4e71463e45ff92414b9bbb58f21df56277c507e08295334"),
    (1, "c48c3e78e0a63647b14260d367f3effdabacb32f4c0db9e3467d4748d07247f7"),
    (2, "009a65177c67a53ff49fc69fe9b3e17c1a436a94dfc2b1415efcbf6c9c4fd430"),
    (3, "33cc6a8473ee1286b5d193150de60fcb9306ac5af5c232b0cc87ce7fdb0fd469"),
    (4, "8f0aec5e52f7f1dc6b01af3d70ed81e17676b8e5b43aeb4c21221682c49425b2"),
    (5, "9d9179361efb9a826de3fbffdfb4f5ca7bb72da842a7ff05d2ef2460095ab480"),
    (6, "686716d1736d8edeff9b8b8b4bc50e375e915080017f9781b35efa22969dedff"),
    (7, "6ac1ba68fc6974b7bc665b2e1371dd1e8c6b0ae58081cd49e00e8bd361c426bd"),
    (8, "753737b57da4bc8d7767d7f8fef997ea704a181528b29263db315a6c9951c487"),
    (9, "11bbff630a8451cfe679bf74e3245e252d631a38233ce5b119cb8972dcd86fdf"),
    (10, "effb1d2ac03fb43505f73c8677b07426bcc1755183377a7466942b427241be10"),
    (11, "053171854c18393c558a229ed83cbb4747c71ea2641d6f63a8e56586c26e8d5c"),
    (12, "3fc01f03759ccad03ea46770c964c05857795dce5534562f283868acbb658401"),
    (13, "f02b3aad0edb3137588424a234440d0f44e683f65570b6974209cae36c32be3a"),
    (14, "8359601b6505daac7fa74904328cd39099f9f08100c179d01b55d08d3b71f9e2"),
    (15, "ae88e8be634b437a2d4f1f02393f146df63de2178cc2fd1e1094d711c334c1f2"),
]

@Suite("RuneRef Reference Tests")
struct RuneRefReferenceTests {
    @Test("metamorphic properties across 128 generated scenes")
    func metamorphic() {
        var rngState: UInt64 = 0x1234_5678_9abc_def0
        func nextByte() -> UInt8 {
            rngState = rngState &+ 0x9e3779b97f4a7c15
            var z = rngState
            z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
            z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
            return UInt8(truncatingIfNeeded: z ^ (z >> 31))
        }

        for caseIdx in 0..<128 {
            let recordCount = caseIdx % 8
            let records: [[UInt8]] = (0..<recordCount).map { _ in
                (0..<32).map { _ in nextByte() }
            }
            let scene = generate.scene(records)
            let original = renderRef(scene)

            var shifted = scene
            shifted.width += 4
            shifted.height += 6
            generate.translate(&shifted, 4.0, 6.0)
            let actual = renderRef(shifted)
            for y in 0..<Int(scene.height) {
                let a = Array(original.rgba[(y * Int(scene.width) * 4)..<((y + 1) * Int(scene.width) * 4)])
                let start = ((y + 6) * Int(shifted.width) + 4) * 4
                let b = Array(actual.rgba[start..<(start + a.count)])
                #expect(a == b)
            }

            // Transparent primitives preserve both bytes and provenance.
            var transparent = scene
            for var p in scene.primitives {
                p.fill = [0.0, 0.0, 0.0, 0.0]
                p.border = [0.0, 0.0, 0.0, 0.0]
                if p.params[1] == 4.0 {
                    p.uv = [0.0, 0.0, 0.0, 0.0]
                }
                transparent.primitives.append(p)
            }
            let actualTransparent = renderRef(transparent)
            #expect(original.rgba == actualTransparent.rgba)
            #expect(original.owners == actualTransparent.owners)

            // Full viewport clip equals no clip at all pixel centers, including edges.
            var full = scene
            for i in full.primitives.indices {
                full.primitives[i].clip = NO_CLIP
                full.primitives[i].fade = [0.0, 0.0, 0.0, 0.0]
            }
            let unclipped = renderRef(full)
            for i in full.primitives.indices {
                full.primitives[i].clip = [0.0, 0.0, 64.0, 64.0]
            }
            #expect(unclipped.rgba == renderRef(full).rgba)

            // Two independently generated groups separated by hard clips cannot interact.
            var disjoint = scene
            for i in disjoint.primitives.indices {
                disjoint.primitives[i].clip = [0.0, 0.0, 31.0, 64.0]
                disjoint.primitives[i].fade = [0.0, 0.0, 0.0, 0.0]
            }
            let leftCount = disjoint.primitives.count
            for var p in scene.primitives {
                p.rect[0] += 32.0
                p.clip = [32.0, 0.0, 64.0, 64.0]
                p.fade = [0.0, 0.0, 0.0, 0.0]
                disjoint.primitives.append(p)
            }
            let firstRender = renderRef(disjoint)
            if leftCount > 0 && leftCount < disjoint.primitives.count {
                let tail = Array(disjoint.primitives[leftCount...])
                let head = Array(disjoint.primitives[..<leftCount])
                disjoint.primitives = tail + head
            }
            #expect(firstRender.rgba == renderRef(disjoint).rgba)
        }
    }

    @Test("provenance and diff name the source")
    func provenanceAndDiffNameTheSource() {
        var s = generate.scene([[UInt8](repeating: 0, count: 32)])
        s.primitives[0].rect = [2.0, 2.0, 10.0, 10.0]
        s.primitives[0].fill = [1.0, 1.0, 1.0, 1.0]
        let f = renderRef(s)
        #expect(f.blame(s, 5, 5)?.source == "generated/0")
        #expect(f.blame(s, 63, 63) == nil)
        var bad = f.rgba
        bad[(5 * 64 + 5) * 4] = 0
        let diff = compare(s, f, bad, 2)
        #expect(diff.outlierPixels == 1)
        #expect(diff.first?.node == 1)
    }

    @Test("canonical BLAKE3 hashes match goldens.json")
    func canonicalHashes() {
        #expect(blake3Hex([]) == "af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262")
        for (seed, expectedHash) in GOLDENS {
            let actualHash = renderRef(generate.seeded(seed, 8)).hash()
            #expect(actualHash == expectedHash, "seed \(seed): got \(actualHash), expected \(expectedHash)")
        }
    }

    @Test("dashed rings translate and stay inside their ring")
    func dashedRingsTranslateAndStayInsideTheirRing() {
        for seed: UInt64 in 0..<32 {
            let scene = generate.dashed(seed, 8)
            let original = renderRef(scene)
            var shifted = scene
            shifted.width += 4
            shifted.height += 6
            generate.translate(&shifted, 4.0, 6.0)
            let actual = renderRef(shifted)
            for y in 0..<64 {
                let a = Array(original.rgba[(y * 256)..<((y + 1) * 256)])
                let b = Array(actual.rgba[(((y + 6) * 68 + 4) * 4)..<(((y + 6) * 68 + 68) * 4)])
                #expect(a == b)
            }
            for p in scene.primitives {
                var one = scene
                one.primitives = [p]
                let dashed = renderRef(one)
                one.primitives[0].params[1] = 4.0
                one.primitives[0].uv = one.primitives[0].border
                one.primitives[0].border = one.primitives[0].fill
                one.primitives[0].fill = [0.0, 0.0, 0.0, 0.0]
                let solid = renderRef(one)
                let dOwners = dashed.owners!
                let sOwners = solid.owners!
                for n in 0..<dOwners.count {
                    #expect(dOwners[n] == nil || sOwners[n] != nil, "seed \(seed): pixel \(n) dashed outside the ring")
                }
            }
        }
    }

    @Test("effect slots are accepted and draw nothing")
    func effectSlotsAreAcceptedAndDrawNothing() {
        for seed: UInt64 in 0..<16 {
            let scene = generate.seeded(seed, 8)
            var slotted = scene
            for (n, p) in scene.primitives.enumerated().reversed() {
                var slot = p
                slot.source = "effect/\(n)"
                slot.fill = [0.0, 0.0, 0.0, 1.0]
                slot.border = [0.0, 0.0, 0.0, 0.0]
                slot.params = [0.0, 12.0, 6.0, 1.0]
                slot.uv = [0.0, 0.0, 0.0, 0.0]
                if n % 3 == 0 {
                    slot.rect[2] = 0.0
                }
                slotted.primitives.insert(slot, at: n)
            }
            let a = renderRef(scene)
            let b = renderRef(slotted)
            #expect(a.rgba == b.rgba, "seed \(seed)")
            for owner in b.owners! {
                if let idx = owner {
                    #expect(slotted.primitives[idx].params[1] != 12.0)
                }
            }
        }
    }

    @Test("glyph rotation turns clockwise and clips on screen")
    func glyphRotationTurnsClockwiseAndClipsOnScreen() {
        let fracPi2: Float = Float.pi * 0.5
        func renderGlyph(_ angle: Float, _ clip: [Float]) -> Frame {
            var s = generate.scene([])
            s.atlas.data = [UInt8](repeating: 0, count: s.atlas.data.count)
            for y in 1..<5 {
                for x in 1..<5 {
                    s.atlas.data[y * 32 + x] = 255
                }
            }
            var p = generate.scene([[UInt8](repeating: 0, count: 32)]).primitives[0]
            p.rect = [20.0, 20.0, 16.0, 16.0]
            p.radii = [0.0, 0.0, 0.0, 0.0]
            p.fill = [1.0, 1.0, 1.0, 1.0]
            p.params = [angle, 2.0, 0.0, 1.0]
            p.uv = [1.0, 1.0, 0.0, 0.0]
            p.clip = clip
            s.primitives.append(p)
            return renderRef(s)
        }
        func lit(_ f: Frame, _ x: UInt32, _ y: UInt32) -> Bool {
            f.rgba[Int((y * 64 + x) * 4)] == 255
        }
        let cw = renderGlyph(fracPi2, NO_CLIP)
        let ccw = renderGlyph(-fracPi2, NO_CLIP)
        #expect(cw.rgba != ccw.rgba)
        #expect(lit(cw, 34, 21) && !lit(cw, 21, 34) && !lit(cw, 21, 21))
        #expect(lit(ccw, 21, 34) && !lit(ccw, 34, 21) && !lit(ccw, 21, 21))
        let clipped = renderGlyph(fracPi2, [28.0, NO_CLIP[1], NO_CLIP[2], NO_CLIP[3]])
        #expect(lit(clipped, 34, 21) && !lit(clipped, 21, 34))
    }

    @Test("validate rejects layers it cannot render")
    func validateRejectsLayersItCannotRender() {
        func makeLayer(_ kind: Float, _ blur: Float) -> Primitive {
            Primitive(
                node: 1,
                source: "layer",
                rect: kind == 9.0 ? [0.0, 0.0, 0.0, 0.0] : [0.0, 0.0, 8.0, 8.0],
                radii: [0.0, 0.0, 0.0, 0.0],
                fill: [0.0, 0.0, 0.0, kind == 9.0 ? 0.0 : 1.0],
                border: [0.0, 0.0, 0.0, 0.0],
                params: [0.0, kind, blur, 0.0],
                uv: [0.0, 0.0, 0.0, 0.0],
                clip: NO_CLIP,
                fade: [0.0, 0.0, 0.0, 0.0],
                fadeOrigin: nil,
                turn: nil
            )
        }
        func isValid(_ primitives: [Primitive]) -> Bool {
            var s = generate.scene([])
            s.primitives = primitives
            if case .success = s.validate() { return true }
            return false
        }

        #expect(isValid([makeLayer(8.0, 0.0), makeLayer(9.0, 0.0)]))
        #expect(!isValid([makeLayer(9.0, 0.0)]))
        #expect(!isValid([makeLayer(8.0, 0.0)]))

        var malformed = makeLayer(8.0, 0.0)
        malformed.params[3] = 2.0
        #expect(!isValid([malformed, makeLayer(9.0, 0.0)]))

        var turned = makeLayer(8.0, 0.0)
        turned.turn = [0.4, 4.0, 4.0]
        #expect(isValid([turned, makeLayer(9.0, 0.0)]))

        turned.params[3] = 1.0
        #expect(!isValid([turned, makeLayer(9.0, 0.0)]))

        #expect(!isValid([makeLayer(8.0, 2.0), makeLayer(9.0, 0.0)]))

        let deep = (0..<1000).map { _ in makeLayer(8.0, 0.0) } + (0..<1000).map { _ in makeLayer(9.0, 0.0) }
        #expect(!isValid(deep))
    }
}
