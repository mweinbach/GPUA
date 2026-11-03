// Ported from: crates/rune/src/clipboard/macos.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

#if os(macOS)
import AppKit
import Foundation

/// Refuse to hand AppKit's RTF parser multi-megabyte blobs (e.g. embedded images).
let MAX_RTF_CONVERT_BYTES: Int = 1024 * 1024
private let MAX_TIFF_BYTES: Int = 8 * MAX_IMAGE_BYTES

/// Replaces the pasteboard's contents with every form `content` carries.
func writeMacPasteboard(_ pb: NSPasteboard, _ content: ClipboardContent) -> Result<Void, ClipboardWriteError> {
    autoreleasepool {
        let refused = { (form: String) in ClipboardWriteError("the pasteboard refused the \(form)") }
        let itemCount = max(1, content.files().count)
        let items: [NSPasteboardItem] = (0..<itemCount).map { _ in NSPasteboardItem() }
        let first = items[0]
        let text = content.text()
        if (!text.isEmpty || !content.isRich()) && !first.setString(text, forType: .string) {
            return .failure(refused("text"))
        }
        if let html = content.html(), !first.setString(declareUtf8(html), forType: .html) {
            return .failure(refused("HTML"))
        }
        if let rtf = content.rtf(), !first.setData(Data(rtf.utf8), forType: .rtf) {
            return .failure(refused("RTF"))
        }
        if let image = content.image() {
            guard let tiff = pngToTiff(image.png()) else {
                return .failure(ClipboardWriteError("the image didn't convert to TIFF"))
            }
            if !first.setData(Data(image.png()), forType: .png)
                || !first.setData(tiff, forType: .tiff)
            {
                return .failure(refused("image"))
            }
        }
        for (item, path) in zip(items, content.files()) {
            let urlStr = URL(fileURLWithPath: path).absoluteString
            if !item.setString(urlStr, forType: .fileURL) {
                return .failure(refused("file"))
            }
        }
        pb.clearContents()
        if !pb.writeObjects(items) {
            return .failure(refused("content"))
        }
        return .success(())
    }
}

/// Plain text, HTML and RTF, with HTML made from the RTF when the pasteboard has no HTML, and
/// with `all`, the pasteboard's PNG (or its TIFF as PNG) and its file URLs too.
func readMacPasteboard(_ pb: NSPasteboard, _ all: Bool) -> ClipboardContent? {
    autoreleasepool {
        let text = pb.string(forType: .string)
        let html: String? = {
            guard let s = pb.string(forType: .html), !s.isEmpty, s.utf8.count <= MAX_RICH_BYTES else {
                return nil
            }
            return s
        }()
        let rtfBytes: [UInt8]? = {
            guard let d = pb.data(forType: .rtf), !d.isEmpty, d.count <= MAX_RICH_BYTES else {
                return nil
            }
            return [UInt8](d)
        }()
        let image = all ? readMacImage(pb) : nil
        let files = all ? readMacFiles(pb) : []
        if text == nil && html == nil && rtfBytes == nil && image == nil && files.isEmpty {
            return nil
        }
        let resolvedHtml = html ?? rtfBytes.flatMap(rtfToHtml)
        var content = ClipboardContent.new(text ?? "").withFiles(files)
        if let resolvedHtml {
            content = content.withHtml(resolvedHtml)
        }
        if let rtfBytes {
            content = content.withRtf(String(decoding: rtfBytes, as: UTF8.self))
        }
        if let image {
            content = content.withImage(image)
        }
        return content
    }
}

private func readMacFiles(_ pb: NSPasteboard) -> [String] {
    guard let items = pb.pasteboardItems else { return [] }
    var out: [String] = []
    for item in items {
        guard let urlStr = item.string(forType: .fileURL),
              let path = macPasteboardFilePath(urlStr) else {
            continue
        }
        out.append(path)
    }
    return out
}

func macPasteboardFilePath(_ rawUrl: String) -> String? {
    guard let nsUrl = NSURL(string: rawUrl), nsUrl.isFileURL else { return nil }
    let resolved = (nsUrl.filePathURL ?? (nsUrl as URL)).path
    return resolved.isEmpty ? nil : resolved
}

/// TIFF for PNG bytes, through `NSBitmapImageRep`.
func pngToTiff(_ png: [UInt8]) -> Data? {
    autoreleasepool {
        NSBitmapImageRep(data: Data(png))?.tiffRepresentation
    }
}

private func readMacImage(_ pb: NSPasteboard) -> ClipboardImage? {
    if let pngData = pb.data(forType: .png), !pngData.isEmpty, pngData.count <= MAX_IMAGE_BYTES,
       let img = ClipboardImage.fromPng([UInt8](pngData))
    {
        return img
    }
    guard let tiffData = pb.data(forType: .tiff), !tiffData.isEmpty, tiffData.count <= MAX_TIFF_BYTES else {
        return nil
    }
    return tiffToPng([UInt8](tiffData))
}

/// PNG for TIFF bytes (the first image of a multi-page TIFF), through `NSBitmapImageRep`.
func tiffToPng(_ tiff: [UInt8]) -> ClipboardImage? {
    guard !tiff.isEmpty, tiff.count <= MAX_TIFF_BYTES, tiffDimensionsOk(tiff) else {
        return nil
    }
    return autoreleasepool {
        guard let rep = NSBitmapImageRep(data: Data(tiff)) else { return nil }
        let w = rep.pixelsWide
        let h = rep.pixelsHigh
        guard w > 0, h > 0, validImageSize(UInt32(w), UInt32(h)) else { return nil }
        guard let pngData = rep.representation(using: .png, properties: [:]),
              pngData.count <= MAX_IMAGE_BYTES else {
            return nil
        }
        return ClipboardImage.fromPng([UInt8](pngData))
    }
}

/// Checks the first TIFF IFD's `ImageWidth` (256) and `ImageLength` (257) before handing the
/// bytes to AppKit, so a compressed decompression bomb cannot allocate a giant bitmap.
func tiffDimensionsOk(_ tiff: [UInt8]) -> Bool {
    guard tiff.count >= 8 else { return false }
    let le: Bool
    if tiff[0] == 0x49 && tiff[1] == 0x49 && tiff[2] == 0x2A && tiff[3] == 0x00 {
        le = true
    } else if tiff[0] == 0x4D && tiff[1] == 0x4D && tiff[2] == 0x00 && tiff[3] == 0x2A {
        le = false
    } else {
        return false
    }

    let u16At = { (at: Int) -> UInt16? in
        guard at >= 0, at + 2 <= tiff.count else { return nil }
        if le {
            return UInt16(tiff[at]) | (UInt16(tiff[at + 1]) << 8)
        } else {
            return (UInt16(tiff[at]) << 8) | UInt16(tiff[at + 1])
        }
    }
    let u32At = { (at: Int) -> UInt32? in
        guard at >= 0, at + 4 <= tiff.count else { return nil }
        if le {
            return UInt32(tiff[at])
                | (UInt32(tiff[at + 1]) << 8)
                | (UInt32(tiff[at + 2]) << 16)
                | (UInt32(tiff[at + 3]) << 24)
        } else {
            return (UInt32(tiff[at]) << 24)
                | (UInt32(tiff[at + 1]) << 16)
                | (UInt32(tiff[at + 2]) << 8)
                | UInt32(tiff[at + 3])
        }
    }

    guard let ifdU32 = u32At(4) else { return false }
    let ifd = Int(ifdU32)
    guard let entriesU16 = u16At(ifd) else { return false }
    let entries = min(Int(entriesU16), 4096)

    var width: UInt32? = nil
    var height: UInt32? = nil
    for i in 0..<entries {
        let (mul, overflow1) = i.multipliedReportingOverflow(by: 12)
        if overflow1 { break }
        let (ifdPlus2, overflow2) = ifd.addingReportingOverflow(2)
        if overflow2 { break }
        let (base, overflow3) = ifdPlus2.addingReportingOverflow(mul)
        if overflow3 || base + 12 > tiff.count { break }
        guard let tag = u16At(base),
              let kind = u16At(base + 2),
              let count = u32At(base + 4) else {
            break
        }
        if (tag == 256 || tag == 257) && count == 1 {
            let val: UInt32? = switch kind {
            case 1: (base + 8 < tiff.count) ? UInt32(tiff[base + 8]) : nil
            case 3: u16At(base + 8).map(UInt32.init)
            case 4: u32At(base + 8)
            default: nil
            }
            if tag == 256 {
                width = val
            } else {
                height = val
            }
        }
    }
    guard let w = width, let h = height else { return false }
    return validImageSize(w, h)
}

/// A UTF-8 HTML document for RTF, through `NSAttributedString`.
func rtfToHtml(_ rtf: [UInt8]) -> String? {
    guard !rtf.isEmpty, rtf.count <= MAX_RTF_CONVERT_BYTES else { return nil }
    return autoreleasepool {
        guard let attrStr = NSAttributedString(rtf: Data(rtf), documentAttributes: nil) else {
            return nil
        }
        let attrs: [NSAttributedString.DocumentAttributeKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue,
        ]
        guard let data = try? attrStr.data(
            from: NSRange(location: 0, length: attrStr.length),
            documentAttributes: attrs
        ), data.count <= MAX_RICH_BYTES else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}

/// Browsers read pasteboard HTML without a charset as Latin-1; say it's UTF-8.
private func declareUtf8(_ html: String) -> String {
    let bytes = Array(html.utf8)
    let headLen = min(bytes.count, 1024)
    let target = Array("charset".utf8)
    if headLen >= 7 {
        for idx in 0...(headLen - 7) {
            var match = true
            for k in 0..<7 {
                let b = bytes[idx + k]
                let lower = (b >= 0x41 && b <= 0x5A) ? (b + 32) : b
                if lower != target[k] {
                    match = false
                    break
                }
            }
            if match { return html }
        }
    }
    return "<meta charset=\"utf-8\">\(html)"
}
#endif
