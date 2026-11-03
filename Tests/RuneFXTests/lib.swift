// Tests ported from: crates/rune-fx/src/lib.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import RuneFX

@Suite("RuneFX Core Primitives")
struct FxLibTests {
    @Test("Shape constructors compute expected rects and radii")
    func shapeConstructors() {
        let r = Shape.rounded(10.0, 20.0, 100.0, 50.0, 12.0)
        #expect(r.rect == Rect.new(10.0, 20.0, 100.0, 50.0))
        #expect(r.radius == 12.0)

        let cap = Shape.capsule(0.0, 0.0, 120.0, 40.0)
        #expect(cap.radius == 20.0)

        let cir = Shape.circle(50.0, 60.0, 15.0)
        #expect(cir.rect == Rect.new(35.0, 45.0, 30.0, 30.0))
        #expect(cir.radius == 15.0)
    }

    @Test("FxBlend and FxSlot contracts match backdrop and cost declarations")
    func blendAndSlotContracts() {
        #expect(!FxBlend.normal.needsBackdrop())
        #expect(!FxBlend.screen.needsBackdrop())
        #expect(FxBlend.multiply.needsBackdrop())
        #expect(FxBlend.overlay.needsBackdrop())
        #expect(FxBlend.softLight.needsBackdrop())

        #expect(FxBlend.normal.cost() == FxCost(passes: 0, samples: 0, alu: 0, backdrop: false, source: false))
        #expect(FxBlend.multiply.cost() == FxCost(passes: 0, samples: 1, alu: 1, backdrop: true, source: false))

        let slot = FxSlot.default()
            .scale(2.0)
            .clip([4.0, 8.0, 68.0, 72.0], [1, 2, 3, 4])
            .backdropSrgb(true)
            .blend(.overlay)
        #expect(slot.scale == 2.0)
        #expect(slot.clip == [4.0, 8.0, 68.0, 72.0])
        #expect(slot.fade == [1, 2, 3, 4])
        #expect(slot.backdropSrgb == true)
        #expect(slot.blend == .overlay)
    }

    @Test("Heat activity and OneShots pruning settle cleanly")
    func heatAndOneShotsLifecycle() {
        var heat = Heat.new(0.1, 0.2)
        #expect(!heat.isActive(0.0))
        heat.set(0.0, true)
        #expect(heat.isActive(0.05))
        heat.set(0.2, false)
        #expect(heat.isActive(0.25))
        #expect(!heat.isActive(5.0))

        var pool = OneShots<Int>.new(2)
        pool.trigger(0.0, 10)
        pool.trigger(0.1, 20)
        #expect(pool.isAnimating(0.2, 0.5))
        pool.prune(1.0, 0.5)
        #expect(!pool.isAnimating(1.0, 0.5))
        #expect(pool.live(1.0, 0.5).isEmpty)
        pool.trigger(1.0, 30)
        pool.clear()
        #expect(pool.live(1.0, 0.5).isEmpty)
    }

    @Test("Fx default placement and static cost declarations match effect families")
    func fxPlacementAndCost() {
        let shape = Shape.rounded(0.0, 0.0, 80.0, 40.0, 8.0)
        #expect(Fx.glow(.default()).on(shape).place == .under)
        #expect(Fx.pulse(.default()).on(shape).place == .under)
        #expect(Fx.fire(.default()).on(shape).place == .under)
        #expect(Fx.aurora(.default()).on(shape).place == .under)
        #expect(Fx.electric(.default()).on(shape).place == .over)
        #expect(Fx.lens(.default()).on(shape).place == .over)
        #expect(Fx.lens(.default()).needsBackdrop())
        #expect(!Fx.glow(.default()).needsBackdrop())
        #expect(Fx.glow(GlowParams(style: .mask)).cost().source)
        #expect(Fx.shimmer(ShimmerParams(useMask: true)).cost().source)
    }
}
