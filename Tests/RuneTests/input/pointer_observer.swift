// Tests ported from: crates/rune/src/input/pointer_observer.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

private final class WakeCounter: @unchecked Sendable {
    private let lock = LiveLock()
    private var count: Int = 0

    func increment() {
        lock.withLock { count += 1 }
    }

    func load() -> Int {
        lock.withLock { count }
    }
}

@Suite("PointerObserverTests")
struct PointerObserverTests {
    @Test("overlay observation sleeps outside canvas and preserves gap display")
    func overlayObservationSleepsOutsideCanvasAndPreservesGapDisplay() {
        let wakes = WakeCounter()
        let observer = PointerObserver.new({ wakes.increment() })
        observer.configure([10, 10, 30, 30], [[0, 0, 100, 100], [200, 0, 300, 100]], true)

        observer.observe((5, 5)) // Initial display resolution.
        let p1 = observer.take()
        #expect(p1?.0 == 5 && p1?.1 == 5)

        for x: Int32 in 31..<100 {
            observer.observe((x, 5))
        }
        #expect(observer.take() == nil)

        observer.observe((15, 15))
        let p2 = observer.take()
        #expect(p2?.0 == 15 && p2?.1 == 15)

        observer.observe((50, 50)) // One exit.
        let p3 = observer.take()
        #expect(p3?.0 == 50 && p3?.1 == 50)

        observer.observe((150, 50)) // Gap retains the previous display.
        #expect(observer.take() == nil)

        observer.observe((250, 50))
        let p4 = observer.take()
        #expect(p4?.0 == 250 && p4?.1 == 50)

        observer.observe((260, 50))
        #expect(observer.take() == nil)

        #expect(wakes.load() == 4)
        #expect(observer.needsGeometry([240, 40, 280, 60], true))
        observer.configure([240, 40, 280, 60], [[0, 0, 100, 100], [200, 0, 300, 100]], true)
        observer.observe((260, 50))
        let p5 = observer.take()
        #expect(p5?.0 == 260 && p5?.1 == 50)
    }
}
