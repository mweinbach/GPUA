// Tests ported from: crates/gpui_web/src/window_environment.rs (#[cfg(test)] items)
// Upstream commit: 650aab59d54f
// Port status: ported

import Testing
@testable import GPUIWeb

private func metrics(_ physicalWidth: UInt32, _ physicalHeight: UInt32, _ scaleFactor: Float) -> CanvasMetrics {
    CanvasMetrics(
        physicalWidth: physicalWidth,
        physicalHeight: physicalHeight,
        logicalWidth: Float(physicalWidth) / scaleFactor,
        logicalHeight: Float(physicalHeight) / scaleFactor,
        scaleFactor: scaleFactor
    )
}

@Suite("GPUIWeb window_environment tests")
struct WindowEnvironmentTests {
    @Test("reconcile emits visible resize for first observation")
    func testReconcileEmitsVisibleResizeForFirstObservation() {
        var state = WindowEnvironmentState.new(2.0)
        state.queueResize(metrics(800, 600, 2.0))

        let update = state.reconcile(2.0, nil, 16_384)

        #expect(update.mediaQuery == nil)
        #expect(
            update.resize == .visible(
                logicalWidth: 400.0,
                logicalHeight: 300.0,
                physicalWidth: 800,
                physicalHeight: 600,
                scaleFactor: 2.0
            )
        )
    }

    @Test("reconcile uses measured metrics after DPR change")
    func testReconcileUsesMeasuredMetricsAfterDprChange() {
        var state = WindowEnvironmentState.new(1.0)
        state.queueResize(metrics(400, 300, 1.0))
        _ = state.reconcile(1.0, nil, 16_384)

        state.queueDprChange()

        let update = state.reconcile(2.0, metrics(800, 600, 2.0), 16_384)

        #expect(update.mediaQuery == "(resolution: 2dppx), (-webkit-device-pixel-ratio: 2)")
        #expect(
            update.resize == .visible(
                logicalWidth: 400.0,
                logicalHeight: 300.0,
                physicalWidth: 800,
                physicalHeight: 600,
                scaleFactor: 2.0
            )
        )
    }

    @Test("reconcile skips duplicate metrics")
    func testReconcileSkipsDuplicateMetrics() {
        var state = WindowEnvironmentState.new(2.0)
        state.queueResize(metrics(800, 600, 2.0))
        _ = state.reconcile(2.0, nil, 16_384)

        state.queueResize(metrics(800, 600, 2.0))
        let update = state.reconcile(2.0, nil, 16_384)

        #expect(update.mediaQuery == nil)
        #expect(update.resize == nil)
    }

    @Test("reconcile emits hidden resize for zero-sized canvas")
    func testReconcileEmitsHiddenResizeForZeroSizedCanvas() {
        var state = WindowEnvironmentState.new(2.0)
        state.queueResize(metrics(0, 0, 2.0))

        let update = state.reconcile(2.0, nil, 16_384)

        #expect(update.resize == .hidden(scaleFactor: 2.0))
    }

    @Test("reconcile clamps drawable size")
    func testReconcileClampsDrawableSize() {
        var state = WindowEnvironmentState.new(2.0)
        state.queueResize(metrics(40_000, 30_000, 2.0))

        let update = state.reconcile(2.0, nil, 16_384)

        #expect(
            update.resize == .visible(
                logicalWidth: 20_000.0,
                logicalHeight: 15_000.0,
                physicalWidth: 16_384,
                physicalHeight: 16_384,
                scaleFactor: 2.0
            )
        )
    }
}
