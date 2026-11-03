// Tests ported from: crates/rune-fx/src/tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import RuneFX

private func testCard() -> Shape {
    Shape.rounded(100.0, 100.0, 200.0, 120.0, 16.0)
}

@Suite("RuneFX Layer & CPU Invariants")
struct FxCoreTests {
    @Test("sparkle_cap_and_tables_reach_64_without_regrowing")
    func sparkleCapAndTablesReach64WithoutRegrowing() {
        let p = SparkleParams(count: 100, life: 10.0, burst: 0.0)
        let layer = Fx.sparkles(p).on(testCard()).at(1.0)
        let (_, packed, _) = try! #require(layer.pack())
        #expect(packed.p0[0] == 64.0)
        #expect(layer.fx.cost().samples == 128)

        var table: [SIMD4<Float>] = []
        table.reserveCapacity(128)
        let capacity = table.capacity
        let (_, count) = cpu.sparkles(p, testCard().rect, 1.0, 1, false, &table)
        #expect(count > 32.0 && count <= 64.0)
        #expect(table.count == Int(count) * 2)
        #expect(table.capacity == capacity)
    }

    @Test("idle_layers_cost_nothing")
    func idleLayersCostNothing() {
        let l0 = Fx.glow(GlowParams(intensity: 0.0)).on(testCard())
        #expect(l0.pack() == nil)
        let l1 = Fx.glow(GlowParams(heat: 0.0)).on(testCard())
        #expect(l1.pack() == nil, "a fully cooled light is culled")

        let ripple = PulseParams(style: .ripple(at: [150.0, 150.0]), t0: 1.0, duration: 0.5)
        #expect(Fx.pulse(ripple).on(testCard()).at(0.5).pack() == nil, "before the tap")
        #expect(Fx.pulse(ripple).on(testCard()).at(1.2).pack() != nil)
        #expect(Fx.pulse(ripple).on(testCard()).at(1.6).pack() == nil, "after the ripple")
        #expect(!Fx.pulse(ripple).on(testCard()).at(1.6).isAnimating())

        let shock = DistortParams.shockwave([0.0, 0.0], 0.0)
        #expect(Fx.distort(shock).on(testCard()).at(2.0).pack() == nil)
    }

    @Test("layers_that_draw_nothing_never_keep_the_loop_awake")
    func layersThatDrawNothingNeverKeepTheLoopAwake() {
        let glow = GlowParams(breathe: 0.3)
        var glowZeroInt = glow
        glowZeroInt.intensity = 0.0
        var glowZeroHeat = glow
        glowZeroHeat.heat = 0.0

        let pulse = PulseParams.default()
        let electric = ElectricParams.default()
        let fire = FireParams.default()
        let haze: (Float) -> DistortParams = { amount in
            .heatHaze(height: 40.0, scale: 14.0, speed: 2.2, amount: amount, wholeShape: false)
        }
        let chroma: (Float) -> DistortParams = { glitch in
            .chromaSplit(offset: [0.0, 0.0], glitch: glitch, feather: 0.0)
        }
        let shimmer = ShimmerParams.default()
        let sparkles = SparkleParams.default()
        let aurora = AuroraParams.default()
        let grain = GrainParams(fps: 24.0)

        let pairs: [(Fx, Fx)] = [
            (.glow(glow), .glow(glowZeroInt)),
            (.glow(glow), .glow(glowZeroHeat)),
            (.pulse(pulse), .pulse(PulseParams(intensity: 0.0))),
            (.electric(electric), .electric(ElectricParams(intensity: 0.0))),
            (.fire(fire), .fire(FireParams(intensity: 0.0))),
            (.distort(haze(1.6)), .distort(haze(0.0))),
            (.distort(chroma(0.5)), .distort(chroma(0.0))),
            (.shimmer(shimmer), .shimmer(ShimmerParams(baseAlpha: 0.0, intensity: 0.0))),
            (.sparkles(sparkles), .sparkles(SparkleParams(intensity: 0.0))),
            (.sparkles(sparkles), .sparkles(SparkleParams(count: 0))),
            (.aurora(aurora), .aurora(AuroraParams(intensity: 0.0))),
            (.grain(grain), .grain(GrainParams(amount: 0.0, fps: 24.0))),
        ]
        for (liveFx, silentFx) in pairs {
            let live = liveFx.on(testCard()).at(1.0)
            #expect(live.isAnimating() && live.pack() != nil)
            #expect(!live.opacity(0.0).isAnimating())
            let silent = silentFx.on(testCard()).at(1.0)
            #expect(!silent.isAnimating() && silent.pack() == nil)
        }
    }

    @Test("a_ping_ticks_until_its_shot_has_cooled")
    func aPingTicksUntilItsShotHasCooled() {
        let ping = PulseParams(
            style: .ping(from: [0.0, 0.0], dir: [1.0, 0.0], travel: 200.0),
            t0: 1.0,
            duration: 0.5
        )
        let at: (Float) -> FxLayer = { t in Fx.pulse(ping).on(testCard()).at(t) }
        let cooling: Float = 1.0 + 0.5 * 2.1
        #expect(at(cooling).pack() != nil, "still drawn while it cools")
        #expect(at(cooling).isAnimating(), "so the loop keeps ticking")
        let done: Float = 1.0 + 0.5 * 2.3
        #expect(at(done).pack() == nil && !at(done).isAnimating())
    }

    @Test("one_shots_overlap_and_retire_by_fading")
    func oneShotsOverlapAndRetireByFading() {
        var p = OneShots<Int>.new(3)
        for k in 0..<3 {
            p.trigger(Float(k) * 0.1, k)
        }
        let live = p.live(0.25, 1.0)
        #expect(live.map(\.0.data) == [0, 1, 2])
        #expect(live.map(\.1) == [1.0, 1.0, 1.0])

        // Full: the oldest fades out over `fade` instead of vanishing.
        p.trigger(0.3, 3)
        let o0: (Float) -> Float = { t in
            p.live(t, 1.0).first(where: { $0.0.data == 0 })?.1 ?? 0.0
        }
        #expect(o0(0.3) == 1.0)
        var prev: Float = 1.0
        for i in 1...20 {
            let v = o0(0.3 + Float(i) * OneShots<Int>.fade / 20.0)
            #expect(v <= prev && prev - v < 0.2, "fades smoothly: \(prev) -> \(v)")
            prev = v
        }
        #expect(prev == 0.0)
        #expect(p.live(0.31, 1.0).filter { $0.1 == 1.0 }.count == 3)

        // A storm of triggers stays bounded.
        for k in 0..<100 {
            p.trigger(0.4 + Float(k) * 0.001, k)
        }
        #expect(p.live(0.5, 1.0).count <= 6)
        let seeds = Set(p.live(0.5, 1.0).map(\.0.seed))
        #expect(seeds.count > 1, "instances get distinct seeds")
    }

    @Test("opacity_zero_is_culled")
    func opacityZeroIsCulled() {
        #expect(Fx.glow(.default()).on(testCard()).opacity(0.0).pack() == nil)
        let (_, i, _) = try! #require(Fx.glow(.default()).on(testCard()).opacity(0.4).pack())
        #expect(i.shape[2] == 0.4)
    }

    @Test("zaps_and_bursts_live_out_their_window_then_cull")
    func zapsAndBurstsLiveOutTheirWindowThenCull() {
        let zap = Fx.electric(ElectricParams(style: .arc(a: [0.0, 0.0], b: [200.0, 40.0]), zap: 1.0)).on(testCard())
        #expect(zap.at(0.9).pack() == nil)
        #expect(zap.at(1.2).pack() != nil && zap.at(1.2).isAnimating())
        #expect(zap.at(1.0 + ElectricParams.zapLife + 0.01).pack() == nil)

        let p = SparkleParams(burst: 2.0)
        let burst = Fx.sparkles(p).on(testCard())
        #expect(burst.at(2.3).pack() != nil)
        #expect(!burst.at(2.0 + p.burstLife() + 0.01).isAnimating())
        var data: [SIMD4<Float>] = []
        let (_, n) = cpu.sparkles(p, testCard().rect, 2.0 + p.burstLife() + 0.01, 1, false, &data)
        #expect(n == 0.0, "every burst star is gone by burstLife()")

        let dense = SparkleParams(count: 64, life: 2.0, burst: 0.0)
        let (_, inst, _) = try! #require(Fx.sparkles(dense).on(testCard()).at(0.3).pack())
        #expect(inst.p0[0] == 64.0)
        var dense100 = dense
        dense100.count = 100
        #expect(Fx.sparkles(dense100).cost().samples == 128)
        data.removeAll()
        let (_, n64) = cpu.sparkles(dense, testCard().rect, 0.3, 1, false, &data)
        #expect(n64 == 64.0, "all 64 burst stars are emitted within the cap")
        #expect(data.count == 128, "two vec4f entries per star")
    }

    @Test("motion_blur_is_one_sample_at_rest_and_scales_with_speed")
    func motionBlurIsOneSampleAtRestAndScalesWithSpeed() {
        let rest = Rect.new(0.0, 0.0, 100.0, 60.0)
        let p = MotionBlurParams.default()
        let still = MotionSamples.fromTrack(p, rest, 1.0, 2.0) { _ in Pose.default() }
        #expect(still.count == 1)
        #expect(!still.isMoving())

        let slow = MotionSamples.fromTrack(p, rest, 1.0, 2.0) { t in Pose(x: t * 300.0) }
        let fast = MotionSamples.fromTrack(p, rest, 1.0, 2.0) { t in Pose(x: t * 1500.0) }
        #expect(slow.count > 1 && fast.count > slow.count)
        let w = fast.xforms.prefix(Int(fast.count)).reduce(Float(0.0)) { $0 + $1[6] }
        #expect(abs(w - 1.0) < 1e-4, "shutter weights sum to opacity: \(w)")
        #expect(fast.bounds.w > rest.w + 10.0)
    }

    @Test("pose_inverse_round_trips")
    func poseInverseRoundTrips() {
        let rest = Rect.new(10.0, 20.0, 100.0, 60.0)
        let pose = Pose(x: 33.0, y: -7.0, rotation: 0.4, scale: 1.3, opacity: 1.0)
        let inv = invert(pose.affine(rest))
        let p = pose.apply(rest, [25.0, 40.0])
        let back: [Float] = [
            inv[0] * p[0] + inv[2] * p[1] + inv[4],
            inv[1] * p[0] + inv[3] * p[1] + inv[5],
        ]
        #expect(abs(back[0] - 25.0) < 1e-3 && abs(back[1] - 40.0) < 1e-3)
    }

    @Test("phase_never_jumps_when_speed_changes")
    func phaseNeverJumpsWhenSpeedChanges() {
        var ph = Phase.new(1.0)
        let before = ph.at(2.0)
        ph.setSpeed(2.0, 3.0)
        #expect(abs(ph.at(2.0) - before) < 1e-6)
        #expect(abs(ph.at(2.1) - before - 0.3) < 1e-5)
    }

    @Test("heat_cools_continuously")
    func heatCoolsContinuously() {
        var h = Heat.new(0.1, 0.3)
        h.set(0.0, true)
        let lit = h.at(0.5)
        #expect(abs(lit - 1.0) < 1e-6)
        h.set(0.5, false)
        #expect(abs(h.at(0.5) - lit) < 1e-6, "no cut at switch-off")
        var prev = h.at(0.5)
        for i in 1..<100 {
            let v = h.at(0.5 + Float(i) * 0.01)
            #expect(v < prev && prev - v < 0.05, "monotonic, no step")
            prev = v
        }
        let mid = h.at(0.7)
        h.set(0.7, true)
        #expect(abs(h.at(0.7) - mid) < 1e-6)
    }

    @Test("cpu_noise_is_bounded_periodic_and_deterministic")
    func cpuNoiseIsBoundedPeriodicAndDeterministic() {
        for i in 0..<2000 {
            let x = Float(i) * 0.173
            let v = cpu.gnoise(x, x * 0.37, 0, 9)
            #expect(abs(v) <= 1.01, "\(v)")
            #expect(v == cpu.gnoise(x, x * 0.37, 0, 9))
            let a = cpu.gnoise(x, 0.4, 7, 3)
            let b = cpu.gnoise(x + 7.0, 0.4, 7, 3)
            #expect(abs(a - b) < 1e-4, "periodic in x")
        }
    }

    @Test("electric_tables_have_the_declared_layout")
    func electricTablesHaveTheDeclaredLayout() {
        var data: [SIMD4<Float>] = []
        let p = ElectricParams(
            style: .arc(a: [0.0, 0.0], b: [300.0, 0.0]),
            forks: 1.0,
            strands: 2
        )
        let xf = cpu.electric(p, testCard(), 1.7, 3, false, &data)
        let n = Int(xf[1])
        let forks = Int(xf[2])
        let strands = Int(xf[3])
        #expect(data.count == 2 + 2 * strands * n / 4 + forks * 6)
        #expect(abs(data[2][0]) < 1e-3, "endpoints are pinned")

        var reducedData: [SIMD4<Float>] = []
        let reduced = cpu.electric(p, testCard(), 1.7, 3, true, &reducedData)
        #expect(reduced[2] == 0.0, "reduced motion: no forks")
    }

    @Test("zero_amplitude_electricity_is_a_straight_finite_line")
    func zeroAmplitudeElectricityIsAStraightFiniteLine() {
        for style in [ElectricStyle.arc(a: [0.0, 0.0], b: [300.0, 0.0]), .border] {
            let p = ElectricParams(style: style, amplitude: 0.0, forks: 1.0)
            for t: Float in [0.0, 0.4, 1.7] {
                var data: [SIMD4<Float>] = []
                _ = cpu.electric(p, testCard(), t, 3, false, &data)
                #expect(data.allSatisfy { v in v.x.isFinite && v.y.isFinite && v.z.isFinite && v.w.isFinite })
            }
        }
    }
}
