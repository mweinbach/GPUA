// Ported from: crates/gpui/src/styled.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Foundation

public let ELLIPSIS: SharedString = SharedString("…")

// Styled protocol is defined in style.swift and extended here with Tailwind-style modifiers.

// MARK: - Core Style Helpers

extension Styled {
    /// Mutates the element's style using a closure and returns the modified element.
    @inlinable
    public func withStyle(_ modify: (inout StyleRefinement) -> Void) -> Self {
        var copy = self
        modify(&copy.style)
        return copy
    }

    /// Mutates the element's text style using a closure and returns the modified element.
    @inlinable
    public func withTextStyle(_ modify: (inout TextStyleRefinement) -> Void) -> Self {
        var copy = self
        modify(&copy.style.text)
        return copy
    }

    // MARK: - Display & Visibility

    /// Sets the display type of the element to `block`.
    public func block() -> Self {
        withStyle { $0.display = .block }
    }

    /// Sets the display type of the element to `flex`.
    public func flex() -> Self {
        withStyle { $0.display = .flex }
    }

    /// Sets the display type of the element to `grid`.
    public func grid() -> Self {
        withStyle { $0.display = .grid }
    }

    /// Sets the display type of the element to `none` (hidden).
    public func hidden() -> Self {
        withStyle { $0.display = Display.none }
    }

    /// Sets the visibility of the element to `visible`.
    public func visible() -> Self {
        withStyle { $0.visibility = .visible }
    }

    /// Sets the visibility of the element to `hidden`.
    public func invisible() -> Self {
        withStyle { $0.visibility = .hidden }
    }

    // MARK: - Positioning

    /// Sets the position of the element to `relative`.
    public func relative() -> Self {
        withStyle { $0.position = .relative }
    }

    /// Sets the position of the element to `absolute`.
    public func absolute() -> Self {
        withStyle { $0.position = .absolute }
    }

    /// Sets all four insets (top, bottom, left, right).
    public func inset(_ length: Length) -> Self {
        withStyle {
            $0.inset.top = length
            $0.inset.bottom = length
            $0.inset.left = length
            $0.inset.right = length
        }
    }

    /// Sets horizontal insets (left, right).
    public func insetX(_ length: Length) -> Self {
        withStyle {
            $0.inset.left = length
            $0.inset.right = length
        }
    }

    /// Sets vertical insets (top, bottom).
    public func insetY(_ length: Length) -> Self {
        withStyle {
            $0.inset.top = length
            $0.inset.bottom = length
        }
    }

    /// Sets top inset.
    public func top(_ length: Length) -> Self {
        withStyle { $0.inset.top = length }
    }

    /// Sets bottom inset.
    public func bottom(_ length: Length) -> Self {
        withStyle { $0.inset.bottom = length }
    }

    /// Sets left inset.
    public func left(_ length: Length) -> Self {
        withStyle { $0.inset.left = length }
    }

    /// Sets right inset.
    public func right(_ length: Length) -> Self {
        withStyle { $0.inset.right = length }
    }

    public func inset0() -> Self { inset(.definite(.pixels(.zero))) }
    public func top0() -> Self { top(.definite(.pixels(.zero))) }
    public func bottom0() -> Self { bottom(.definite(.pixels(.zero))) }
    public func left0() -> Self { left(.definite(.pixels(.zero))) }
    public func right0() -> Self { right(.definite(.pixels(.zero))) }
    public func insetAuto() -> Self { inset(.auto) }
    public func topAuto() -> Self { top(.auto) }
    public func bottomAuto() -> Self { bottom(.auto) }
    public func leftAuto() -> Self { left(.auto) }
    public func rightAuto() -> Self { right(.auto) }

    // MARK: - Overflow

    /// Sets overflow on both axes to hidden.
    public func overflowHidden() -> Self {
        withStyle {
            $0.overflow.x = .hidden
            $0.overflow.y = .hidden
        }
    }

    /// Sets overflow on the X axis to hidden.
    public func overflowXHidden() -> Self {
        withStyle { $0.overflow.x = .hidden }
    }

    /// Sets overflow on the Y axis to hidden.
    public func overflowYHidden() -> Self {
        withStyle { $0.overflow.y = .hidden }
    }

    /// Sets overflow on both axes to scroll.
    public func overflowScroll() -> Self {
        withStyle {
            $0.overflow.x = .scroll
            $0.overflow.y = .scroll
        }
    }

    /// Sets overflow on the X axis to scroll.
    public func overflowXScroll() -> Self {
        withStyle { $0.overflow.x = .scroll }
    }

    /// Sets overflow on the Y axis to scroll.
    public func overflowYScroll() -> Self {
        withStyle { $0.overflow.y = .scroll }
    }

    // MARK: - Text & Typography

    public func whitespaceNormal() -> Self {
        withTextStyle { $0.whiteSpace = .normal }
    }

    public func whitespaceNowrap() -> Self {
        withTextStyle { $0.whiteSpace = .nowrap }
    }

    public func textEllipsis() -> Self {
        withTextStyle { $0.textOverflow = .truncate(ELLIPSIS) }
    }

    public func textEllipsisStart() -> Self {
        withTextStyle { $0.textOverflow = .truncateStart(ELLIPSIS) }
    }

    public func textOverflow(_ overflow: TextOverflow) -> Self {
        withTextStyle { $0.textOverflow = overflow }
    }

    public func textAlign(_ align: TextAlign) -> Self {
        withTextStyle { $0.textAlign = align }
    }

    public func textLeft() -> Self { textAlign(.left) }
    public func textCenter() -> Self { textAlign(.center) }
    public func textRight() -> Self { textAlign(.right) }

    public func truncate() -> Self {
        self.overflowHidden().whitespaceNowrap().textEllipsis()
    }

    public func lineClamp(_ lines: Int) -> Self {
        self.withTextStyle { $0.lineClamp = lines }.overflowHidden()
    }

    public func textColor(_ color: Hsla) -> Self {
        withTextStyle { $0.color = color }
    }

    public func fontWeight(_ weight: FontWeight) -> Self {
        withTextStyle { $0.fontWeight = weight }
    }

    public func textBg(_ bg: Hsla) -> Self {
        withTextStyle { $0.backgroundColor = bg }
    }

    public func textSize(_ size: AbsoluteLength) -> Self {
        withTextStyle { $0.fontSize = size }
    }

    public func textXs() -> Self { textSize(.rems(GPUI.rems(0.75))) }
    public func textSm() -> Self { textSize(.rems(GPUI.rems(0.875))) }
    public func textBase() -> Self { textSize(.rems(GPUI.rems(1.0))) }
    public func textLg() -> Self { textSize(.rems(GPUI.rems(1.125))) }
    public func textXl() -> Self { textSize(.rems(GPUI.rems(1.25))) }
    public func text2xl() -> Self { textSize(.rems(GPUI.rems(1.5))) }
    public func text3xl() -> Self { textSize(.rems(GPUI.rems(1.875))) }

    public func italic() -> Self {
        withTextStyle { $0.fontStyle = .italic }
    }

    public func notItalic() -> Self {
        withTextStyle { $0.fontStyle = .normal }
    }

    public func underline() -> Self {
        withTextStyle {
            $0.underline = UnderlineStyle(
                thickness: GPUI.px(1.0),
                color: nil,
                wavy: false
            )
        }
    }

    public func lineThrough() -> Self {
        withTextStyle {
            $0.strikethrough = StrikethroughStyle(
                thickness: GPUI.px(1.0),
                color: nil
            )
        }
    }

    public func textDecorationNone() -> Self {
        withTextStyle {
            $0.underline = nil
            $0.strikethrough = nil
        }
    }

    public func textDecorationColor(_ color: Hsla) -> Self {
        withTextStyle {
            if $0.underline != nil {
                $0.underline?.color = color
            } else {
                $0.underline = UnderlineStyle(thickness: GPUI.px(1.0), color: color, wavy: false)
            }
        }
    }

    public func textDecorationSolid() -> Self {
        withTextStyle {
            $0.underline?.wavy = false
        }
    }

    public func textDecorationWavy() -> Self {
        withTextStyle {
            $0.underline?.wavy = true
        }
    }

    public func textDecoration0() -> Self {
        withTextStyle { $0.underline?.thickness = GPUI.px(0.0) }
    }

    public func textDecoration1() -> Self {
        withTextStyle { $0.underline?.thickness = GPUI.px(1.0) }
    }

    public func textDecoration2() -> Self {
        withTextStyle { $0.underline?.thickness = GPUI.px(2.0) }
    }

    public func textDecoration4() -> Self {
        withTextStyle { $0.underline?.thickness = GPUI.px(4.0) }
    }

    public func textDecoration8() -> Self {
        withTextStyle { $0.underline?.thickness = GPUI.px(8.0) }
    }

    public func fontFamily(_ familyName: SharedString) -> Self {
        withTextStyle { $0.fontFamily = familyName }
    }

    public func fontFeatures(_ features: FontFeatures) -> Self {
        withTextStyle { $0.fontFeatures = features }
    }

    public func font(_ font: Font) -> Self {
        withTextStyle {
            $0.fontFamily = font.family
            $0.fontFeatures = font.features
            $0.fontWeight = font.weight
            $0.fontStyle = font.style
            $0.fontFallbacks = font.fallbacks
        }
    }

    public func lineHeight(_ lineHeight: DefiniteLength) -> Self {
        withTextStyle { $0.lineHeight = lineHeight }
    }

    // MARK: - Flexbox

    public func flexCol() -> Self {
        withStyle { $0.flexDirection = .column }
    }

    public func flexColReverse() -> Self {
        withStyle { $0.flexDirection = .columnReverse }
    }

    public func flexRow() -> Self {
        withStyle { $0.flexDirection = .row }
    }

    public func flexRowReverse() -> Self {
        withStyle { $0.flexDirection = .rowReverse }
    }

    public func flex1() -> Self {
        withStyle {
            $0.flexGrow = 1.0
            $0.flexShrink = 1.0
            $0.flexBasis = .definite(GPUI.relative(0.0))
        }
    }

    public func flexAuto() -> Self {
        withStyle {
            $0.flexGrow = 1.0
            $0.flexShrink = 1.0
            $0.flexBasis = .auto
        }
    }

    public func flexInitial() -> Self {
        withStyle {
            $0.flexGrow = 0.0
            $0.flexShrink = 1.0
            $0.flexBasis = .auto
        }
    }

    public func flexNone() -> Self {
        withStyle {
            $0.flexGrow = 0.0
            $0.flexShrink = 0.0
        }
    }

    public func flexBasis(_ basis: Length) -> Self {
        withStyle { $0.flexBasis = basis }
    }

    public func flexGrow(_ grow: Float = 1.0) -> Self {
        withStyle { $0.flexGrow = grow }
    }

    public func flexShrink(_ shrink: Float = 1.0) -> Self {
        withStyle { $0.flexShrink = shrink }
    }

    public func flexShrink0() -> Self {
        withStyle { $0.flexShrink = 0.0 }
    }

    public func flexWrap() -> Self {
        withStyle { $0.flexWrap = .wrap }
    }

    public func flexWrapReverse() -> Self {
        withStyle { $0.flexWrap = .wrapReverse }
    }

    public func flexNowrap() -> Self {
        withStyle { $0.flexWrap = .noWrap }
    }

    public func itemsStart() -> Self {
        withStyle { $0.alignItems = .flexStart }
    }

    public func itemsEnd() -> Self {
        withStyle { $0.alignItems = .flexEnd }
    }

    public func itemsCenter() -> Self {
        withStyle { $0.alignItems = .center }
    }

    public func itemsBaseline() -> Self {
        withStyle { $0.alignItems = .baseline }
    }

    public func itemsStretch() -> Self {
        withStyle { $0.alignItems = .stretch }
    }

    public func selfStart() -> Self {
        withStyle { $0.alignSelf = .start }
    }

    public func selfEnd() -> Self {
        withStyle { $0.alignSelf = .end }
    }

    public func selfFlexStart() -> Self {
        withStyle { $0.alignSelf = .flexStart }
    }

    public func selfFlexEnd() -> Self {
        withStyle { $0.alignSelf = .flexEnd }
    }

    public func selfCenter() -> Self {
        withStyle { $0.alignSelf = .center }
    }

    public func selfBaseline() -> Self {
        withStyle { $0.alignSelf = .baseline }
    }

    public func selfStretch() -> Self {
        withStyle { $0.alignSelf = .stretch }
    }

    public func justifyStart() -> Self {
        withStyle { $0.justifyContent = .start }
    }

    public func justifyEnd() -> Self {
        withStyle { $0.justifyContent = .end }
    }

    public func justifyCenter() -> Self {
        withStyle { $0.justifyContent = .center }
    }

    public func justifyBetween() -> Self {
        withStyle { $0.justifyContent = .spaceBetween }
    }

    public func justifyAround() -> Self {
        withStyle { $0.justifyContent = .spaceAround }
    }

    public func justifyEvenly() -> Self {
        withStyle { $0.justifyContent = .spaceEvenly }
    }

    public func contentNormal() -> Self {
        withStyle { $0.alignContent = nil }
    }

    public func contentCenter() -> Self {
        withStyle { $0.alignContent = .center }
    }

    public func contentStart() -> Self {
        withStyle { $0.alignContent = .flexStart }
    }

    public func contentEnd() -> Self {
        withStyle { $0.alignContent = .flexEnd }
    }

    public func contentBetween() -> Self {
        withStyle { $0.alignContent = .spaceBetween }
    }

    public func contentAround() -> Self {
        withStyle { $0.alignContent = .spaceAround }
    }

    public func contentEvenly() -> Self {
        withStyle { $0.alignContent = .spaceEvenly }
    }

    public func contentStretch() -> Self {
        withStyle { $0.alignContent = .stretch }
    }

    public func aspectRatio(_ ratio: Float) -> Self {
        withStyle { $0.aspectRatio = ratio }
    }

    public func aspectSquare() -> Self {
        withStyle { $0.aspectRatio = 1.0 }
    }

    // MARK: - Width, Height & Size

    public func w(_ length: Length) -> Self {
        withStyle { $0.size.width = length }
    }

    public func w(_ px: Pixels) -> Self {
        w(Length(px))
    }

    public func h(_ length: Length) -> Self {
        withStyle { $0.size.height = length }
    }

    public func h(_ px: Pixels) -> Self {
        h(Length(px))
    }

    public func size(_ length: Length) -> Self {
        withStyle {
            $0.size.width = length
            $0.size.height = length
        }
    }

    public func size(_ px: Pixels) -> Self {
        size(Length(px))
    }

    public func minW(_ length: Length) -> Self {
        withStyle { $0.minSize.width = length }
    }

    public func maxW(_ length: Length) -> Self {
        withStyle { $0.maxSize.width = length }
    }

    public func minH(_ length: Length) -> Self {
        withStyle { $0.minSize.height = length }
    }

    public func maxH(_ length: Length) -> Self {
        withStyle { $0.maxSize.height = length }
    }

    public func wFull() -> Self { w(.definite(GPUI.relative(1.0))) }
    public func wAuto() -> Self { w(.auto) }
    public func wHalf() -> Self { w(.definite(GPUI.relative(0.5))) }

    public func hFull() -> Self { h(.definite(GPUI.relative(1.0))) }
    public func hAuto() -> Self { h(.auto) }
    public func hHalf() -> Self { h(.definite(GPUI.relative(0.5))) }

    public func sizeFull() -> Self { size(.definite(GPUI.relative(1.0))) }
    public func sizeAuto() -> Self { size(.auto) }
    public func sizeHalf() -> Self { size(.definite(GPUI.relative(0.5))) }

    // MARK: - Margins

    public func m(_ length: Length) -> Self {
        withStyle {
            $0.margin.top = length
            $0.margin.bottom = length
            $0.margin.left = length
            $0.margin.right = length
        }
    }

    public func mt(_ length: Length) -> Self { withStyle { $0.margin.top = length } }
    public func mb(_ length: Length) -> Self { withStyle { $0.margin.bottom = length } }
    public func ml(_ length: Length) -> Self { withStyle { $0.margin.left = length } }
    public func mr(_ length: Length) -> Self { withStyle { $0.margin.right = length } }

    public func mx(_ length: Length) -> Self {
        withStyle {
            $0.margin.left = length
            $0.margin.right = length
        }
    }

    public func my(_ length: Length) -> Self {
        withStyle {
            $0.margin.top = length
            $0.margin.bottom = length
        }
    }

    public func mAuto() -> Self { m(.auto) }
    public func mxAuto() -> Self { mx(.auto) }
    public func myAuto() -> Self { my(.auto) }

    // MARK: - Padding

    public func p(_ length: DefiniteLength) -> Self {
        withStyle {
            $0.padding.top = length
            $0.padding.bottom = length
            $0.padding.left = length
            $0.padding.right = length
        }
    }

    public func p(_ px: Pixels) -> Self {
        p(DefiniteLength(px))
    }

    public func pt(_ length: DefiniteLength) -> Self { withStyle { $0.padding.top = length } }
    public func pb(_ length: DefiniteLength) -> Self { withStyle { $0.padding.bottom = length } }
    public func pl(_ length: DefiniteLength) -> Self { withStyle { $0.padding.left = length } }
    public func pr(_ length: DefiniteLength) -> Self { withStyle { $0.padding.right = length } }

    public func px(_ length: DefiniteLength) -> Self {
        withStyle {
            $0.padding.left = length
            $0.padding.right = length
        }
    }

    public func py(_ length: DefiniteLength) -> Self {
        withStyle {
            $0.padding.top = length
            $0.padding.bottom = length
        }
    }

    // MARK: - Gap

    public func gap(_ length: DefiniteLength) -> Self {
        withStyle {
            $0.gap.width = length
            $0.gap.height = length
        }
    }

    public func gapX(_ length: DefiniteLength) -> Self {
        withStyle { $0.gap.width = length }
    }

    public func gapY(_ length: DefiniteLength) -> Self {
        withStyle { $0.gap.height = length }
    }

    // MARK: - Border

    public func border(_ width: AbsoluteLength) -> Self {
        withStyle {
            $0.borderWidths.top = width
            $0.borderWidths.bottom = width
            $0.borderWidths.left = width
            $0.borderWidths.right = width
        }
    }

    public func borderT(_ width: AbsoluteLength) -> Self { withStyle { $0.borderWidths.top = width } }
    public func borderB(_ width: AbsoluteLength) -> Self { withStyle { $0.borderWidths.bottom = width } }
    public func borderL(_ width: AbsoluteLength) -> Self { withStyle { $0.borderWidths.left = width } }
    public func borderR(_ width: AbsoluteLength) -> Self { withStyle { $0.borderWidths.right = width } }

    public func borderX(_ width: AbsoluteLength) -> Self {
        withStyle {
            $0.borderWidths.left = width
            $0.borderWidths.right = width
        }
    }

    public func borderY(_ width: AbsoluteLength) -> Self {
        withStyle {
            $0.borderWidths.top = width
            $0.borderWidths.bottom = width
        }
    }

    public func border0() -> Self { border(.pixels(GPUI.px(0.0))) }
    public func border1() -> Self { border(.pixels(GPUI.px(1.0))) }
    public func border2() -> Self { border(.pixels(GPUI.px(2.0))) }
    public func border4() -> Self { border(.pixels(GPUI.px(4.0))) }
    public func border8() -> Self { border(.pixels(GPUI.px(8.0))) }

    public func borderColor(_ color: Hsla) -> Self {
        withStyle { $0.borderColor = color }
    }

    public func borderDashed() -> Self {
        withStyle { $0.borderStyle = .dashed }
    }

    // MARK: - Rounded Corners

    public func rounded(_ radius: AbsoluteLength) -> Self {
        withStyle {
            $0.cornerRadii.topLeft = radius
            $0.cornerRadii.topRight = radius
            $0.cornerRadii.bottomLeft = radius
            $0.cornerRadii.bottomRight = radius
        }
    }

    public func roundedT(_ radius: AbsoluteLength) -> Self {
        withStyle {
            $0.cornerRadii.topLeft = radius
            $0.cornerRadii.topRight = radius
        }
    }

    public func roundedB(_ radius: AbsoluteLength) -> Self {
        withStyle {
            $0.cornerRadii.bottomLeft = radius
            $0.cornerRadii.bottomRight = radius
        }
    }

    public func roundedL(_ radius: AbsoluteLength) -> Self {
        withStyle {
            $0.cornerRadii.topLeft = radius
            $0.cornerRadii.bottomLeft = radius
        }
    }

    public func roundedR(_ radius: AbsoluteLength) -> Self {
        withStyle {
            $0.cornerRadii.topRight = radius
            $0.cornerRadii.bottomRight = radius
        }
    }

    public func roundedTl(_ radius: AbsoluteLength) -> Self { withStyle { $0.cornerRadii.topLeft = radius } }
    public func roundedTr(_ radius: AbsoluteLength) -> Self { withStyle { $0.cornerRadii.topRight = radius } }
    public func roundedBl(_ radius: AbsoluteLength) -> Self { withStyle { $0.cornerRadii.bottomLeft = radius } }
    public func roundedBr(_ radius: AbsoluteLength) -> Self { withStyle { $0.cornerRadii.bottomRight = radius } }

    public func roundedNone() -> Self { rounded(.pixels(GPUI.px(0.0))) }
    public func roundedXs() -> Self { rounded(.rems(GPUI.rems(0.125))) }
    public func roundedSm() -> Self { rounded(.rems(GPUI.rems(0.125))) }
    public func roundedMd() -> Self { rounded(.rems(GPUI.rems(0.375))) }
    public func roundedLg() -> Self { rounded(.rems(GPUI.rems(0.5))) }
    public func roundedXl() -> Self { rounded(.rems(GPUI.rems(0.75))) }
    public func rounded2xl() -> Self { rounded(.rems(GPUI.rems(1.0))) }
    public func rounded3xl() -> Self { rounded(.rems(GPUI.rems(1.5))) }
    public func roundedFull() -> Self { rounded(.pixels(GPUI.px(9999.0))) }

    // MARK: - Background, Shadow & Opacity

    public func bg(_ fill: Fill) -> Self {
        withStyle { $0.background = fill }
    }

    public func bg(_ color: Hsla) -> Self {
        withStyle { $0.background = Fill(color) }
    }

    public func shadow(_ shadows: [BoxShadow]) -> Self {
        withStyle { $0.boxShadow = shadows }
    }

    public func shadowSm() -> Self {
        shadow([
            BoxShadow(
                color: hsla(0.0, 0.0, 0.0, 0.05),
                offset: point(GPUI.px(0.0), GPUI.px(1.0)),
                blurRadius: GPUI.px(2.0),
                spreadRadius: GPUI.px(0.0)
            )
        ])
    }

    public func shadowMd() -> Self {
        shadow([
            BoxShadow(
                color: hsla(0.0, 0.0, 0.0, 0.1),
                offset: point(GPUI.px(0.0), GPUI.px(4.0)),
                blurRadius: GPUI.px(6.0),
                spreadRadius: GPUI.px(-1.0)
            ),
            BoxShadow(
                color: hsla(0.0, 0.0, 0.0, 0.06),
                offset: point(GPUI.px(0.0), GPUI.px(2.0)),
                blurRadius: GPUI.px(4.0),
                spreadRadius: GPUI.px(-1.0)
            )
        ])
    }

    public func shadowLg() -> Self {
        shadow([
            BoxShadow(
                color: hsla(0.0, 0.0, 0.0, 0.1),
                offset: point(GPUI.px(0.0), GPUI.px(10.0)),
                blurRadius: GPUI.px(15.0),
                spreadRadius: GPUI.px(-3.0)
            ),
            BoxShadow(
                color: hsla(0.0, 0.0, 0.0, 0.05),
                offset: point(GPUI.px(0.0), GPUI.px(4.0)),
                blurRadius: GPUI.px(6.0),
                spreadRadius: GPUI.px(-2.0)
            )
        ])
    }

    public func shadowXl() -> Self {
        shadow([
            BoxShadow(
                color: hsla(0.0, 0.0, 0.0, 0.1),
                offset: point(GPUI.px(0.0), GPUI.px(20.0)),
                blurRadius: GPUI.px(25.0),
                spreadRadius: GPUI.px(-5.0)
            ),
            BoxShadow(
                color: hsla(0.0, 0.0, 0.0, 0.04),
                offset: point(GPUI.px(0.0), GPUI.px(10.0)),
                blurRadius: GPUI.px(10.0),
                spreadRadius: GPUI.px(-5.0)
            )
        ])
    }

    public func shadow2xl() -> Self {
        shadow([
            BoxShadow(
                color: hsla(0.0, 0.0, 0.0, 0.25),
                offset: point(GPUI.px(0.0), GPUI.px(25.0)),
                blurRadius: GPUI.px(50.0),
                spreadRadius: GPUI.px(-12.0)
            )
        ])
    }

    public func shadowNone() -> Self {
        shadow([])
    }

    public func opacity(_ opacity: Float) -> Self {
        withStyle { $0.opacity = opacity }
    }

    // MARK: - Cursor

    public func cursor(_ cursor: CursorStyle) -> Self {
        withStyle { $0.mouseCursor = cursor }
    }

    public func cursorDefault() -> Self { cursor(.arrow) }
    public func cursorPointer() -> Self { cursor(.pointingHand) }
    public func cursorText() -> Self { cursor(.iBeam) }
    public func cursorMove() -> Self { cursor(.closedHand) }
    public func cursorNotAllowed() -> Self { cursor(.notAllowed) }
    public func cursorContextMenu() -> Self { cursor(.arrow) }
    public func cursorCrosshair() -> Self { cursor(.crosshair) }
    public func cursorGrab() -> Self { cursor(.openHand) }
    public func cursorGrabbing() -> Self { cursor(.closedHand) }
    public func cursorEwResize() -> Self { cursor(.resizeLeftRight) }
    public func cursorNsResize() -> Self { cursor(.resizeUpDown) }
    public func cursorColResize() -> Self { cursor(.resizeLeftRight) }
    public func cursorRowResize() -> Self { cursor(.resizeUpDown) }

    // MARK: - Grid

    public func gridCols(_ cols: UInt16) -> Self {
        withStyle {
            $0.gridCols = GridTemplate(repeat: cols, minSize: .zero)
        }
    }

    public func gridColsMinContent(_ cols: UInt16) -> Self {
        withStyle {
            $0.gridCols = GridTemplate(repeat: cols, minSize: .minContent)
        }
    }

    public func gridColsMaxContent(_ cols: UInt16) -> Self {
        withStyle {
            $0.gridCols = GridTemplate(repeat: cols, minSize: .maxContent)
        }
    }

    public func gridRows(_ rows: UInt16) -> Self {
        withStyle {
            $0.gridRows = GridTemplate(repeat: rows, minSize: .zero)
        }
    }

    public func colStart(_ start: Int16) -> Self {
        withStyle {
            var loc = $0.gridLocationMut()
            loc.column = Int(start)..<loc.column.upperBound
            $0.gridLocation = loc
        }
    }

    public func colEnd(_ end: Int16) -> Self {
        withStyle {
            var loc = $0.gridLocationMut()
            loc.column = loc.column.lowerBound..<Int(end)
            $0.gridLocation = loc
        }
    }

    public func rowStart(_ start: Int16) -> Self {
        withStyle {
            var loc = $0.gridLocationMut()
            loc.row = Int(start)..<loc.row.upperBound
            $0.gridLocation = loc
        }
    }

    public func rowEnd(_ end: Int16) -> Self {
        withStyle {
            var loc = $0.gridLocationMut()
            loc.row = loc.row.lowerBound..<Int(end)
            $0.gridLocation = loc
        }
    }

    // MARK: - Tailwind Numeric Scales (0, 1, 2, 3, 4, 5, 6, 8, 10, 12, 16, 20, 24, 32, 40, 48, 56, 64, 72, 80, 96)

    public func w0() -> Self { w(.definite(.pixels(GPUI.px(0.0)))) }
    public func w1() -> Self { w(.definite(.rems(GPUI.rems(0.25)))) }
    public func w2() -> Self { w(.definite(.rems(GPUI.rems(0.5)))) }
    public func w3() -> Self { w(.definite(.rems(GPUI.rems(0.75)))) }
    public func w4() -> Self { w(.definite(.rems(GPUI.rems(1.0)))) }
    public func w5() -> Self { w(.definite(.rems(GPUI.rems(1.25)))) }
    public func w6() -> Self { w(.definite(.rems(GPUI.rems(1.5)))) }
    public func w8() -> Self { w(.definite(.rems(GPUI.rems(2.0)))) }
    public func w10() -> Self { w(.definite(.rems(GPUI.rems(2.5)))) }
    public func w12() -> Self { w(.definite(.rems(GPUI.rems(3.0)))) }
    public func w16() -> Self { w(.definite(.rems(GPUI.rems(4.0)))) }
    public func w20() -> Self { w(.definite(.rems(GPUI.rems(5.0)))) }
    public func w24() -> Self { w(.definite(.rems(GPUI.rems(6.0)))) }
    public func w32() -> Self { w(.definite(.rems(GPUI.rems(8.0)))) }
    public func w40() -> Self { w(.definite(.rems(GPUI.rems(10.0)))) }
    public func w48() -> Self { w(.definite(.rems(GPUI.rems(12.0)))) }
    public func w56() -> Self { w(.definite(.rems(GPUI.rems(14.0)))) }
    public func w64() -> Self { w(.definite(.rems(GPUI.rems(16.0)))) }
    public func w72() -> Self { w(.definite(.rems(GPUI.rems(18.0)))) }
    public func w80() -> Self { w(.definite(.rems(GPUI.rems(20.0)))) }
    public func w96() -> Self { w(.definite(.rems(GPUI.rems(24.0)))) }

    public func h0() -> Self { h(.definite(.pixels(GPUI.px(0.0)))) }
    public func h1() -> Self { h(.definite(.rems(GPUI.rems(0.25)))) }
    public func h2() -> Self { h(.definite(.rems(GPUI.rems(0.5)))) }
    public func h3() -> Self { h(.definite(.rems(GPUI.rems(0.75)))) }
    public func h4() -> Self { h(.definite(.rems(GPUI.rems(1.0)))) }
    public func h5() -> Self { h(.definite(.rems(GPUI.rems(1.25)))) }
    public func h6() -> Self { h(.definite(.rems(GPUI.rems(1.5)))) }
    public func h8() -> Self { h(.definite(.rems(GPUI.rems(2.0)))) }
    public func h10() -> Self { h(.definite(.rems(GPUI.rems(2.5)))) }
    public func h12() -> Self { h(.definite(.rems(GPUI.rems(3.0)))) }
    public func h16() -> Self { h(.definite(.rems(GPUI.rems(4.0)))) }
    public func h20() -> Self { h(.definite(.rems(GPUI.rems(5.0)))) }
    public func h24() -> Self { h(.definite(.rems(GPUI.rems(6.0)))) }
    public func h32() -> Self { h(.definite(.rems(GPUI.rems(8.0)))) }
    public func h40() -> Self { h(.definite(.rems(GPUI.rems(10.0)))) }
    public func h48() -> Self { h(.definite(.rems(GPUI.rems(12.0)))) }
    public func h56() -> Self { h(.definite(.rems(GPUI.rems(14.0)))) }
    public func h64() -> Self { h(.definite(.rems(GPUI.rems(16.0)))) }
    public func h72() -> Self { h(.definite(.rems(GPUI.rems(18.0)))) }
    public func h80() -> Self { h(.definite(.rems(GPUI.rems(20.0)))) }
    public func h96() -> Self { h(.definite(.rems(GPUI.rems(24.0)))) }

    public func size0() -> Self { size(.definite(.pixels(GPUI.px(0.0)))) }
    public func size1() -> Self { size(.definite(.rems(GPUI.rems(0.25)))) }
    public func size2() -> Self { size(.definite(.rems(GPUI.rems(0.5)))) }
    public func size3() -> Self { size(.definite(.rems(GPUI.rems(0.75)))) }
    public func size4() -> Self { size(.definite(.rems(GPUI.rems(1.0)))) }
    public func size5() -> Self { size(.definite(.rems(GPUI.rems(1.25)))) }
    public func size6() -> Self { size(.definite(.rems(GPUI.rems(1.5)))) }
    public func size8() -> Self { size(.definite(.rems(GPUI.rems(2.0)))) }
    public func size10() -> Self { size(.definite(.rems(GPUI.rems(2.5)))) }
    public func size12() -> Self { size(.definite(.rems(GPUI.rems(3.0)))) }
    public func size16() -> Self { size(.definite(.rems(GPUI.rems(4.0)))) }
    public func size20() -> Self { size(.definite(.rems(GPUI.rems(5.0)))) }
    public func size24() -> Self { size(.definite(.rems(GPUI.rems(6.0)))) }
    public func size32() -> Self { size(.definite(.rems(GPUI.rems(8.0)))) }
    public func size40() -> Self { size(.definite(.rems(GPUI.rems(10.0)))) }
    public func size48() -> Self { size(.definite(.rems(GPUI.rems(12.0)))) }
    public func size56() -> Self { size(.definite(.rems(GPUI.rems(14.0)))) }
    public func size64() -> Self { size(.definite(.rems(GPUI.rems(16.0)))) }
    public func size72() -> Self { size(.definite(.rems(GPUI.rems(18.0)))) }
    public func size80() -> Self { size(.definite(.rems(GPUI.rems(20.0)))) }
    public func size96() -> Self { size(.definite(.rems(GPUI.rems(24.0)))) }

    public func p0() -> Self { p(.pixels(GPUI.px(0.0))) }
    public func p1() -> Self { p(.rems(GPUI.rems(0.25))) }
    public func p2() -> Self { p(.rems(GPUI.rems(0.5))) }
    public func p3() -> Self { p(.rems(GPUI.rems(0.75))) }
    public func p4() -> Self { p(.rems(GPUI.rems(1.0))) }
    public func p5() -> Self { p(.rems(GPUI.rems(1.25))) }
    public func p6() -> Self { p(.rems(GPUI.rems(1.5))) }
    public func p8() -> Self { p(.rems(GPUI.rems(2.0))) }
    public func p10() -> Self { p(.rems(GPUI.rems(2.5))) }
    public func p12() -> Self { p(.rems(GPUI.rems(3.0))) }
    public func p16() -> Self { p(.rems(GPUI.rems(4.0))) }

    public func px0() -> Self { self.px(.pixels(GPUI.px(0.0))) }
    public func px1() -> Self { self.px(.rems(GPUI.rems(0.25))) }
    public func px2() -> Self { self.px(.rems(GPUI.rems(0.5))) }
    public func px3() -> Self { self.px(.rems(GPUI.rems(0.75))) }
    public func px4() -> Self { self.px(.rems(GPUI.rems(1.0))) }
    public func px6() -> Self { self.px(.rems(GPUI.rems(1.5))) }
    public func px8() -> Self { self.px(.rems(GPUI.rems(2.0))) }

    public func py0() -> Self { py(.pixels(GPUI.px(0.0))) }
    public func py1() -> Self { py(.rems(GPUI.rems(0.25))) }
    public func py2() -> Self { py(.rems(GPUI.rems(0.5))) }
    public func py3() -> Self { py(.rems(GPUI.rems(0.75))) }
    public func py4() -> Self { py(.rems(GPUI.rems(1.0))) }
    public func py6() -> Self { py(.rems(GPUI.rems(1.5))) }
    public func py8() -> Self { py(.rems(GPUI.rems(2.0))) }

    public func m0() -> Self { m(.definite(.pixels(GPUI.px(0.0)))) }
    public func m1() -> Self { m(.definite(.rems(GPUI.rems(0.25)))) }
    public func m2() -> Self { m(.definite(.rems(GPUI.rems(0.5)))) }
    public func m3() -> Self { m(.definite(.rems(GPUI.rems(0.75)))) }
    public func m4() -> Self { m(.definite(.rems(GPUI.rems(1.0)))) }
    public func m6() -> Self { m(.definite(.rems(GPUI.rems(1.5)))) }
    public func m8() -> Self { m(.definite(.rems(GPUI.rems(2.0)))) }

    public func mt0() -> Self { mt(.definite(.pixels(GPUI.px(0.0)))) }
    public func mt1() -> Self { mt(.definite(.rems(GPUI.rems(0.25)))) }
    public func mt2() -> Self { mt(.definite(.rems(GPUI.rems(0.5)))) }
    public func mt3() -> Self { mt(.definite(.rems(GPUI.rems(0.75)))) }
    public func mt4() -> Self { mt(.definite(.rems(GPUI.rems(1.0)))) }
    public func mt6() -> Self { mt(.definite(.rems(GPUI.rems(1.5)))) }
    public func mt8() -> Self { mt(.definite(.rems(GPUI.rems(2.0)))) }

    public func mb0() -> Self { mb(.definite(.pixels(GPUI.px(0.0)))) }
    public func mb1() -> Self { mb(.definite(.rems(GPUI.rems(0.25)))) }
    public func mb2() -> Self { mb(.definite(.rems(GPUI.rems(0.5)))) }
    public func mb3() -> Self { mb(.definite(.rems(GPUI.rems(0.75)))) }
    public func mb4() -> Self { mb(.definite(.rems(GPUI.rems(1.0)))) }
    public func mb6() -> Self { mb(.definite(.rems(GPUI.rems(1.5)))) }
    public func mb8() -> Self { mb(.definite(.rems(GPUI.rems(2.0)))) }

    public func ml0() -> Self { ml(.definite(.pixels(GPUI.px(0.0)))) }
    public func ml1() -> Self { ml(.definite(.rems(GPUI.rems(0.25)))) }
    public func ml2() -> Self { ml(.definite(.rems(GPUI.rems(0.5)))) }
    public func ml3() -> Self { ml(.definite(.rems(GPUI.rems(0.75)))) }
    public func ml4() -> Self { ml(.definite(.rems(GPUI.rems(1.0)))) }
    public func ml6() -> Self { ml(.definite(.rems(GPUI.rems(1.5)))) }
    public func ml8() -> Self { ml(.definite(.rems(GPUI.rems(2.0)))) }

    public func mr0() -> Self { mr(.definite(.pixels(GPUI.px(0.0)))) }
    public func mr1() -> Self { mr(.definite(.rems(GPUI.rems(0.25)))) }
    public func mr2() -> Self { mr(.definite(.rems(GPUI.rems(0.5)))) }
    public func mr3() -> Self { mr(.definite(.rems(GPUI.rems(0.75)))) }
    public func mr4() -> Self { mr(.definite(.rems(GPUI.rems(1.0)))) }
    public func mr6() -> Self { mr(.definite(.rems(GPUI.rems(1.5)))) }
    public func mr8() -> Self { mr(.definite(.rems(GPUI.rems(2.0)))) }

    public func mx0() -> Self { mx(.definite(.pixels(GPUI.px(0.0)))) }
    public func mx1() -> Self { mx(.definite(.rems(GPUI.rems(0.25)))) }
    public func mx2() -> Self { mx(.definite(.rems(GPUI.rems(0.5)))) }
    public func mx3() -> Self { mx(.definite(.rems(GPUI.rems(0.75)))) }
    public func mx4() -> Self { mx(.definite(.rems(GPUI.rems(1.0)))) }
    public func mx6() -> Self { mx(.definite(.rems(GPUI.rems(1.5)))) }
    public func mx8() -> Self { mx(.definite(.rems(GPUI.rems(2.0)))) }

    public func my0() -> Self { my(.definite(.pixels(GPUI.px(0.0)))) }
    public func my1() -> Self { my(.definite(.rems(GPUI.rems(0.25)))) }
    public func my2() -> Self { my(.definite(.rems(GPUI.rems(0.5)))) }
    public func my3() -> Self { my(.definite(.rems(GPUI.rems(0.75)))) }
    public func my4() -> Self { my(.definite(.rems(GPUI.rems(1.0)))) }
    public func my6() -> Self { my(.definite(.rems(GPUI.rems(1.5)))) }
    public func my8() -> Self { my(.definite(.rems(GPUI.rems(2.0)))) }

    public func gap0() -> Self { gap(.pixels(GPUI.px(0.0))) }
    public func gap1() -> Self { gap(.rems(GPUI.rems(0.25))) }
    public func gap2() -> Self { gap(.rems(GPUI.rems(0.5))) }
    public func gap3() -> Self { gap(.rems(GPUI.rems(0.75))) }
    public func gap4() -> Self { gap(.rems(GPUI.rems(1.0))) }
    public func gap6() -> Self { gap(.rems(GPUI.rems(1.5))) }
    public func gap8() -> Self { gap(.rems(GPUI.rems(2.0))) }

    // MARK: - Debug

    public func debug() -> Self {
        withStyle { $0.debug = true }
    }

    public func debugBelow() -> Self {
        withStyle { $0.debugBelow = true }
    }
}
