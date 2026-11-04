// swift-tools-version: 6.2
//
// GPUA — a file-for-file Swift port of GPUI (https://github.com/Glass-HQ/gpui).
//
// Every Rust crate maps 1:1 to a SwiftPM target and every `.rs` file maps 1:1 to
// a `.swift` file. The mapping lives in `porting.json` and is enforced by
// `Scripts/port.py check`. See docs/ARCHITECTURE.md and docs/PORTING_GUIDE.md.

import PackageDescription

// MARK: - Shared settings

let swiftSettings: [SwiftSetting] = [
    // Rust `dyn Trait` ↔ Swift `any Protocol`: make existentials explicit, like upstream.
    .enableUpcomingFeature("ExistentialAny"),
]

// Platform conditions, mirroring upstream `#[cfg(target_os = ...)]` dependencies.
let apple: [Platform] = [.macOS, .iOS, .visionOS, .macCatalyst]
let wgpuPlatforms: [Platform] = [.linux, .windows, .android, .wasi]

/// Upstream crate → SwiftPM target. Keep this list in the same order as porting.json.
func crate(
    _ name: String,
    _ dependencies: [Target.Dependency] = [],
    exclude: [String] = [],
    resources: [Resource]? = nil,
    linkerSettings: [LinkerSetting]? = nil
) -> Target {
    .target(
        name: name,
        dependencies: dependencies,
        exclude: exclude,
        resources: resources,
        swiftSettings: swiftSettings,
        linkerSettings: linkerSettings
    )
}

func crateTests(
    _ name: String,
    _ extra: [Target.Dependency] = [],
    exclude: [String] = []
) -> Target {
    .testTarget(
        name: "\(name)Tests",
        dependencies: [.target(name: name)] + extra,
        exclude: exclude,
        swiftSettings: swiftSettings
    )
}

// MARK: - Package

let package = Package(
    name: "GPUA",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .visionOS(.v1),
        .macCatalyst(.v17),
    ],
    products: [
        // The framework: core types, elements, styling, entities, windows.
        .library(name: "GPUI", targets: ["GPUI"]),
        // The layout engine: flexbox, CSS grid, block layout
        .library(name: "Taffy", targets: ["Taffy"]),
        // `application()` / `current_platform()` — picks the right backend for the OS.
        .library(name: "GPUIPlatform", targets: ["GPUIPlatform"]),
        // Upstream example gallery: `swift run gpui-examples hello_world`.
        .executable(name: "gpui-examples", targets: ["GPUIExamples"]),

        // ---- Rune (https://github.com/anomalyco/rune, ADR-0014) ------------
        .library(name: "Rune", targets: ["Rune"]),
        .library(name: "RuneKit", targets: ["RuneKit"]),
        .library(name: "RuneMotion", targets: ["RuneMotion"]),
        .library(name: "RuneFX", targets: ["RuneFX"]),
        .library(name: "RuneLight", targets: ["RuneLight"]),
        .library(name: "RuneMermaid", targets: ["RuneMermaid"]),
        .library(name: "RuneKnobs", targets: ["RuneKnobs"]),
        .library(name: "RuneThemeOpenCode", targets: ["RuneThemeOpenCode"]),

        // ---- Unified Shadcn-style UI Ornaments (ADR-0015) ------------------
        .library(name: "GPUAUI", targets: ["GPUAUI"]),
    ],
    // Cargo features ↔ SwiftPM package traits. `#[cfg(feature = "test-support")]`
    // becomes `#if TestSupport`, etc. See docs/PORTING_GUIDE.md#cfg-and-features.
    traits: [
        .trait(name: "TestSupport", description: "gpui `test-support`: TestPlatform, TestAppContext, leak detection."),
        .trait(name: "Inspector", description: "gpui `inspector`: element inspector support."),
        .trait(name: "ScreenCapture", description: "gpui `screen-capture`."),
        .trait(name: "Wayland", description: "gpui `wayland` (Linux)."),
        .trait(name: "X11", description: "gpui `x11` (Linux)."),
        .trait(name: "RuntimeShaders", description: "gpui `runtime_shaders`: compile shaders from source at runtime."),
        // TestSupport is on by default while porting; revisit before 1.0.
        .default(enabledTraits: ["TestSupport", "Wayland", "X11"]),
    ],
    targets: [
        // ---- Support crates ------------------------------------------------
        crate("GPUICollections"),                                   // crates/collections
        crate("ZedUtil", ["GPUICollections", "GPUIUtil"]),                      // crates/util
        crate("GPUIUtil"),                                          // crates/gpui_util
        crate("SumTree"),                                           // crates/sum_tree
        crate("Scheduler"),                                         // crates/scheduler
        crate("DeriveRefineable"),                                  // crates/refineable/derive_refineable (→ Swift macro later)
        crate("Refineable", ["DeriveRefineable"]),                  // crates/refineable
        crate("HTTPClient", ["ZedUtil"]),                           // crates/http_client
        crate("Media"),                                             // crates/media
        crate("GPUIMacros"),                                        // crates/gpui_macros (→ `.macro` target later)
        crate("Taffy"),                                             // upstream taffy (flexbox, grid, block layout)

        // ---- C interop packaging -------------------------------------------
        .target(
            name: "CWebGPU",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("include"),
            ]
        ),
        .target(
            name: "CLinuxSys",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("include"),
            ]
        ),
        .target(
            name: "CWinSys",
            path: "Sources/CWinSys",
            publicHeadersPath: "include"
        ),
        .target(
            name: "CAndroidSys",
            path: "Sources/CAndroidSys",
            publicHeadersPath: "include"
        ),
        .target(
            name: "CWebSys",
            path: "Sources/CWebSys",
            publicHeadersPath: "include"
        ),

        // ---- Core ----------------------------------------------------------
        crate(                                                      // crates/gpui
            "GPUI",
            ["GPUICollections", "GPUIMacros", "GPUIUtil", "HTTPClient", "Media", "Refineable", "Scheduler", "SumTree", "Taffy"],
            exclude: ["platform/mac/shaders.metal"]
        ),

        // ---- Renderers -----------------------------------------------------
        crate("GPUIMetal", ["GPUI", "GPUICollections", "Media"],    // crates/gpui_metal
              resources: [.copy("shaders.metal")]),
        crate(
            "GPUIWGPU",
            [
                "GPUI",
                "GPUICollections",
                "GPUIUtil",
                "CWebGPU",
                .target(name: "CLinuxSys", condition: .when(platforms: [.linux])),
            ],
            resources: [.copy("shaders.wgsl"), .copy("shaders_subpixel.wgsl")],
            linkerSettings: [
                .linkedLibrary("wgpu_native", .when(platforms: [.linux])),
                .linkedLibrary("freetype", .when(platforms: [.linux])),
                .linkedLibrary("harfbuzz", .when(platforms: [.linux])),
                .linkedLibrary("fontconfig", .when(platforms: [.linux])),
            ]
        ),

        // ---- Platforms -----------------------------------------------------
        crate("GPUIApple", ["GPUI", "GPUICollections", "GPUIMetal"]),                         // crates/gpui_apple
        crate("GPUIMacOS", ["GPUI", "GPUIApple", "GPUIMetal", "GPUICollections", "Media", "ZedUtil"]), // crates/gpui_macos
        crate("GPUIiOS", ["GPUI", "GPUIApple", "GPUIMetal", "GPUICollections"]),              // crates/gpui_ios
        crate(
            "GPUILinux",
            ["GPUI", "GPUIWGPU", "GPUICollections", "GPUIUtil", "HTTPClient", "ZedUtil", "CWebGPU", "CLinuxSys"],
            linkerSettings: [
                .linkedLibrary("wayland-client", .when(platforms: [.linux])),
                .linkedLibrary("wayland-cursor", .when(platforms: [.linux])),
                .linkedLibrary("X11", .when(platforms: [.linux])),
                .linkedLibrary("X11-xcb", .when(platforms: [.linux])),
                .linkedLibrary("xcb", .when(platforms: [.linux])),
                .linkedLibrary("xcb-randr", .when(platforms: [.linux])),
                .linkedLibrary("xcb-xinput", .when(platforms: [.linux])),
                .linkedLibrary("xcb-sync", .when(platforms: [.linux])),
                .linkedLibrary("xcb-shape", .when(platforms: [.linux])),
                .linkedLibrary("xcb-xkb", .when(platforms: [.linux])),
                .linkedLibrary("Xcursor", .when(platforms: [.linux])),
                .linkedLibrary("xkbcommon", .when(platforms: [.linux])),
                .linkedLibrary("xkbcommon-x11", .when(platforms: [.linux])),
                .linkedLibrary("freetype", .when(platforms: [.linux])),
                .linkedLibrary("harfbuzz", .when(platforms: [.linux])),
                .linkedLibrary("fontconfig", .when(platforms: [.linux])),
            ]
        ),
        crate(
            "GPUIWindows",
            ["GPUI", "GPUICollections", "GPUIUtil", "HTTPClient", "ZedUtil", .target(name: "CWinSys", condition: .when(platforms: [.windows]))],
            resources: [.copy("shaders.hlsl"), .copy("alpha_correction.hlsl"), .copy("color_text_raster.hlsl")],
            linkerSettings: [
                .linkedLibrary("d3d11", .when(platforms: [.windows])),
                .linkedLibrary("dxgi", .when(platforms: [.windows])),
                .linkedLibrary("d3dcompiler", .when(platforms: [.windows])),
                .linkedLibrary("dwrite", .when(platforms: [.windows])),
                .linkedLibrary("dwmapi", .when(platforms: [.windows])),
                .linkedLibrary("imm32", .when(platforms: [.windows])),
                .linkedLibrary("uxtheme", .when(platforms: [.windows])),
                .linkedLibrary("ole32", .when(platforms: [.windows])),
                .linkedLibrary("shell32", .when(platforms: [.windows])),
                .linkedLibrary("user32", .when(platforms: [.windows])),
                .linkedLibrary("gdi32", .when(platforms: [.windows])),
                .linkedLibrary("shcore", .when(platforms: [.windows])),
                .linkedLibrary("advapi32", .when(platforms: [.windows])),
                .linkedLibrary("winmm", .when(platforms: [.windows])),
            ]
        ),
        crate(
            "GPUIWeb",
            [
                "GPUI",
                "GPUIWGPU",
                "GPUICollections",
                "GPUIUtil",
                "HTTPClient",
                "ZedUtil",
                "CWebGPU",
                .target(name: "CWebSys", condition: .when(platforms: [.wasi])),
            ]
        ),                                                                                      // crates/gpui_web
        crate(
            "GPUIAndroid",
            [
                "GPUI",
                "GPUIWGPU",
                "GPUICollections",
                "GPUIUtil",
                "HTTPClient",
                "ZedUtil",
                "CWebGPU",
                .target(name: "CAndroidSys", condition: .when(platforms: [.android])),
            ],
            linkerSettings: [
                .linkedLibrary("android", .when(platforms: [.android])),
                .linkedLibrary("log", .when(platforms: [.android])),
            ]
        ),                                                                                      // Swift-only (no upstream crate)

        crate(                                                      // crates/gpui_platform
            "GPUIPlatform",
            [
                "GPUI",
                .target(name: "GPUIMacOS", condition: .when(platforms: [.macOS])),
                .target(name: "GPUIiOS", condition: .when(platforms: [.iOS, .visionOS, .macCatalyst])),
                .target(name: "GPUIWindows", condition: .when(platforms: [.windows])),
                .target(name: "GPUILinux", condition: .when(platforms: [.linux])),
                .target(name: "GPUIAndroid", condition: .when(platforms: [.android])),
                .target(name: "GPUIWeb", condition: .when(platforms: [.wasi])),
            ]
        ),

        // ---- Examples ------------------------------------------------------
        .executableTarget(                                          // crates/gpui_examples
            name: "GPUIExamples",
            dependencies: ["GPUI", "GPUIPlatform"],
            resources: [.copy("examples/image"), .copy("examples/svg")],
            swiftSettings: swiftSettings
        ),

        // ---- Rune (anomalyco/rune, ADR-0014) -------------------------------
        crate("Procwatch"),                                         // crates/procwatch
        crate("RuneStaging", ["CWebGPU"]),                          // crates/rune-staging
        crate("RuneRegister"),                                      // crates/rune-register
        crate("RuneMotion"),                                        // crates/rune-motion
        crate("RunePerf", ["Procwatch"]),                           // crates/rune-perf
        crate("RuneMac"),                                           // crates/rune-mac (#if os(macOS))
        crate(                                                      // crates/rune-light
            "RuneLight",
            ["RuneStaging", "CWebGPU"],
            resources: [.copy("shaders")]
        ),
        crate(                                                      // crates/rune-fx
            "RuneFX",
            ["RuneMotion", "RuneStaging", "CWebGPU"],
            resources: [.copy("shaders")]
        ),
        crate(                                                      // crates/rune
            "Rune",
            [
                "RuneMotion",
                "RuneStaging",
                "Procwatch",
                "Taffy",
                "CWebGPU",
                .target(name: "CLinuxSys", condition: .when(platforms: [.linux])),
                .target(name: "CWinSys", condition: .when(platforms: [.windows])),
                .target(name: "CAndroidSys", condition: .when(platforms: [.android])),
                .target(name: "CWebSys", condition: .when(platforms: [.wasi])),
            ],
            resources: [
                .copy("assets"),
                .copy("backdrop_blur.wgsl"),
                .copy("backdrop_composite.wgsl"),
                .copy("clip.wgsl"),
                .copy("gpu/springs.wgsl"),
                .copy("layer_blur.wgsl"),
                .copy("native_surface/video.wgsl"),
                .copy("shader.wgsl"),
            ],
            linkerSettings: [
                .linkedLibrary("xcb", .when(platforms: [.linux])),
                .linkedLibrary("xcb-randr", .when(platforms: [.linux])),
                .linkedLibrary("xcb-xinput", .when(platforms: [.linux])),
                .linkedLibrary("dwmapi", .when(platforms: [.windows])),
                .linkedLibrary("shell32", .when(platforms: [.windows])),
                .linkedLibrary("user32", .when(platforms: [.windows])),
                .linkedLibrary("gdi32", .when(platforms: [.windows])),
            ]
        ),
        crate("RuneRef", ["Rune"]),                                 // crates/rune-ref
        crate("RuneKnobs", ["Rune"]),                               // crates/rune-knobs
        crate("RuneMermaid", ["Rune"]),                             // crates/rune-mermaid
        crate("RuneKit", ["Rune", "RuneMotion", "RuneMermaid"]),    // crates/rune-kit
        crate(                                                      // themes/opencode
            "RuneThemeOpenCode",
            ["Rune", "RuneKit"],
            resources: [.copy("assets")]
        ),

        // ---- Unified Shadcn-style Ornaments across GPUI & Rune (ADR-0015) --
        crate(
            "GPUAUI",
            [
                "GPUI",
                "Rune",
                "RuneMotion",
                "RuneKit",
                "RuneMermaid",
                "RuneKnobs",
                "RuneFX",
                "RuneLight",
                "RuneThemeOpenCode",
            ]
        ),

        // ---- Tests (inline `#[cfg(test)]` modules + crates/*/tests) ---------
        crateTests("GPUICollections"),
        crateTests("GPUIUtil"),
        crateTests("Refineable"),
        crateTests("ZedUtil"),
        crateTests("SumTree"),
        crateTests("Scheduler"),
        crateTests("HTTPClient"),
        crateTests("GPUIMacros"),
        crateTests("Taffy"),
        crateTests("GPUI", exclude: ["Fixtures"]),
        crateTests("GPUIMetal"),
        crateTests("GPUIWGPU"),
        crateTests("GPUIMacOS"),
        crateTests("GPUIiOS"),
        crateTests("GPUILinux", ["GPUIUtil"]),
        crateTests("GPUIWindows", ["GPUIUtil"]),
        crateTests("GPUIWeb", ["GPUIUtil"]),
        crateTests("GPUIAndroid", ["GPUIUtil"]),
        crateTests("GPUIPlatform"),
        crateTests("Procwatch"),
        crateTests("RuneRegister"),
        crateTests("RuneMotion"),
        crateTests("RunePerf"),
        crateTests("RuneMac"),
        crateTests("RuneLight", ["Rune", "RuneFX"]),
        crateTests("RuneFX", ["Rune", "RuneRef"]),
        crateTests("Rune", exclude: ["tests/coretext"]),
        crateTests("RuneRef"),
        crateTests("RuneKnobs"),
        crateTests("RuneMermaid"),
        crateTests("RuneKit", ["Procwatch", "RuneThemeOpenCode"]),
        crateTests("RuneThemeOpenCode"),
        crateTests(
            "GPUAUI",
            [
                "GPUI",
                "Rune",
                "RuneMotion",
                "RuneKit",
                "RuneMermaid",
                "RuneKnobs",
                "RuneLight",
                "RuneThemeOpenCode",
                .target(name: "GPUIMetal", condition: .when(platforms: apple)),
                .target(name: "GPUIMacOS", condition: .when(platforms: [.macOS])),
            ]
        ),
    ]
)
