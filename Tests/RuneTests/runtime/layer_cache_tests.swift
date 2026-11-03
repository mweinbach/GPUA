// Tests ported from: crates/rune/src/runtime/layer_cache_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import RuneMotion
import Testing
@testable import Rune

@Suite("LayerCacheTests")
struct LayerCacheTests {
    @Test("LayerCacheStore inserts, looks up, prunes dead NodeIds, evicts, and clears")
    func layerCacheStoreLifecycle() {
        var store = LayerCacheStore()
        let idA = RuneMotion.NodeId(101)
        let idB = RuneMotion.NodeId(202)
        let entry = CachedLayerEntry(
            signature: 0xDEAD_BEEF,
            rasterScale: 2.0,
            seenScale: 2.0,
            scaleChangedAt: 0.0,
            envScale: 2.0,
            wasLive: false,
            relBounds: [0.0, 0.0, 48.0, 32.0],
            glyphs: 6,
            commitGen: 1,
            paintStateHash: 42
        )
        store.insert(idA, entry)
        store.insert(idB, entry)
        #expect(store.get(idA)?.signature == 0xDEAD_BEEF)
        #expect(store.get(idB)?.glyphs == 6)

        store.prune(keeping: [idA])
        #expect(store.get(idA) != nil)
        #expect(store.get(idB) == nil)

        store.evict(idA)
        #expect(store.get(idA) == nil)
    }

    @Test("sealCacheLayerMarker packs NodeId, non-zero signature, and appends KIND_LAYER_END")
    func sealCacheLayerMarkerPacksMetadata() {
        var instances: [Instance] = [
            Instance.beginLayer([4.0, 6.0, 40.0, 28.0], NO_CLIP, LayerSpec(opacity: 1.0))
        ]
        sealCacheLayerMarker(
            &instances,
            start: 0,
            rect: [8.0, 10.0, 40.0, 28.0],
            id: RuneMotion.NodeId(0x1234_5678_9ABC_DEF0),
            signature: 0
        )
        #expect(instances.count == 2)
        #expect(instances[0].rect == [8.0, 10.0, 40.0, 28.0])
        #expect(instances[0].params[1] == KIND_LAYER)
        #expect(instances[0].params[3] == 1.0)
        #expect(instances[1].params[1] == KIND_LAYER_END)
    }

    @Test("Clicks land on panned card children under liveOffset without rebuilding the view")
    func clicksLandAfterLiveOffsetPanWithoutCommit() {
        let pan = Live<[Float]>.new([0.0, 0.0])
        let rt: Runtime<Int> = Runtime.new(0, { _, _ in
            el().size(96.0, 64.0).child(
                el().size(96.0, 64.0).liveOffset(Binding(live: pan)).child(
                    el().size(32.0, 32.0).bg(.WHITE).child(
                        el().key("button").size(16.0, 16.0).bg(Color(r: 1.0, g: 0.0, b: 0.0, a: 1.0))
                            .onPress { (count: inout Int, _) in count += 1 }
                    )
                )
            )
        }, (96.0, 64.0), Env.new(true, 1.0))

        _ = rt.frame(0.0)
        let commitsBeforePan = rt.totalCommits

        pan.set([50.0, 30.0])
        _ = rt.frame(1.0 / 60.0)
        #expect(rt.totalCommits == commitsBeforePan)

        // Old un-panned location misses; panned location hits
        for (x, y) in [(Float(8.0), Float(8.0)), (Float(58.0), Float(38.0))] {
            rt.pointerMove(x, y)
            rt.pointerDown(x, y)
            rt.pointerUp(x, y)
            _ = rt.frame(1.0 / 60.0)
        }
        #expect(rt.state == 1)
        let btn = rtElement(rt, "button")!
        #expect([btn.rect[0], btn.rect[1]] == [50.0, 30.0])
    }
}
