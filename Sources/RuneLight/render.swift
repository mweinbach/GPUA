// Ported from: crates/rune-light/src/render.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import CWebGPU
import RuneStaging

extension LightRenderer {
    /// Encodes all lighting passes onto `encoder`, reading the unlit UI in `base` and writing the
    /// lit UI to `out`.
    ///
    /// Pass linear-light views (see ``surfaceView(_:)``). `base` and `out` must be distinct textures.
    /// Returns `false` and records nothing when lighting is disabled or has no active contributors;
    /// the caller should then present or blit `base` directly.
    @discardableResult
    public func render(
        _ encoder: WGPUCommandEncoder,
        _ base: WGPUTextureView,
        _ glyphMask: WGPUTextureView?,
        _ out: WGPUTextureView,
        _ size: (UInt32, UInt32),
        _ scene: Scene,
        _ settings: Settings
    ) -> Bool {
        let hasEmitters = scene.extraEmission != nil
            || scene.prims.contains(where: { ($0.flags() & FLAG_EMISSIVE) != 0 })
        if !settings.enabled
            || size.0 == 0
            || size.1 == 0
            || (scene.lights.isEmpty && !(settings.gi.enabled && hasEmitters)) {
            lastPasses = 0
            return false
        }

        let s = max(scene.scale, 1e-4)
        var zmax: Float = 0.0
        var prims: [Prim] = []
        prims.reserveCapacity(scene.prims.count)
        for p in scene.prims {
            var pr = p
            for k in 0..<4 {
                pr.rect[k] *= s
                pr.radii[k] *= s
            }
            pr.z[0] *= s
            pr.z[1] *= s
            pr.z[2] *= s
            pr.z[3] *= s
            if pr.z[1] > zmax {
                zmax = pr.z[1]
            }
            prims.append(pr)
        }

        let maxLightCount = min(scene.lights.count, MAX_LIGHTS)
        var lights: [Light] = []
        lights.reserveCapacity(maxLightCount)
        for idx in 0..<maxLightCount {
            lights.append(scene.lights[idx].scaled(s))
        }

        if prims.count > primCap {
            primCap = Int(nextPowerOfTwo(UInt64(prims.count)))
            primBuf = createBuffer(
                device,
                "light.prims",
                UInt64(primCap * Prim.gpuByteStride),
                WGPUBufferUsage_Storage | WGPUBufferUsage_CopyDst
            )
            rebindPrims()
        }

        let fScale = min(max(settings.fieldScale, 0.125), 1.0)
        let t = targets(size, fScale)
        let runGi = settings.gi.enabled
            && (hasEmitters || (settings.gi.bounce > 0.0 && !lights.isEmpty))
        let giScale = min(max(settings.gi.scale, 0.125), 0.5)
        if runGi {
            _ = giTargets(size, giScale, t.field, t.gb0)
            if settings.inspectCascade != nil {
                ownTargets(t.field, t.gb0)
            }
        }

        let fs = t.fieldSize
        let giSize = runGi ? giTargetsCache!.giSize : (1, 1)
        let cascadesCount = min(max(settings.gi.cascades, 1), UInt32(CASCADES))

        var flags: UInt32 = 0
        if runGi { flags |= 1 }
        if settings.shafts { flags |= 2 }
        if glyphMask != nil && settings.text != .none { flags |= 4 }
        if glyphMask != nil && settings.text == .cast { flags |= 8 }
        if scene.extraEmission != nil { flags |= 16 }

        let srgbFlag: Float = isSrgbTextureFormat(surfaceFormat) ? 1.0 : 0.0
        let frame = FrameU(
            surfField: SIMD4<Float>(Float(size.0), Float(size.1), Float(fs.0), Float(fs.1)),
            giScales: SIMD4<Float>(
                Float(giSize.0),
                Float(giSize.1),
                Float(fs.0) / Float(size.0),
                Float(giSize.0) / Float(size.0)
            ),
            counts: SIMD4<UInt32>(UInt32(prims.count), UInt32(lights.count), cascadesCount, flags),
            ambient: SIMD4<Float>(
                settings.ambient[0],
                settings.ambient[1],
                settings.ambient[2],
                settings.ambientStrength
            ),
            strengths: SIMD4<Float>(
                settings.bevelStrength,
                settings.specularStrength,
                settings.dither,
                Float(bitPattern: settings.debug)
            ),
            giParams: SIMD4<Float>(
                settings.gi.strength,
                0.0,
                settings.gi.bounce,
                settings.gi.occlusion
            ),
            misc: SIMD4<Float>(zmax, s, 0.0, 0.0),
            extra: SIMD4<Float>(srgbFlag, scene.extraEmissionGain, 0.0, 0.0),
            pad: .zero
        )

        staging.writeBuffer(frameBuf, 0, frame.toBytes())
        if !prims.isEmpty {
            var primBytes: [UInt8] = []
            primBytes.reserveCapacity(prims.count * Prim.gpuByteStride)
            for pr in prims {
                pr.appendBytes(to: &primBytes)
            }
            staging.writeBuffer(primBuf, 0, primBytes)
        }
        if !lights.isEmpty {
            var lightBytes: [UInt8] = []
            lightBytes.reserveCapacity(lights.count * Light.gpuByteStride)
            for l in lights {
                l.appendBytes(to: &lightBytes)
            }
            staging.writeBuffer(lightBuf, 0, lightBytes)
        }
        staging.flush(encoder)
        let primCapSnap = primCap

        let isLive = SyntheticLightGPU.shared.isLiveDevice(device)

        // 1. G-buffer: rasterise primitives in painter's order (own SDF, analytical normal, top z, id+1).
        #if os(Linux) || os(Android) || os(WASI)
        if isLive {
            recordGbufferPass(
                encoder: encoder,
                t: t,
                primCount: UInt32(prims.count),
                tsQs: tsQs
            )
        }
        #endif

        // 2-4. Compute: scene field, soft shadow + shafts, optional radiance cascades.
        var passes: UInt32 = (tsQs != nil) ? 1 : 0
        var sbgForGi: WGPUBindGroup?
        if runGi {
            let extra = scene.extraEmission ?? black
            let pBuf = primBuf
            let lBuf = lightBuf
            let lin = linear
            let gSceneBgl = giSceneBgl
            let gEmit = giTargetsCache!.sceneEmit
            let gOcc = giTargetsCache!.sceneOcc
            let dev = device
            sbgForGi = sceneBg.get(SceneBgKey(extra: tv(extra), primCap: primCapSnap)) {
                bind(dev, "light.gi.scene.bg", gSceneBgl, [
                    .buf(pBuf),
                    .buf(lBuf),
                    .view(t.vis),
                    .view(extra),
                    .samp(lin),
                    .view(gEmit),
                    .view(gOcc),
                ])
            }
        }

        passes += 2
        #if os(Linux) || os(Android) || os(WASI)
        if isLive {
            recordFieldComputePass(encoder: encoder, t: t, fs: fs, qs: tsQs)
            recordShadowComputePass(
                encoder: encoder,
                t: t,
                fs: fs,
                hasLights: !lights.isEmpty,
                qs: tsQs
            )
        }
        #endif

        if runGi, let sbg = sbgForGi, let g = giTargetsCache {
            passes += 2 + cascadesCount
            if settings.inspectCascade != nil && !g.ownBgs.isEmpty {
                passes += 1
            }
            #if os(Linux) || os(Android) || os(WASI)
            if isLive {
                recordGiComputePasses(
                    encoder: encoder,
                    sbg: sbg,
                    g: g,
                    cascadesCount: Int(cascadesCount),
                    inspectCascade: settings.inspectCascade,
                    qs: tsQs
                )
            }
            #endif
        }

        if tsQs != nil {
            passes += 1
        }

        // 5. Composite: bevel + GGX + shafts + GI fluence + glyph emboss + IGN dither -> out.
        let glyph = glyphMask ?? black
        let fluView = runGi ? giTargetsCache!.fluence : black
        let cascView: WGPUTextureView = {
            guard runGi, let g = giTargetsCache else { return black }
            if let k = settings.inspectCascade {
                let clamped = min(max(k, 0), g.own.count - 1)
                return g.own[clamped]
            }
            return g.levels[0]
        }()

        let dev = device
        let cBgl = compBgl
        let fBuf = frameBuf
        let pBuf = primBuf
        let lBuf = lightBuf
        let lin = linear
        let cbg = compBg.get(CompBgKey(
            base: tv(base),
            glyph: tv(glyph),
            gb0: tv(t.gb0),
            gb1: tv(t.gb1),
            field: tv(t.field),
            flu: tv(fluView),
            casc: tv(cascView),
            primCap: primCapSnap
        )) {
            bind(dev, "light.comp.bg", cBgl, [
                .buf(fBuf),
                .buf(pBuf),
                .buf(lBuf),
                .view(base),
                .view(t.gb0),
                .view(t.gb1),
                .view(t.field),
                .view(t.vis),
                .view(t.air),
                .view(fluView),
                .view(glyph),
                .samp(lin),
                .view(cascView),
            ])
        }

        #if os(Linux) || os(Android) || os(WASI)
        if isLive {
            recordCompositePass(encoder: encoder, out: out, cbg: cbg)
            if let qs = tsQs, let res = tsResolve, let read = tsRead {
                let count: UInt32 = runGi ? 8 : 6
                wgpuCommandEncoderResolveQuerySet(encoder, qs, 0, count, res, 0)
                if !tsMapped {
                    wgpuCommandEncoderCopyBufferToBuffer(encoder, res, 0, read, 0, 64)
                }
            }
        }
        #else
        _ = out
        _ = cbg
        #endif

        lastHasGi = runGi
        lastPasses = passes
        return true
    }

    /// Number of compute passes encoded by the most recent ``render(_:_:_:_:_:_:_:)`` call (for tests).
    public func computePasses() -> UInt32 {
        lastPasses
    }
}

func isSrgbTextureFormat(_ format: WGPUTextureFormat) -> Bool {
    switch format {
    case WGPUTextureFormat_RGBA8UnormSrgb,
         WGPUTextureFormat_BGRA8UnormSrgb,
         WGPUTextureFormat_BC1RGBAUnormSrgb,
         WGPUTextureFormat_BC2RGBAUnormSrgb,
         WGPUTextureFormat_BC3RGBAUnormSrgb,
         WGPUTextureFormat_BC7RGBAUnormSrgb,
         WGPUTextureFormat_ETC2RGB8UnormSrgb,
         WGPUTextureFormat_ETC2RGB8A1UnormSrgb,
         WGPUTextureFormat_ETC2RGBA8UnormSrgb,
         WGPUTextureFormat_ASTC4x4UnormSrgb,
         WGPUTextureFormat_ASTC5x4UnormSrgb,
         WGPUTextureFormat_ASTC5x5UnormSrgb,
         WGPUTextureFormat_ASTC6x5UnormSrgb,
         WGPUTextureFormat_ASTC6x6UnormSrgb,
         WGPUTextureFormat_ASTC8x5UnormSrgb,
         WGPUTextureFormat_ASTC8x6UnormSrgb,
         WGPUTextureFormat_ASTC8x8UnormSrgb,
         WGPUTextureFormat_ASTC10x5UnormSrgb,
         WGPUTextureFormat_ASTC10x6UnormSrgb,
         WGPUTextureFormat_ASTC10x8UnormSrgb,
         WGPUTextureFormat_ASTC10x10UnormSrgb,
         WGPUTextureFormat_ASTC12x10UnormSrgb,
         WGPUTextureFormat_ASTC12x12UnormSrgb:
        return true
    default:
        return false
    }
}

#if os(Linux) || os(Android) || os(WASI)
extension LightRenderer {
    fileprivate func recordGbufferPass(
        encoder: WGPUCommandEncoder,
        t: Targets,
        primCount: UInt32,
        tsQs: WGPUQuerySet?
    ) {
        var ca0 = WGPURenderPassColorAttachment()
        ca0.view = t.gb0
        ca0.depthSlice = WGPU_DEPTH_SLICE_UNDEFINED
        ca0.loadOp = WGPULoadOp_Clear
        ca0.storeOp = WGPUStoreOp_Store
        ca0.clearValue = WGPUColor(r: 1e4, g: 0.0, b: 0.0, a: 0.0)

        var ca1 = WGPURenderPassColorAttachment()
        ca1.view = t.gb1
        ca1.depthSlice = WGPU_DEPTH_SLICE_UNDEFINED
        ca1.loadOp = WGPULoadOp_Clear
        ca1.storeOp = WGPUStoreOp_Store
        ca1.clearValue = WGPUColor(r: 0.0, g: 0.0, b: 0.0, a: 0.0)

        let attachments = [ca0, ca1]
        withWGPUStringView("light.gbuffer") { labelView in
            attachments.withUnsafeBufferPointer { attBuf in
                var tsWrites = WGPURenderPassTimestampWrites()
                if let qs = tsQs {
                    tsWrites.querySet = qs
                    tsWrites.beginningOfPassWriteIndex = 0
                    tsWrites.endOfPassWriteIndex = 1
                }
                withUnsafePointer(to: &tsWrites) { tsPtr in
                    var desc = WGPURenderPassDescriptor()
                    desc.label = labelView
                    desc.colorAttachmentCount = attBuf.count
                    desc.colorAttachments = attBuf.baseAddress
                    desc.timestampWrites = (tsQs != nil) ? tsPtr : nil
                    if let pass = wgpuCommandEncoderBeginRenderPass(encoder, &desc) {
                        if primCount > 0 {
                            wgpuRenderPassEncoderSetPipeline(pass, gbPipe)
                            wgpuRenderPassEncoderSetBindGroup(pass, 0, gbBg, 0, nil)
                            wgpuRenderPassEncoderDraw(pass, 4, primCount, 0, 0)
                        }
                        wgpuRenderPassEncoderEnd(pass)
                        wgpuRenderPassEncoderRelease(pass)
                    }
                }
            }
        }
    }

    fileprivate func recordFieldComputePass(
        encoder: WGPUCommandEncoder,
        t: Targets,
        fs: (UInt32, UInt32),
        qs: WGPUQuerySet?
    ) {
        withWGPUStringView("light.field") { labelView in
            var tsWrites = WGPUComputePassTimestampWrites()
            if let qs {
                tsWrites.querySet = qs
                tsWrites.beginningOfPassWriteIndex = 2
                tsWrites.endOfPassWriteIndex = 3
            }
            withUnsafePointer(to: &tsWrites) { tsPtr in
                var desc = WGPUComputePassDescriptor(
                    nextInChain: nil,
                    label: labelView,
                    timestampWrites: (qs != nil) ? tsPtr : nil
                )
                if let pass = wgpuCommandEncoderBeginComputePass(encoder, &desc) {
                    wgpuComputePassEncoderSetPipeline(pass, fieldPipe)
                    wgpuComputePassEncoderSetBindGroup(pass, 0, t.fieldBg, 0, nil)
                    wgpuComputePassEncoderDispatchWorkgroups(pass, (fs.0 + 15) / 16, (fs.1 + 15) / 16, 1)
                    wgpuComputePassEncoderEnd(pass)
                    wgpuComputePassEncoderRelease(pass)
                }
            }
        }
    }

    fileprivate func recordShadowComputePass(
        encoder: WGPUCommandEncoder,
        t: Targets,
        fs: (UInt32, UInt32),
        hasLights: Bool,
        qs: WGPUQuerySet?
    ) {
        withWGPUStringView("light.shadow") { labelView in
            var tsWrites = WGPUComputePassTimestampWrites()
            if let qs {
                tsWrites.querySet = qs
                tsWrites.beginningOfPassWriteIndex = 4
                tsWrites.endOfPassWriteIndex = 5
            }
            withUnsafePointer(to: &tsWrites) { tsPtr in
                var desc = WGPUComputePassDescriptor(
                    nextInChain: nil,
                    label: labelView,
                    timestampWrites: (qs != nil) ? tsPtr : nil
                )
                if let pass = wgpuCommandEncoderBeginComputePass(encoder, &desc) {
                    if hasLights {
                        wgpuComputePassEncoderSetPipeline(pass, shadowPipe)
                        wgpuComputePassEncoderSetBindGroup(pass, 0, t.shadowBg, 0, nil)
                        wgpuComputePassEncoderDispatchWorkgroups(pass, (fs.0 + 7) / 8, (fs.1 + 7) / 8, 1)
                    }
                    wgpuComputePassEncoderEnd(pass)
                    wgpuComputePassEncoderRelease(pass)
                }
            }
        }
    }

    fileprivate func recordSingleGiPass(
        encoder: WGPUCommandEncoder,
        label: String,
        tsPair: (UInt32, UInt32)?,
        qs: WGPUQuerySet?,
        body: (WGPUComputePassEncoder) -> Void
    ) {
        withWGPUStringView(label) { labelView in
            var tsWrites = WGPUComputePassTimestampWrites()
            let hasTs = (qs != nil && tsPair != nil)
            if let qs, let tsPair {
                tsWrites.querySet = qs
                tsWrites.beginningOfPassWriteIndex = tsPair.0
                tsWrites.endOfPassWriteIndex = tsPair.1
            }
            withUnsafePointer(to: &tsWrites) { tsPtr in
                var desc = WGPUComputePassDescriptor(
                    nextInChain: nil,
                    label: labelView,
                    timestampWrites: hasTs ? tsPtr : nil
                )
                if let pass = wgpuCommandEncoderBeginComputePass(encoder, &desc) {
                    wgpuComputePassEncoderSetBindGroup(pass, 0, frameBg, 0, nil)
                    body(pass)
                    wgpuComputePassEncoderEnd(pass)
                    wgpuComputePassEncoderRelease(pass)
                }
            }
        }
    }

    fileprivate func recordGiComputePasses(
        encoder: WGPUCommandEncoder,
        sbg: WGPUBindGroup,
        g: GiTargets,
        cascadesCount: Int,
        inspectCascade: Int?,
        qs: WGPUQuerySet?
    ) {
        recordSingleGiPass(encoder: encoder, label: "gi.scene", tsPair: (6, 6), qs: qs) { pass in
            wgpuComputePassEncoderSetPipeline(pass, giScenePipe)
            wgpuComputePassEncoderSetBindGroup(pass, 1, sbg, 0, nil)
            wgpuComputePassEncoderDispatchWorkgroups(pass, (g.giSize.0 + 7) / 8, (g.giSize.1 + 7) / 8, 1)
        }

        let cw = (g.giSize.0 * 2 + 7) / 8
        let ch = (g.giSize.1 * 2 + 7) / 8
        for n in stride(from: cascadesCount - 1, through: 0, by: -1) {
            recordSingleGiPass(encoder: encoder, label: "gi.cascade", tsPair: nil, qs: nil) { pass in
                wgpuComputePassEncoderSetPipeline(pass, giCascPipe)
                wgpuComputePassEncoderSetBindGroup(pass, 1, g.cascBgs[n], 0, nil)
                wgpuComputePassEncoderDispatchWorkgroups(pass, cw, ch, 1)
            }
        }

        recordSingleGiPass(encoder: encoder, label: "gi.fluence", tsPair: (7, 7), qs: qs) { pass in
            wgpuComputePassEncoderSetPipeline(pass, giFluPipe)
            wgpuComputePassEncoderSetBindGroup(pass, 1, g.fluBg, 0, nil)
            wgpuComputePassEncoderDispatchWorkgroups(pass, (g.giSize.0 + 7) / 8, (g.giSize.1 + 7) / 8, 1)
        }

        if let k = inspectCascade, !g.ownBgs.isEmpty {
            let clamped = min(max(k, 0), cascadesCount - 1)
            recordSingleGiPass(encoder: encoder, label: "gi.inspect", tsPair: nil, qs: nil) { pass in
                wgpuComputePassEncoderSetPipeline(pass, giCascPipe)
                wgpuComputePassEncoderSetBindGroup(pass, 1, g.ownBgs[clamped], 0, nil)
                wgpuComputePassEncoderDispatchWorkgroups(pass, cw, ch, 1)
            }
        }
    }

    fileprivate func recordCompositePass(
        encoder: WGPUCommandEncoder,
        out: WGPUTextureView,
        cbg: WGPUBindGroup
    ) {
        var ca = WGPURenderPassColorAttachment()
        ca.view = out
        ca.depthSlice = WGPU_DEPTH_SLICE_UNDEFINED
        ca.loadOp = WGPULoadOp_Clear
        ca.storeOp = WGPUStoreOp_Store
        ca.clearValue = WGPUColor(r: 0.0, g: 0.0, b: 0.0, a: 1.0)

        withWGPUStringView("light.composite") { labelView in
            withUnsafePointer(to: &ca) { caPtr in
                var desc = WGPURenderPassDescriptor()
                desc.label = labelView
                desc.colorAttachmentCount = 1
                desc.colorAttachments = caPtr
                if let pass = wgpuCommandEncoderBeginRenderPass(encoder, &desc) {
                    wgpuRenderPassEncoderSetPipeline(pass, compPipe)
                    wgpuRenderPassEncoderSetBindGroup(pass, 0, cbg, 0, nil)
                    wgpuRenderPassEncoderDraw(pass, 4, 1, 0, 0)
                    wgpuRenderPassEncoderEnd(pass)
                    wgpuRenderPassEncoderRelease(pass)
                }
            }
        }
    }
}
#endif
