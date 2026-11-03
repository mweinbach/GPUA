// Ported from: crates/rune/src/window/platform_sync.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Syncs runtime cursor, IME cursor area, help tooltip, and drag regions to the native window (`crates/rune/src/window/platform_sync.rs`).

#if os(macOS)
import AppKit
#endif

extension Win {
    func applyCursor(_ cursor: Cursor) {
        guard currentCursor != cursor else { return }
        currentCursor = cursor
        window.setCursor(cursor)
        #if os(macOS)
        if let rawWin = window.rawNSWindowPointer(), Thread.isMainThread {
            let addr = UInt(bitPattern: rawWin)
            let viewAddr = window.rawNSViewPointer().map { UInt(bitPattern: $0) } ?? 0
            MainActor.assumeIsolated {
                guard let ptr = UnsafeMutableRawPointer(bitPattern: addr) else { return }
                let nsWin = Unmanaged<NSWindow>.fromOpaque(ptr).takeUnretainedValue()
                let nsView: NSView? = viewAddr != 0
                    ? Unmanaged<NSView>.fromOpaque(UnsafeMutableRawPointer(bitPattern: viewAddr)!).takeUnretainedValue()
                    : nsWin.contentView
                _ = macWindowCursor(window: nsWin, contentView: nsView, next: cursor)
            }
        }
        #endif
    }
}

func syncPlatform<S>(
    win: Win,
    rt: Runtime<S>,
    chrome: Chrome,
    options: WindowOptions,
    fullscreen: Bool = false
) {
    // 1. Titlebar inset
    #if os(macOS)
    let inset = macTitlebarInset(chrome: chrome, borderless: options.borderless, fullscreen: fullscreen)
    #else
    let inset: Float = 0.0
    #endif
    rt.hostSetTitlebarInset(inset)

    // 2. Cursor (when not click-through)
    if !options.clickThrough {
        win.applyCursor(rt.hostCursor())
    }

    // 3. Scoped drag regions
    if usesDragRegions(chrome, options) {
        win.dragRegions = scopeDragRegions(
            chrome: chrome,
            borderless: options.borderless,
            fullscreen: fullscreen,
            viewport: rt.viewport,
            regions: rt.hostDragRegions()
        )
    } else {
        win.dragRegions.removeAll(keepingCapacity: true)
    }

    // 4. Help tooltip regions on macOS
    #if os(macOS)
    if let rawView = win.window.rawNSViewPointer(), Thread.isMainThread {
        let addr = UInt(bitPattern: rawView)
        let scale = rt.env.scale
        let regions: [([Float], String)]
        if let (tip, rect) = rt.hostHelpTooltip(), rect.count == 4 {
            regions = [([rect[0], rect[1], rect[0] + rect[2], rect[1] + rect[3]], tip)]
        } else {
            regions = []
        }
        let currentHelp = win.macHelp
        let nextHelp: MacNativeHelp = MainActor.assumeIsolated {
            let h = currentHelp ?? MacNativeHelp()
            if let ptr = UnsafeMutableRawPointer(bitPattern: addr) {
                let nsView = Unmanaged<NSView>.fromOpaque(ptr).takeUnretainedValue()
                h.sync(contentView: nsView, scale: scale, regions: regions)
            }
            return h
        }
        win.macHelp = nextHelp
    }
    #endif

    // 5. IME allowed & cursor spot
    let hs = windowHostState(for: rt)
    if win.imeAllowed != hs.imeActive {
        win.imeAllowed = hs.imeActive
        win.window.setImeAllowed(hs.imeActive)
    }
    if let (pos, sz) = hs.imeSpot {
        let dp = (Double(pos.0), Double(pos.1))
        let ds = (Double(sz.0), Double(sz.1))
        if win.imeSpot?.0.0 != dp.0 || win.imeSpot?.0.1 != dp.1 || win.imeSpot?.1.0 != ds.0 || win.imeSpot?.1.1 != ds.1 {
            win.imeSpot = (dp, ds)
            win.window.setImeCursorArea(dp, ds)
        }
    }
}
