// Ported from: crates/rune/src/window/presented.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Deduplicates identical rendered frames (`crates/rune/src/window/presented.rs`).

/// Tracks the last presented instance/layer buffer + atlas generations so unchanged idle frames skip GPU submission.
// PORT NOTE: Named `WindowPresented` instead of `Presented` because `Sources/Rune/lib.swift` re-exports `RuneMotion.Presented` as `public typealias Presented`.
struct WindowPresented: Sendable {
    private var valid: Bool = false
    private var size: (UInt32, UInt32) = (0, 0)
    private var clear: [Float] = [0, 0, 0, 0]
    private var glyphGen: UInt64 = 0
    private var imageCopies: UInt64 = 0
    private var effectGens: [(UInt32, UInt64)] = []
    private var layers: [LayerSpec] = []
    private var instances: [Instance] = []

    init() {}

    mutating func invalidate() {
        valid = false
    }

    func same<S>(
        size: (UInt32, UInt32),
        clear: Color,
        rt: Runtime<S>,
        instances: [Instance],
        layers: [LayerSpec],
        effectGens: [(UInt32, UInt64)] = []
    ) -> Bool {
        guard valid else { return false }
        let clearRgba = [clear.r, clear.g, clear.b, clear.a]
        let atlasGen = rt.text.atlas.resets() &+ rt.text.atlas.rasterized()
        guard self.size.0 == size.0,
              self.size.1 == size.1,
              self.clear == clearRgba,
              self.glyphGen == atlasGen,
              self.imageCopies == rt.images.copies,
              self.effectGens.count == effectGens.count,
              zip(self.effectGens, effectGens).allSatisfy({ $0.0.0 == $0.1.0 && $0.0.1 == $0.1.1 }),
              self.layers == layers,
              self.instances == instances
        else {
            return false
        }
        return true
    }

    mutating func record<S>(
        size: (UInt32, UInt32),
        clear: Color,
        rt: Runtime<S>,
        instances: [Instance],
        layers: [LayerSpec],
        effectGens: [(UInt32, UInt64)] = []
    ) {
        self.valid = true
        self.size = size
        self.clear = [clear.r, clear.g, clear.b, clear.a]
        self.glyphGen = rt.text.atlas.resets() &+ rt.text.atlas.rasterized()
        self.imageCopies = rt.images.copies
        self.effectGens = effectGens
        self.layers = layers
        self.instances = instances
    }

    func unchanged<S>(
        size: (UInt32, UInt32),
        clear: Color,
        rt: Runtime<S>,
        instances: [Instance],
        layers: [LayerSpec],
        stats: FrameStats,
        effectGens: [(UInt32, UInt64)] = []
    ) -> Bool {
        !stats.animating
            && !rt.hostLivePending()
            && same(
                size: size,
                clear: clear,
                rt: rt,
                instances: instances,
                layers: layers,
                effectGens: effectGens
            )
    }

    mutating func settle<S>(
        size: (UInt32, UInt32),
        clear: Color,
        rt: Runtime<S>,
        instances: [Instance],
        layers: [LayerSpec],
        stats: FrameStats,
        effectGens: [(UInt32, UInt64)] = []
    ) {
        if stats.animating {
            valid = false
        } else {
            record(
                size: size,
                clear: clear,
                rt: rt,
                instances: instances,
                layers: layers,
                effectGens: effectGens
            )
        }
    }
}
