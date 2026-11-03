// Ported from: crates/rune/src/text/coretext_match.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! How Rune's glyphs approach CoreText's: the `FontSmoothing` modes and what each changes.

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Android)
import Android
#elseif os(Windows)
import CRT
#elseif os(WASI)
import WASILibc
#endif

/// How glyphs are rasterised and placed: CoreGraphics' glyph pipeline, with or without font
/// smoothing's dilation. Set app-wide with `App.fontSmoothing`, or at run time with
/// `Tx.setFontSmoothing`, which redraws with glyphs rasterised for the new mode.
///
/// The default is `.on` on macOS and `.off` on every other platform (Linux, Windows, Android, WASI),
/// which has no font smoothing to match. Both work on any OS (they are arithmetic on outlines,
/// not calls into CoreText).
public enum FontSmoothing: UInt8, Sendable, Equatable, Hashable {
    /// Text that matches CoreText's with font smoothing on (macOS's default): the pipeline plus
    /// font smoothing's outline dilation (`ApplePipeline.SMOOTHED`).
    case on = 0
    /// Text that matches CoreText with font smoothing off (`-webkit-font-smoothing: antialiased`):
    /// the pipeline without dilation (`ApplePipeline.UNSMOOTHED`).
    case off = 1

    public static var `default`: FontSmoothing {
        #if os(macOS)
        return .on
        #else
        return .off
        #endif
    }

    /// The CoreGraphics stages glyphs rasterise with: all of them for `.on`, all but the
    /// dilation for `.off`.
    public func pipeline() -> ApplePipeline {
        switch self {
        case .on:
            return ApplePipeline.SMOOTHED
        case .off:
            return ApplePipeline.UNSMOOTHED
        }
    }
}

/// Glyph x phases are in sixtieths of a device pixel (`PHASES`), which hold every step
/// CoreGraphics quantises to (fifths to wholes).
// PORT NOTE: Named `GLYPH_X_PHASES` at Swift module scope to avoid colliding with `frame/profile.swift`'s `PHASES`.
let GLYPH_X_PHASES: Float = 60.0

/// How many x positions per device pixel CoreGraphics' subpixel quantisation draws a glyph of
/// `ppem` device px at: one more than the whole number of times `ppem` goes into 33 1/3, at most
/// five. Fifths below 8 1/3 ppem, quarters to 11.1, thirds to 16.7, halves to 33.3 and whole
/// pixels above, at every scale.
func quantisationSteps(_ ppem: Float) -> Float {
    if ppem > 0.0 {
        return min(1.0 + ((100.0 / 3.0) / ppem).rounded(.down), 5.0)
    } else {
        return 5.0
    }
}

/// The device pixel a glyph's quad starts at and its x phase in sixtieths of a pixel (its atlas
/// bin, `PHASES`), for a pen at `x` device px and a glyph of `ppem` device px.
func glyphX(_ x: Float, _ ppem: Float) -> (Float, UInt8) {
    let steps = quantisationSteps(ppem)
    // Snap to 1/256 px grid first so summing advances in different orders produces identical bins.
    let snapped = (((x * 256.0).rounded(.toNearestOrAwayFromZero) / 256.0) * steps).rounded(.down) / steps
    let fx = snapped.rounded(.down)
    let phase = ((snapped - fx) * steps).rounded(.toNearestOrAwayFromZero)
    if phase >= steps {
        return (fx + 1.0, 0)
    } else {
        return (fx, UInt8((phase * (GLYPH_X_PHASES / steps)).rounded(.towardZero)))
    }
}
