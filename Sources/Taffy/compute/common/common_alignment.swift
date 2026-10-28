// Ported from: src/compute/common/alignment.rs
// Upstream commit: 599b1b7d7410d97e13bafc4c01fbe6d7a9cf060a
// Port status: ported

/// Implement fallback alignment.
///
/// In addition to the spec at https://www.w3.org/TR/css-align-3/ this implementation follows
/// the resolution of https://github.com/w3c/csswg-drafts/issues/10154
@inlinable
public func applyAlignmentFallback(
    freeSpace: Float,
    numItems: Int,
    alignmentMode: AlignContent,
    isSafe: Bool
) -> AlignContent {
    var mode = alignmentMode
    var safe = isSafe

    // 1. If there is only a single item being aligned and alignment is a distributed alignment keyword
    if numItems <= 1 || freeSpace <= 0.0 {
        switch mode {
        case .stretch:
            mode = .flexStart
            safe = true
        case .spaceBetween:
            mode = .flexStart
            safe = true
        case .spaceAround:
            mode = .center
            safe = true
        case .spaceEvenly:
            mode = .center
            safe = true
        default:
            break
        }
    }

    // 2. If free space is negative the "safe" alignment variants all fallback to Start alignment
    if freeSpace <= 0.0 && safe {
        mode = .start
    }

    return mode
}

/// Generic alignment function that is used:
///   - For both align-content and justify-content alignment
///   - For both the Flexbox and CSS Grid algorithms
///
/// CSS Grid does not apply gaps as part of alignment, so the gap parameter should
/// always be set to zero for CSS Grid.
@inlinable
public func computeAlignmentOffset(
    freeSpace: Float,
    numItems: Int,
    gap: Float,
    alignmentMode: AlignContent,
    layoutIsFlexReversed: Bool,
    isFirst: Bool
) -> Float {
    if isFirst {
        switch alignmentMode {
        case .start:
            return 0.0
        case .flexStart:
            return layoutIsFlexReversed ? freeSpace : 0.0
        case .end:
            return freeSpace
        case .flexEnd:
            return layoutIsFlexReversed ? 0.0 : freeSpace
        case .center:
            return freeSpace / 2.0
        case .stretch:
            return 0.0
        case .spaceBetween:
            return 0.0
        case .spaceAround:
            if freeSpace >= 0.0 {
                return (freeSpace / Float(numItems)) / 2.0
            } else {
                return freeSpace / 2.0
            }
        case .spaceEvenly:
            if freeSpace >= 0.0 {
                return freeSpace / Float(numItems + 1)
            } else {
                return freeSpace / 2.0
            }
        }
    } else {
        let positiveFreeSpace = f32_max(freeSpace, 0.0)
        let alignmentOffset: Float
        switch alignmentMode {
        case .start, .flexStart, .end, .flexEnd, .center, .stretch:
            alignmentOffset = 0.0
        case .spaceBetween:
            alignmentOffset = positiveFreeSpace / Float(numItems - 1)
        case .spaceAround:
            alignmentOffset = positiveFreeSpace / Float(numItems)
        case .spaceEvenly:
            alignmentOffset = positiveFreeSpace / Float(numItems + 1)
        }
        return gap + alignmentOffset
    }
}
