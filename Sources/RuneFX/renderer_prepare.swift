// Ported from: crates/rune-fx/src/renderer_prepare.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import CWebGPU
import RuneStaging

extension FxRenderer {
    /// Cull, pack and upload. Layer `i` of `frame.layers` can then be drawn with `drawLayer(pass, i)`.
    @discardableResult
    public func prepare(_ device: WGPUDevice, _ queue: WGPUQueue, _ frame: FxFrame) -> FxStats {
        prepareWithSlots(device, queue, frame, [])
    }

    /// Like `prepare`, with device scale and clipping for each layer's effect slot.
    /// Entries correspond to `frame.layers`; missing entries use `FxSlot()`.
    @discardableResult
    public func prepareWithSlots(
        _ device: WGPUDevice,
        _ queue: WGPUQueue,
        _ frame: FxFrame,
        _ slots: [FxSlot]
    ) -> FxStats {
        if let srgb = self.srgb {
            let target = srgb ? wgpuFormatRemoveSrgbSuffix(format) : wgpuFormatAddSrgbSuffix(format)
            setFormat(target)
        }
        var stats = FxStats()
        scratch.removeAll(keepingCapacity: true)
        scratchXf.removeAll(keepingCapacity: true)
        prepared.removeAll(keepingCapacity: true)
        binds.begin()
        blurBinds.begin()

        let vw = Float(frame.viewport[0])
        let vh = Float(frame.viewport[1])
        viewport = frame.viewport
        blurSlot = 0

        let wantsBlur: (FxLayer) -> Bool = { l in
            switch l.fx {
            case let .distort(.lens(p)):
                return p.frost > 0.0
            case let .fill(fp):
                if case let .flutedGlass(p) = fp.style {
                    return p.frost > 0.0
                }
                return false
            default:
                return false
            }
        }
        if frame.layers.contains(where: wantsBlur) {
            _ = blurPasses.get()
            if blur == nil || blur!.size != frame.viewport {
                blur = BlurPyramid.new(device, frame.viewport, blurBgl, dummy, sampler, blurUniforms)
            }
        }
        sims?.beginFrame()

        for (index, layer) in frame.layers.enumerated() {
            let slot = index < slots.count ? slots[index] : FxSlot()
            guard let packed = layer.pack() else {
                stats.culledIdle += 1
                prepared.append(nil)
                continue
            }
            let kind = packed.0
            var inst = packed.1
            let b = packed.2

            let s = slot.scale > 0.0 ? slot.scale : frame.scale
            let x0 = max(max((b.x * s).rounded(.down), slot.clip[0].rounded(.down)), 0.0)
            let y0 = max(max((b.y * s).rounded(.down), slot.clip[1].rounded(.down)), 0.0)
            let x1 = min(min(((b.x + b.w) * s).rounded(.up), slot.clip[2].rounded(.up)), vw)
            let y1 = min(min(((b.y + b.h) * s).rounded(.up), slot.clip[3].rounded(.up)), vh)
            if x1 <= x0 || y1 <= y0 {
                stats.culledOffscreen += 1
                prepared.append(nil)
                continue
            }

            layer.fill(&inst, &scratchXf)
            let grid: Int?
            if case let .fire(p) = layer.fx, let sims = self.sims, (p.style == .top || p.style == .heat) {
                let (g, ext) = sims.plan(device, layer, p, b, layer.reducedMotion)
                inst.t[2] = 4.0
                inst.aux = [b.x, b.y, ext[0], ext[1]]
                inst.p3[1] = b.w
                inst.p3[2] = b.h
                grid = g
            } else {
                grid = nil
            }

            inst.bounds = SIMD4<Float>(x0, y0, x1, y1)
            let sc = slot.clip
            inst.clip = sc.count >= 4 ? SIMD4<Float>(sc[0], sc[1], sc[2], sc[3]) : SIMD4<Float>(noClip[0], noClip[1], noClip[2], noClip[3])
            let sf = slot.fade
            inst.fade = sf.count >= 4 ? SIMD4<UInt32>(sf[0], sf[1], sf[2], sf[3]) : .zero
            inst.shape[1] = s
            inst.t[3] = Float(UInt32(max(inst.t[3], 0.0)) | (slot.blend.code() << 1))

            let needsBd = layer.fx.needsBackdrop() || slot.blend.needsBackdrop()
            if needsBd {
                stats.needsBackdrop = true
            }
            let blurPx: Float
            switch layer.fx {
            case let .distort(.lens(p)):
                blurPx = max(min(max(p.frost, 0.0), 1.0) * lensFrostSigma * s, 0.0)
            case let .fill(fp):
                if case let .flutedGlass(p) = fp.style {
                    blurPx = max(min(max(p.frost, 0.0), 1.0) * lensFrostSigma * s, 0.0)
                } else {
                    blurPx = 0.0
                }
            default:
                blurPx = 0.0
            }

            let readsBd = needsBd && frame.backdrop != nil
            let bd = readsBd ? frame.backdrop! : dummy
            let src: WGPUTextureView
            if let g = grid, let sims = self.sims {
                src = sims.finalView(g)
            } else if let srcSpec = layer.source, Int(srcSpec.slot) < frame.sources.count {
                src = frame.sources[Int(srcSpec.slot)]
            } else {
                src = dummy
            }
            let blurred: WGPUTextureView = (blurPx > 0.0 && frame.backdrop != nil)
                ? (blur?.result ?? dummy)
                : dummy
            let enc = ((readsBd ? 1 : 0) << 1) | ((slot.backdropSrgb ?? false) ? 1 : 0)
            let bind = fx1(&binds, device, bgl1, sampler, backdropEncoding, [bd, src, blurred], enc)

            stats.drawn += 1
            stats.pixels += UInt64((x1 - x0) * (y1 - y0))
            let instIndex = UInt32(scratch.count)
            let bdSrgb = slot.backdropSrgb ?? (frame.backdrop == nil && (srgb ?? false))
            prepared.append(Prepared(
                kind: kind,
                instance: instIndex,
                bind: bind,
                bounds: [x0, y0, x1, y1],
                blurPx: blurPx,
                needsBackdrop: needsBd,
                backdropSrgb: bdSrgb,
                blend: slot.blend,
                bdView: bd,
                srcView: src,
                blurView: blurred,
                enc: enc
            ))
            scratch.append(inst)
        }

        var regrow = (bg0 == nil)
        if scratch.count > instCap {
            instCap = Int(nextPowerOfTwo(UInt64(scratch.count)))
            insts = FxRenderer.storageBuffer(device, "fx insts", instCap * instByteSize)
            regrow = true
        }
        if scratchXf.count > xformCap {
            xformCap = Int(nextPowerOfTwo(UInt64(scratchXf.count)))
            xforms = FxRenderer.storageBuffer(device, "fx xforms", xformCap * 16)
            regrow = true
        }
        if regrow {
            bg0 = createFXBindGroup(device, "fx0", bgl0, [
                (0, .buffer(globals, offset: 0, size: UInt64.max)),
                (1, .buffer(insts, offset: 0, size: UInt64.max)),
                (2, .buffer(xforms, offset: 0, size: UInt64.max)),
            ])
        }

        let staging = self.staging(device, queue)
        if !scratch.isEmpty {
            var instBytes = [UInt8]()
            instBytes.reserveCapacity(scratch.count * instByteSize)
            for raw in scratch {
                instBytes.append(contentsOf: raw.toBytes())
            }
            staging.writeBuffer(insts, 0, instBytes)
        }
        if !scratchXf.isEmpty {
            var xfBytes = [UInt8]()
            xfBytes.reserveCapacity(scratchXf.count * 16)
            for vec in scratchXf {
                for lane in 0..<4 {
                    let bits = vec[lane].bitPattern.littleEndian
                    xfBytes.append(UInt8(truncatingIfNeeded: bits))
                    xfBytes.append(UInt8(truncatingIfNeeded: bits >> 8))
                    xfBytes.append(UInt8(truncatingIfNeeded: bits >> 16))
                    xfBytes.append(UInt8(truncatingIfNeeded: bits >> 24))
                }
            }
            staging.writeBuffer(xforms, 0, xfBytes)
        }

        let g: [Float] = [vw, vh, opts.dither ? 1.0 : 0.0, (srgb ?? false) ? 1.0 : 0.0]
        let prev = stagingState!.1
        let same = prev.count == 4 && prev[0] == g[0] && prev[1] == g[1] && prev[2] == g[2] && prev[3] == g[3]
        if !same {
            stagingState!.1 = g
            var gBytes = [UInt8]()
            gBytes.reserveCapacity(16)
            for v in g {
                let bits = v.bitPattern.littleEndian
                gBytes.append(UInt8(truncatingIfNeeded: bits))
                gBytes.append(UInt8(truncatingIfNeeded: bits >> 8))
                gBytes.append(UInt8(truncatingIfNeeded: bits >> 16))
                gBytes.append(UInt8(truncatingIfNeeded: bits >> 24))
            }
            staging.writeBuffer(globals, 0, gBytes)
        }
        staging.submit()

        let wanted = prepared.compactMap { p -> (Int, Int)? in
            guard let p else { return nil }
            return (p.kind, blendIndex(p.blend))
        }
        pipes.warm(format, wanted)
        return stats
    }

    /// The upload staging; its globals start unknown (`NaN`), so the first `prepare` writes them.
    func staging(_ device: WGPUDevice, _ queue: WGPUQueue) -> Staging {
        if let existing = stagingState {
            return existing.0
        }
        let created = SyntheticFXGPU.shared.isLiveDevice(device)
            ? Staging.new(device, queue)
            : Staging.headless()
        stagingState = (created, [.nan, .nan, .nan, .nan])
        return created
    }
}
