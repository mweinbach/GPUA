// Ported from: crates/rune/src/window/win.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Per-window surface, visibility, cursor, and pacing state (`crates/rune/src/window/win.rs`).

#if !os(WASI)
import Foundation
#endif

/// Per-window surface and platform wrapper (`crates/rune/src/window/win.rs`).
final class Win {
    let window: NativeWindow
    var config: WindowSurfaceConfig
    var surfaceMeter = WindowSurfaceMeter()
    var presented = WindowPresented()
    var firstFrame: FirstFrame
    var launchDrawables: LaunchDrawables
    var hiddenPace = HiddenPace()
    var fileDrop = FileDrop()
    var native = WindowNative()
    #if os(macOS)
    var macHelp: MacNativeHelp? = nil
    #endif

    var visible: Bool {
        didSet {
            if !visible {
                presented.invalidate()
            }
        }
    }
    var occluded: Bool = false {
        didSet {
            if occluded {
                presented.invalidate()
            }
        }
    }
    var occludedRetry: Duration? = nil
    var floatingOnOpen: Bool = false
    var currentCursor: Cursor = .default
    var cursorHidden: Bool = false
    var imeAllowed: Bool = false
    var imeSpot: ((Double, Double), (Double, Double))? = nil
    var dragRegions: [[Float]] = []
    var lastTitlebarClick: (RuneInstant, (Float, Float))? = nil
    var gpuReleased: Bool = false

    /// Test-injectable queue of swapchain acquire statuses (for `occluded_surface_tests`, etc.).
    var simulatedAcquireStatuses: [SurfaceAcquireStatus] = []
    var drawCount: Int = 0

    init(
        window: NativeWindow,
        options: WindowOptions,
        mac: MacWindowOptions,
        srgb: Bool,
        floatOnOpen: Bool = false,
        deferReveal: Bool = false,
        now: RuneInstant = .now()
    ) {
        self.window = window
        let size = window.innerSize()
        self.config = makeSurfaceConfig(
            size: size,
            transparent: options.transparent,
            srgb: srgb,
            displayLink: false
        )
        configureWindowSurface(&self.config, &self.surfaceMeter)
        self.visible = options.visible
        self.firstFrame = FirstFrame(deferred: deferReveal && options.visible, now: now)
        #if os(macOS)
        let warmLauncher = mac.launcher && !options.visible
        #else
        let warmLauncher = false
        #endif
        self.launchDrawables = LaunchDrawables(active: warmLauncher)
        if floatOnOpen && options.visible && !floatOnOpenFixed(options, mac) {
            self.floatingOnOpen = true
            window.setWindowLevel(WINDOW_LEVEL_ALWAYS_ON_TOP)
        }
        self.fileDrop.attach(window)
    }

    var isCovered: Bool {
        !visible || occluded || (window.isMinimized() == true)
    }

    func resize(_ newSize: (UInt32, UInt32)) {
        guard newSize.0 > 0 && newSize.1 > 0 else { return }
        window.setInnerSize(newSize)
        if config.width != newSize.0 || config.height != newSize.1 {
            config.width = newSize.0
            config.height = newSize.1
            configureWindowSurface(&config, &surfaceMeter)
            surfaceMeter.reconfigured()
            presented.invalidate()
        }
    }

    func setSrgbBlend(_ srgb: Bool) {
        guard config.srgb != srgb else { return }
        config.srgb = srgb
        configureWindowSurface(&config, &surfaceMeter)
        surfaceMeter.reconfigured()
        presented.invalidate()
    }

    func nextAcquireStatus() -> SurfaceAcquireStatus {
        if !simulatedAcquireStatuses.isEmpty {
            return simulatedAcquireStatuses.removeFirst()
        }
        return occluded ? .occluded : .good
    }

    func releaseGpu() {
        gpuReleased = true
        presented.invalidate()
        native.detach()
    }

    func ensureGpu() {
        if gpuReleased {
            gpuReleased = false
            configureWindowSurface(&config, &surfaceMeter)
            presented.invalidate()
        }
    }
}
