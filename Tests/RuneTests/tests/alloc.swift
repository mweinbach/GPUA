// Tests ported from: crates/rune/tests/alloc.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Count the whole runtime frame, not only the spring evaluator. No GPU/driver allocations.
// PORT NOTE: Upstream replaces Rust's process-wide `#[global_allocator]` (`GlobalAlloc`) to count
// Rust heap allocations across Wave 2 trace hooks, streaming presentation, scroll edge fades, and
// glyph ink probes. Swift's runtime has no per-test global `malloc` hook, so we verify the live
// multi-thread `Live` publication invariants directly and mark the Rust `GlobalAlloc` count assertions
// disabled until Wave 2 streaming/edge-fade/trace-hook internals land.

#if !os(WASI)
import Foundation
#endif
import Testing
@testable import Rune

private struct AllocLiveTriple {
    var opacity: Live<Float>
    var offset: Live<[Float]>
    var fill: Live<Color>
}

@Suite("AllocIntegrationTests")
struct AllocIntegrationTests {
    @Test(.disabled("Requires Rust #[global_allocator] hook and Wave 2 El.traceName / Tx.traceEvent APIs"))
    func disabledTraceHooksNeitherFormatNorAllocate() {}

    @Test(.disabled("Requires Rust #[global_allocator] hook and Wave 2 static faded scope planning"))
    func staticFadedContainerPlanningAllocatesNothing() {}

    @Test(.disabled("Requires Rust #[global_allocator] hook and Wave 2 El.streaming / El.reveal presentation"))
    func streamingPresentationAllocatesNothing() {}

    @Test func livePublicationAndPresentationUpdateCleanlyAcrossThreads() {
        func view(_ s: AllocLiveTriple, _: Cx<AllocLiveTriple>) -> El {
            el().size(200.0, 200.0).child(
                el().key("box").size(20.0, 20.0)
                    .liveOpacity(Binding(live: s.opacity))
                    .liveOffset(Binding(live: s.offset))
                    .liveFill(Binding(live: s.fill))
            )
        }
        let state = AllocLiveTriple(
            opacity: Live.new(1.0),
            offset: Live.new([0.0, 0.0]),
            fill: Live.new(.WHITE)
        )
        let rt = IntegrationSupport.runtime(state, view, (200.0, 200.0), Env.new(true, 2.0))
        _ = rt.hostFrame(0.0)
        #if !os(WASI)
        let pOpacity = state.opacity
        let pOffset = state.offset
        let pFill = state.fill
        let done = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            for i in 0..<120 {
                pOpacity.set(0.3 + Float(i) / 240.0)
                pOffset.set([Float(i), Float(i)])
                pFill.set(Color(r: Float(i) / 120.0, g: 1.0, b: 1.0, a: 1.0))
            }
            done.signal()
        }
        done.wait()
        #endif
        _ = rt.hostFrame(0.0)
        for i in 0..<30 {
            state.opacity.set(0.5 + Float(i) / 240.0)
            state.offset.set([Float(i), Float(i)])
            state.fill.set(Color(r: Float(i) / 120.0, g: 1.0, b: 1.0, a: 1.0))
            _ = rt.hostFrame(1.0 / 120.0)
        }
        let found = IntegrationSupport.find(rt, "box")
        #expect(abs(found.opacity - (0.5 + 29.0 / 240.0)) < 1e-4)
    }

    @Test(.disabled("Requires Rust #[global_allocator] hook and Wave 2 El.scrollEdgeFade / Runtime.fling"))
    func scrollEdgeFadesAllocateNothingPerFrame() {}

    @Test(.disabled("Requires Rust #[global_allocator] hook and Wave 2 text.ink cache"))
    func aCachedInkProbeAllocatesNothing() {}
}
