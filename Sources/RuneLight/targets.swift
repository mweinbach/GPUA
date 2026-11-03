// Ported from: crates/rune-light/src/targets.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import CWebGPU

/// Direct-light textures: allocated on first frame and on resize / `fieldScale` change.
struct Targets {
    var size: (UInt32, UInt32)
    var fieldSize: (UInt32, UInt32)
    var gb0: WGPUTextureView
    var gb1: WGPUTextureView
    var field: WGPUTextureView
    var visTex: WGPUTexture
    var vis: WGPUTextureView
    var air: WGPUTextureView
    var fieldBg: WGPUBindGroup
    var shadowBg: WGPUBindGroup
}

/// GI textures: allocated lazily the first frame `gi.enabled` is true; never touched while GI is off.
struct GiTargets {
    var giSize: (UInt32, UInt32)
    var field: UInt
    var gb0: UInt
    var sceneEmit: WGPUTextureView
    var sceneOcc: WGPUTextureView
    var levels: [WGPUTextureView]
    var own: [WGPUTextureView]
    var fluence: WGPUTextureView
    var cascBgs: [WGPUBindGroup]
    var ownBgs: [WGPUBindGroup]
    var fluBg: WGPUBindGroup
}

extension LightRenderer {
    func targets(_ size: (UInt32, UInt32), _ fScale: Float) -> Targets {
        let fs = (
            max(UInt32((Float(size.0) * fScale).rounded()), 1),
            max(UInt32((Float(size.1) * fScale).rounded()), 1)
        )
        if let existing = targetsCache,
           existing.size == size,
           existing.fieldSize == fs {
            return existing
        }

        let rt = WGPUTextureUsage_RenderAttachment | WGPUTextureUsage_TextureBinding
        let st = WGPUTextureUsage_StorageBinding | WGPUTextureUsage_TextureBinding | WGPUTextureUsage_CopySrc

        let (_, gb0) = texture(device, "light.gb0", size, 1, WGPUTextureFormat_RGBA16Float, rt)
        let (_, gb1) = texture(device, "light.gb1", size, 1, WGPUTextureFormat_R16Uint, rt)
        let (_, field) = texture(device, "light.field", fs, 1, WGPUTextureFormat_RGBA16Float, st)
        let (visTex, vis) = texture(device, "light.vis", fs, 2, WGPUTextureFormat_RGBA16Float, st)
        let (_, air) = texture(device, "light.air", fs, 2, WGPUTextureFormat_RGBA16Float, st)

        let fieldBg = bind(device, "light.field.bg", fieldBgl, [
            .buf(frameBuf),
            .buf(primBuf),
            .view(field),
        ])
        let shadowBg = bind(device, "light.shadow.bg", shadowBgl, [
            .buf(frameBuf),
            .buf(lightBuf),
            .view(field),
            .samp(linear),
            .view(gb0),
            .view(vis),
            .view(air),
        ])

        let created = Targets(
            size: size,
            fieldSize: fs,
            gb0: gb0,
            gb1: gb1,
            field: field,
            visTex: visTex,
            vis: vis,
            air: air,
            fieldBg: fieldBg,
            shadowBg: shadowBg
        )
        targetsCache = created
        return created
    }

    func giTargets(
        _ size: (UInt32, UInt32),
        _ giScale: Float,
        _ field: WGPUTextureView,
        _ gb0: WGPUTextureView
    ) -> GiTargets {
        let raw = (
            max(UInt32((Float(size.0) * giScale).rounded()), 16),
            max(UInt32((Float(size.1) * giScale).rounded()), 16)
        )
        let step: UInt32 = 1 << (CASCADES - 1)
        let gs = (
            (raw.0 + step - 1) & ~(step - 1),
            (raw.1 + step - 1) & ~(step - 1)
        )

        if let existing = giTargetsCache,
           existing.giSize == gs,
           existing.field == tv(field),
           existing.gb0 == tv(gb0) {
            return existing
        }

        let st = WGPUTextureUsage_StorageBinding | WGPUTextureUsage_TextureBinding | WGPUTextureUsage_CopySrc
        let (_, sceneEmit) = texture(device, "light.gi.emit", gs, 1, WGPUTextureFormat_RGBA16Float, st)
        let (_, sceneOcc) = texture(device, "light.gi.occ", gs, 1, WGPUTextureFormat_RGBA16Float, st)

        // Every cascade has total size 2 * gs: probe grid (gs / 2^n) * dir block (2^(n+1)).
        let cs = (gs.0 * 2, gs.1 * 2)
        var levels: [WGPUTextureView] = []
        levels.reserveCapacity(CASCADES)
        for _ in 0..<CASCADES {
            let (_, v) = texture(device, "light.gi.cascade", cs, 1, WGPUTextureFormat_RGBA16Float, st)
            levels.append(v)
        }
        let (_, fluence) = texture(device, "light.gi.fluence", gs, 1, WGPUTextureFormat_RGBA16Float, st)

        var cascBgs: [WGPUBindGroup] = []
        cascBgs.reserveCapacity(CASCADES)
        for n in 0..<CASCADES {
            let upper = (n + 1 < CASCADES) ? levels[n + 1] : black
            let off = UInt64(n) * UInt64(cascadeStride)
            let bg = bind(device, "light.gi.casc.bg", giCascBgl, [
                .bufSlice(cascadeBuf, off, 16),
                .view(sceneEmit),
                .view(sceneOcc),
                .view(field),
                .samp(linear),
                .view(upper),
                .view(levels[n]),
                .view(gb0),
            ])
            cascBgs.append(bg)
        }

        let fluBg = bind(device, "light.gi.flu.bg", giFluBgl, [
            .view(levels[0]),
            .view(fluence),
        ])

        let created = GiTargets(
            giSize: gs,
            field: tv(field),
            gb0: tv(gb0),
            sceneEmit: sceneEmit,
            sceneOcc: sceneOcc,
            levels: levels,
            own: [],
            fluence: fluence,
            cascBgs: cascBgs,
            ownBgs: [],
            fluBg: fluBg
        )
        giTargetsCache = created
        return created
    }

    /// Unmerged cascade textures, allocated only when ``Settings/inspectCascade`` is used.
    func ownTargets(_ field: WGPUTextureView, _ gb0: WGPUTextureView) {
        guard var g = giTargetsCache else { return }
        if !g.own.isEmpty { return }
        let st = WGPUTextureUsage_StorageBinding | WGPUTextureUsage_TextureBinding | WGPUTextureUsage_CopySrc
        let cs = (g.giSize.0 * 2, g.giSize.1 * 2)
        var ownViews: [WGPUTextureView] = []
        ownViews.reserveCapacity(CASCADES)
        for _ in 0..<CASCADES {
            let (_, v) = texture(device, "light.gi.cascade.own", cs, 1, WGPUTextureFormat_RGBA16Float, st)
            ownViews.append(v)
        }
        var ownBgs: [WGPUBindGroup] = []
        ownBgs.reserveCapacity(CASCADES)
        for n in 0..<CASCADES {
            let off = UInt64(CASCADES + n) * UInt64(cascadeStride)
            let bg = bind(device, "light.gi.own.bg", giCascBgl, [
                .bufSlice(cascadeBuf, off, 16),
                .view(g.sceneEmit),
                .view(g.sceneOcc),
                .view(field),
                .samp(linear),
                .view(black),
                .view(ownViews[n]),
                .view(gb0),
            ])
            ownBgs.append(bg)
        }
        g.own = ownViews
        g.ownBgs = ownBgs
        giTargetsCache = g
    }

    func rebindPrims() {
        gbBg = bind(device, "light.gb.bg", gbBgl, [
            .buf(frameBuf),
            .buf(primBuf),
        ])
        if var t = targetsCache {
            t.fieldBg = bind(device, "light.field.bg", fieldBgl, [
                .buf(frameBuf),
                .buf(primBuf),
                .view(t.field),
            ])
            targetsCache = t
        }
    }
}
