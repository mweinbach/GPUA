# 0015: `GPUAUI` — Unified Shadcn-Style Ornament & Component Target Across GPUI and Rune

- **Status:** Accepted
- **Date:** 2026-11-01

## Context

With both `GPUI` (`Glass-HQ/gpui`) and `Rune` / `RuneKit` (`anomalyco/rune`) hosted in GPUA, Swift developers want an ergonomic, batteries-included way to compose **UI ornaments** and controls across both engines in the style of [shadcn/ui](https://ui.shadcn.com):
- A semantic design-token theme schema (`background`, `foreground`, `card`, `popover`, `primary`, `secondary`, `muted`, `accent`, `destructive`, `border`, `input`, `ring`, `radius`) with curated light/dark presets (`Zinc`, `Slate`, `Neutral`, `Rose`, `Blue`, `OpenCode`) and OKLab palette derivation.
- Composable prebuilt Swift value types with predictable `variant` and `size` axes — importable directly as a SwiftPM library product (`GPUAUI`) with zero external dependencies and no file-copying CLI required.
- Live dual-engine rendering on **both** `GPUI` (`IntoElement` / `AnyElement`) and `Rune` (`Rune.El` + `RuneKit.Kit` + `RuneMotion` springs), covering floating chrome & overlays, menus/modals/command palettes, core Shadcn controls, and rich developer ornaments (streaming Markdown, native Mermaid diagrams, syntax/diff blocks, and live tuning knobs).

## Decision

1. **Swift-Only Library Product & Target (`GPUAUI` + `GPUAUITests`)**:
   - Add a public `.library(name: "GPUAUI", targets: ["GPUAUI"])` product and `GPUAUI` target in `Package.swift`, registered in `porting.json` under `swift_only_targets` (every file carrying a `// Swift-only:` header per Golden Rule #9).
   - `GPUAUI` depends on `GPUI`, `Rune`, `RuneMotion`, `RuneKit`, `RuneMermaid`, `RuneKnobs`, `RuneFX`, `RuneLight`, and `RuneThemeOpenCode`.

2. **Unified Shadcn Semantic Token Layer (`OrnamentTheme`)**:
   - Define `OrnamentTheme` with Shadcn's semantic color roles, border radii (`sm`, `md`, `lg`, `full`), elevation shadows, frosted-glass parameters, syntax colors, and `RuneMotion.Spring` presets (`snappy`, `bouncy`, `gentle`).
   - Provide built-in `.zinc`, `.slate`, `.neutral`, `.rose`, `.blue`, and `.openCode` themes in `.light` and `.dark` appearances, plus `OrnamentTheme.fromSeed(...)` via OKLab contrast-floor derivation.
   - Bridge `OrnamentTheme` bidirectionally to `GPUI.Hsla` / `GPUI.BoxShadow` and `RuneKit.Kit` / `Rune.Color` so an ornament styled with an `OrnamentTheme` looks identical in both `GPUI` and `Rune` windows.

3. **Dual-Engine `Ornament` Protocol**:
   - Every ornament in `GPUAUI` conforms to `GPUAOrnament`, providing:
     - `renderGPUI(theme: OrnamentTheme) -> GPUI.AnyElement` (plus `GPUI.IntoElement` conformance so ornaments drop directly into `.child(...)` or `OrnamentHost` in GPUI views), and
     - `renderRune(theme: OrnamentTheme, layer: inout [Rune.El]) -> Rune.El` (mounting anchored popovers/menus/modals/tooltips into the Rune root overlay layer while returning the trigger/inline `El`).

4. **Initial Ornament Catalog**:
   - **Floating Chrome & Overlays**: `OrnamentAnchor`, `OrnamentHost`, `UIFloatingToolbar` (pill bar), `UIGlassCard`, `UIFrostedBar`, `UIPopover`, `UITooltip`, `UIHoverCard`, `UIToast`, `UIToastViewport`.
   - **Menus, Modals & Command**: `UICommandPalette` (`⌘K`), `UIDropdownMenu`, `UIContextMenu`, `UIDialog`, `UISheet`.
   - **Core Shadcn Controls**: `UIButton`, `UIIconButton`, `UIBadge`, `UICard`, `UITabs` / `UISegmented`, `UISwitch`, `UICheckbox`, `UIInput`, `UIKbd`.
   - **Rich Developer Ornaments**: `UIMarkdown` (streaming CommonMark + GFM tables + syntax fences), `UIMermaidCard` (native flowchart/sequence/state vector diagrams via `RuneMermaid`), `UICodeBlock` & `UIDiffBlock` (syntax + Myers word-level diff via `RuneKit`), and `UIKnobsHUD` (live interactive parameter panel via `RuneKnobs`).

## Alternatives Considered

- **File-Copying CLI Only (`shadcn add`)**: Rejected per user preference for a clean, directly importable SwiftPM library target (`import GPUAUI`) with composable prebuilt Swift APIs.
- **Separate `GPUI`-only and `Rune`-only Component APIs**: Forces apps or host shells mixing GPUI and Rune windows to learn two component vocabularies and maintain duplicate themes.

## Consequences

- Downstream Swift apps can `import GPUAUI` and immediately render Shadcn-styled ornaments, floating toolbars, frosted glass cards, command palettes, streaming Markdown, Mermaid diagrams, diffs, and live knobs in either a `GPUI` window or a `Rune` window from one shared `OrnamentTheme`.
- Zero external SwiftPM dependencies; compiles cleanly across macOS, iOS / visionOS, Linux, Windows, Android, and WebAssembly.
