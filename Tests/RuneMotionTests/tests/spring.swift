// Tests ported from: crates/rune-motion/tests/spring.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import RuneMotion

/// RK4 on x'' = −k(x − T) − c x' in f64 with a tiny step: the reference the closed form must match.
private func integrate(
    _ s: Spring,
    _ x0: Double,
    _ v0: Double,
    _ target: Double,
    _ tEnd: Double
) -> (Double, Double) {
    let k = Double(s.stiffness())
    let c = Double(s.damping())
    let f = { (x: Double, v: Double) -> (Double, Double) in
        (v, -k * (x - target) - c * v)
    }
    let dt = 1e-5
    var x = x0
    var v = v0
    let steps = Int((tEnd / dt).rounded())
    for _ in 0..<steps {
        let (a1, b1) = f(x, v)
        let (a2, b2) = f(x + 0.5 * dt * a1, v + 0.5 * dt * b1)
        let (a3, b3) = f(x + 0.5 * dt * a2, v + 0.5 * dt * b2)
        let (a4, b4) = f(x + dt * a3, v + dt * b3)
        x += dt / 6.0 * (a1 + 2.0 * a2 + 2.0 * a3 + a4)
        v += dt / 6.0 * (b1 + 2.0 * b2 + 2.0 * b3 + b4)
    }
    return (x, v)
}

@Test func closed_form_matches_ode_integration_in_every_regime() {
    let springs = [
        Spring.new(0.3, 0.0),      // critical (Kit's default)
        Spring.new(0.5, 0.3),      // under (SwiftUI .bouncy)
        Spring.new(0.4, 0.7),      // very bouncy
        Spring.new(0.35, -0.5),    // over
        Spring.new(0.6, 0.0005),   // near-critical, under
        Spring.new(0.25, -0.0005), // near-critical, over
    ]
    let starts: [(Float, Float)] = [(0.0, 0.0), (0.0, 25.0), (0.7, -8.0)]
    for s in springs {
        for (x0, v0) in starts {
            for t: Float in [0.01, 0.05, 0.13, 0.3, 0.71] {
                let (x, v) = s.sample(x0, v0, 1.0, t)
                let (rx, rv) = integrate(s, Double(x0), Double(v0), 1.0, Double(t))
                // Position within 1e-4 per unit of travel; velocity scaled by ω.
                #expect(abs(Double(x) - rx) < 1e-4, "\(s) x0=\(x0) v0=\(v0) t=\(t): x \(x) vs \(rx)")
                let vtol = 1e-4 * Double(s.omega()) + 1e-4 * Double(abs(v0))
                #expect(abs(Double(v) - rv) < vtol, "\(s) x0=\(x0) v0=\(v0) t=\(t): v \(v) vs \(rv)")
            }
        }
    }
}

@Test func swiftui_parameter_mapping() {
    // Spring(duration: 0.5, bounce: 0): stiffness (2π/0.5)² ≈ 157.914, damping 4π ≈ 25.133.
    let s = Spring.new(0.5, 0.0)
    #expect(abs(s.stiffness() - 157.913_67) < 1e-2, "\(s.stiffness())")
    #expect(abs(s.damping() - 25.132_74) < 1e-3, "\(s.damping())")
    #expect(Spring.bouncy.zeta() == 0.7)
    #expect(abs(Spring.snappy.zeta() - 0.85) < 1e-6)
    #expect(Spring.new(0.4, -0.5).zeta() == 2.0)
    // Round trips.
    let back = Spring.fromStiffnessDamping(s.stiffness(), s.damping(), 1.0)
    #expect(abs(back.duration - 0.5) < 1e-5 && abs(back.bounce) < 1e-5)
    let r = Spring.fromResponse(0.55, 0.825)
    #expect(abs(r.duration - 0.55) < 1e-6 && abs(r.zeta() - 0.825) < 1e-6)
    let over = Spring.fromOmegaZeta(10.0, 2.0)
    #expect(abs(over.bounce + 0.5) < 1e-6 && abs(over.zeta() - 2.0) < 1e-5)
    // Mass: k/m and c/(2√(km)).
    let m = Spring.fromStiffnessDamping(400.0, 20.0, 2.0)
    #expect(abs(m.omega() - Float(200.0).squareRoot()) < 1e-4)
    // Motion's visualDuration is ours / 1.2.
    #expect(abs(Spring.fromMotion(0.45, 0.0).duration - 0.54) < 1e-6)
    #expect(abs(motion.glide.motionVisualDuration() - 0.32 / 1.2) < 1e-6)
}

@Test func kit_tokens_match_kit_motion_json() {
    let expectTokens: [(String, Float, Float, Float, Float)] = [
        ("instant", 0.1, 0.0, 0.1, 0.0),
        ("snap", 0.25, 0.0, 0.2, 0.0),
        ("settle", 0.3, 0.0, 0.24, 0.0),
        ("reflow", 0.4, 0.0, 0.32, 0.0),
        ("glide", 0.32, 0.0, 0.26, 0.0),
        ("morph", 0.3, 0.16, 0.27, 0.08),
        ("pop", 0.25, 0.15, 0.2, 0.05),
        ("drift", 0.85, 0.0, 0.6, 0.0),
    ]
    #expect(expectTokens.count == motion.all.count)
    for (idx, (name, ed, eb, xd, xb)) in expectTokens.enumerated() {
        let (n, pair) = motion.all[idx]
        #expect(name == n)
        #expect(pair.enter.duration == ed && pair.enter.bounce == eb, "\(name)")
        #expect(pair.exit.duration == xd && pair.exit.bounce == xb, "\(name)")
        if name != "instant" {
            // Exits run 10–25 % shorter (instant is already at the floor).
            let ratio = xd / ed
            #expect((0.7...0.9).contains(ratio), "\(name) exit ratio \(ratio)")
        }
    }
}

@Test func settle_time_bounds_the_whole_tail() {
    for s in [Spring.new(0.3, 0.0), Spring.new(0.5, 0.3), Spring.new(0.4, -0.4), Spring.new(0.3, 0.9)] {
        let ts = s.settlingDuration(1e-3)
        #expect(ts > 0.0 && ts < 20.0, "\(s) \(ts)")
        for i in 0..<2000 {
            let t = ts + Float(i) * 0.005
            let (x, v) = s.sample(0.0, 0.0, 1.0, t)
            #expect(abs(x - 1.0) <= 1.01e-3, "\(s) t=\(t) x=\(x)")
            #expect(abs(v) <= 1.01e-2, "\(s) t=\(t) v=\(v)")
        }
    }
    // Critically damped at duration d settles in about d (SwiftUI's perceptual duration).
    let t = Spring.new(0.5, 0.0).settlingDuration(1e-3)
    #expect(t > 0.4 && t < 1.0, "\(t)")
}

@Test func critically_damped_from_rest_never_overshoots() {
    let s = motion.settle
    var prev: Float = 0.0
    for i in 1..<400 {
        let (x, _) = s.sample(0.0, 0.0, 1.0, Float(i) / 400.0)
        #expect(x >= prev && x <= 1.0)
        prev = x
    }
}

@Test func animated_value_retargets_keeping_velocity() {
    var a = Animated.new(Float(0.0))
    a.animateTo(100.0, motion.glide, 0.0)
    let (x1, v1) = (a.sample(0.1), a.velocity(0.1))
    a.animateTo(-50.0, motion.glide, 0.1)
    #expect(abs(a.sample(0.1) - x1) < 1e-4)
    #expect(abs(a.velocity(0.1) - v1) < 1e-2)
    a.retarget(-50.0, 0.2) // unchanged: no-op
    #expect(a.isSettled(5.0))
    #expect(abs(a.sample(5.0) + 50.0) < 1e-3)
    // Decay coasts to x + v/k.
    var d = Animated.new(Float(0.0))
    d.release(1000.0, 0.0, Curve.decay(.iosNormal), 0.0)
    #expect(abs(d.target() - 1000.0 / Decay.iosNormal.rate) < 1e-2)
    #expect(abs(d.sample(30.0) - d.target()) < 1e-2)
}

/// Bit-exact golden for `animateTo`/`release` across every curve kind, so a refactor of the
/// lane restart can't drift the numbers.
@Test func animated_retarget_golden() {
    let tween = Curve.tween(duration: 0.3, easing: .easeOut)
    let curves: [Curve] = [
        .spring(motion.glide),
        .spring(Spring.new(0.5, 0.3)),
        tween,
        .decay(.iosNormal),
        .instant,
    ]
    var h: UInt64 = 0xcbf2_9ce4_8422_2325
    let mix = { (x: Float) in
        h ^= UInt64(x.bitPattern)
        h = h &* 0x100_0000_01b3
    }
    for (n, c) in curves.enumerated() {
        var a = Animated.new(Vec2.new(0.0, 10.0))
        a.animateTo(Vec2.new(100.0, -40.0), Anim.new(.spring(motion.snap)), 0.0)
        a.animateTo(Vec2.new(-30.0, 60.0), Anim.new(c), 0.07)
        a.animateTo(Vec2.new(5.0, 5.0), Anim.new(c).velocity(.uniform(250.0)), 0.13)
        a.release(Vec2.new(-800.0, 400.0), Vec2.new(20.0 * Float(n), 0.0), c, 0.2)
        for k in 0..<40 {
            let t = 0.2 + Double(k) * 0.025
            let (x, v) = (a.sample(t), a.velocity(t))
            for val in [x.x, x.y, v.x, v.y] {
                mix(val)
            }
        }
        let tg = a.target()
        mix(tg.x)
        mix(tg.y)
    }
    #expect(h == 15_969_925_884_686_696_054, "golden hash: \(h)")
}

@Test func css_linear_export() {
    let (css, ms) = motion.settle.cssLinear()
    #expect(css.hasPrefix("linear(0,") && css.hasSuffix(",1)"))
    #expect(ms > 200 && ms < 1000, "\(ms)")
}

@Test func the_none_spring_is_an_instant_curve_everywhere_a_spring_converts() {
    #expect(Curve(Spring.none) == .instant)
    #expect(Anim(Spring.none).curve == .instant)
    #expect(Anim(SpringPair.none).curve == .instant)
    // Reduce Motion keeps it instant; a short spring would become a fade.
    #expect(PropClass.presence.reduce(Spring.none.intoCurve()) == .instant)
    let t = Transition.none()
    #expect(t.insertion == .identity && t.removal == .identity && t.springs == .none)
    // Any other spring, however short, is still a spring.
    #expect(Curve(Spring.new(0.001, 0.0)) == .spring(Spring.new(0.001, 0.0)))
}
