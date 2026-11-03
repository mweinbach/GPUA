// Ported from: crates/rune/src/window/native.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Per-window native platform state (`crates/rune/src/window/native.rs`).

#if os(macOS)
import AppKit
#endif

/// Platform-specific per-window state (DisplayLink, appearance observer, full-screen watch, panel bridge, corner shape).
struct WindowNative {
    #if os(macOS)
    var displayLink: DisplayLink? = nil
    var fullScreenWatch: FullScreenWatch? = nil
    var trafficLightSpot: MacTrafficLightSpot? = nil
    var panelBridge: MacPanelBridge? = nil
    var panelActive: Bool = false
    #endif
    private(set) var hasDisplayLink: Bool = false

    init() {}

    mutating func detach() {
        #if os(macOS)
        displayLink?.stop()
        displayLink = nil
        fullScreenWatch = nil
        trafficLightSpot = nil
        panelBridge = nil
        panelActive = false
        #endif
        hasDisplayLink = false
    }

    mutating func setupMacOS(
        window: NativeWindow,
        chrome: Chrome,
        options: WindowOptions,
        mac: MacWindowOptions,
        onTick: @escaping @Sendable () -> Void
    ) {
        #if os(macOS)
        if let rawPtr = window.rawNSWindowPointer() {
            let addr = UInt(bitPattern: rawPtr)
            let spotOut: MacTrafficLightSpot? = MainActor.assumeIsolated {
                guard let ptr = UnsafeMutableRawPointer(bitPattern: addr) else { return nil }
                let nsWin = Unmanaged<NSWindow>.fromOpaque(ptr).takeUnretainedValue()
                applyMacWindowOptions(nsWin, options: options, mac: mac, chrome: chrome)
                return MacTrafficLightSpot(window: nsWin)
            }
            trafficLightSpot = spotOut
            fullScreenWatch = FullScreenWatch(rawWindowPtr: addr, chrome: chrome)
            displayLink = DisplayLink.new(displayId: nil, wake: onTick)
            hasDisplayLink = displayLink != nil
            panelActive = mac.nonactivatingPanelFlag
        }
        #else
        _ = window
        _ = chrome
        _ = options
        _ = mac
        _ = onTick
        #endif
    }

    mutating func setDisplayLinkPaused(_ paused: Bool) {
        #if os(macOS)
        if paused {
            displayLink?.stop()
        } else {
            _ = displayLink?.start()
        }
        #else
        _ = paused
        #endif
    }

    var isDisplayLinkRunning: Bool {
        #if os(macOS)
        return displayLink?.running() ?? false
        #else
        return false
        #endif
    }
}

#if os(macOS)
@MainActor
func applyMacWindowOptions(
    _ window: NSWindow,
    options: WindowOptions,
    mac: MacWindowOptions,
    chrome: Chrome
) {
    macConfigureWindow(window, mac)
    if mac.levelValue == nil && options.alwaysOnTop {
        window.level = .floating
    }
    if options.transparent && options.borderless {
        window.isOpaque = false
        window.backgroundColor = .clear
    }
    if let view = window.contentView {
        macApplyWindowCorners(
            view: view,
            cornerRadius: mac.cornerRadiusValue,
            cornerCurveCircular: mac.cornerCurveCircularFlag,
            transparent: options.transparent,
            borderless: options.borderless
        )
    }
    if chrome.fullSizeContent && !options.borderless {
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        if let spot = chrome.trafficLights {
            macPlaceTrafficLights(window: window, spot: spot)
        }
    }
    ownWindowDragging(window, enabled: usesDragRegions(chrome, options))
}
#endif
