// Swift-only: Unified Shadcn-style UI ornaments across GPUI and Rune (ADR-0015).

#if os(macOS)
import AppKit
import CoreGraphics
import CoreText
import Foundation
import GPUI
import GPUAUI
import ImageIO
import Rune
import RuneKit
import RuneKnobs
import RuneMermaid
import Testing
import UniformTypeIdentifiers
@testable import GPUIMacOS

@Suite("GPUAUI Retina Showcase Image Generator")
struct ShowcaseImagesTests {
    private struct EmptyRuneState {}

    // MARK: - GPUI Metal 2x Retina Offscreen Renderer

    private struct ClosureGPUIView: GPUI.Render, @unchecked Sendable {
        let build: () -> GPUI.AnyElement

        mutating func render(_: inout GPUI.Window, _: inout GPUI.Context<ClosureGPUIView>) -> GPUI.AnyElement {
            build()
        }
    }

    @MainActor
    private func renderGPUIScene(
        width: Float,
        height: Float,
        platform: MacPlatform,
        cx: GPUI.App,
        _ build: @escaping () -> GPUI.AnyElement
    ) throws -> (width: Int, height: Int, rgba: [UInt8]) {
        let options = GPUI.WindowOptions(
            windowBounds: .windowed(
                GPUI.Bounds(
                    origin: GPUI.point(GPUI.px(40.0), GPUI.px(40.0)),
                    size: GPUI.size(GPUI.px(width), GPUI.px(height))
                )
            ),
            titlebar: GPUI.TitlebarOptions(title: "GPUAUI Showcase", appearsTransparent: true),
            focus: false,
            show: false,
            kind: .popUpMenu
        )
        let handle = try cx.openWindow(options) { _, app in
            app.new { _ in ClosureGPUIView(build: build) }
        }
        var captured: (width: UInt32, height: UInt32, rgba: [UInt8])?
        try cx.updateWindow(handle.anyHandle) { _, window, app in
            let macWin = try #require(window.platformWindow as? MacWindow)
            macWin.captureFrames = true
            var appMut = app
            window.draw(cx: &appMut)
            captured = macWin.lastCapturedFrame
        }
        let frame = try #require(captured, "Expected Metal texture readback from MacWindow")
        return (Int(frame.width), Int(frame.height), frame.rgba)
    }

    // MARK: - Rune 2x Retina Instance + Glyph Atlas Compositor

    private func renderRuneScene(
        width: Float,
        height: Float,
        scale: Float = 2.0,
        theme: OrnamentTheme,
        _ build: @escaping () -> Rune.El
    ) -> (width: Int, height: Int, rgba: [UInt8]) {
        let rt = Rune.Runtime.new(
            EmptyRuneState(),
            { _, _ in build() },
            (width, height),
            Rune.Env.new(theme.appearance.isDark, scale)
        )
        let (instances, _) = rt.frame(0.0)
        let pw = Int((width * scale).rounded())
        let ph = Int((height * scale).rounded())

        let bg = theme.background
        let bgR = UInt8(clamping: Int((bg.r * 255.0).rounded()))
        let bgG = UInt8(clamping: Int((bg.g * 255.0).rounded()))
        let bgB = UInt8(clamping: Int((bg.b * 255.0).rounded()))
        var rgba = [UInt8](repeating: 255, count: pw * ph * 4)
        for p in 0..<(pw * ph) {
            let idx = p * 4
            rgba[idx] = bgR
            rgba[idx + 1] = bgG
            rgba[idx + 2] = bgB
            rgba[idx + 3] = 255
        }

        @inline(__always)
        func blendPremulSrgb(_ dstIdx: Int, _ sr: Float, _ sg: Float, _ sb: Float, _ sa: Float) {
            guard sa > 0.0005 else { return }
            let a = min(max(sa, 0.0), 1.0)
            let inv = 1.0 - a
            let dr = Float(rgba[dstIdx]) / 255.0
            let dg = Float(rgba[dstIdx + 1]) / 255.0
            let db = Float(rgba[dstIdx + 2]) / 255.0
            rgba[dstIdx] = UInt8(clamping: Int(((sr * a + dr * inv) * 255.0).rounded()))
            rgba[dstIdx + 1] = UInt8(clamping: Int(((sg * a + dg * inv) * 255.0).rounded()))
            rgba[dstIdx + 2] = UInt8(clamping: Int(((sb * a + db * inv) * 255.0).rounded()))
            rgba[dstIdx + 3] = 255
        }

        @inline(__always)
        func decodePremulLinear(_ c: [Float]) -> (r: Float, g: Float, b: Float, a: Float) {
            guard c.count >= 4 else { return (0, 0, 0, 0) }
            let a = min(max(c[3], 0.0), 1.0)
            guard a > 1e-5 else { return (0, 0, 0, 0) }
            let lr = min(max(c[0] / a, 0.0), 1.0)
            let lg = min(max(c[1] / a, 0.0), 1.0)
            let lb = min(max(c[2] / a, 0.0), 1.0)
            return (Rune.srgbEncode(lr), Rune.srgbEncode(lg), Rune.srgbEncode(lb), a)
        }

        @inline(__always)
        func roundedRectSDF(_ fx: Float, _ fy: Float, _ rx: Float, _ ry: Float, _ rw: Float, _ rh: Float, _ rad: Float) -> Float {
            let r = min(rad, min(rw, rh) * 0.5)
            let cx0 = rx + r, cy0 = ry + r
            let cx1 = rx + rw - r, cy1 = ry + rh - r
            var sdf = -min(min(fx - rx, rx + rw - fx), min(fy - ry, ry + rh - fy))
            if r > 0.0 {
                let dx: Float = (fx < cx0) ? (cx0 - fx) : ((fx > cx1) ? (fx - cx1) : 0.0)
                let dy: Float = (fy < cy0) ? (cy0 - fy) : ((fy > cy1) ? (fy - cy1) : 0.0)
                if dx > 0.0 || dy > 0.0 {
                    sdf = (dx * dx + dy * dy).squareRoot() - r
                }
            }
            return sdf
        }

        let atlasSize = Int(Rune.ATLAS_SIZE)

        for inst in instances {
            guard inst.rect.count >= 4, inst.params.count >= 3 else { continue }
            let kind = inst.params[1]
            if kind == Rune.KIND_LAYER || kind == Rune.KIND_LAYER_END || kind == Rune.KIND_EFFECT || kind == Rune.KIND_BACKDROP_BLUR {
                continue
            }
            let rx = inst.rect[0], ry = inst.rect[1], rw = inst.rect[2], rh = inst.rect[3]
            guard rw > 0.0, rh > 0.0 else { continue }

            let clipX0 = inst.clip.count >= 4 ? inst.clip[0] : -1e6
            let clipY0 = inst.clip.count >= 4 ? inst.clip[1] : -1e6
            let clipX1 = inst.clip.count >= 4 ? inst.clip[2] : 1e6
            let clipY1 = inst.clip.count >= 4 ? inst.clip[3] : 1e6

            let x0 = max(0, Int(max(rx, clipX0).rounded(.down)))
            let y0 = max(0, Int(max(ry, clipY0).rounded(.down)))
            let x1 = min(pw, Int(min(rx + rw, clipX1).rounded(.up)))
            let y1 = min(ph, Int(min(ry + rh, clipY1).rounded(.up)))
            guard x0 < x1, y0 < y1 else { continue }

            if kind == Rune.KIND_GLYPH {
                let hasAtlasMask = inst.uv.count >= 2 && (
                    inst.uv[0] > 0.0 ||
                    inst.uv[1] > 0.0 ||
                    (inst.uv.count >= 4 && (inst.uv[2] > 0.0 || inst.uv[3] > 0.0))
                )
                guard hasAtlasMask else { continue }
                let (sr, sg, sb, sa) = decodePremulLinear(inst.fill)
                guard sa > 0.0 else { continue }
                let pageIdx = Int(inst.params[2].rounded())
                guard let pageBytes = rt.text.atlas.pageData(pageIdx) else { continue }
                let u0 = inst.uv[0]
                let v0 = inst.uv[1]
                let uw = (inst.uv.count >= 4 && inst.uv[2] > 0.0) ? inst.uv[2] : rw
                let uh = (inst.uv.count >= 4 && inst.uv[3] > 0.0) ? inst.uv[3] : rh

                for py in y0..<y1 {
                    let ty = ((Float(py) + 0.5) - ry) / max(rh, 1.0) * uh
                    let ay = Int((v0 + ty).rounded(.down))
                    guard ay >= 0 && ay < atlasSize else { continue }
                    for px in x0..<x1 {
                        let tx = ((Float(px) + 0.5) - rx) / max(rw, 1.0) * uw
                        let ax = Int((u0 + tx).rounded(.down))
                        guard ax >= 0 && ax < atlasSize else { continue }
                        let cov = Float(pageBytes[ay * atlasSize + ax]) / 255.0
                        if cov > 0.0 {
                            blendPremulSrgb((py * pw + px) * 4, sr, sg, sb, sa * cov)
                        }
                    }
                }
                continue
            }

            if kind == Rune.KIND_SHADOW {
                let (sr, sg, sb, sa) = decodePremulLinear(inst.fill)
                guard sa > 0.0 else { continue }
                let sigma = max(inst.params[2], 1.0)
                let pad = sigma * 2.0
                let irx = rx + pad * 0.35
                let iry = ry + pad * 0.35
                let irw = max(rw - pad * 0.7, 1.0)
                let irh = max(rh - pad * 0.7, 1.0)
                let rad = inst.radii.first.map { abs($0) } ?? 8.0
                for py in y0..<y1 {
                    let fy = Float(py) + 0.5
                    for px in x0..<x1 {
                        let fx = Float(px) + 0.5
                        let d = max(roundedRectSDF(fx, fy, irx, iry, irw, irh, rad), 0.0)
                        let falloff = exp(-(d * d) / (2.0 * sigma * sigma))
                        if falloff > 0.004 {
                            blendPremulSrgb((py * pw + px) * 4, sr, sg, sb, sa * falloff)
                        }
                    }
                }
                continue
            }

            if kind == Rune.KIND_SEGMENT {
                let (sr, sg, sb, sa) = decodePremulLinear(inst.fill)
                guard sa > 0.0, inst.radii.count >= 4 else { continue }
                let ax = inst.radii[0], ay = inst.radii[1], bx = inst.radii[2], by = inst.radii[3]
                let hw = max(inst.params[0], 0.5)
                let abx = bx - ax, aby = by - ay
                let abLenSq = max(abx * abx + aby * aby, 1e-5)
                for py in y0..<y1 {
                    let fy = Float(py) + 0.5
                    for px in x0..<x1 {
                        let fx = Float(px) + 0.5
                        let t = min(max(((fx - ax) * abx + (fy - ay) * aby) / abLenSq, 0.0), 1.0)
                        let qx = ax + t * abx
                        let qy = ay + t * aby
                        let dist = ((fx - qx) * (fx - qx) + (fy - qy) * (fy - qy)).squareRoot()
                        let cov = min(max(0.5 - (dist - hw), 0.0), 1.0)
                        if cov > 0.0 {
                            blendPremulSrgb((py * pw + px) * 4, sr, sg, sb, sa * cov)
                        }
                    }
                }
                continue
            }

            if kind == Rune.KIND_TRIANGLE {
                let (sr, sg, sb, sa) = decodePremulLinear(inst.fill)
                guard sa > 0.0, inst.radii.count >= 4, inst.uv.count >= 2 else { continue }
                let ax = inst.radii[0], ay = inst.radii[1]
                let bx = inst.radii[2], by = inst.radii[3]
                let cx = inst.uv[0], cy = inst.uv[1]
                let area = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)
                guard abs(area) > 1e-4 else { continue }
                let sign: Float = area > 0 ? 1.0 : -1.0
                for py in y0..<y1 {
                    let fy = Float(py) + 0.5
                    for px in x0..<x1 {
                        let fx = Float(px) + 0.5
                        let e0 = ((bx - ax) * (fy - ay) - (by - ay) * (fx - ax)) * sign
                        let e1 = ((cx - bx) * (fy - by) - (cy - by) * (fx - bx)) * sign
                        let e2 = ((ax - cx) * (fy - cy) - (ay - cy) * (fx - cx)) * sign
                        if e0 >= -0.5 && e1 >= -0.5 && e2 >= -0.5 {
                            let minEdge = min(min(e0, e1), e2)
                            let cov = min(max(minEdge + 0.5, 0.0), 1.0)
                            blendPremulSrgb((py * pw + px) * 4, sr, sg, sb, sa * cov)
                        }
                    }
                }
                continue
            }

            // KIND_RECT / KIND_GRADIENT / KIND_DASHED / KIND_INSET
            let (fillR, fillG, fillB, fillA) = decodePremulLinear(inst.fill)
            let borderW = max(inst.params[0], 0.0)
            let (bordR, bordG, bordB, bordA) = borderW > 0.0 ? decodePremulLinear(inst.border) : (0, 0, 0, 0)
            guard fillA > 0.0 || bordA > 0.0 else { continue }
            let rad = inst.radii.first.map { abs($0) } ?? 0.0

            for py in y0..<y1 {
                let fy = Float(py) + 0.5
                for px in x0..<x1 {
                    let fx = Float(px) + 0.5
                    let sdf = roundedRectSDF(fx, fy, rx, ry, rw, rh, rad)
                    let cov = min(max(0.5 - sdf, 0.0), 1.0)
                    guard cov > 0.0 else { continue }
                    let dstIdx = (py * pw + px) * 4
                    if bordA > 0.0 && sdf >= -borderW {
                        if fillA > 0.0 && sdf < -borderW + 1.0 {
                            blendPremulSrgb(dstIdx, fillR, fillG, fillB, fillA * cov)
                        }
                        let innerCov = min(max(sdf + borderW + 0.5, 0.0), 1.0)
                        blendPremulSrgb(dstIdx, bordR, bordG, bordB, bordA * cov * innerCov)
                    } else if fillA > 0.0 {
                        blendPremulSrgb(dstIdx, fillR, fillG, fillB, fillA * cov)
                    }
                }
            }
        }

        // Rasterize laid-out Rune text elements crisply via CoreText onto the RGBA framebuffer
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        let elems = rt.elements()
        rgba.withUnsafeMutableBytes { rawBuf in
            guard let base = rawBuf.baseAddress,
                  let ctx = CGContext(
                      data: base,
                      width: pw,
                      height: ph,
                      bitsPerComponent: 8,
                      bytesPerRow: pw * 4,
                      space: colorSpace,
                      bitmapInfo: bitmapInfo
                  )
            else { return }

            ctx.setAllowsAntialiasing(true)
            ctx.setShouldAntialias(true)
            ctx.setAllowsFontSmoothing(true)
            ctx.setShouldSmoothFonts(true)
            ctx.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
            ctx.textMatrix = .identity

            let canvasH = CGFloat(height)
            for el in elems {
                guard let str = el.text, !str.isEmpty, el.rect.count >= 4, el.opacity > 0.01 else { continue }
                let ex = CGFloat(el.rect[0])
                let ey = CGFloat(el.rect[1])
                let ew = CGFloat(el.rect[2])
                let eh = CGFloat(el.rect[3])
                guard ew > 0.5 && eh > 0.5 else { continue }

                let baseCol = OrnamentColor(runeColor: el.textColor ?? theme.foreground.toRuneColor())
                let col = baseCol.withAlpha(baseCol.a * el.opacity)
                let nsColor = NSColor(
                    srgbRed: CGFloat(col.r),
                    green: CGFloat(col.g),
                    blue: CGFloat(col.b),
                    alpha: CGFloat(col.a)
                )
                let fontSize = min(max(eh * 0.72, 10.5), 16.0)
                let weight: NSFont.Weight = (eh >= 21.0 || el.role == "heading") ? .semibold : (eh <= 15.5 ? .medium : .regular)
                let font = NSFont.systemFont(ofSize: fontSize, weight: weight)
                let attr = NSAttributedString(
                    string: str,
                    attributes: [
                        .font: font,
                        .foregroundColor: nsColor,
                    ]
                )
                let line = CTLineCreateWithAttributedString(attr as CFAttributedString)
                var ascent: CGFloat = 0
                var descent: CGFloat = 0
                var leading: CGFloat = 0
                _ = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
                let baselineY = canvasH - (ey + eh * 0.5) - (ascent - descent) * 0.5
                ctx.textPosition = CGPoint(x: ex, y: baselineY)
                CTLineDraw(line, ctx)
            }
        }

        return (pw, ph, rgba)
    }

    // MARK: - PNG Writer

    private func writePNG(width: Int, height: Int, rgba: [UInt8], to outputURL: URL) throws {
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        let data = Data(rgba)
        let provider = try #require(CGDataProvider(data: data as CFData))
        let cgImage = try #require(
            CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
            )
        )
        let pngData = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(pngData as CFMutableData, UTType.png.identifier as CFString, 1, nil)
        )
        CGImageDestinationAddImage(destination, cgImage, nil)
        #expect(CGImageDestinationFinalize(destination))
        try (pngData as Data).write(to: outputURL, options: .atomic)
    }

    // MARK: - Shared Scene Builders

    private func buildHeroDashboard(theme: OrnamentTheme) -> GPUI.AnyElement {
        OrnamentTheme.withTheme(theme) {
            let topBar = UIFrostedBar(
                leading: [
                    AnyOrnament(UIBadge("GPUAUI", status: .info, icon: .sparkles)),
                    AnyOrnament(UIText("Shadcn Ornaments for GPUI & Rune", sizePx: 13.0, weight: 600.0)),
                ],
                center: [
                    AnyOrnament(
                        UISegmented(
                            items: [
                                UITabItem(id: "gpui", label: "GPUI (Metal)", icon: .bolt),
                                UITabItem(id: "rune", label: "Rune (WebGPU)", icon: .layers),
                                UITabItem(id: "both", label: "Dual Engine", badgeCount: 6),
                            ],
                            activeId: "both"
                        )
                    ),
                ],
                trailing: [
                    AnyOrnament(UIBadge(theme.appearance == .dark ? "Blue Dark" : "Blue Light", status: .outline)),
                    AnyOrnament(UIButton("Command", variant: .outline, size: .sm, icon: .search, shortcut: UIKbd(["⌘", "K"], compact: true))),
                ]
            )

            // Left column: Settings card + Liquid Glass card
            let settingsCard = UICard(
                title: "Workspace Ornaments",
                description: "Shared semantic tokens across all 6 platform targets.",
                icon: .sliders,
                badge: UIBadge("v1.0", status: .secondary)
            )
            .child(
                UIInput(
                    value: "OrnamentTheme.blue(.\(theme.appearance.rawValue))",
                    label: "Active Theme Preset",
                    leadingIcon: .palette,
                    focused: true
                )
            )
            .child(UISwitch(checked: true, label: "Liquid Glass Refraction", description: "RuneLight IOR 1.52 + GPUI backdrop"))
            .child(UISwitch(checked: true, label: "Spring Choreography", description: "RuneMotion analytic spring curves"))
            .child(UICheckbox(checked: true, label: "Strict Swift 6 Sendable & WASI ready"))
            .footerItem(UIButton("Reset", variant: .ghost, size: .sm))
            .footerItem(UIButton("Apply Tokens", variant: .primary, size: .sm, icon: .check))

            let glassCard = UIGlassCard(
                title: "Liquid Glass Surface",
                subtitle: "Physical optics + specular rim",
                icon: .sparkles,
                badge: UIBadge("IOR 1.52", status: .info)
            )
            .child(
                UIText(
                    "Translucent chrome cards share identical corner radii, frost blur, and specular rim tokens on macOS, iOS, Linux, Windows, Android, and Web.",
                    sizePx: 12.0,
                    muted: true
                )
            )

            // Center column: Command Palette + Mermaid diagram
            let palette = UICommandPalette(
                query: "",
                placeholder: "Type a command or search 25+ ornaments...",
                groups: [
                    UICommandGroup(
                        heading: "Quick Actions",
                        items: [
                            UICommandItem(id: "mermaid", title: "Insert Mermaid Diagram", subtitle: "Native vector flowchart", icon: .gitBranch, shortcut: ["⌘", "M"]),
                            UICommandItem(id: "diff", title: "Open Myers Diff Inspector", subtitle: "Word-level spans", icon: .code, shortcut: ["⌘", "D"]),
                            UICommandItem(id: "knobs", title: "Toggle Live Knobs HUD", subtitle: "Interactive shader tuning", icon: .sliders, shortcut: ["⌥", "K"]),
                        ]
                    ),
                    UICommandGroup(
                        heading: "Switch Theme",
                        items: [
                            UICommandItem(id: "rose", title: "Activate Rose Preset", icon: .palette, shortcut: ["⌘", "1"]),
                            UICommandItem(id: "opencode", title: "Activate OpenCode Preset", icon: .terminal, shortcut: ["⌘", "2"]),
                        ]
                    ),
                ],
                selectedId: "mermaid",
                widthPx: 452.0
            )

            let mermaid = UIMermaidCard(
                """
                flowchart LR
                    Tokens[OrnamentTheme] --> GPUI[GPUI Engine]
                    Tokens --> Rune[Rune Engine]
                    GPUI --> Out[6 Platforms]
                    Rune --> Out
                """,
                title: "Unified Architecture",
                maxWidthPx: 420.0
            )

            // Right column: Diff block + Toasts
            let diff = UIDiffBlock(
                filename: "Sources/App/Ornaments.swift",
                old: """
                let card = div().p4().roundedLg()
                let btn = div().child("Deploy")
                """,
                new: """
                let card = UIGlassCard(title: "Ship")
                let btn = UIButton("Deploy", icon: .bolt)
                """
            )

            let toasts = UIToastViewport([
                UIToast(
                    title: "All 6 CI targets green",
                    description: "macOS, iOS, Linux, Windows, Android, Wasm verified.",
                    status: .success,
                    actionLabel: "View",
                    widthPx: 388.0
                ),
                UIToast(
                    title: "Streaming Markdown active",
                    description: "1,797 upstream files mapped 1:1.",
                    status: .info,
                    widthPx: 388.0
                ),
            ])

            let floatingBar = UIFloatingToolbar([
                .icon(.sparkles, label: "AI Assist", active: true),
                .action("Inspect", icon: .eye, shortcut: UIKbd(["⌘", "I"], compact: true)),
                .action("Terminal", icon: .terminal, shortcut: UIKbd(["⌃", "`"], compact: true)),
                .separator,
                .badge(UIBadge("60 FPS • 2x Retina", status: .success, dot: true)),
            ])

            let grid = GPUI.div()
                .flex()
                .flexRow()
                .itemsStart()
                .gap(.pixels(GPUI.px(18.0)))
                .wFull()
                .child(
                    GPUI.div().flex().flexCol().gap(.pixels(GPUI.px(16.0))).w(GPUI.px(356.0)).flexShrink0()
                        .child(settingsCard)
                        .child(glassCard)
                )
                .child(
                    GPUI.div().flex().flexCol().gap(.pixels(GPUI.px(16.0))).w(GPUI.px(452.0)).flexShrink0()
                        .child(palette)
                        .child(mermaid)
                )
                .child(
                    GPUI.div().flex().flexCol().itemsStart().gap(.pixels(GPUI.px(16.0))).w(GPUI.px(388.0)).flexShrink0()
                        .child(diff)
                        .child(toasts)
                )

            return GPUI.div()
                .flex()
                .flexCol()
                .justifyBetween()
                .w(GPUI.px(1280.0))
                .h(GPUI.px(820.0))
                .p(GPUI.px(24.0))
                .bg(theme.background.toGPUIHsla())
                .child(
                    GPUI.div().flex().flexCol().gap(.pixels(GPUI.px(18.0))).wFull()
                        .child(topBar)
                        .child(grid)
                )
                .child(
                    GPUI.div().flex().flexRow().justifyCenter().wFull()
                        .child(floatingBar)
                )
                .intoAnyElement()
        }
    }

    private func buildDualEngineSampleOrnament() -> UICard {
        UICard(
            title: "Dual-Engine Ornament",
            description: "One Swift declaration rendered natively by GPUI and Rune.",
            icon: .sparkles,
            badge: UIBadge("Rose Dark", status: .info),
            headerTrailing: AnyOrnament(UIKbd(["⌘", "E"], compact: true))
        )
        .child(
            UITabs(
                items: [
                    UITabItem(id: "overview", label: "Overview", icon: .layers),
                    UITabItem(id: "metrics", label: "Metrics", badgeCount: 4),
                    UITabItem(id: "tokens", label: "Tokens", icon: .palette),
                ],
                activeId: "overview"
            )
        )
        .child(
            UIInput(
                value: "https://github.com/mweinbach/GPUA",
                label: "Repository",
                leadingIcon: .globe,
                focused: true
            )
        )
        .child(
            UISwitch(
                checked: true,
                label: "Synchronize OKLab Palette",
                description: "Gamma sRGB (GPUI) ↔ Linear sRGB (Rune)"
            )
        )
        .child(
            UIMermaidCard(
                """
                flowchart LR
                    Swift[GPUAUI] --> GPUI[GPUI Metal]
                    Swift --> Rune[Rune Scene]
                """,
                title: "Shared Vector Scene",
                maxWidthPx: 490.0
            )
        )
        .footerItem(UIButton("Inspect", variant: .outline, size: .sm, icon: .eye))
        .footerItem(UIButton("Deploy Release", variant: .primary, size: .sm, icon: .bolt))
    }

    // MARK: - Showcase Generator Entry Point

    @Test("Generates 2x Retina showcase PNGs into docs/images when GPUA_WRITE_SHOWCASE_IMAGES=1")
    @MainActor
    func generateShowcaseGalleryPNGs() throws {
        guard ProcessInfo.processInfo.environment["GPUA_WRITE_SHOWCASE_IMAGES"] == "1" else {
            return
        }

        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // GPUAUITests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repo root
        let imagesDir = repoRoot
            .appendingPathComponent("docs", isDirectory: true)
            .appendingPathComponent("images", isDirectory: true)

        let platform = MacPlatform.new(headless: false)
        let cx = GPUI.App.newApp(platform: platform)

        // 1. Hero Dark (1280 x 820)
        let heroDark = try renderGPUIScene(width: 1280.0, height: 820.0, platform: platform, cx: cx) {
            buildHeroDashboard(theme: .blue(.dark))
        }
        try writePNG(width: heroDark.width, height: heroDark.height, rgba: heroDark.rgba, to: imagesDir.appendingPathComponent("gpuaui-hero-dark.png"))

        // 2. Hero Light (1280 x 820)
        let heroLight = try renderGPUIScene(width: 1280.0, height: 820.0, platform: platform, cx: cx) {
            buildHeroDashboard(theme: .blue(.light))
        }
        try writePNG(width: heroLight.width, height: heroLight.height, rgba: heroLight.rgba, to: imagesDir.appendingPathComponent("gpuaui-hero-light.png"))

        // 3. All 6 Curated Themes Grid (1280 x 780)
        let themesFrame = try renderGPUIScene(width: 1280.0, height: 780.0, platform: platform, cx: cx) {
            let outer = OrnamentTheme.zinc(.dark)
            let presets: [(OrnamentTheme, String)] = [
                (.zinc(.dark), "Crisp monochrome neutral"),
                (.slate(.dark), "Cool architectural steel"),
                (.neutral(.light), "Clean daylight editorial"),
                (.rose(.dark), "Vibrant crimson accent"),
                (.blue(.dark), "Electric cobalt studio"),
                (.openCode(.dark), "Anomaly OpenCode terminal"),
            ]

            func themeTile(_ preset: OrnamentTheme, _ subtitle: String) -> GPUI.AnyElement {
                OrnamentTheme.withTheme(preset) {
                    var swatches = GPUI.div().flex().flexRow().itemsCenter().gap(.pixels(GPUI.px(5.0)))
                    for col in [preset.background, preset.primary, preset.accent, preset.success, preset.destructive] {
                        swatches = swatches.child(
                            GPUI.div()
                                .size(GPUI.px(15.0))
                                .roundedFull()
                                .bg(col.toGPUIHsla())
                                .border1()
                                .borderColor(preset.border.toGPUIHsla())
                        )
                    }

                    let btnRow = GPUI.div().flex().flexRow().itemsCenter().gap(.pixels(GPUI.px(6.0)))
                        .child(UIButton("Primary", variant: .primary, size: .xs, icon: .sparkles).renderGPUI(theme: preset))
                        .child(UIButton("Outline", variant: .outline, size: .xs).renderGPUI(theme: preset))
                        .child(UIBadge("Active", status: .success, dot: true).renderGPUI(theme: preset))

                    let card = UICard(
                        title: "\(preset.name) (\(preset.appearance == .dark ? "Dark" : "Light"))",
                        description: subtitle,
                        icon: .palette,
                        headerTrailing: AnyOrnament(UIKbd(["⌘", "T"], compact: true))
                    )
                    .child(
                        UITabs(
                            items: [
                                UITabItem(id: "preview", label: "Preview"),
                                UITabItem(id: "tokens", label: "Tokens", badgeCount: 16),
                            ],
                            activeId: "preview"
                        )
                    )
                    .child(UISwitch(checked: true, label: "OKLab Contrast Verified"))

                    return GPUI.div()
                        .flex()
                        .flexCol()
                        .justifyBetween()
                        .w(GPUI.px(396.0))
                        .h(GPUI.px(322.0))
                        .p(GPUI.px(14.0))
                        .rounded(.pixels(GPUI.px(14.0)))
                        .bg(preset.background.toGPUIHsla())
                        .border1()
                        .borderColor(preset.border.toGPUIHsla())
                        .child(card.renderGPUI(theme: preset))
                        .child(
                            GPUI.div().flex().flexRow().itemsCenter().justifyBetween().wFull().pt(.pixels(GPUI.px(8.0)))
                                .child(swatches)
                                .child(btnRow)
                        )
                        .intoAnyElement()
                }
            }

            let row1 = GPUI.div().flex().flexRow().gap(.pixels(GPUI.px(18.0)))
                .child(themeTile(presets[0].0, presets[0].1))
                .child(themeTile(presets[1].0, presets[1].1))
                .child(themeTile(presets[2].0, presets[2].1))
            let row2 = GPUI.div().flex().flexRow().gap(.pixels(GPUI.px(18.0)))
                .child(themeTile(presets[3].0, presets[3].1))
                .child(themeTile(presets[4].0, presets[4].1))
                .child(themeTile(presets[5].0, presets[5].1))

            return GPUI.div()
                .flex()
                .flexCol()
                .gap(.pixels(GPUI.px(18.0)))
                .w(GPUI.px(1280.0))
                .h(GPUI.px(780.0))
                .p(GPUI.px(26.0))
                .bg(OrnamentColor(hex: 0x070709).toGPUIHsla())
                .child(
                    GPUI.div().flex().flexRow().itemsCenter().justifyBetween().wFull()
                        .child(
                            GPUI.div().flex().flexRow().itemsCenter().gap(.pixels(GPUI.px(10.0)))
                                .child(UIBadge("6 Curated Presets + OKLab Seed", status: .info, icon: .palette).renderGPUI(theme: outer))
                                .child(UIText("OrnamentTheme Design Token Palettes", sizePx: 16.0, weight: 600.0).renderGPUI(theme: outer))
                        )
                        .child(UIText("Automatic WCAG contrast • Dark & Light appearances", sizePx: 12.5, muted: true).renderGPUI(theme: outer))
                )
                .child(row1)
                .child(row2)
                .intoAnyElement()
        }
        try writePNG(width: themesFrame.width, height: themesFrame.height, rgba: themesFrame.rgba, to: imagesDir.appendingPathComponent("gpuaui-themes.png"))

        // 4. Category 1 — Floating Chrome & Liquid Glass (1240 x 760)
        let floatingFrame = try renderGPUIScene(width: 1240.0, height: 760.0, platform: platform, cx: cx) {
            let theme = OrnamentTheme.blue(.dark)
            return OrnamentTheme.withTheme(theme) {
                let frostedBar = UIFrostedBar(
                    leading: [
                        AnyOrnament(UIBadge("Floating Chrome", status: .info, icon: .layers)),
                        AnyOrnament(UIText("Scene Canvas • OrnamentHost", sizePx: 13.0, weight: 600.0)),
                    ],
                    center: [
                        AnyOrnament(UIBadge("Backdrop Blur 22px", status: .outline)),
                        AnyOrnament(UIBadge("RuneLight Glass IOR 1.52", status: .secondary)),
                    ],
                    trailing: [
                        AnyOrnament(UIKbd(["⌘", "."], compact: true)),
                    ]
                )

                let leftCol = GPUI.div().flex().flexCol().gap(.pixels(GPUI.px(18.0))).w(GPUI.px(368.0)).flexShrink0()
                    .child(
                        UIGlassCard(
                            title: "Liquid Glass Ornament",
                            subtitle: "Specular top rim + frosted translucency",
                            icon: .sparkles,
                            badge: UIBadge("Glass", status: .info)
                        )
                        .child(UIText("Bridges directly to RuneLight.Glass(x, y, w, h) for physical refraction, bevel Dispersion, and frost blur.", sizePx: 12.5, muted: true))
                        .child(
                            UIHStack(gapPx: 8.0)
                                .child(UIButton("Inspect Shader", variant: .primary, size: .sm, icon: .eye))
                                .child(UIButton("Copy Preset", variant: .outline, size: .sm, icon: .copy))
                        )
                    )
                    .child(
                        UIHoverCard(
                            trigger: UIButton("@mweinbach/GPUA", variant: .secondary, size: .sm, icon: .globe),
                            icon: .bolt,
                            title: "GPUA + Rune",
                            subtitle: "@mweinbach/GPUA",
                            bio: "File-for-file Swift 6 port of GPUI and Rune with unified Shadcn-style UI ornaments.",
                            meta: "macOS • iOS • Linux • Windows • Android • Wasm"
                        )
                    )

                let midCol = GPUI.div().flex().flexCol().gap(.pixels(GPUI.px(18.0))).w(GPUI.px(384.0)).flexShrink0()
                    .child(
                        UIPopover(
                            trigger: UIButton("Configure Anchor", variant: .outline, size: .sm, icon: .sliders, trailingIcon: .chevronDown),
                            title: "Ornament Anchor & Inset",
                            description: "Pin floating chrome to any of 9 viewport anchors.",
                            content: [
                                AnyOrnament(UIInput(value: ".bottom (inset: 16px)", label: "Anchor Slot", leadingIcon: .layers, focused: true)),
                                AnyOrnament(UISwitch(checked: true, label: "Spring Entrance", description: "RuneMotion.Spring.snappy")),
                            ],
                            widthPx: 330.0
                        )
                    )
                    .child(
                        UICard(title: "Tooltips & Shortcut Chips", description: "Instant keyboard discovery on icon chrome.", icon: .info)
                            .child(
                                UIHStack(gapPx: 22.0)
                                    .child(UITooltip(trigger: UIIconButton(.bolt, label: "Build", variant: .primary), text: "Run Build", shortcut: UIKbd(["⌘", "B"], compact: true)))
                                    .child(UITooltip(trigger: UIIconButton(.terminal, label: "Shell", variant: .secondary), text: "Toggle Shell", shortcut: UIKbd(["⌃", "`"], compact: true)))
                            )
                    )

                let rightCol = GPUI.div().flex().flexCol().itemsStart().gap(.pixels(GPUI.px(14.0))).w(GPUI.px(396.0)).flexShrink0()
                    .child(
                        UIToastViewport([
                            UIToast(title: "Release artifact signed", description: "Universal macOS + iOS xcframework notarized.", status: .success, actionLabel: "Open", widthPx: 396.0),
                            UIToast(title: "WASI bundle optimized", description: "GPUAUI target compiled in 12.3s.", status: .info, widthPx: 396.0),
                            UIToast(title: "High refresh rate active", description: "ProMotion 120Hz frame pacing locked.", status: .warning, widthPx: 396.0),
                            UIToast(title: "Connection interrupted", description: "Retrying remote shader cache...", status: .destructive, actionLabel: "Retry", widthPx: 396.0),
                        ])
                    )

                let pillToolbar = UIFloatingToolbar([
                    .icon(.sparkles, label: "Compose", active: true),
                    .action("Select", icon: .eye, shortcut: UIKbd(["V"], compact: true)),
                    .action("Layers", icon: .layers, shortcut: UIKbd(["L"], compact: true)),
                    .action("Code", icon: .code, shortcut: UIKbd(["⌘", "U"], compact: true)),
                    .separator,
                    .badge(UIBadge("9 Anchors", status: .info)),
                    .icon(.settings, label: "Preferences"),
                ])

                // Decorative atmospheric glow bands behind floating glass
                let canvas = GPUI.div()
                    .relative()
                    .flex()
                    .flexCol()
                    .justifyBetween()
                    .w(GPUI.px(1240.0))
                    .h(GPUI.px(760.0))
                    .p(GPUI.px(24.0))
                    .bg(OrnamentColor(hex: 0x060A14).toGPUIHsla())
                    .child(
                        GPUI.div()
                            .absolute()
                            .top(.pixels(GPUI.px(90.0)))
                            .left(.pixels(GPUI.px(60.0)))
                            .w(GPUI.px(340.0))
                            .h(GPUI.px(200.0))
                            .roundedFull()
                            .bg(theme.primary.withAlpha(0.14).toGPUIHsla())
                    )
                    .child(
                        GPUI.div().flex().flexCol().gap(.pixels(GPUI.px(20.0))).wFull()
                            .child(frostedBar)
                            .child(
                                GPUI.div().flex().flexRow().itemsStart().gap(.pixels(GPUI.px(20.0))).wFull()
                                    .child(leftCol)
                                    .child(midCol)
                                    .child(rightCol)
                            )
                    )
                    .child(
                        GPUI.div().flex().flexRow().justifyCenter().wFull()
                            .child(pillToolbar)
                    )
                return canvas.intoAnyElement()
            }
        }
        try writePNG(width: floatingFrame.width, height: floatingFrame.height, rgba: floatingFrame.rgba, to: imagesDir.appendingPathComponent("gpuaui-floating-glass.png"))

        // 5. Category 2 — Command Palette, Menus, Dialogs & Sheet (1240 x 760)
        let modalsFrame = try renderGPUIScene(width: 1240.0, height: 760.0, platform: platform, cx: cx) {
            let theme = OrnamentTheme.zinc(.dark)
            return OrnamentTheme.withTheme(theme) {
                let palette = UICommandPalette(
                    query: "",
                    placeholder: "Search commands, files, or themes...",
                    groups: [
                        UICommandGroup(
                            heading: "Navigation",
                            items: [
                                UICommandItem(id: "go-file", title: "Go to Ornament Definition", subtitle: "Sources/GPUAUI", icon: .folder, shortcut: ["⌘", "P"]),
                                UICommandItem(id: "go-sym", title: "Search Workspace Symbols", icon: .search, shortcut: ["⌘", "T"]),
                            ]
                        ),
                        UICommandGroup(
                            heading: "Appearance & Rendering",
                            items: [
                                UICommandItem(id: "toggle-dark", title: "Toggle Dark / Light Appearance", icon: .moon, shortcut: ["⇧", "⌘", "L"]),
                                UICommandItem(id: "export-png", title: "Capture 2x Retina Framebuffer", icon: .sparkles, shortcut: ["⌘", "S"]),
                            ]
                        ),
                    ],
                    selectedId: "go-file",
                    widthPx: 430.0
                )

                let dropdown = UIDropdownMenu(
                    trigger: UIButton("Workspace", variant: .outline, size: .sm, icon: .layers, trailingIcon: .chevronDown),
                    entries: [
                        .label("Edit & Layout"),
                        .item(title: "Duplicate", icon: .copy, shortcut: "⌘D", highlighted: true),
                        .item(title: "Snap to Grid", checked: true),
                        .item(title: "Layout Bounds", checked: false),
                        .separator,
                        .item(title: "Delete", icon: .trash, shortcut: "⌘⌫", destructive: true),
                    ],
                    widthPx: 207.0
                )

                let contextMenu = UIContextMenu(
                    target: UIBadge("Canvas Target", status: .secondary, icon: .sparkles),
                    entries: [
                        .item(title: "Inspect in GPUI", icon: .eye, shortcut: "⌥⌘I", highlighted: true),
                        .item(title: "Copy Swift", icon: .code, shortcut: "⌘C"),
                        .separator,
                        .item(title: "Reset Overrides", icon: .x, destructive: true),
                    ],
                    widthPx: 207.0
                )

                let dialog1 = UIDialog(
                    title: "Publish GPUAUI Package",
                    description: "Tag release and verify strict Swift 6 builds across macOS, iOS, Linux, Windows, Android, and WebAssembly.",
                    icon: .bolt,
                    body: [
                        AnyOrnament(UIInput(value: "1.0.0", label: "Semantic Version", leadingIcon: .check, focused: true)),
                        AnyOrnament(UICheckbox(checked: true, label: "Run 1,797-file port parity check")),
                    ],
                    cancelLabel: "Cancel",
                    confirmLabel: "Publish Release",
                    showScrim: false,
                    widthPx: 390.0
                )

                let dialog2 = UIDialog(
                    title: "Discard Unsaved Token Edits?",
                    description: "Custom OKLab seed overrides in this session will be reverted to Zinc Dark.",
                    icon: .trash,
                    cancelLabel: "Keep Editing",
                    confirmLabel: "Discard Overrides",
                    destructive: true,
                    showScrim: false,
                    widthPx: 390.0
                )

                let sheet = UISheet(
                    side: .right,
                    title: "Token Inspector",
                    description: "Live Shadcn semantic surface & motion parameters.",
                    body: [
                        AnyOrnament(
                            UISegmented(
                                items: [
                                    UITabItem(id: "colors", label: "Colors"),
                                    UITabItem(id: "radii", label: "Radii"),
                                    UITabItem(id: "motion", label: "Motion"),
                                ],
                                activeId: "colors"
                            )
                        ),
                        AnyOrnament(UIInput(value: "8.0 px", label: "Card Radius (md)")),
                        AnyOrnament(UIInput(value: "22.0 px", label: "Backdrop Blur Sigma")),
                        AnyOrnament(UISwitch(checked: true, label: "Specular Top Rim", description: "26% alpha highlight")),
                        AnyOrnament(UISwitch(checked: true, label: "Keyboard Trap Focus", description: "ESC & Tab ring navigation")),
                    ],
                    footer: [
                        AnyOrnament(UIButton("Cancel", variant: .outline, size: .sm)),
                        AnyOrnament(UIButton("Save Preset", variant: .primary, size: .sm, icon: .check)),
                    ],
                    widthPx: 332.0
                )

                return GPUI.div()
                    .flex()
                    .flexRow()
                    .itemsStretch()
                    .gap(.pixels(GPUI.px(20.0)))
                    .w(GPUI.px(1240.0))
                    .h(GPUI.px(760.0))
                    .p(GPUI.px(24.0))
                    .bg(theme.background.toGPUIHsla())
                    .child(
                        GPUI.div().flex().flexCol().gap(.pixels(GPUI.px(18.0))).w(GPUI.px(430.0))
                            .child(palette)
                            .child(
                                GPUI.div().flex().flexRow().itemsStart().gap(.pixels(GPUI.px(16.0)))
                                    .child(dropdown)
                                    .child(contextMenu)
                            )
                    )
                    .child(
                        GPUI.div().flex().flexCol().gap(.pixels(GPUI.px(18.0))).w(GPUI.px(390.0))
                            .child(dialog1)
                            .child(dialog2)
                    )
                    .child(sheet)
                    .intoAnyElement()
            }
        }
        try writePNG(width: modalsFrame.width, height: modalsFrame.height, rgba: modalsFrame.rgba, to: imagesDir.appendingPathComponent("gpuaui-command-modals.png"))

        // 6. Category 3 — Core Shadcn Controls Matrix (1240 x 780)
        let controlsFrame = try renderGPUIScene(width: 1240.0, height: 780.0, platform: platform, cx: cx) {
            let theme = OrnamentTheme.slate(.dark)
            return OrnamentTheme.withTheme(theme) {
                let variantsCard = UICard(
                    title: "Buttons & Icon Chrome",
                    description: "7 Shadcn variants × 5 size steps with vector Lucide icons and shortcut chips.",
                    icon: .sparkles,
                    badge: UIBadge("UIButton", status: .info)
                )
                .child(
                    UIHStack(gapPx: 8.0, wrap: true)
                        .child(UIButton("Default", variant: .default))
                        .child(UIButton("Primary", variant: .primary, icon: .bolt))
                        .child(UIButton("Secondary", variant: .secondary))
                        .child(UIButton("Outline", variant: .outline, icon: .copy))
                        .child(UIButton("Ghost", variant: .ghost))
                        .child(UIButton("Destructive", variant: .destructive, icon: .trash))
                        .child(UIButton("Documentation", variant: .link, trailingIcon: .externalLink))
                )
                .child(
                    UIHStack(gapPx: 10.0)
                        .child(UIButton("XS", variant: .outline, size: .xs))
                        .child(UIButton("Small", variant: .outline, size: .sm))
                        .child(UIButton("Medium", variant: .primary, size: .md, shortcut: UIKbd(["⌘", "↵"], compact: true)))
                        .child(UIButton("Large Action", variant: .secondary, size: .lg, icon: .bolt))
                        .child(UIIconButton(.plus, label: "Add", variant: .primary))
                        .child(UIIconButton(.search, label: "Search", variant: .outline))
                        .child(UIIconButton(.bell, label: "Alerts", variant: .secondary))
                        .child(UIIconButton(.settings, label: "Settings", variant: .ghost))
                )

                let badgesAndTabsCard = UICard(
                    title: "Badges, Segmented & Underline Tabs, Kbd",
                    description: "Semantic status pills, indicator dots, and keyboard chord badges.",
                    icon: .layers,
                    badge: UIBadge("7 Statuses", status: .secondary)
                )
                .child(
                    UIHStack(gapPx: 8.0, wrap: true)
                        .child(UIBadge("Default", status: .default))
                        .child(UIBadge("Secondary", status: .secondary))
                        .child(UIBadge("Outline", status: .outline))
                        .child(UIBadge("Healthy", status: .success, dot: true))
                        .child(UIBadge("Degraded", status: .warning, dot: true))
                        .child(UIBadge("Failed", status: .destructive, dot: true))
                        .child(UIBadge("2x Retina", status: .info, icon: .eye))
                )
                .child(
                    UITabs(
                        items: [
                            UITabItem(id: "all", label: "All Targets", icon: .globe, badgeCount: 6),
                            UITabItem(id: "apple", label: "Apple Metal", icon: .bolt),
                            UITabItem(id: "wasm", label: "WebAssembly", icon: .code),
                        ],
                        activeId: "all",
                        style: .segmented
                    )
                )
                .child(
                    UITabs(
                        items: [
                            UITabItem(id: "props", label: "Properties"),
                            UITabItem(id: "layout", label: "Taffy Layout"),
                            UITabItem(id: "a11y", label: "Accessibility", badgeCount: 12),
                        ],
                        activeId: "props",
                        style: .underline
                    )
                )
                .child(
                    UIHStack(gapPx: 10.0)
                        .child(UIText("Shortcuts:", sizePx: 12.0, muted: true))
                        .child(UIKbd(["⌘", "K"]))
                        .child(UIKbd(["⇧", "⌘", "P"]))
                        .child(UIKbd(["⌥", "Space"]))
                        .child(UIKbd(["ESC"]))
                )

                let formsCard = UICard(
                    title: "Inputs, Switches & Checkboxes",
                    description: "Focus rings, validation states, and accessible form controls.",
                    icon: .sliders,
                    badge: UIBadge("Forms", status: .outline)
                )
                .child(
                    UIInput(
                        value: "",
                        placeholder: "Filter ornaments by name...",
                        label: "Search Catalog",
                        leadingIcon: .search,
                        trailingShortcut: UIKbd(["⌘", "F"], compact: true)
                    )
                )
                .child(
                    UIInput(
                        value: "Sources/GPUAUI/Theme/OrnamentTheme.swift",
                        label: "Focused Input (2px Ring)",
                        helperText: "Shared across GPUI and Rune targets.",
                        leadingIcon: .folder,
                        focused: true
                    )
                )
                .child(
                    UIInput(
                        value: "invalid-hex-token",
                        label: "Validation Error State",
                        helperText: "Expected #RRGGBB or #RRGGBBAA hex color literal.",
                        leadingIcon: .warning,
                        invalid: true
                    )
                )
                .child(UISwitch(checked: true, label: "Enable GPU MSAA Path Rasterization", description: "4x multisample vector edges"))
                .child(UISwitch(checked: false, label: "Reduce Motion", description: "Snap spring transitions immediately"))
                .child(UICheckbox(checked: true, label: "Export public SwiftPM library product", description: ".library(name: \"GPUAUI\", targets: [\"GPUAUI\"])"))
                .child(UICheckbox(checked: false, indeterminate: true, label: "3 of 6 optional showcase presets selected"))
                .footerItem(UIButton("Reset Defaults", variant: .outline, size: .sm))
                .footerItem(UIButton("Save Controls", variant: .primary, size: .sm, icon: .check))

                return GPUI.div()
                    .flex()
                    .flexRow()
                    .itemsStart()
                    .gap(.pixels(GPUI.px(20.0)))
                    .w(GPUI.px(1240.0))
                    .h(GPUI.px(780.0))
                    .p(GPUI.px(24.0))
                    .bg(theme.background.toGPUIHsla())
                    .child(
                        GPUI.div().flex().flexCol().gap(.pixels(GPUI.px(18.0))).w(GPUI.px(630.0))
                            .child(variantsCard)
                            .child(badgesAndTabsCard)
                    )
                    .child(
                        GPUI.div().flex().flexCol().flex1()
                            .child(formsCard)
                    )
                    .intoAnyElement()
            }
        }
        try writePNG(width: controlsFrame.width, height: controlsFrame.height, rgba: controlsFrame.rgba, to: imagesDir.appendingPathComponent("gpuaui-controls.png"))

        // 7. Category 4 — Rich Developer Ornaments (1280 x 820)
        let devFrame = try renderGPUIScene(width: 1280.0, height: 820.0, platform: platform, cx: cx) {
            let theme = OrnamentTheme.openCode(.dark)
            return OrnamentTheme.withTheme(theme) {
                let md = UIMarkdown(
                    """
                    ## Developer Ornaments

                    Native **CommonMark + GFM** rendering powered by `RuneKit.markdown` with zero webviews:

                    - **Syntax Highlighting** across 13 languages (`swift`, `rust`, `ts`, `python`, `sql`, ...)
                    - **Vector Mermaid** flowcharts, sequence, state, class & ER diagrams

                    | Target | Upstream | Parity |
                    | :--- | :---: | ---: |
                    | `GPUI` + `Taffy` | `650aab59d54f` | 100% |
                    | `Rune` (14 crates) | `5f6d53ddae78` | 100% |
                    | `GPUAUI` | `ADR-0015` | Dual |
                    """
                )

                let mermaid = UIMermaidCard(
                    """
                    sequenceDiagram
                        participant App as Swift App
                        participant UI as GPUAUI
                        participant GPU as Metal / WebGPU
                        App->>UI: UIButton + UIMermaidCard
                        UI->>GPU: Instanced Quads + Vector Paths
                    """,
                    title: "Mermaid Sequence Diagram",
                    maxWidthPx: 530.0
                )

                let codeBlock = UICodeBlock(
                    """
                    import GPUAUI

                    let palette = OrnamentTheme.openCode(.dark)
                    let card = UIGlassCard(title: "Shader Live", icon: .sparkles)
                        .child(UIButton("Compile", variant: .primary, icon: .bolt))
                    """,
                    language: "swift",
                    filename: "Sources/Demo/Preview.swift",
                    highlightedLines: [4, 5]
                )

                let diffBlock = UIDiffBlock(
                    filename: "Package.swift",
                    old: """
                    .library(name: "RuneMermaid", targets: ["RuneMermaid"]),
                    """,
                    new: """
                    .library(name: "RuneMermaid", targets: ["RuneMermaid"]),
                    .library(name: "GPUAUI", targets: ["GPUAUI"]),
                    """
                )

                let blurK = RuneKnobs.Knob("Frost Sigma", 0.0, 40.0, 22.0)
                let iorK = RuneKnobs.Knob("Refraction IOR", 1.0, 2.0, 1.52)
                let springK = RuneKnobs.Knob("Spring Bounce", 0.0, 0.6, 0.18)
                let engineK = RuneKnobs.Knob.choice("Backend", ["Auto", "GPUI", "Rune"], 0)
                let group = RuneKnobs.Group("Optics & Motion", "optics", [blurK, iorK, springK, engineK])
                    .presets([
                        RuneKnobs.Preset("Liquid", [("Frost Sigma", 24.0), ("Refraction IOR", 1.52)]),
                        RuneKnobs.Preset("Crisp", [("Frost Sigma", 10.0), ("Refraction IOR", 1.25)]),
                    ])
                let knobs = UIKnobsHUD(
                    title: "Live Parameter Knobs",
                    groups: [group],
                    values: ["Frost Sigma": 24.0, "Refraction IOR": 1.52, "Spring Bounce": 0.18],
                    widthPx: 620.0
                )

                return GPUI.div()
                    .flex()
                    .flexRow()
                    .itemsStart()
                    .gap(.pixels(GPUI.px(20.0)))
                    .w(GPUI.px(1280.0))
                    .h(GPUI.px(820.0))
                    .p(GPUI.px(24.0))
                    .bg(theme.background.toGPUIHsla())
                    .child(
                        GPUI.div().flex().flexCol().gap(.pixels(GPUI.px(18.0))).w(GPUI.px(590.0))
                            .child(
                                GPUI.div()
                                    .p(GPUI.px(18.0))
                                    .rounded(.pixels(GPUI.px(theme.radii.lg)))
                                    .bg(theme.card.toGPUIHsla())
                                    .border1()
                                    .borderColor(theme.border.toGPUIHsla())
                                    .child(md)
                            )
                            .child(mermaid)
                    )
                    .child(
                        GPUI.div().flex().flexCol().gap(.pixels(GPUI.px(16.0))).flex1()
                            .child(codeBlock)
                            .child(diffBlock)
                            .child(knobs)
                    )
                    .intoAnyElement()
            }
        }
        try writePNG(width: devFrame.width, height: devFrame.height, rgba: devFrame.rgba, to: imagesDir.appendingPathComponent("gpuaui-developer-ornaments.png"))

        // 8. Dual-Engine Side-by-Side Comparison (1240 x 680 -> Left 620x680 GPUI Metal, Right 620x680 Rune Runtime)
        let dualTheme = OrnamentTheme.rose(.dark)
        let sharedOrnament = buildDualEngineSampleOrnament()

        let gpuiHalf = try renderGPUIScene(width: 620.0, height: 680.0, platform: platform, cx: cx) {
            OrnamentTheme.withTheme(dualTheme) {
                GPUI.div()
                    .flex()
                    .flexCol()
                    .gap(.pixels(GPUI.px(14.0)))
                    .w(GPUI.px(620.0))
                    .h(GPUI.px(680.0))
                    .p(GPUI.px(22.0))
                    .bg(dualTheme.background.toGPUIHsla())
                    .child(
                        GPUI.div().flex().flexRow().itemsCenter().justifyBetween().wFull()
                            .child(UIBadge("GPUI Engine • GPUIMetal + CoreText", status: .info, icon: .bolt))
                            .child(UIText("renderGPUI(theme:)", sizePx: 12.0, muted: true))
                    )
                    .child(sharedOrnament)
                    .intoAnyElement()
            }
        }

        let scale = Float(gpuiHalf.width) / 620.0
        let runeHalf = renderRuneScene(width: 620.0, height: 680.0, scale: scale, theme: dualTheme) {
            var layer: [Rune.El] = []
            let header = Rune.row()
                .wFull()
                .justifyBetween()
                .centerY()
                .child(UIBadge("Rune Engine • Scene + RuneMermaid + Atlas", status: .success, icon: .layers).renderRune(theme: dualTheme, layer: &layer))
                .child(
                    Rune.text("renderRune(theme:)")
                        .font(Rune.TextStyle.new(12.0, 400.0).lh(16.0))
                        .color(dualTheme.mutedForeground.toRuneColor())
                )
            let body = sharedOrnament.renderRune(theme: dualTheme, layer: &layer)
            var root = Rune.col()
                .size(620.0, 680.0)
                .padding(22.0)
                .gap(14.0)
                .fill(dualTheme.background.toRuneColor())
                .child(header)
                .child(body)
            for l in layer {
                root = root.child(l)
            }
            return root
        }

        let totalW = gpuiHalf.width + runeHalf.width
        let totalH = min(gpuiHalf.height, runeHalf.height)
        var combined = [UInt8](repeating: 255, count: totalW * totalH * 4)
        let divCol = dualTheme.border
        let divR = UInt8(clamping: Int((divCol.r * 255.0).rounded()))
        let divG = UInt8(clamping: Int((divCol.g * 255.0).rounded()))
        let divB = UInt8(clamping: Int((divCol.b * 255.0).rounded()))

        for y in 0..<totalH {
            let leftRowStart = y * gpuiHalf.width * 4
            let dstRowStart = y * totalW * 4
            combined.replaceSubrange(
                dstRowStart..<(dstRowStart + gpuiHalf.width * 4),
                with: gpuiHalf.rgba[leftRowStart..<(leftRowStart + gpuiHalf.width * 4)]
            )
            let rightRowStart = y * runeHalf.width * 4
            let dstRightStart = dstRowStart + gpuiHalf.width * 4
            combined.replaceSubrange(
                dstRightStart..<(dstRightStart + runeHalf.width * 4),
                with: runeHalf.rgba[rightRowStart..<(rightRowStart + runeHalf.width * 4)]
            )
            // Crisp 2px center divider
            for dx in -1...0 {
                let cxPx = gpuiHalf.width + dx
                if cxPx >= 0 && cxPx < totalW {
                    let pIdx = (y * totalW + cxPx) * 4
                    combined[pIdx] = divR
                    combined[pIdx + 1] = divG
                    combined[pIdx + 2] = divB
                    combined[pIdx + 3] = 255
                }
            }
        }
        try writePNG(width: totalW, height: totalH, rgba: combined, to: imagesDir.appendingPathComponent("gpuaui-dual-engine.png"))

        // Verify all 8 files exist and are non-empty PNGs
        let expectedFiles = [
            "gpuaui-hero-dark.png",
            "gpuaui-hero-light.png",
            "gpuaui-themes.png",
            "gpuaui-floating-glass.png",
            "gpuaui-command-modals.png",
            "gpuaui-controls.png",
            "gpuaui-developer-ornaments.png",
            "gpuaui-dual-engine.png",
        ]
        for file in expectedFiles {
            let url = imagesDir.appendingPathComponent(file)
            let bytes = try Data(contentsOf: url)
            #expect(bytes.count > 20_000, "Expected rich PNG bytes for \(file), got \(bytes.count)")
            #expect(Array(bytes.prefix(8)) == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        }
    }
}
#endif
