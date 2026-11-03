// Ported from: crates/rune/src/render/pass.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! The frame pass a renderer records into, and how it splits at a backdrop slot: the pass
//! ends, its target is copied into a pooled texture, and a new pass re-opens with `LoadOp::Load`.

import CWebGPU

public struct Backdrop {
    public let format: WGPUTextureFormat
    public let texture: MetalTexture
    public let view: MetalView
}

final class ActivePass {
    private enum PassInner {
        case borrowed(MetalRenderPass)
        case owned(MetalRenderPass)
    }

    private var inner: PassInner?
    private let encoderAndView: (MetalCommandEncoder, MetalView)?
    private(set) var scissor: [UInt32]? = nil
    private var timestamps: MetalPassTimestampWrites? = nil

    private init(inner: PassInner, encoderAndView: (MetalCommandEncoder, MetalView)?) {
        self.inner = inner
        self.encoderAndView = encoderAndView
    }

    static func borrowed(_ pass: MetalRenderPass) -> ActivePass {
        ActivePass(inner: .borrowed(pass), encoderAndView: nil)
    }

    static func owned(
        _ pass: MetalRenderPass,
        _ encoder: MetalCommandEncoder,
        _ view: MetalView
    ) -> ActivePass {
        ActivePass(inner: .owned(pass), encoderAndView: (encoder, view))
    }

    static func openOwned(
        _ encoder: MetalCommandEncoder,
        _ view: MetalView,
        _ size: [UInt32],
        _ clear: [Float]?,
        inLayer: Bool = false,
        timestamps: MetalPassTimestampWrites? = nil
    ) -> ActivePass {
        let loadOp: MetalLoadOp
        if let c = clear {
            loadOp = .clear(r: Double(c[0]), g: Double(c[1]), b: Double(c[2]), a: Double(c[3]))
        } else {
            loadOp = .load
        }
        let pass = encoder.beginRenderPass(
            label: inLayer ? "isolated group" : "frame",
            colorAttachment: MetalRenderPassColorAttachment(
                view: view,
                loadOp: loadOp,
                storeOp: .store
            ),
            timestampWrites: timestamps
        )
        if size[0] > 0 && size[1] > 0 {
            pass.setViewport(x: 0, y: 0, width: Float(size[0]), height: Float(size[1]))
        }
        return ActivePass.owned(pass, encoder, view).withTimestamps(timestamps)
    }

    func withTimestamps(_ timestamps: MetalPassTimestampWrites?) -> ActivePass {
        self.timestamps = timestamps
        return self
    }

    var pass: MetalRenderPass {
        switch inner {
        case .borrowed(let p): return p
        case .owned(let p): return p
        case .none: fatalError("active pass missing")
        }
    }

    func endIfOwned() {
        if case .owned(let p) = inner {
            p.end()
            inner = nil
        }
    }

    /// Sets the scissor to `rect` (`[x, y, width, height]`), or to the whole `size` target.
    func setScissor(_ rect: [UInt32]?, _ size: [UInt32]) {
        scissor = rect
        let r = rect ?? [0, 0, size[0], size[1]]
        if r[2] > 0 && r[3] > 0 {
            pass.setScissorRect(x: r[0], y: r[1], width: r[2], height: r[3])
        }
    }

    @discardableResult
    func splitForBackdrop(
        _ renderer: Renderer,
        _ at: UInt32,
        _ instance: Instance,
        _ format: WGPUTextureFormat,
        _ origin: [Float],
        _ size: [UInt32],
        _ inLayer: Bool,
        _ hook: EffectBackdropHook
    ) -> MetalView? {
        guard let bd = split(renderer, format, origin, size, inLayer, nil, { encoder, bd in
            let site = EffectSite(
                index: at,
                instance: instance,
                mark: effectMark(instance),
                data: instance.uv,
                scale: instance.params[3],
                format: format,
                origin: origin,
                size: size,
                inLayer: inLayer,
                srgbBlend: renderer.srgbBlendEnabled,
                backdrop: bd.view
            )
            hook(.backdrop(encoder), site)
        }) else {
            return nil
        }
        return bd.view
    }

    /// Ends the pass, copies its target into the pooled backdrop of `format` (all of it, or
    /// only `copy`, a window device-pixel rect `[x0, y0, x1, y1]`), runs `then` on the encoder,
    /// and re-opens the pass with `LoadOp::Load`. `nil` when the pass has no encoder, its
    /// target lacks `COPY_SRC`, or no backdrop of `format` is pooled.
    @discardableResult
    func split(
        _ renderer: Renderer,
        _ format: WGPUTextureFormat,
        _ origin: [Float],
        _ size: [UInt32],
        _ inLayer: Bool,
        _ copy: [Float]?,
        _ then: (MetalCommandEncoder, Backdrop) -> Void
    ) -> Backdrop? {
        guard let (encoder, view) = encoderAndView else { return nil }
        guard (view.raw.usage & UInt32(WGPUTextureUsage_CopySrc)) != 0 else { return nil }
        guard let bd = renderer.backdrops.first(where: { $0.format == format }) else { return nil }

        if case .owned(let p) = inner {
            p.end()
        }
        inner = nil

        let vw = bd.texture.width
        let vh = bd.texture.height
        if inLayer {
            let clearPass = encoder.beginRenderPass(
                label: "backdrop clear",
                colorAttachment: MetalRenderPassColorAttachment(
                    view: bd.view,
                    loadOp: .clear(r: 0, g: 0, b: 0, a: 0),
                    storeOp: .store
                )
            )
            clearPass.end()
        }

        let srcTexW = view.raw.width
        let srcTexH = view.raw.height
        let srcX: UInt32
        let srcY: UInt32
        let dstX: UInt32
        let dstY: UInt32
        let copyW: UInt32
        let copyH: UInt32

        if let r = copy {
            func span(_ lo: Float, _ hi: Float, _ o: Float, _ src: UInt32, _ dst: UInt32) -> (Float, UInt32) {
                let clampedLo = max(max(lo.rounded(.down), o.rounded(.up)), 0.0)
                let clampedHi = min(min(hi.rounded(.up), o + Float(src)), Float(dst))
                return (clampedLo, UInt32(max(clampedHi - clampedLo, 0.0)))
            }
            let (x, w) = span(r[0], r[2], origin[0], min(size[0], srcTexW), vw)
            let (y, h) = span(r[1], r[3], origin[1], min(size[1], srcTexH), vh)
            srcX = UInt32(max(x - origin[0].rounded(.up), 0.0))
            srcY = UInt32(max(y - origin[1].rounded(.up), 0.0))
            dstX = UInt32(x)
            dstY = UInt32(y)
            copyW = w
            copyH = h
        } else {
            let sx = UInt32(max(-origin[0], 0.0))
            let sy = UInt32(max(-origin[1], 0.0))
            let dx = UInt32(max(origin[0], 0.0))
            let dy = UInt32(max(origin[1], 0.0))
            let limSrcW = min(size[0], srcTexW)
            let limSrcH = min(size[1], srcTexH)
            let remSrcW = limSrcW > sx ? (limSrcW - sx) : 0
            let remSrcH = limSrcH > sy ? (limSrcH - sy) : 0
            let remDstW = vw > dx ? (vw - dx) : 0
            let remDstH = vh > dy ? (vh - dy) : 0
            srcX = sx
            srcY = sy
            dstX = dx
            dstY = dy
            copyW = min(remSrcW, remDstW)
            copyH = min(remSrcH, remDstH)
        }

        if copyW > 0 && copyH > 0 {
            let srcTex = MetalTexture(raw: view.raw)
            encoder.copyTextureToTexture(
                source: srcTex,
                sourceMip: view.baseMipLevel,
                sourceLayer: view.baseArrayLayer,
                sourceOrigin: (srcX, srcY),
                destination: bd.texture,
                destinationMip: 0,
                destinationLayer: 0,
                destinationOrigin: (dstX, dstY),
                width: copyW,
                height: copyH
            )
        }

        then(encoder, bd)

        let reopenedTs: MetalPassTimestampWrites?
        if let ts = timestamps, let endIdx = ts.endIndex {
            reopenedTs = MetalPassTimestampWrites(querySet: ts.querySet, beginningIndex: nil, endIndex: endIdx)
        } else {
            reopenedTs = nil
        }

        let next = encoder.beginRenderPass(
            label: inLayer ? "isolated group" : "frame",
            colorAttachment: MetalRenderPassColorAttachment(
                view: view,
                loadOp: .load,
                storeOp: .store
            ),
            timestampWrites: reopenedTs
        )
        if size[0] > 0 && size[1] > 0 {
            next.setViewport(x: 0, y: 0, width: Float(size[0]), height: Float(size[1]))
        }
        if let sc = scissor, sc[2] > 0 && sc[3] > 0 {
            next.setScissorRect(x: sc[0], y: sc[1], width: sc[2], height: sc[3])
        }
        inner = .owned(next)
        return bd
    }
}

extension Renderer {
    func ensureBackdrop(_ device: MetalDevice, _ format: WGPUTextureFormat, _ size: (UInt32, UInt32)) {
        let width = max(size.0, 1)
        let height = max(size.1, 1)
        if let existing = backdrops.first(where: { $0.format == format }),
           existing.texture.width == width && existing.texture.height == height {
            return
        }
        let texture = device.createTexture(
            label: "effect backdrop",
            format: format,
            width: width,
            height: height,
            usage: UInt32(WGPUTextureUsage_TextureBinding | WGPUTextureUsage_CopyDst | WGPUTextureUsage_RenderAttachment)
        )
        let view = texture.createView()
        backdropBlur?.bindBackdrop(device, format, view)
        let bd = Backdrop(format: format, texture: texture, view: view)
        if let idx = backdrops.firstIndex(where: { $0.format == format }) {
            backdrops[idx] = bd
        } else {
            backdrops.append(bd)
        }
    }
}
