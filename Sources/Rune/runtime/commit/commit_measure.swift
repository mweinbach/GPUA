// Ported from: crates/rune/src/runtime/commit/measure.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Taffy leaf/container measurement callback (`text`, `pixels`, `aspectFit`).

import Taffy

enum NodeMeasureContext: Sendable {
    case text(Int)
    case pixels(UInt32, UInt32)
    case aspectFit(Float)
}

// PORT NOTE: `TaffyTree.computeLayoutWithMeasure` invokes `MeasureFunction` synchronously on the
// calling runtime thread before returning, so this non-escaping lifetime bridge is single-threaded.
private final class SynchronousMeasureBridge<S>: @unchecked Sendable {
    unowned let runtime: Runtime<S>
    init(_ runtime: Runtime<S>) {
        self.runtime = runtime
    }
}

extension Runtime {
    func makeTaffyMeasureClosure() -> TaffyTree<NodeMeasureContext>.MeasureFunction {
        let bridge = SynchronousMeasureBridge(self)
        return { known, avail, _, ctx, _ in
            bridge.runtime.measureNodeLeaf(knownDimensions: known, availableSpace: avail, context: ctx)
        }
    }

    func measureNodeLeaf(
        knownDimensions: Size<Float?>,
        availableSpace: Size<AvailableSpace>,
        context: NodeMeasureContext?
    ) -> Size<Float> {
        guard let context else {
            return Size(width: knownDimensions.width ?? 0.0, height: knownDimensions.height ?? 0.0)
        }

        switch context {
        case .text(let nodeIdx):
            guard nodes.indices.contains(nodeIdx), let spec = nodes[nodeIdx].textSpec else {
                return Size(width: knownDimensions.width ?? 0.0, height: knownDimensions.height ?? 0.0)
            }
            let maxW: Float? = {
                if let kw = knownDimensions.width {
                    return kw
                }
                switch availableSpace.width {
                case .definite(let aw):
                    return aw
                case .minContent:
                    return 0.01
                case .maxContent:
                    return nil
                }
            }()

            // Empty input fields still measure to at least placeholder width and 1 line height.
            let isSecret = spec.redacted || (nodes[nodeIdx].input?.edit.isSecure() == true)
            var effectiveSpec = spec
            if effectiveSpec.content.isEmpty, let inp = nodes[nodeIdx].input, !inp.placeholder.isEmpty {
                effectiveSpec.content = inp.placeholder
            }

            let cacheKey = makeTextLayoutCacheKey(effectiveSpec, maxWidth: maxW)
            let layout: RtTextLayout
            if !isSecret, let cached = textLayoutCache[cacheKey] {
                layout = cached
            } else {
                let prevText = isSecret ? nil : previousShapedByPath[nodes[nodeIdx].path]
                let computed = layoutTextSpec(
                    effectiveSpec,
                    maxWidth: maxW,
                    textSys: text,
                    previouslyShapedText: prevText
                )
                if !isSecret {
                    previousShapedByPath[nodes[nodeIdx].path] = effectiveSpec.content
                    textLayoutCache[cacheKey] = computed
                }
                layout = computed
            }

            // Store real text layout on the node (using actual `spec`, not placeholder)
            if spec.content != effectiveSpec.content {
                let emptyKey = makeTextLayoutCacheKey(spec, maxWidth: maxW)
                let realLayout = (!isSecret ? textLayoutCache[emptyKey] : nil)
                    ?? layoutTextSpec(spec, maxWidth: maxW, textSys: text, previouslyShapedText: spec.content)
                if !isSecret {
                    textLayoutCache[emptyKey] = realLayout
                }
                nodes[nodeIdx].textLayout = realLayout
            } else {
                nodes[nodeIdx].textLayout = layout
            }

            let minLineH = spec.style.linePx()
            let measuredW = knownDimensions.width ?? layout.width
            let measuredH = knownDimensions.height ?? max(layout.height, minLineH)
            return Size(width: measuredW, height: measuredH)

        case .pixels(let pw, let ph):
            let iw = Float(pw)
            let ih = Float(ph)
            if let kw = knownDimensions.width, let kh = knownDimensions.height {
                return Size(width: kw, height: kh)
            }
            if let kw = knownDimensions.width {
                return Size(width: kw, height: (iw > 0.0 && ih > 0.0) ? kw * (ih / iw) : 0.0)
            }
            if let kh = knownDimensions.height {
                return Size(width: (iw > 0.0 && ih > 0.0) ? kh * (iw / ih) : 0.0, height: kh)
            }
            return Size(width: 0.0, height: 0.0)

        case .aspectFit(let ratio):
            let safeRatio = max(ratio, 1e-4)
            let availW: Float? = knownDimensions.width ?? {
                if case .definite(let w) = availableSpace.width { return w }
                return nil
            }()
            let availH: Float? = knownDimensions.height ?? {
                if case .definite(let h) = availableSpace.height { return h }
                return nil
            }()
            switch (availW, availH) {
            case (let w?, let h?):
                let fitW = min(w, h * safeRatio)
                let fitH = fitW / safeRatio
                return Size(width: max(fitW, 0.0), height: max(fitH, 0.0))
            case (let w?, nil):
                return Size(width: max(w, 0.0), height: max(w / safeRatio, 0.0))
            case (nil, let h?):
                return Size(width: max(h * safeRatio, 0.0), height: max(h, 0.0))
            case (nil, nil):
                return Size(width: 0.0, height: 0.0)
            }
        }
    }
}
