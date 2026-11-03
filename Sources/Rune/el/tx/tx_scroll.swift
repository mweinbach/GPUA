// Ported from: crates/rune/src/el/tx/scroll.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! `Tx`'s scroll requests: revealing a row, moving a viewport to its end, a page or an
//! offset, and holding an element where it shows.

import RuneMotion

extension Tx {
    /// Reveal a keyed row, including a currently unrealized virtual row.
    public mutating func scrollIntoView(_ key: String) {
        scrollToRequests.append(ScrollReveal(key: key, center: false, animated: true))
        scrollRevealScopes.append(nil)
    }

    /// ``scrollIntoView(_:)`` for row `key` inside the element keyed `scope` only, so lists
    /// that key their rows alike don't reveal each other's rows.
    public mutating func scrollIntoViewIn(_ scope: String, _ key: String) {
        scrollToRequests.append(ScrollReveal(key: key, center: false, animated: true))
        scrollRevealScopes.append(scope)
    }

    /// Reveal and vertically centre a keyed element, virtual row or `TextHighlight`,
    /// gliding on the spring ``scrollTo(_:_:_:)`` uses.
    public mutating func scrollCenter(_ key: String) {
        scrollToRequests.append(ScrollReveal(key: key, center: true, animated: true))
        scrollRevealScopes.append(nil)
    }

    /// ``scrollCenter(_:)`` inside the element keyed `scope` only.
    public mutating func scrollCenterIn(_ scope: String, _ key: String) {
        scrollToRequests.append(ScrollReveal(key: key, center: true, animated: true))
        scrollRevealScopes.append(scope)
    }

    /// ``scrollCenter(_:)`` without the glide.
    public mutating func scrollCenterInstant(_ key: String) {
        scrollToRequests.append(ScrollReveal(key: key, center: true, animated: false))
        scrollRevealScopes.append(nil)
    }

    /// ``scrollCenterIn(_:_:)`` without the glide.
    public mutating func scrollCenterInInstant(_ scope: String, _ key: String) {
        scrollToRequests.append(ScrollReveal(key: key, center: true, animated: false))
        scrollRevealScopes.append(scope)
    }

    /// Glide the scroll viewport keyed `key` (or the one containing it) to its bottom.
    public mutating func scrollToBottom(_ key: String, animated: Bool = true) {
        scrollBottomRequests.append((key, animated))
    }

    /// ``scrollToBottom(_:animated:)`` without the glide.
    public mutating func scrollToBottomInstant(_ key: String) {
        scrollBottomRequests.append((key, false))
    }

    /// Page the scroll viewport keyed `key` (or the one containing it) by `pages` pages, down
    /// for positive, as Page Up and Page Down do.
    public mutating func scrollPage(_ key: String, _ pages: Int32) {
        scrollPagesRequests.append((key, pages))
    }

    /// Move the horizontal scroll viewport keyed `key` (or the nearest one containing it) so it
    /// shows its content from `x` points in, clamped to its ends. Instant; any momentum stops.
    public mutating func scrollToX(_ key: String, _ x: Float) {
        scrollOffsetRequests.append(ScrollRequest(key: key, x: x, y: nil, animated: false, spring: nil))
        scrollOffsetAnchors.append(false)
    }

    /// Move the vertical scroll viewport keyed `key` (or the nearest one containing it) so it
    /// shows its content from `y` points down, clamped to its ends. Instant; any momentum stops.
    public mutating func scrollToY(_ key: String, _ y: Float) {
        scrollOffsetRequests.append(ScrollRequest(key: key, x: nil, y: y, animated: false, spring: nil))
        scrollOffsetAnchors.append(false)
    }

    /// Spine compatibility helper scrolling vertically to `y`.
    public mutating func scrollTo(_ key: String, _ y: Float, animated: Bool = true) {
        let spring: Spring? = animated ? tok.motion.GLIDE : nil
        scrollOffsetRequests.append(ScrollRequest(key: key, x: nil, y: y, animated: animated, spring: spring))
        scrollOffsetAnchors.append(false)
    }

    /// Glide the scroll viewport keyed `key` (or the nearest one containing it) to show its
    /// content from `(x, y)` points in, on the spring ``scrollToBottom(_:animated:)`` uses.
    public mutating func scrollTo(_ key: String, _ x: Float, _ y: Float) {
        scrollOffsetRequests.append(ScrollRequest(key: key, x: x, y: y, animated: true, spring: tok.motion.GLIDE))
        scrollOffsetAnchors.append(false)
    }

    /// ``scrollTo(_:_:_:)`` on `spring` instead of the default glide.
    public mutating func scrollToWith(_ key: String, _ x: Float, _ y: Float, _ spring: Spring) {
        scrollOffsetRequests.append(ScrollRequest(key: key, x: x, y: y, animated: true, spring: spring))
        scrollOffsetAnchors.append(false)
    }

    /// ``scrollTo(_:_:_:)`` without the glide.
    public mutating func scrollToInstant(_ key: String, _ x: Float, _ y: Float) {
        scrollOffsetRequests.append(ScrollRequest(key: key, x: x, y: y, animated: false, spring: nil))
        scrollOffsetAnchors.append(false)
    }

    /// Move the vertical scroll viewport around the element or `TextHighlight` keyed `key` so its
    /// top sits `at` points below the viewport's top, clamped to the content's ends.
    public mutating func scrollKeyTo(_ key: String, _ at: Float) {
        scrollOffsetRequests.append(ScrollRequest(key: key, x: nil, y: at, animated: false, spring: nil))
        scrollOffsetAnchors.append(true)
    }

    /// Keep the element keyed `key` (or at that path) where it shows on screen across the
    /// commit this handler causes, by moving the nearest vertical scroll viewport around it.
    public mutating func keepOnScreen(_ key: String) {
        keepOnScreenKeys.append(key)
    }
}
