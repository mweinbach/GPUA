# 0009: Linux Windowing, Input, and System Library Dependencies

- **Status:** Accepted
- **Date:** 2026-10-29

## Context

Upstream GPUI's Linux backend (`crates/gpui_linux`) targets Wayland and X11 windowing environments, using standard freedesktop system libraries for display server protocols, raw keyboard/input handling, font configuration, and rasterization:
- Display / Windowing: Wayland client protocol (`libwayland-client`, `wayland-protocols`), X11 (`libX11`, `libX11-xcb`), and XCB protocol extensions (`libxcb`, `xcb-randr`, `xcb-xinput`, `xcb-sync`, `xcb-xkb`, `libXcursor`).
- Keyboard & Input: `libxkbcommon` and `libxkbcommon-x11` for keymap compilation, modifier state, and compose sequences.
- Typography & Fonts: `libfreetype6`, `libharfbuzz`, and `libfontconfig1` for system font discovery, shaping, and glyph metrics (mirroring ADR-0006).
- Desktop Portals: XDG desktop portal interfaces (via D-Bus) for system dialogs, dark mode / theme preference detection, and file picker interaction.
- GPU Presentation: WebGPU through `wgpu-native` (mirroring ADR-0004), targeting Vulkan (or Lavapipe software rasterizer in CI and containerized environments).

Under SwiftPM, importing C APIs requires either system library targets (`systemLibrary`) or C target modules (`.target` with C sources and headers). Direct SwiftPM `systemLibrary` targets require custom `.pc` pkg-config files that may vary across Linux distributions or cross-compilation environments.

## Decision

1. Package system C headers into a dedicated Swift-only target `CLinuxSys`:
   - `Sources/CLinuxSys/include/CLinuxSys.h` acts as an umbrella header declaring standard Linux C includes guarded with `#if defined(__linux__)`.
   - On non-Linux platforms (macOS, iOS, Windows, Android), `CLinuxSys.h` compiles cleanly as an empty unit, ensuring `swift build` and multi-platform compilation succeed unconditionally without platform guards breaking.
2. Link required system libraries through `Package.swift` linker settings on `GPUILinux`:
   - `wayland-client`, `wayland-cursor`, `X11`, `X11-xcb`, `xcb`, `xkbcommon`, `xkbcommon-x11`, `freetype`, `harfbuzz`, and `fontconfig`, each guarded with `.when(platforms: [.linux])`.
3. Generate standard Wayland client protocols into `CLinuxSys`:
   - `xdg-shell` client protocol headers (`xdg-shell-client-protocol.h`) and private code (`xdg-shell-protocol.c`) are pre-generated via `wayland-scanner` from upstream freedesktop `xdg-shell.xml` and committed into `Sources/CLinuxSys/`, guarded by `#if defined(__linux__) && !defined(__ANDROID__)`. This eliminates build-time plugin requirements and guarantees identical C symbol bindings across Linux toolchains while allowing macOS, Windows, and Android to build cleanly.
4. Provide an architecture-aware provisioning script `Scripts/install_linux_deps.sh`:
   - Installs Debian/Ubuntu packages for `x86_64` and `aarch64`, including `xvfb` for headless X11 and `weston` for headless Wayland compositor testing (`weston --backend=headless`).
   - Downloads prebuilt `wgpu-native v24.0.0.2` (`libwgpu_native.so`) to `/usr/local/lib` and executes `ldconfig`.
   - Configures Mesa Lavapipe Vulkan ICD (`mesa-vulkan-drivers`) and `xvfb` so headless CI and local containerized testing execute deterministically without physical GPU hardware.
5. Integrate into CI (`.github/workflows/ci.yml`):
   - Linux job runs `bash Scripts/install_linux_deps.sh` and executes test suites under `xvfb-run -a swift test`.

## Alternatives considered

- Pure Swift Wayland / XCB protocol implementations: Prohibitive complexity and maintenance overhead compared to standard C library bindings used by all native Linux applications.
- Standalone SwiftPM `systemLibrary` targets with pkg-config: Fragile on container images where `.pc` search paths or multi-arch prefixes differ between Ubuntu versions and architectures.
- Dynamic runtime `dlopen` without header interop: Loses Swift compile-time type checking for C structs, event unions, and protocol function pointers.

## Consequences

- Full binary and protocol fidelity with upstream GPUI's Linux backend.
- Zero impact on macOS, Windows, and Android host builds due to `#if defined(__linux__)` and `.when(platforms: [.linux])` scoping.
- Containerized Linux workflows (`swift:6.3-noble`) reproduce CI environment identically across `x86_64` and `aarch64`.
