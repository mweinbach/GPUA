// Ported from: crates/rune/src/platform/macos/help.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! `El.help` as AppKit's own tooltips. Rects are snapped to device pixels and synced one by one:
//! only a region that moved or changed text is removed and added again, so scrolling a list
//! doesn't restart a still toolbar button's tooltip.

#if os(macOS)
import AppKit
import Foundation
#endif

/// `r` (window points, x0 y0 x1 y1) on the device pixel grid at `scale`.
func macHelpSnap(_ r: [Float], _ scale: Float) -> [Float] {
    guard scale > 0 else { return r }
    return r.map { ($0 * scale).rounded() / scale }
}

/// Which registered regions `have` stay (`true`) and which wanted regions `want` they already
/// cover (`true`); the rest of `have` is removed and the rest of `want` added.
func macHelpDiff(
    _ have: [([Float], String)],
    _ want: [([Float], String)]
) -> ([Bool], [Bool]) {
    var covered = [Bool](repeating: false, count: want.count)
    let stays: [Bool] = have.map { h in
        if let k = want.indices.first(where: { !covered[$0] && want[$0].0 == h.0 && want[$0].1 == h.1 }) {
            covered[k] = true
            return true
        }
        return false
    }
    return (stays, covered)
}

#if os(macOS)
@MainActor
final class MacNativeHelp {
    private struct Region {
        var rect: [Float]
        var text: String
        var tag: NSView.ToolTipTag
        /// AppKit doesn't retain tooltip owners: each lives here until its rect is removed.
        var owner: NSString
    }

    private var regions: [Region] = []
    private weak var view: NSView? = nil

    init() {}

    /// Registers `regions` (window points, x0 y0 x1 y1) with `contentView`, adding and
    /// removing only the ones that changed since the last sync. Main thread.
    func sync(contentView: NSView, scale: Float, regions nextRegions: [([Float], String)]) {
        let want: [([Float], String)] = nextRegions
            .map { (macHelpSnap($0.0, scale), $0.1) }
            .filter { $0.0.count >= 4 && $0.0[2] > $0.0[0] && $0.0[3] > $0.0[1] }
        let have: [([Float], String)] = self.regions.map { ($0.rect, $0.text) }
        let (stays, covered) = macHelpDiff(have, want)
        if view === contentView && stays.allSatisfy({ $0 }) && covered.allSatisfy({ $0 }) {
            return
        }
        if let prevView = view, prevView !== contentView {
            prevView.removeAllToolTips()
            self.regions.removeAll()
        }
        var kept: [Region] = []
        for (region, stay) in zip(self.regions, stays) {
            if stay && view === contentView {
                kept.append(region)
            } else {
                contentView.removeToolTip(region.tag)
            }
        }
        self.regions = kept
        for (k, (r, text)) in want.enumerated() {
            if covered[k] && view === contentView { continue }
            let owner = text as NSString
            let rect = NSRect(
                x: CGFloat(r[0]),
                y: CGFloat(r[1]),
                width: CGFloat(r[2] - r[0]),
                height: CGFloat(r[3] - r[1])
            )
            let tag = contentView.addToolTip(rect, owner: owner, userData: nil)
            self.regions.append(Region(rect: r, text: text, tag: tag, owner: owner))
        }
        self.view = contentView
    }

    func clear() {
        if let v = view {
            v.removeAllToolTips()
            view = nil
        }
        regions.removeAll()
    }

    deinit {
        if Thread.isMainThread {
            let v = view
            MainActor.assumeIsolated {
                v?.removeAllToolTips()
            }
        }
    }
}
#endif
