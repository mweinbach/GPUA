// Ported from: crates/rune/src/gpu/springs.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
import RuneMotion
@testable import Rune

@Suite("GPU Springs Tests")
struct GpuSpringsTests {
    @Test("arbitrary retarget settle bounds hold for the tail")
    func arbitraryRetargetSettleBoundsHoldForTail() {
        #expect(springs.Track.byteSize == 48)
        #expect(springs.Node.byteSize == 144)
        #expect(springs.Node(
            x: .constant(0.0),
            y: .constant(0.0),
            opacity: .constant(1.0)
        ).toBytes().count == 144)

        for bounce: Float in [-0.9, -0.2, 0.0, 0.16, 0.8] {
            let spring = Spring.new(0.4, bounce)
            for velocity: Float in [-800.0, 0.0, 900.0] {
                let (from, vel) = spring.sample(-120.0, velocity, 40.0, 0.12)
                let duration = spring.settlingDurationFrom(from, vel, -30.0, 0.001)
                let track = springs.Track.new(spring, 1000.25, from, -30.0, vel, 0.001)
                // Also verify GPU track evaluator agrees with Spring.sample before settle!
                for k in [0, 3, 10, 25] {
                    let dt = Float(k) / 120.0
                    if dt < duration {
                        let (wantX, _) = spring.sample(from, vel, -30.0, dt)
                        let (gotX, _) = track.sample(springs.splitTime(1000.25 + Double(dt)))
                        #expect(abs(gotX - wantX) <= 1e-2, "bounce=\(bounce) dt=\(dt): got \(gotX) want \(wantX)")
                    }
                }
                for i in 0..<200 {
                    let (x, v) = spring.sample(from, vel, -30.0, duration + Float(i) / 120.0)
                    #expect(abs(x + 30.0) <= 0.00101, "\(bounce): \(x)")
                    #expect(abs(v) <= 0.01001, "\(bounce): \(v)")
                }
            }
        }
        #expect(springs.Track.constant(1.0).settleAt() == 0.0)
    }
}
