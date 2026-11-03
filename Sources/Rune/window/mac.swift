// Ported from: crates/rune/src/window/mac.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! macOS window chrome, drag regions, full-screen watch, and titlebar double-click (`crates/rune/src/window/mac.rs`).

#if !os(WASI)
import Foundation
#endif
#if os(macOS)
import AppKit
#endif

/// Height of the standard macOS titlebar band in points (`28.0`).
let MAC_TITLEBAR_HEIGHT: Float = 28.0

/// Returns `true` when Rune owns window drag regions rather than AppKit's background drag.
func usesDragRegions(_ chrome: Chrome, _ options: WindowOptions) -> Bool {
    chrome.dragRegions || (chrome.fullSizeContent && !options.borderless)
}

/// Computes the traffic-light `titlebarInset` for `Cx.titlebarInset()`.
func macTitlebarInset(chrome: Chrome, borderless: Bool, fullscreen: Bool) -> Float {
    if borderless || fullscreen {
        return 0.0
    }
    return chrome.titlebarInset()
}

/// Height of the top band where double-clicking zooms/minimizes the window on macOS.
func macNativeTitlebarBand(chrome: Chrome, borderless: Bool, fullscreen: Bool) -> Float {
    if borderless || fullscreen || !chrome.fullSizeContent {
        return 0.0
    }
    if let (_, y) = chrome.trafficLights {
        return max(MAC_TITLEBAR_HEIGHT, y + Chrome.TRAFFIC_LIGHT + 6.0)
    }
    return MAC_TITLEBAR_HEIGHT
}

/// Clips and scopes `El.windowDrag` rects against the viewport and traffic-light buttons.
func scopeDragRegions(
    chrome: Chrome,
    borderless: Bool,
    fullscreen: Bool,
    viewport: (Float, Float),
    regions: [[Float]]
) -> [[Float]] {
    let vw = max(viewport.0, 0.0)
    let vh = max(viewport.1, 0.0)
    guard vw > 0.0 && vh > 0.0 else { return [] }

    let exclusions: [[Float]]
    if !borderless && !fullscreen, let lights = chrome.trafficLightRects() {
        // Expand exclusion box around the 3 traffic lights slightly so clicks near buttons never start a window drag.
        let minX = max((lights.map { $0[0] }.min() ?? 0.0) - 4.0, 0.0)
        let minY = max((lights.map { $0[1] }.min() ?? 0.0) - 4.0, 0.0)
        let maxX = (lights.map { $0[0] + $0[2] }.max() ?? 0.0) + 4.0
        let maxY = (lights.map { $0[1] + $0[3] }.max() ?? 0.0) + 4.0
        exclusions = [[minX, minY, max(maxX - minX, 0.0), max(maxY - minY, 0.0)]]
    } else {
        exclusions = []
    }

    var clipped: [[Float]] = []
    for raw in regions where raw.count == 4 {
        let x0 = min(max(raw[0], 0.0), vw)
        let y0 = min(max(raw[1], 0.0), vh)
        let x1 = min(max(raw[0] + raw[2], 0.0), vw)
        let y1 = min(max(raw[1] + raw[3], 0.0), vh)
        guard x1 > x0 && y1 > y0 else { continue }
        var pieces = [[x0, y0, x1 - x0, y1 - y0]]
        for ex in exclusions {
            pieces = pieces.flatMap { subtractRect($0, ex) }
        }
        clipped.append(contentsOf: pieces)
    }
    return clipped
}

private func subtractRect(_ r: [Float], _ cut: [Float]) -> [[Float]] {
    let rx0 = r[0], ry0 = r[1], rx1 = r[0] + r[2], ry1 = r[1] + r[3]
    let cx0 = cut[0], cy0 = cut[1], cx1 = cut[0] + cut[2], cy1 = cut[1] + cut[3]

    let ix0 = max(rx0, cx0)
    let iy0 = max(ry0, cy0)
    let ix1 = min(rx1, cx1)
    let iy1 = min(ry1, cy1)
    if ix0 >= ix1 || iy0 >= iy1 {
        return [r]
    }
    var out: [[Float]] = []
    if iy0 > ry0 {
        out.append([rx0, ry0, rx1 - rx0, iy0 - ry0])
    }
    if iy1 < ry1 {
        out.append([rx0, iy1, rx1 - rx0, ry1 - iy1])
    }
    if ix0 > rx0 {
        out.append([rx0, iy0, ix0 - rx0, iy1 - iy0])
    }
    if ix1 < rx1 {
        out.append([ix1, iy0, rx1 - ix1, iy1 - iy0])
    }
    return out
}

func pointInDragRegions(_ x: Float, _ y: Float, regions: [[Float]]) -> Bool {
    for r in regions where r.count == 4 {
        if x >= r[0] && x <= r[0] + r[2] && y >= r[1] && y <= r[1] + r[3] {
            return true
        }
    }
    return false
}

func macDoubleClickInterval() -> Duration {
    #if os(macOS)
    let secs = MainActor.assumeIsolated { NSEvent.doubleClickInterval }
    let nanos = max(secs, 0.05) * 1_000_000_000.0
    return .nanoseconds(Int64(nanos.rounded()))
    #else
    return .milliseconds(500)
    #endif
}

/// Resolves macOS system double-click-on-titlebar preference (`AppleActionOnDoubleClick`).
func macSystemTitlebarAction(_ prefValue: String?) -> TitlebarAction {
    switch prefValue {
    case "Minimize":
        return .minimize
    case "None":
        return .none
    default:
        return .zoom
    }
}

func performTitlebarDoubleClick(action: TitlebarAction, window: NativeWindow) {
    switch action {
    case .none, .drag:
        break
    case .minimize:
        window.setMinimized(true)
        #if os(macOS)
        if let rawPtr = window.rawNSWindowPointer() {
            let addr = UInt(bitPattern: rawPtr)
            MainActor.assumeIsolated {
                guard let ptr = UnsafeMutableRawPointer(bitPattern: addr) else { return }
                let nsWin = Unmanaged<NSWindow>.fromOpaque(ptr).takeUnretainedValue()
                nsWin.performMiniaturize(nil)
            }
        }
        #endif
    case .zoom, .doubleClick:
        #if os(macOS)
        if let rawPtr = window.rawNSWindowPointer() {
            let addr = UInt(bitPattern: rawPtr)
            MainActor.assumeIsolated {
                guard let ptr = UnsafeMutableRawPointer(bitPattern: addr) else { return }
                let nsWin = Unmanaged<NSWindow>.fromOpaque(ptr).takeUnretainedValue()
                nsWin.zoom(nil)
            }
        }
        #endif
    }
}

#if os(macOS)
@MainActor
func ownWindowDragging(_ window: NSWindow, enabled: Bool) {
    if enabled {
        window.isMovableByWindowBackground = false
    }
}

/// Observes `NSWindow` full-screen transitions and repositions custom traffic lights on exit (`crates/rune/src/window/mac.rs`).
// PORT NOTE: Created and notified exclusively on the AppKit main thread (`queue: .main`), matching `FullScreenWatch` in `crates/rune/src/window/mac.rs`.
final class FullScreenWatch: @unchecked Sendable {
    private let rawWindowPtr: UInt
    private let chrome: Chrome
    private(set) var isFullscreen: Bool = false
    private var enterObserver: (any NSObjectProtocol)? = nil
    private var exitObserver: (any NSObjectProtocol)? = nil

    init(rawWindowPtr: UInt, chrome: Chrome) {
        self.rawWindowPtr = rawWindowPtr
        self.chrome = chrome
        guard rawWindowPtr != 0 else { return }
        let addr = rawWindowPtr
        let ch = chrome
        MainActor.assumeIsolated {
            guard let ptr = UnsafeMutableRawPointer(bitPattern: addr) else { return }
            let nsWin = Unmanaged<NSWindow>.fromOpaque(ptr).takeUnretainedValue()
            self.isFullscreen = nsWin.styleMask.contains(.fullScreen)
            let center = NotificationCenter.default
            self.enterObserver = center.addObserver(
                forName: NSWindow.didEnterFullScreenNotification,
                object: nsWin,
                queue: .main
            ) { [weak self] _ in
                self?.isFullscreen = true
            }
            self.exitObserver = center.addObserver(
                forName: NSWindow.didExitFullScreenNotification,
                object: nsWin,
                queue: .main
            ) { [weak self] _ in
                self?.isFullscreen = false
                MainActor.assumeIsolated {
                    guard let p = UnsafeMutableRawPointer(bitPattern: addr) else { return }
                    let w = Unmanaged<NSWindow>.fromOpaque(p).takeUnretainedValue()
                    if let spot = ch.trafficLights {
                        macPlaceTrafficLights(window: w, spot: spot)
                    }
                }
            }
        }
    }

    deinit {
        if let e1 = enterObserver {
            NotificationCenter.default.removeObserver(e1)
        }
        if let e2 = exitObserver {
            NotificationCenter.default.removeObserver(e2)
        }
    }
}
#endif
