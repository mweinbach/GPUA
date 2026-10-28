# GPUA

**A file-for-file Swift port of [GPUI](https://github.com/Glass-HQ/gpui).** GPUI is the GPU-accelerated UI framework behind the [Zed](https://zed.dev) editor. GPUA ships it as a SwiftPM package, so Swift apps get one native, GPU-rendered UI SDK for **macOS, iOS, Windows, Linux, Android**, and later **the web**.

> [!WARNING]
> **Pre-alpha. Nothing renders yet.** The repo is set up for the port: every upstream Rust file has a Swift stub at the same path. The porting rules and tooling are written and checked in. See [docs/PORTING_STATUS.md](docs/PORTING_STATUS.md) for live progress.

## Why

- **GPUI's design holds up.** It mixes immediate and retained mode, styles with a Tailwind-like fluent API, keeps state in entities, renders through a GPU scene graph, and has ten years of editor-grade polish behind it.
- **Swift runs everywhere now.** Swift 6 has official toolchains for macOS, Linux, Windows, Android (the Swift SDK for Android), and Wasm. What it doesn't have is a native, GPU-rendered UI framework that works on all of them. GPUA aims to fill that gap.
- **A faithful port keeps up with upstream.** Each Swift file maps to exactly one upstream Rust file, so upstream changes turn into a mechanical diff to re-port. That's better than a rewrite that drifts away.

## What it will look like

```swift
import GPUI
import GPUIPlatform

struct HelloWorld: Render {
    var text: SharedString

    func render(_ window: Window, _ cx: Context<Self>) -> some IntoElement {
        div()
            .flex()
            .flexCol()
            .gap3()
            .bg(rgb(0x505050))
            .size(px(500))
            .justifyCenter()
            .itemsCenter()
            .shadowLg()
            .textXl()
            .textColor(rgb(0xffffff))
            .child("Hello, \(text)!")
    }
}

application().run { cx in
    let bounds = Bounds.centered(nil, size(px(500), px(500)), cx)
    _ = try! cx.openWindow(WindowOptions(windowBounds: .windowed(bounds))) { _, cx in
        cx.new { _ in HelloWorld(text: "World") }
    }
    cx.activate(true)
}
```

Compare that with the Rust [`hello_world.rs`](https://github.com/Glass-HQ/gpui/blob/650aab59d54f4f6f85d42c965831935568ac1162/crates/gpui_examples/examples/hello_world.rs). The Swift API faithfully ports GPUI's logic and behavior into idiomatic Swift. See [docs/API_DESIGN.md](docs/API_DESIGN.md).

## Platform plan

| Platform | Window/input backend | Renderer | Text | Upstream crate |
|---|---|---|---|---|
| macOS | AppKit | Metal | CoreText | `gpui_macos`, `gpui_metal` |
| iOS / iPadOS / visionOS | UIKit | Metal | CoreText | `gpui_ios`, `gpui_metal` |
| Linux | Wayland + X11 | WebGPU (wgpu-native → Vulkan) | FreeType + HarfBuzz | `gpui_linux`, `gpui_wgpu` |
| Windows | Win32 | Direct3D 11 (port of upstream) | DirectWrite | `gpui_windows` |
| Android | NDK `ANativeActivity` / `GameActivity` | WebGPU (wgpu-native → Vulkan) | FreeType + HarfBuzz | *none (new: `GPUIAndroid`)* |
| Web | Browser DOM via JavaScriptKit | WebGPU | Canvas / swash-equivalent | `gpui_web`, `gpui_wgpu` |

Details: [docs/PLATFORMS.md](docs/PLATFORMS.md).

## Repository layout

The layout mirrors upstream. Each crate becomes a target, and each file keeps its path:

```
crates/gpui/src/elements/div.rs        →  Sources/GPUI/elements/div.swift
crates/gpui/src/app/entity_map.rs      →  Sources/GPUI/app/entity_map.swift
crates/gpui/src/app/entity_map.rs      →  Tests/GPUITests/app/entity_map.swift   (its #[cfg(test)] module)
crates/gpui_macos/src/window.rs        →  Sources/GPUIMacOS/window.swift
crates/gpui_metal/src/shaders.metal    →  Sources/GPUIMetal/shaders.metal       (copied verbatim)
```

| Upstream crate | Swift target | | Upstream crate | Swift target |
|---|---|---|---|---|
| `gpui` | `GPUI` | | `gpui_wgpu` | `GPUIWGPU` |
| `gpui_platform` | `GPUIPlatform` | | `gpui_web` | `GPUIWeb` |
| `gpui_apple` | `GPUIApple` | | `gpui_macros` | `GPUIMacros` |
| `gpui_macos` | `GPUIMacOS` | | `gpui_util` | `GPUIUtil` |
| `gpui_ios` | `GPUIiOS` | | `gpui_examples` | `GPUIExamples` |
| `gpui_metal` | `GPUIMetal` | | `collections` | `GPUICollections` |
| `gpui_linux` | `GPUILinux` | | `util` | `ZedUtil` |
| `gpui_windows` | `GPUIWindows` | | `sum_tree` / `scheduler` / `refineable` | `SumTree` / `Scheduler` / `Refineable` |
| *(new)* | `GPUIAndroid` | | `http_client` / `media` | `HTTPClient` / `Media` |

The mapping lives in [`porting.json`](porting.json) and is enforced by [`Scripts/port.py`](Scripts/port.py).

## Getting started (contributors)

```sh
git clone https://github.com/mweinbach/GPUA && cd GPUA
Scripts/port.py fetch          # pinned upstream checkout → .upstream/gpui (gitignored)
swift build                    # everything compiles (stubs are empty)
Scripts/port.py todo --target SumTree   # what's left, smallest files first
Scripts/port.py map crates/gpui/src/geometry.rs
Scripts/port.py check          # CI gate: mapping, headers, status doc
```

Then read, in order:

1. [AGENTS.md](AGENTS.md): the rules for any human or AI agent working here
2. [docs/PORTING_GUIDE.md](docs/PORTING_GUIDE.md): Rust → Swift translation rules
3. [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): how GPUI works and how the targets fit together
4. [docs/ROADMAP.md](docs/ROADMAP.md): what to port first
5. [docs/adr/](docs/adr): the decisions behind all of the above

## Documentation

| Doc | What's in it |
|---|---|
| [VISION.md](docs/VISION.md) | Goals, non-goals, success criteria |
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | GPUI's architecture, the frame pipeline, the target graph |
| [PORTING_GUIDE.md](docs/PORTING_GUIDE.md) | File mapping, naming, Rust → Swift idioms, headers, tests |
| [API_DESIGN.md](docs/API_DESIGN.md) | What the public Swift API looks like, with side-by-side examples |
| [PLATFORMS.md](docs/PLATFORMS.md) | Per-platform backends, system deps, toolchains |
| [ROADMAP.md](docs/ROADMAP.md) | Phased plan and milestones |
| [UPSTREAM_SYNC.md](docs/UPSTREAM_SYNC.md) | How to bump the pinned upstream and re-port diffs |
| [PORTING_STATUS.md](docs/PORTING_STATUS.md) | Generated per-file progress |

## License

Apache-2.0, the same as upstream GPUI. GPUA is a derivative work of GPUI by Zed Industries, Inc. and the Glass-HQ fork contributors. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
