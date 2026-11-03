// Ported from: crates/rune/src/platform/macos/cursor.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! AppKit cursors set directly: for overlays, which are rarely the key window, and for image
//! cursors, which winit would size in pixels (twice too big on Retina).

#if os(macOS)
import AppKit
import Foundation

// PORT NOTE: Main-thread cache of constructed `NSCursor` instances keyed by `CursorImage`.
nonisolated(unsafe) private var macCachedImageCursors: [CursorImage: NSCursor?] = [:]
// PORT NOTE: Main-thread lazy transparent cursor (`16x16` transparent GIF).
nonisolated(unsafe) private var macTransparentCursor: NSCursor? = nil
// PORT NOTE: Main-thread lazy move cursor from HIServices PDF.
nonisolated(unsafe) private var macMoveCursor: NSCursor? = nil

private let macSourceCursorScale: Double = 2.0

@MainActor
private func macNativeImageCursor(_ image: CursorImage) -> NSCursor? {
    if let cached = macCachedImageCursors[image] {
        return cached
    }
    let created = (try? macBuildNsCursor(image, scale: macSourceCursorScale))
    macCachedImageCursors[image] = created
    return created
}

/// Sets an image cursor on `window` itself, with the window's cursor rects off so AppKit
/// doesn't put its own back on entering, focus or a rect rebuild.
@MainActor
func macWindowCursor(window: NSWindow, contentView: NSView?, next: Cursor) -> Cursor? {
    if case .custom(let image) = next, let cursor = macNativeImageCursor(image) {
        window.disableCursorRects()
        cursor.set()
        return nil
    }
    let resolved: Cursor
    if case .custom = next {
        resolved = .default
    } else {
        resolved = next
    }
    if !window.areCursorRectsEnabled {
        window.enableCursorRects()
        if let contentView {
            window.invalidateCursorRects(for: contentView)
        }
        macSetNsCursor(resolved)
    }
    return resolved
}

/// Sets an image cursor again while it holds the pointer.
@MainActor
func macReassertCursor(_ image: CursorImage) {
    guard let cached = macCachedImageCursors[image], let cursor = cached else { return }
    cursor.set()
}

/// An `NSCursor` whose image is sized in points with `image`'s pixels as its bitmap.
@MainActor
func macBuildNsCursor(_ image: CursorImage, scale: Double = 2.0) throws -> NSCursor {
    let w = Int(image.width)
    let h = Int(image.height)
    guard w > 0, h > 0, image.rgba.count >= w * h * 4 else {
        throw AppIconError("the cursor bitmap has no pixels")
    }
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: w,
        pixelsHigh: h,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bitmapFormat: [],
        bytesPerRow: w * 4,
        bitsPerPixel: 32
    ), let data = rep.bitmapData, rep.bytesPerRow >= w * 4 else {
        throw AppIconError("could not allocate a cursor bitmap")
    }
    let stride = rep.bytesPerRow
    for y in 0..<h {
        let srcRow = y * w * 4
        let dstRow = data.advanced(by: y * stride)
        for x in 0..<w {
            let p0 = UInt32(image.rgba[srcRow + x * 4 + 0])
            let p1 = UInt32(image.rgba[srcRow + x * 4 + 1])
            let p2 = UInt32(image.rgba[srcRow + x * 4 + 2])
            let a = UInt32(image.rgba[srcRow + x * 4 + 3])
            dstRow[x * 4 + 0] = UInt8((p0 * a + 127) / 255)
            dstRow[x * 4 + 1] = UInt8((p1 * a + 127) / 255)
            dstRow[x * 4 + 2] = UInt8((p2 * a + 127) / 255)
            dstRow[x * 4 + 3] = UInt8(a)
        }
    }
    let taggedRep = rep.retagging(with: .sRGB) ?? rep
    let effectiveScale = scale > 0 ? scale : 1.0
    let nsImage = NSImage(
        size: NSSize(
            width: Double(w) / effectiveScale,
            height: Double(h) / effectiveScale
        )
    )
    nsImage.addRepresentation(taggedRep)
    let hot = NSPoint(
        x: Double(image.hotspotX) / effectiveScale,
        y: Double(image.hotspotY) / effectiveScale
    )
    return NSCursor(image: nsImage, hotSpot: hot)
}

/// `[NSCursor set]` for each cursor shape. Main thread.
@MainActor
func macSetNsCursor(_ cursor: Cursor, hidden: Bool = false) {
    if hidden {
        if macTransparentCursor == nil {
            macTransparentCursor = macSpecialImageCursor(name: nil)
        }
        macTransparentCursor?.set()
        return
    }
    let ns: NSCursor?
    switch cursor {
    case .custom(let image), .image(let image):
        ns = macNativeImageCursor(image) ?? .arrow
    case .hidden:
        if macTransparentCursor == nil {
            macTransparentCursor = macSpecialImageCursor(name: nil)
        }
        ns = macTransparentCursor
    case .pointer:
        ns = .pointingHand
    case .text:
        ns = .iBeam
    case .grab:
        ns = .openHand
    case .grabbing:
        ns = .closedHand
    case .notAllowed:
        ns = .operationNotAllowed
    case .move:
        ns = macSpecialImageCursor(name: "move") ?? .openHand
    case .ewResize, .resizeColumn:
        ns = .resizeLeftRight
    case .nsResize, .resizeRow:
        ns = .resizeUpDown
    case .crosshair:
        ns = .crosshair
    case .default, .neswResize, .nwseResize:
        ns = .arrow
    }
    ns?.set()
}

@MainActor
private func macSpecialImageCursor(name: String?) -> NSCursor? {
    // A 16x16 transparent GIF.
    let transparentGif: [UInt8] = [
        0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0x10, 0x00, 0x10, 0x00, 0xf0, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x21, 0xf9, 0x04, 0x01, 0x00, 0x00, 0x00, 0x00, 0x2c, 0x00, 0x00,
        0x00, 0x00, 0x10, 0x00, 0x10, 0x00, 0x00, 0x02, 0x0e, 0x84, 0x8f, 0xa9, 0xcb, 0xed, 0x0f,
        0xa3, 0x9c, 0xb4, 0xda, 0x8b, 0xb3, 0x3e, 0x05, 0x00, 0x3b,
    ]
    let image: NSImage?
    if let name {
        let path = "/System/Library/Frameworks/ApplicationServices.framework/Versions/A/Frameworks/HIServices.framework/Versions/A/Resources/cursors/\(name)/cursor.pdf"
        image = NSImage(byReferencingFile: path)
    } else {
        image = NSImage(data: Data(transparentGif))
    }
    guard let image else { return nil }
    let size = image.size
    let hot = name != nil
        ? NSPoint(x: size.width / 2.0, y: size.height / 2.0)
        : NSPoint(x: 0.0, y: 0.0)
    return NSCursor(image: image, hotSpot: hot)
}
#endif
