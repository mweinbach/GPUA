// Tests ported from: crates/rune/src/live.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

#if !os(WASI)
import Dispatch
import Foundation
#endif
import Testing
@testable import Rune

private final class AtomicCounter: @unchecked Sendable {
    private let lock = LiveLock()
    private var value: Int = 0

    func increment() {
        lock.withLock { value += 1 }
    }

    func load() -> Int {
        lock.withLock { value }
    }
}

@Suite("LiveTests")
struct LiveTests {
    #if !os(WASI)
    @Test("concurrent producers never tear color lanes")
    func concurrentProducersNeverTearColorLanes() {
        let live = Live.new(Color.WHITE)
        DispatchQueue.concurrentPerform(iterations: 5) { worker in
            if worker < 4 {
                for i in 0..<20_000 {
                    let n = Float(i * 4 + worker)
                    live.set(Color(r: n, g: n, b: n, a: n))
                }
            } else {
                for _ in 0..<80_000 {
                    let c = live.get()
                    #expect([c.r, c.r, c.r] == [c.g, c.b, c.a])
                }
            }
        }
    }
    #endif

    @Test("subscriptions coalesce and respect visibility and lifetime")
    func subscriptionsCoalesceAndRespectVisibilityAndLifetime() {
        let live = Live.new(Float(0.0))
        let count = AtomicCounter()
        var wakeRef: LiveWake? = LiveWake { count.increment() }
        let subscription = live.source.subscribe(wakeRef!)
        #expect(subscription === live.source.subscribe(wakeRef!))
        #expect(!live.set(0.0))
        for n in 1..<100 {
            live.set(Float(n))
        }
        #expect(count.load() == 1)
        wakeRef!.pending = false
        wakeRef!.setVisible(false)
        live.set(100.0)
        #expect(count.load() == 1)
        wakeRef!.setVisible(true)
        #expect(count.load() == 2)
        wakeRef!.pending = false
        subscription.active = false
        live.set(101.0)
        #expect(!wakeRef!.pending)
        subscription.active = true
        wakeRef = nil
        live.set(102.0)
        #expect(count.load() == 2)
    }

    @Test("non finite values never panic")
    func nonFiniteValuesNeverPanic() {
        let v = Live.new(Float(0.5))
        #expect(!v.set(.nan))
        #expect(v.get() == 0.5)
        #expect(v.set(.infinity))
        #expect(v.get() == Float.greatestFiniteMagnitude)
        #expect(v.set(-.infinity))
        #expect(v.get() == -Float.greatestFiniteMagnitude)
        #expect(v.set(0.0))
        #expect(!v.set(-0.0))
        #expect(v.get().bitPattern == Float(0.0).bitPattern)
        #expect(Live.new(Float.nan).get() == 0.0)

        let p = Live.new([Float(1.0), Float(2.0)])
        #expect(!p.set([.nan, 3.0]))
        // PORT NOTE: `[Float]` conforms to `LiveValue` for both 2- and 4-lane vectors; decoded `[Float]`
        // always unpacks all 4 lanes with trailing zeros for 2-lane inputs.
        #expect(Array(p.get().prefix(2)) == [1.0, 2.0])

        let r = Live.new([Float](repeating: 0.0, count: 4))
        #expect(r.set([0.0, 0.0, .infinity, 1.0]))
        #expect(r.get() == [0.0, 0.0, Float.greatestFiniteMagnitude, 1.0])

        let c = Live.new(Color(r: 1.0, g: 0.0, b: 0.0, a: 1.0))
        #expect(!c.set(Color(r: .nan, g: 0.0, b: 0.0, a: 1.0)))
        #expect(c.get().r == 1.0)
    }

    @Test("LiveText equal strings do not wake subscribers")
    func liveTextEqualStringsDoNotWake() {
        let text = LiveText.new("hello")
        let count = AtomicCounter()
        let wake = LiveWake { count.increment() }
        _ = text.source.subscribe(wake)
        #expect(!text.set("hello"))
        #expect(count.load() == 0)
        #expect(text.set("world"))
        #expect(text.get() == "world")
        #expect(count.load() == 1)
    }
}
