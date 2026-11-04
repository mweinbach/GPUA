// Ported from: crates/rune-kit/src/glyphs.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! The small built-in glyphs components draw (check marks, chevrons, close, stars). Geometric
//! shapes, not an icon catalog; a theme may replace any of them through `Kit.glyph`.
//! `MIC`, `KEYBOARD`, `CURSOR_TEXT`, `ARROW_RIGHT`, `SPARKLE`, `STAR` and `STAR_FILLED` have no `Glyphs` slot: draw them with `icon(glyphs.MIC, 16.0)`.

import Rune

private let pageSvg = #"<path d="M3.5 1.5H9.5L12.5 4.5V14.5H3.5V1.5Z" stroke="currentColor" stroke-linejoin="round"/><path d="M9.5 1.5V4.5H12.5" stroke="currentColor" stroke-linejoin="round"/>"#

/// Namespace mirroring `rune_kit::glyphs` module exports.
public enum glyphs {
    public static let CHECK = Icon(
        name: "kit-check",
        view: 12.0,
        body: #"<path d="M3 7.17905L5.02703 8.85135L9 3.5" stroke="currentColor" stroke-width="1.5" stroke-linecap="square"/>"#
    )
    public static let check = CHECK

    public static let CHECK_SMALL = Icon(
        name: "kit-check-small",
        view: 16.0,
        body: #"<path d="M3.53564 8.17857L6.39279 11.75L12.4642 4.25" stroke="currentColor" stroke-width="1" stroke-linecap="round" stroke-linejoin="round"/>"#
    )
    public static let checkSmall = CHECK_SMALL

    public static let CHEVRON_DOWN = Icon(
        name: "kit-chevron-down",
        view: 16.0,
        body: #"<path d="M5 6.5L8 9.5L11 6.5" stroke="currentColor" stroke-width="1" stroke-linecap="round" stroke-linejoin="round"/>"#
    )
    public static let chevronDown = CHEVRON_DOWN

    public static let CHEVRON_UP = Icon(
        name: "kit-chevron-up",
        view: 16.0,
        body: #"<path d="M11 9.5L8 6.5L5 9.5" stroke="currentColor" stroke-width="1" stroke-linecap="round" stroke-linejoin="round"/>"#
    )
    public static let chevronUp = CHEVRON_UP

    public static let CARET_RIGHT = Icon(
        name: "kit-caret-right",
        view: 16.0,
        body: #"<path d="M6 4L10 8L6 12V4Z" fill="currentColor"/>"#
    )
    public static let caretRight = CARET_RIGHT

    public static let TRIANGLE_DOWN = Icon(
        name: "kit-triangle-down",
        view: 16.0,
        body: #"<path d="M4 6H12L8 10.5L4 6Z" fill="currentColor"/>"#
    )
    public static let triangleDown = TRIANGLE_DOWN

    public static let CLOSE = Icon(
        name: "kit-close",
        view: 16.0,
        body: #"<path d="M4.25 11.75L11.75 4.25" stroke="currentColor"/><path d="M11.75 11.75L4.25 4.25" stroke="currentColor"/>"#
    )
    public static let close = CLOSE

    public static let COPY = Icon(
        name: "kit-copy",
        view: 16.0,
        body: #"<path d="M4.5 4.5V2.5H13.5V11.5H11.5M2.5 4.5H11.5V13.5H2.5V4.5Z" stroke="currentColor"/>"#
    )
    public static let copy = COPY

    public static let SEARCH = Icon(
        name: "kit-search",
        view: 16.0,
        body: #"<path d="M14 14L10.3454 10.3454M6.88889 11.7778C9.58889 11.7778 11.7778 9.58889 11.7778 6.88889C11.7778 4.18889 9.58889 2 6.88889 2C4.18889 2 2 4.18889 2 6.88889C2 9.58889 4.18889 11.7778 6.88889 11.7778Z" stroke="currentColor"/>"#
    )
    public static let search = SEARCH

    public static let CIRCLE_X = Icon(
        name: "kit-circle-x",
        view: 16.0,
        body: #"<path d="M6 6L10 10M10 6L6 10M14.5 8C14.5 11.5899 11.5899 14.5 8 14.5C4.41015 14.5 1.5 11.5899 1.5 8C1.5 4.41015 4.41015 1.5 8 1.5C11.5899 1.5 14.5 4.41015 14.5 8Z" stroke="currentColor"/>"#
    )
    public static let circleX = CIRCLE_X

    public static let LOCK = Icon(
        name: "kit-lock",
        view: 16.0,
        body: #"<rect x="3.5" y="7" width="9" height="7" rx="1" stroke="currentColor"/><path d="M5.5 7V4.5a2.5 2.5 0 0 1 5 0V7M8 10v1.5" stroke="currentColor" stroke-linecap="round"/>"#
    )
    public static let lock = LOCK

    public static let EYE = Icon(
        name: "kit-eye",
        view: 16.0,
        body: #"<path d="M1 8s2.5-4.5 7-4.5S15 8 15 8s-2.5 4.5-7 4.5S1 8 1 8Z" stroke="currentColor" stroke-linejoin="round"/><circle cx="8" cy="8" r="2" stroke="currentColor"/>"#
    )
    public static let eye = EYE

    public static let EYE_OFF = Icon(
        name: "kit-eye-off",
        view: 16.0,
        body: #"<path d="m2 2 12 12M6.2 3.7A8 8 0 0 1 8 3.5C12.5 3.5 15 8 15 8a13 13 0 0 1-2.4 2.8M10.3 12.1a8 8 0 0 1-2.3.4C3.5 12.5 1 8 1 8a13 13 0 0 1 2.5-2.9M6.6 6.6a2 2 0 0 0 2.8 2.8" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"/>"#
    )
    public static let eyeOff = EYE_OFF

    /// `fill-triangle-down` turned a quarter counter-clockwise (a collapsed disclosure).
    public static let TRIANGLE_RIGHT = Icon(
        name: "kit-triangle-right",
        view: 16.0,
        body: #"<path d="M6.75194 10.62376C6.41861 10.81816 6 10.57776 6 10.19186V5.8079C6 5.422 6.41861 5.1816 6.75194 5.376L10.5096 7.56797C10.8404 7.76091 10.8404 8.23881 10.5096 8.43175L6.75194 10.62376Z" fill="currentColor"/>"#
    )
    public static let triangleRight = TRIANGLE_RIGHT

    public static let DASH = Icon(
        name: "kit-dash",
        view: 20.0,
        body: #"<rect x="5" y="9.5" width="10" height="1" fill="currentColor"/>"#
    )
    public static let dash = DASH

    /// A microphone. Not a `Glyphs` slot: `icon(glyphs.MIC, 16.0)`.
    public static let MIC = Icon(
        name: "kit-mic",
        view: 16.0,
        body: #"<rect x="5.5" y="1.5" width="5" height="8" rx="2.5" stroke="currentColor"/><path d="M3.5 7V7.5A4.5 4.5 0 0 0 12.5 7.5V7M8 12V14.5M5.5 14.5H10.5" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"/>"#
    )
    public static let mic = MIC

    /// A keyboard. Not a `Glyphs` slot: `icon(glyphs.KEYBOARD, 16.0)`.
    public static let KEYBOARD = Icon(
        name: "kit-keyboard",
        view: 16.0,
        body: #"<rect x="1.5" y="3.5" width="13" height="9" rx="1.5" stroke="currentColor"/><path d="M4.5 6.5H5.5M7.5 6.5H8.5M10.5 6.5H11.5M5.5 9.5H10.5" stroke="currentColor" stroke-linecap="round"/>"#
    )
    public static let keyboard = KEYBOARD

    /// The text I-beam cursor. Not a `Glyphs` slot: `icon(glyphs.CURSOR_TEXT, 16.0)`.
    public static let CURSOR_TEXT = Icon(
        name: "kit-cursor-text",
        view: 16.0,
        body: #"<path d="M5.5 2.5H10.5M8 2.5V13.5M5.5 13.5H10.5" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"/>"#
    )
    public static let cursorText = CURSOR_TEXT

    /// An arrow pointing right. Not a `Glyphs` slot: `icon(glyphs.ARROW_RIGHT, 16.0)`.
    public static let ARROW_RIGHT = Icon(
        name: "kit-arrow-right",
        view: 16.0,
        body: #"<path d="M2.5 8H13.5M9 3.5L13.5 8L9 12.5" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"/>"#
    )
    public static let arrowRight = ARROW_RIGHT

    /// A four-point sparkle. Not a `Glyphs` slot: `icon(glyphs.SPARKLE, 16.0)`.
    public static let SPARKLE = Icon(
        name: "kit-sparkle",
        view: 16.0,
        body: #"<path d="M8 1.5Q10 6 14.5 8Q10 10 8 14.5Q6 10 1.5 8Q6 6 8 1.5Z" stroke="currentColor" stroke-linejoin="round"/>"#
    )
    public static let sparkle = SPARKLE

    /// A five-point star, outline. Not a `Glyphs` slot: `icon(glyphs.STAR, 16.0)`.
    public static let STAR = Icon(
        name: "kit-star",
        view: 16.0,
        body: #"<path d="M8 2.1L9.7 6.25L14.18 6.59L10.76 9.5L11.82 13.86L8 11.5L4.18 13.86L5.24 9.5L1.82 6.59L6.3 6.25Z" stroke="currentColor" stroke-linejoin="round"/>"#
    )
    public static let star = STAR

    /// A five-point star, filled. Not a `Glyphs` slot: `icon(glyphs.STAR_FILLED, 16.0)`.
    public static let STAR_FILLED = Icon(
        name: "kit-star-filled",
        view: 16.0,
        body: #"<path d="M8 2.1L9.7 6.25L14.18 6.59L10.76 9.5L11.82 13.86L8 11.5L4.18 13.86L5.24 9.5L1.82 6.59L6.3 6.25Z" fill="currentColor" stroke="currentColor" stroke-linejoin="round"/>"#
    )
    public static let starFilled = STAR_FILLED

    /// A closed folder (file trees).
    public static let FOLDER = Icon(
        name: "kit-folder",
        view: 16.0,
        body: #"<path d="M1.5 3.5H6L7.5 5H14.5V13.5H1.5V3.5Z" stroke="currentColor" stroke-linejoin="round"/>"#
    )
    public static let folder = FOLDER

    /// An open folder.
    public static let FOLDER_OPEN = Icon(
        name: "kit-folder-open",
        view: 16.0,
        body: #"<path d="M1.5 13.5V3.5H6L7.5 5H13.5V7.5" stroke="currentColor" stroke-linejoin="round"/><path d="M1.5 13.5L3.5 7.5H15L13 13.5H1.5Z" stroke="currentColor" stroke-linejoin="round"/>"#
    )
    public static let folderOpen = FOLDER_OPEN

    /// A plain file.
    public static let FILE = Icon(name: "kit-file", view: 16.0, body: pageSvg)
    public static let file = FILE

    /// A source file.
    public static let FILE_CODE = Icon(
        name: "kit-file-code",
        view: 16.0,
        body: pageSvg + #"<path d="M7 8L5.5 9.75L7 11.5M9 8L10.5 9.75L9 11.5" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"/>"#
    )
    public static let fileCode = FILE_CODE

    /// A text, data or config file.
    public static let FILE_TEXT = Icon(
        name: "kit-file-text",
        view: 16.0,
        body: pageSvg + #"<path d="M5.5 8.5H10.5M5.5 10.5H10.5M5.5 12.5H8.5" stroke="currentColor"/>"#
    )
    public static let fileText = FILE_TEXT

    /// An image file.
    public static let FILE_IMAGE = Icon(
        name: "kit-file-image",
        view: 16.0,
        body: pageSvg + #"<circle cx="6.5" cy="7.5" r="1" fill="currentColor"/><path d="M3.5 12.5L6.5 9.5L8 11L9.5 9.5L12.5 12.5" stroke="currentColor" stroke-linejoin="round"/>"#
    )
    public static let fileImage = FILE_IMAGE

    public static let DEFAULT = Glyphs(
        check: CHECK,
        checkSmall: CHECK_SMALL,
        chevronDown: CHEVRON_DOWN,
        chevronUp: CHEVRON_UP,
        caretRight: CARET_RIGHT,
        triangleDown: TRIANGLE_DOWN,
        triangleRight: TRIANGLE_RIGHT,
        close: CLOSE,
        clear: CLOSE,
        copy: COPY,
        search: SEARCH,
        lock: LOCK,
        eye: EYE,
        eyeOff: EYE_OFF,
        circleX: CIRCLE_X,
        dash: DASH
    )
    public static let `default` = DEFAULT
}
