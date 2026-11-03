// Ported from: crates/rune/src/playground/region.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Which of the playground's three columns has the keyboard: the story list, the stage or the
//! side column. One at a time, and only it gets keys.

/// A column of the open playground, as the keyboard sees it.
enum PlaygroundRegion: Equatable, Sendable {
    case list
    case stage
    case side
}

extension PlaygroundLive {
    func region() -> PlaygroundRegion {
        currentRegion
    }

    /// Gives `region` the keyboard; true when that changed.
    func setRegion(_ next: PlaygroundRegion) -> Bool {
        let prev = currentRegion
        currentRegion = next
        return prev != next
    }

    /// The column at window point `x`, in a window `width` wide.
    func regionAt(_ x: Float, _ width: Float) -> PlaygroundRegion {
        let (sidebarW, sideW) = widths(width)
        if x < sidebarW + 1.0 {
            return .list
        } else if x >= width - sideW {
            return .side
        } else {
            return .stage
        }
    }

    /// Focus as the region last saw it, so a focus that only a hover moved is passed over
    /// rather than taken as a move: true when `focused` is new.
    func seeFocus(_ focused: String?) -> Bool {
        if regionSeen == focused {
            return false
        }
        regionSeen = focused
        return true
    }
}
