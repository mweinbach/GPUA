// Ported from: src/compute/common/content_size.rs
// Upstream commit: 599b1b7d7410d97e13bafc4c01fbe6d7a9cf060a
// Port status: ported

/// Determine how much width/height a given node contributes to its parent's content size
@inlinable
public func computeContentSizeContribution(
    location: Point<Float>,
    size: Size<Float>,
    contentSize: Size<Float>,
    overflow: Point<Overflow>
) -> Size<Float> {
    let sizeContentSizeContribution = Size<Float>(
        width: overflow.x == .visible ? f32_max(size.width, contentSize.width) : size.width,
        height: overflow.y == .visible ? f32_max(size.height, contentSize.height) : size.height
    )
    if sizeContentSizeContribution.width > 0.0 && sizeContentSizeContribution.height > 0.0 {
        return Size<Float>(
            width: location.x + sizeContentSizeContribution.width,
            height: location.y + sizeContentSizeContribution.height
        )
    } else {
        return Size<Float>.ZERO
    }
}
