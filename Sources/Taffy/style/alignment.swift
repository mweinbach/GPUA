// Ported from: src/style/alignment.rs
// Upstream commit: 599b1b7d7410d97e13bafc4c01fbe6d7a9cf060a
// Port status: ported

/// Used to control how child nodes are aligned.
/// For Flexbox it controls alignment in the cross axis.
/// For Grid it controls alignment in the block axis.
///
/// [MDN](https://developer.mozilla.org/en-US/docs/Web/CSS/align-items)
public enum AlignItems: Sendable, Hashable {
    /// Items are packed toward the start of the axis
    case start
    /// Items are packed toward the end of the axis
    case end
    /// Items are packed towards the flex-relative start of the axis.
    case flexStart
    /// Items are packed towards the flex-relative end of the axis.
    case flexEnd
    /// Items are packed along the center of the cross axis
    case center
    /// Items are aligned such as their baselines align
    case baseline
    /// Stretch to fill the container
    case stretch
}

/// Used to control how child nodes are aligned.
/// Does not apply to Flexbox, and will be ignored if specified on a flex container.
/// For Grid it controls alignment in the inline axis.
///
/// [MDN](https://developer.mozilla.org/en-US/docs/Web/CSS/justify-items)
public typealias JustifyItems = AlignItems

/// Controls alignment of an individual node.
///
/// Overrides the parent Node's `AlignItems` property.
/// For Flexbox it controls alignment in the cross axis.
/// For Grid it controls alignment in the block axis.
///
/// [MDN](https://developer.mozilla.org/en-US/docs/Web/CSS/align-self)
public typealias AlignSelf = AlignItems

/// Controls alignment of an individual node.
///
/// Overrides the parent Node's `JustifyItems` property.
/// Does not apply to Flexbox, and will be ignored if specified on a flex child.
/// For Grid it controls alignment in the inline axis.
///
/// [MDN](https://developer.mozilla.org/en-US/docs/Web/CSS/justify-self)
public typealias JustifySelf = AlignItems

/// Sets the distribution of space between and around content items.
/// For Flexbox it controls alignment in the cross axis.
/// For Grid it controls alignment in the block axis.
///
/// [MDN](https://developer.mozilla.org/en-US/docs/Web/CSS/align-content)
public enum AlignContent: Sendable, Hashable {
    /// Items are packed toward the start of the axis
    case start
    /// Items are packed toward the end of the axis
    case end
    /// Items are packed towards the flex-relative start of the axis.
    case flexStart
    /// Items are packed towards the flex-relative end of the axis.
    case flexEnd
    /// Items are centered around the middle of the axis
    case center
    /// Items are stretched to fill the container
    case stretch
    /// The first and last items are aligned flush with the edges of the container (no gap)
    case spaceBetween
    /// The gap between the first and last items is exactly THE SAME as the gap between items.
    case spaceEvenly
    /// The gap between the first and last items is exactly HALF the gap between items.
    case spaceAround
}

/// Sets the distribution of space between and around content items.
/// For Flexbox it controls alignment in the main axis.
/// For Grid it controls alignment in the inline axis.
///
/// [MDN](https://developer.mozilla.org/en-US/docs/Web/CSS/justify-content)
public typealias JustifyContent = AlignContent
