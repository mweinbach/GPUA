// Tests ported from: crates/rune-fx/src/fill.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import RuneFX

private func fillCard() -> Shape {
    Shape.rounded(20.0, 30.0, 160.0, 90.0, 14.0)
}

private func everyPreset() -> [(StyleInfo, Preset)] {
    fillStyles().flatMap { s in s.presets.map { p in (s, p) } }
}

private func packed(_ l: FxLayer) -> (InstRaw, [SIMD4<Float>])? {
    guard var (_, i, _) = l.pack() else { return nil }
    var data: [SIMD4<Float>] = []
    l.fill(&i, &data)
    return (i, data)
}

private func bits(_ i: InstRaw) -> [UInt32] {
    i.words()
}

private func allFinite(_ data: [SIMD4<Float>]) -> Bool {
    data.allSatisfy { v in v.x.isFinite && v.y.isFinite && v.z.isFinite && v.w.isFinite }
}

@Suite("RuneFX Fills")
struct FillUnitTests {
    @Test("idle_fills_are_culled")
    func idleFillsAreCulled() {
        for (s, p) in everyPreset() {
            #expect(Fx.fill(p.fill().intensity(0.0)).on(fillCard()).pack() == nil, "\(s.id) \(p.id)")
            #expect(Fx.fill(p.fill().intensity(.nan)).on(fillCard()).pack() == nil, "\(s.id) \(p.id)")
            #expect(Fx.fill(p.fill().border(-1.0)).on(fillCard()).pack() == nil)
            #expect(Fx.fill(p.fill().border(.nan)).on(fillCard()).pack() == nil)
            #expect(Fx.fill(p.fill().border(.infinity)).on(fillCard()).pack() == nil)
            #expect(Fx.fill(p.fill()).on(Shape.rounded(10.0, 10.0, 0.0, 40.0, 0.0)).pack() == nil, "\(s.id) \(p.id): zero width")
            #expect(Fx.fill(p.fill()).on(Shape.rounded(10.0, 10.0, 40.0, 0.0, 0.0)).pack() == nil, "\(s.id) \(p.id): zero height")
            #expect(Fx.fill(p.fill()).on(fillCard()).pack() != nil)
        }
    }

    @Test("reduced_motion_holds_one_pose")
    func reducedMotionHoldsOnePose() {
        for (s, p) in everyPreset() {
            let l = Fx.fill(p.fill()).on(fillCard()).seed(3).reduced(true)
            #expect(!l.isAnimating(), "\(s.id) \(p.id)")
            let (a, da) = try! #require(packed(l.at(0.5)))
            let (b, db) = try! #require(packed(l.at(7.25)))
            #expect(bits(a) == bits(b), "\(s.id) \(p.id): same instance at any time")
            #expect(da == db, "\(s.id) \(p.id): same tables at any time")
        }
    }

    @Test("invisible_fills_never_animate")
    func invisibleFillsNeverAnimate() {
        for (s, p) in everyPreset() {
            var params = p.fill()
            params.intensity = 0.0
            let off = Fx.fill(params).on(fillCard()).seed(11)
            #expect(!off.isAnimating() && off.pack() == nil, "\(s.id) \(p.id)")
            #expect(!Fx.fill(p.fill()).on(fillCard()).opacity(0.0).isAnimating(), "\(s.id) \(p.id)")
        }
        #expect(everyPreset().contains { _, p in p.fill().animates() })
    }

    @Test("moving_fills_animate_and_are_deterministic")
    func movingFillsAnimateAndAreDeterministic() {
        for (s, p) in everyPreset() {
            let l = Fx.fill(p.fill()).on(fillCard()).seed(11)
            #expect(l.isAnimating() == p.fill().animates(), "\(s.id) \(p.id)")
            let (a, da) = try! #require(packed(l.at(1.5)))
            let (b, db) = try! #require(packed(l.at(1.5)))
            #expect(bits(a) == bits(b))
            #expect(da == db)
            #expect(allFinite(da), "\(s.id) \(p.id)")
        }
        #expect(FillParams.from(LiquidMetalParams.gold()).animates())
        var stillGold = LiquidMetalParams.gold()
        stillGold.flow = 0.0
        #expect(!FillParams.from(stillGold).animates())
        #expect(!FillParams.from(FlutedGlassParams.reeded()).animates())
        #expect(!FillParams.from(DitherParams.bayer()).animates(), "a ramp holds still")
        var flatSea = WaveParams.sea()
        flatSea.amplitude = 0.0
        #expect(!FillParams.from(flatSea).animates(), "flat waves hold still")
    }

    @Test("large_times_fold_without_precision_loss_or_jump")
    func largeTimesFoldWithoutPrecisionLossOrJump() {
        #expect(cpu.foldT(0.0) == 0.0)
        #expect(cpu.foldT(1.2) == 1.2)
        #expect(cpu.foldT(512.0) == 512.0)
        for t: Float in [1e4, 1e5, -1e5] {
            let a = cpu.foldT(t)
            let b = cpu.foldT(t + 1.0 / 60.0)
            #expect((0.0...512.0).contains(a) && (0.0...512.0).contains(b), "\(t) -> \(a)")
            #expect(abs(b - a) > 1e-3 && abs(b - a) < 0.05, "smooth step at \(t): \(a) -> \(b)")
        }
        for (s, p) in everyPreset() {
            let l = Fx.fill(p.fill()).on(fillCard()).seed(7)
            let (i0, d0) = try! #require(packed(l.at(1e5)))
            let (i1, d1) = try! #require(packed(l.at(1e5 + 0.25)))
            #expect(i0.t[0] >= 0.0 && i0.t[0] <= 512.0, "\(s.id) \(p.id)")
            #expect(allFinite(d0), "\(s.id) \(p.id)")
            if p.fill().animates() {
                #expect(i0.t[0] != i1.t[0] || d0 != d1, "\(s.id) \(p.id) still moves at t = 1e5")
            }
        }
    }

    @Test("backdrop_and_placement_follow_the_input")
    func backdropAndPlacementFollowTheInput() {
        for (s, p) in everyPreset() {
            let f = p.fill()
            if f.needsBackdrop() {
                #expect(s.readsBackdrop, "\(s.id) \(p.id)")
            }
            let l = Fx.fill(f).on(fillCard())
            #expect(l.fx.needsBackdrop() == f.needsBackdrop())
            #expect(l.place == (f.needsBackdrop() ? .over : .under))
            #expect(l.fx.cost().backdrop == f.needsBackdrop())
        }
        #expect(Fx.fill(DitherParams.backdrop()).needsBackdrop())
        #expect(!Fx.fill(DitherParams.bayer()).needsBackdrop())
    }

    @Test("element_anchor_only_moves_the_anchor_slot")
    func elementAnchorOnlyMovesTheAnchorSlot() {
        #expect(LiquidMetalParams.default().anchor == .world)
        let world = try! #require(packed(Fx.fill(LiquidMetalParams.gold()).on(fillCard()).at(3.0))).0
        var element = try! #require(packed(Fx.fill(LiquidMetalParams.gold().anchor(.element)).on(fillCard()).at(3.0))).0
        #expect(world.p2 == .zero)
        #expect(element.p2 == SIMD4<Float>(1.0, 0.0, 0.0, 0.0))
        element.p2 = .zero
        #expect(bits(element) == bits(world))
    }

    @Test("plastic_holds_still")
    func plasticHoldsStill() {
        for p in [PlasticParams.glossy(), PlasticParams.matte(), PlasticParams.dished()] {
            #expect(!FillParams.from(p).animates())
            #expect(!Fx.fill(p).on(fillCard()).at(2.0).isAnimating())
            #expect(Fx.fill(p).cost() == FxCost(passes: 1, samples: 0, alu: 0, backdrop: false, source: false))
        }
        var nonFinitePlastic = PlasticParams.glossy()
        nonFinitePlastic.roughness = .nan
        nonFinitePlastic.dome = .infinity
        nonFinitePlastic.bevel = -.infinity
        nonFinitePlastic.angle = .nan

        var nonFiniteMetal = LiquidMetalParams.chrome()
        nonFiniteMetal.flow = .nan
        nonFiniteMetal.scale = .nan
        nonFiniteMetal.speed = .infinity
        nonFiniteMetal.bevel = .nan
        nonFiniteMetal.dome = -.infinity
        nonFiniteMetal.angle = .nan
        nonFiniteMetal.iridescence = .infinity
        nonFiniteMetal.contrast = .nan

        for fx in [Fx.fill(nonFinitePlastic), Fx.fill(nonFiniteMetal)] {
            let (i, _) = try! #require(packed(fx.on(fillCard()).at(1.0)))
            let vectors = [i.p0, i.p1, i.p2]
            #expect(vectors.allSatisfy { v in v.x.isFinite && v.y.isFinite && v.z.isFinite && v.w.isFinite })
        }
    }

    @Test("mesh_points_wander_within_drift")
    func meshPointsWanderWithinDrift() {
        let p = MeshGradientParams.dusk()
        for k in 0..<40 {
            let pts = cpu.meshPoints(p, Float(k) * 0.37, 5)
            for (q, r) in zip(pts, p.points) {
                #expect(abs(q[0] - r[0]) <= p.drift * 1.5 && abs(q[1] - r[1]) <= p.drift * 1.5)
            }
        }
        var still = p
        still.drift = 0.0
        #expect(cpu.meshPoints(still, 3.0, 5) == p.points)
    }

    @Test("blue_noise_tile_ranks_every_pixel_once")
    func blueNoiseTileRanksEveryPixelOnce() {
        let t = cpu.blueNoise()
        #expect(t.count * 4 == cpu.BLUE_N * cpu.BLUE_N)
        var v: [Float] = []
        v.reserveCapacity(t.count * 4)
        for vec in t {
            v.append(vec.x)
            v.append(vec.y)
            v.append(vec.z)
            v.append(vec.w)
        }
        v.sort()
        for (k, x) in v.enumerated() {
            #expect(abs(x - (Float(k) + 0.5) / Float(v.count)) < 1e-6)
        }
        let n = cpu.BLUE_N
        func at(_ x: Int, _ y: Int) -> Float {
            let idx = (y % n) * n + (x % n)
            return t[idx / 4][idx % 4]
        }
        var worst: Float = 0.0
        for i in 0..<(n * n) {
            let x = i % n
            let y = i / n
            let mean = (at(x, y) + at(x + 1, y) + at(x, y + 1) + at(x + 1, y + 1)) / 4.0
            worst = max(worst, abs(mean - 0.5))
        }
        #expect(worst < 0.36, "\(worst)")
    }

    @Test("oklab_of_white_and_grey_is_neutral")
    func oklabOfWhiteAndGreyIsNeutral() {
        let w = oklab(Rgb(repeating: 1.0))
        #expect(abs(w[0] - 1.0) < 1e-3 && abs(w[1]) < 1e-3 && abs(w[2]) < 1e-3)
        let g = oklab(rgb(0x777777))
        #expect(abs(g[1]) < 1e-3 && abs(g[2]) < 1e-3)
    }

    @Test("stops_keep_order_and_cap")
    func stopsKeepOrderAndCap() {
        let s = Stops.hex([0xff0000, 0x00ff00, 0x0000ff])
        #expect(s.len() == 3)
        #expect(s.asSlice()[1].hex() == 0x00ff00)
        #expect(Stops.hex(Array(repeating: 0, count: 9)).len() == maxStops)
        #expect(Stops.new([]).len() == 1)
    }
}
