// Swift-only: Unified Shadcn-style UI ornaments across GPUI and Rune (ADR-0015).

import GPUI
import GPUAUI
import Rune
import RuneKit
import RuneKnobs
import RuneLight
import RuneMermaid
import RuneThemeOpenCode
import Testing

#if os(macOS)
@testable import GPUIMacOS
#endif

@Suite("GPUAUI Dual-Engine Shadcn Ornaments Tests")
struct GPUAUITests {
    private struct EmptyState {}

    private func mountRune<O: GPUAOrnament>(
        _ ornament: O,
        theme: OrnamentTheme = .zinc(.dark),
        size: (Float, Float) = (960.0, 640.0)
    ) -> (instances: [Rune.Instance], elements: [Rune.ElementInfo]) {
        let rt = Rune.Runtime.new(
            EmptyState(),
            { _, _ in ornament.renderRune(theme: theme) },
            size,
            Rune.Env.new(theme.appearance.isDark, 2.0)
        )
        let (instances, _) = rt.frame(0.0)
        return (instances, rt.elements())
    }

    @Test("OrnamentColor bridges gamma sRGB (GPUI) and linear sRGB (Rune) accurately")
    func colorBridgeRoundTripAndContrast() throws {
        let zincCard = try #require(OrnamentColor(hexString: "#18181b"))
        #expect(abs(zincCard.r - (24.0 / 255.0)) < 0.005)
        #expect(abs(zincCard.g - (24.0 / 255.0)) < 0.005)
        #expect(abs(zincCard.b - (27.0 / 255.0)) < 0.005)

        // Rune.Color stores linear sRGB (< gamma sRGB for midtones/shadows)
        let runeCol = zincCard.toRuneColor()
        #expect(runeCol.r < zincCard.r)
        let roundTripFromRune = OrnamentColor(runeColor: runeCol)
        #expect(abs(roundTripFromRune.r - zincCard.r) < 0.002)
        #expect(abs(roundTripFromRune.g - zincCard.g) < 0.002)
        #expect(abs(roundTripFromRune.b - zincCard.b) < 0.002)

        // GPUI.Hsla stores gamma sRGB
        let gpuiHsla = zincCard.toGPUIHsla()
        let roundTripFromGPUI = OrnamentColor(gpuiHsla: gpuiHsla)
        #expect(abs(roundTripFromGPUI.r - zincCard.r) < 0.004)
        #expect(abs(roundTripFromGPUI.g - zincCard.g) < 0.004)
        #expect(abs(roundTripFromGPUI.b - zincCard.b) < 0.004)

        // Contrast ratio invariants
        #expect(OrnamentColor.white.contrastRatio(with: .black) > 20.5)
    }

    @Test("All 6 curated OrnamentTheme presets and OKLab fromSeed meet WCAG contrast invariants")
    func allThemePresetsAndSeedDerivation() {
        for appearance in OrnamentAppearance.allCases {
            let presets = OrnamentTheme.allPresets(appearance)
            #expect(presets.count == 6)
            for theme in presets {
                #expect(theme.appearance == appearance)
                #expect(
                    theme.foreground.contrastRatio(with: theme.background) >= 4.5,
                    "\(theme.name) (\(appearance)) fg/bg contrast below 4.5"
                )
                #expect(
                    theme.cardForeground.contrastRatio(with: theme.card) >= 4.5,
                    "\(theme.name) (\(appearance)) card contrast below 4.5"
                )

                // Verify engine token bridges initialize cleanly
                let kit = theme.runeKit()
                #expect(kit.dark == appearance.isDark)
                let mermaid = theme.mermaidStyle(maxWidth: 500.0)
                #expect(mermaid.maxWidth == 500.0)
                let knobs = theme.knobsStyle()
                #expect(knobs.fg.a == 1.0)
                #expect(!theme.gpuiCardShadows().isEmpty)
                #expect(!theme.gpuiPopoverShadows().isEmpty)
                #expect(!theme.gpuiModalShadows().isEmpty)
            }
        }

        let seeded = OrnamentTheme.fromSeed(
            name: "Emerald",
            bg: OrnamentColor(hex: 0x06130E),
            fg: OrnamentColor(hex: 0xECFDF5),
            accent: OrnamentColor(hex: 0x10B981)
        )
        #expect(seeded.appearance == .dark)
        #expect(seeded.foreground.contrastRatio(with: seeded.background) >= 4.5)
        #expect(seeded.mutedForeground.contrastRatio(with: seeded.background) >= 4.4)

        // TaskLocal scoping
        #expect(OrnamentTheme.current.name == "Zinc")
        OrnamentTheme.withTheme(.rose(.light)) {
            #expect(OrnamentTheme.current.name == "Rose")
            #expect(OrnamentTheme.current.appearance == .light)
        }
        #expect(OrnamentTheme.current.name == "Zinc")
    }

    @Test("Category 1 — Floating Chrome & Overlays render live on both Rune and GPUI")
    func floatingChromeAndOverlaysDualEngine() {
        let toolbar = UIFloatingToolbar([
            .icon(.sparkles, label: "AI", active: true),
            .action("Inspect", icon: .eye, shortcut: UIKbd(["⌘", "I"], compact: true)),
            .separator,
            .badge(UIBadge("Live", status: .success, dot: true)),
        ])
        let glassCard = UIGlassCard(
            title: "Liquid Glass Surface",
            subtitle: "Refraction + specular rim",
            icon: .layers,
            badge: UIBadge("IOR 1.52", status: .info)
        ).child(UIText("Backed by RuneLight.Glass optical parameters."))

        let physGlass = glassCard.runeLightGlass(
            x: 24.0,
            y: 24.0,
            width: 320.0,
            height: 160.0,
            theme: .blue(.dark)
        )
        #expect(physGlass.rect == SIMD4<Float>(24.0, 24.0, 320.0, 160.0))
        #expect(abs(physGlass.optics[0] - 1.52) < 0.01)

        let frostedBar = UIFrostedBar(
            leading: [AnyOrnament(UIBadge("GPUAUI", status: .default))],
            center: [AnyOrnament(UIText("Workspace • main", sizePx: 12.5, muted: true))],
            trailing: [AnyOrnament(UIKbd(["⌘", "K"], compact: true))]
        )
        let popover = UIPopover(
            trigger: UIButton("Dimensions", variant: .outline, size: .sm),
            title: "Viewport Bounds",
            description: "Set logical frame dimensions.",
            content: [AnyOrnament(UIInput(value: "1280 × 800", label: "Resolution"))]
        )
        let tooltip = UITooltip(
            trigger: UIIconButton(.bolt, label: "Deploy"),
            text: "Instant Build",
            shortcut: UIKbd(["⌘", "B"], compact: true)
        )
        let hoverCard = UIHoverCard(
            trigger: UIButton("@gpua/ui", variant: .link, size: .sm),
            title: "GPUAUI",
            subtitle: "@mweinbach/GPUA",
            bio: "Shadcn-style ornaments running natively across GPUI and Rune.",
            meta: "Zero external dependencies • Swift 6"
        )
        let toasts = UIToastViewport([
            UIToast(title: "Build succeeded", description: "6/6 platform targets green.", status: .success, actionLabel: "Logs"),
            UIToast(title: "Shader cache warmed", status: .info),
        ])

        let host = OrnamentHost(content: glassCard)
            .ornament(at: .top, frostedBar)
            .ornament(at: .bottom, toolbar)
            .ornament(at: .bottomTrailing, toasts)
            .ornament(at: .topLeading, popover)
            .ornament(at: .topTrailing, tooltip)
            .ornament(at: .leading, hoverCard)

        let runeOut = mountRune(host, theme: .blue(.dark))
        #expect(runeOut.instances.count > 25)
        #expect(runeOut.elements.contains(where: { $0.text?.contains("Liquid Glass Surface") == true }))
        #expect(runeOut.elements.contains(where: { $0.text?.contains("Build succeeded") == true }))

        let gpuiEl = GPUI.div().sizeFull().child(host).intoAnyElement()
        _ = gpuiEl
    }

    @Test("Category 2 — Command Palette, Menus, Dialog, and Sheet render and filter on both engines")
    func commandPaletteMenusAndModalsDualEngine() {
        let palette = UICommandPalette(
            query: "merm",
            groups: [
                UICommandGroup(
                    heading: "Ornaments",
                    items: [
                        UICommandItem(id: "btn", title: "Insert Button", icon: .plus, shortcut: ["⌘", "B"]),
                        UICommandItem(id: "mmd", title: "Render Mermaid Diagram", subtitle: "Vector flowchart", icon: .layers, shortcut: ["⌘", "M"]),
                    ]
                ),
                UICommandGroup(
                    heading: "Theme",
                    items: [
                        UICommandItem(id: "dark", title: "Switch to Rose Dark", icon: .moon),
                    ]
                ),
            ]
        )
        let filtered = palette.filteredGroups()
        #expect(filtered.count == 1)
        #expect(filtered[0].items.count == 1)
        #expect(filtered[0].items[0].id == "mmd")

        let dropdown = UIDropdownMenu(
            trigger: UIButton("Actions", variant: .outline, size: .sm, trailingIcon: .chevronDown),
            entries: [
                .label("Workspace"),
                .item(title: "Duplicate View", icon: .copy, shortcut: "⌘D", highlighted: true),
                .item(title: "Auto Layout", checked: true),
                .separator,
                .item(title: "Delete Target", icon: .trash, shortcut: "⌘⌫", destructive: true),
            ]
        )
        let contextMenu = UIContextMenu(
            target: UIBadge("Right-click target", status: .outline),
            entries: [.item(title: "Inspect Element", icon: .search, shortcut: "⌥⌘I")]
        )
        let dialog = UIDialog(
            title: "Publish Release",
            description: "Tag and build universal binaries across all 6 targets.",
            icon: .bolt,
            body: [AnyOrnament(UICheckbox(checked: true, label: "Run test parity gate"))],
            confirmLabel: "Publish"
        )
        let sheet = UISheet(
            side: .right,
            title: "Inspector",
            description: "Tune active ornament tokens.",
            body: [AnyOrnament(UISwitch(checked: true, label: "Backdrop Blur"))],
            footer: [AnyOrnament(UIButton("Apply", variant: .primary, size: .sm))]
        )

        for item: AnyOrnament in [
            AnyOrnament(palette),
            AnyOrnament(dropdown),
            AnyOrnament(contextMenu),
            AnyOrnament(dialog),
            AnyOrnament(sheet),
        ] {
            let runeRes = mountRune(item, theme: .rose(.dark))
            #expect(!runeRes.instances.isEmpty)
            _ = item.renderGPUI(theme: .rose(.dark))
        }
    }

    @Test("Category 3 — Core Shadcn Controls cover all variants, sizes, and states on both engines")
    func coreShadcnControlsDualEngine() {
        var card = UICard(
            title: "Build Configuration",
            description: "Configure rendering backend and strict concurrency flags.",
            icon: .settings,
            badge: UIBadge("Swift 6.2", status: .info),
            headerTrailing: AnyOrnament(UIKbd(["⌘", ","], compact: true))
        )
        for v in OrnamentVariant.allCases {
            card = card.child(UIButton("Variant \(v.rawValue)", variant: v, size: .sm, icon: .sparkles))
        }
        card = card
            .child(
                UITabs(
                    items: [
                        UITabItem(id: "gpui", label: "GPUI", icon: .bolt, badgeCount: 22),
                        UITabItem(id: "rune", label: "Rune", icon: .layers, badgeCount: 14),
                    ],
                    activeId: "gpui"
                )
            )
            .child(UISwitch(checked: true, label: "Hardware Metal Rasterizer", description: "2x Retina MSAA"))
            .child(UICheckbox(checked: true, label: "ExistentialAny enabled"))
            .child(UIInput(value: "Sources/GPUAUI", label: "Target Path", leadingIcon: .folder, focused: true))
            .footerItem(UIButton("Cancel", variant: .ghost, size: .sm))
            .footerItem(UIButton("Save Changes", variant: .primary, size: .sm))

        let runeOut = mountRune(card, theme: .openCode(.dark))
        #expect(runeOut.instances.count > 30)
        #expect(runeOut.elements.contains(where: { $0.text?.contains("Build Configuration") == true }))
        _ = card.renderGPUI(theme: .openCode(.dark))
    }

    @Test("Category 4 — Developer Ornaments (Markdown, Mermaid, CodeBlock, DiffBlock, KnobsHUD) render on both engines")
    func developerOrnamentsDualEngine() {
        let codeBlock = UICodeBlock(
            """
            import GPUAUI

            let button = UIButton("Deploy", variant: .primary, icon: .bolt)
            """,
            language: "swift",
            filename: "App.swift",
            highlightedLines: [3]
        )

        let diffBlock = UIDiffBlock(
            filename: "Package.swift",
            old: ".library(name: \"RuneKit\", targets: [\"RuneKit\"]),\n",
            new: ".library(name: \"RuneKit\", targets: [\"RuneKit\"]),\n.library(name: \"GPUAUI\", targets: [\"GPUAUI\"]),\n"
        )
        #expect(diffBlock.fileDiff.additions() == 1)

        let mermaidCard = UIMermaidCard(
            """
            flowchart LR
                Theme[OrnamentTheme] --> GPUI[GPUI Engine]
                Theme --> Rune[Rune Engine]
            """,
            title: "Dual-Engine Pipeline"
        )

        let markdown = UIMarkdown(
            """
            ## Release Notes

            Unified **Shadcn** ornaments across `GPUI` and `Rune`:

            | Crate | Status | Engine |
            | :--- | :---: | ---: |
            | `GPUAUI` | Ready | Dual |
            | `RuneMermaid` | Ready | Vector |
            """
        )

        let blurKnob = RuneKnobs.Knob("Glass Blur", 0.0, 40.0, 24.0)
        let modeKnob = RuneKnobs.Knob.choice("Appearance", ["Dark", "Light"], 0)
        let group = RuneKnobs.Group("Glass", "hero", [blurKnob, modeKnob])
            .presets([RuneKnobs.Preset("Frosted", [("Glass Blur", 32.0)])])
        let knobsHUD = UIKnobsHUD(
            title: "Shader Knobs",
            groups: [group],
            values: ["Glass Blur": 28.0]
        )

        for ornament: AnyOrnament in [
            AnyOrnament(codeBlock),
            AnyOrnament(diffBlock),
            AnyOrnament(mermaidCard),
            AnyOrnament(markdown),
            AnyOrnament(knobsHUD),
        ] {
            let runeOut = mountRune(ornament, theme: .zinc(.dark), size: (800.0, 600.0))
            #expect(!runeOut.instances.isEmpty)
            _ = ornament.renderGPUI(theme: .zinc(.dark))
        }
    }

    #if os(macOS)
    @Test("End-to-end GPUI MacWindow + MetalRenderer + CoreText offscreen draw renders GPUAUI pixels")
    @MainActor
    func macOSMetalEndToEndGPUAUIRender() throws {
        struct OrnamentProbeView: GPUI.Render, Sendable {
            mutating func render(_: inout GPUI.Window, _: inout GPUI.Context<OrnamentProbeView>) -> GPUI.AnyElement {
                OrnamentTheme.withTheme(.blue(.dark)) {
                    GPUI.div()
                        .flex()
                        .flexCol()
                        .gap(.pixels(GPUI.px(12.0)))
                        .size(GPUI.px(420.0))
                        .p(GPUI.px(20.0))
                        .bg(OrnamentTheme.current.background.toGPUIHsla())
                        .child(
                            UICard(
                                title: "GPUAUI Metal Probe",
                                description: "Rendered via GPUIMetal + CoreText",
                                icon: .sparkles,
                                badge: UIBadge("2x Retina", status: .info)
                            )
                            .child(UIButton("Launch Palette", variant: .primary, size: .sm, shortcut: UIKbd(["⌘", "K"], compact: true)))
                        )
                        .intoAnyElement()
                }
            }
        }

        let platform = MacPlatform.new(headless: false)
        let cx = GPUI.App.newApp(platform: platform)
        let options = GPUI.WindowOptions(
            windowBounds: .windowed(
                GPUI.Bounds(
                    origin: GPUI.point(GPUI.px(80.0), GPUI.px(80.0)),
                    size: GPUI.size(GPUI.px(420.0), GPUI.px(420.0))
                )
            ),
            titlebar: GPUI.TitlebarOptions(title: "GPUAUI Probe", appearsTransparent: true),
            focus: false,
            show: false
        )
        let handle = try cx.openWindow(options) { _, app in
            app.new { _ in OrnamentProbeView() }
        }
        var captured: (width: UInt32, height: UInt32, rgba: [UInt8])?
        try cx.updateWindow(handle.anyHandle) { _, window, app in
            let macWin = try #require(window.platformWindow as? MacWindow)
            macWin.captureFrames = true
            var appMut = app
            window.draw(cx: &appMut)
            captured = macWin.lastCapturedFrame
        }
        let frame = try #require(captured)
        #expect(frame.width >= 420)
        #expect(frame.height >= 420)
        let nonZeroPixels = stride(from: 0, to: frame.rgba.count, by: 16).filter { idx in
            frame.rgba[idx] > 20 || frame.rgba[idx + 1] > 20 || frame.rgba[idx + 2] > 20
        }.count
        #expect(nonZeroPixels > 500)
    }
    #endif
}
