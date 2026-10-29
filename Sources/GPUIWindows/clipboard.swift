// Ported from: crates/gpui_windows/src/clipboard.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(Windows)
import Foundation
import GPUI
#if canImport(CWinSys)
import CWinSys
#endif

// MARK: - Constants & Win32 Clipboard Formats

private let DRAGDROP_GET_FILES_COUNT: UInt32 = 0xFFFFFFFF

public let CF_DIB: UInt32 = 8
public let CF_UNICODETEXT: UInt32 = 13
public let CF_HDROP: UInt32 = 15

// PORT NOTE: Dynamic clipboard formats registered once on Windows.
public let CLIPBOARD_HASH_FORMAT: UInt32 = registerClipboardFormat("GPUI internal text hash")
public let CLIPBOARD_METADATA_FORMAT: UInt32 = registerClipboardFormat("GPUI internal metadata")
public let CLIPBOARD_SVG_FORMAT: UInt32 = registerClipboardFormat("image/svg+xml")
public let CLIPBOARD_GIF_FORMAT: UInt32 = registerClipboardFormat("GIF")
public let CLIPBOARD_PNG_FORMAT: UInt32 = registerClipboardFormat("PNG")
public let CLIPBOARD_JPG_FORMAT: UInt32 = registerClipboardFormat("JFIF")

public enum ClipboardFormatType: Sendable, Equatable {
    case text
    case image
    case files
}

@inline(__always)
public func formatToType(_ format: UInt32) -> ClipboardFormatType? {
    if format == CF_UNICODETEXT {
        return .text
    } else if format == CF_DIB || format == CLIPBOARD_PNG_FORMAT || format == CLIPBOARD_GIF_FORMAT || format == CLIPBOARD_JPG_FORMAT || format == CLIPBOARD_SVG_FORMAT {
        return .image
    } else if format == CF_HDROP {
        return .files
    }
    return nil
}

// MARK: - Public API

public func writeToClipboard(_ item: ClipboardItem) {
    _ = withClipboard {
        _ = cwin_win32_clipboard_empty()
        if let data = item.data {
            data.withUnsafeBytes { rawBuf in
                if let base = rawBuf.baseAddress {
                    _ = cwin_win32_clipboard_set_binary_data(CLIPBOARD_PNG_FORMAT, base, rawBuf.count)
                }
            }
        }
        if let text = item.text {
            writeStringToClipboard(text)
        }
    }
}

public func readFromClipboard() -> ClipboardItem? {
    withClipboard {
        var textResult: String? = nil
        var imageResult: Data? = nil
        var filesResult: [String]? = nil

        let count = cwin_win32_clipboard_count_formats()
        var currentFormat: UInt32 = 0
        for _ in 0..<count {
            currentFormat = cwin_win32_clipboard_enum_formats(currentFormat)
            if currentFormat == 0 { break }
            guard let formatType = formatToType(currentFormat) else { continue }
            switch formatType {
            case .text:
                if textResult == nil {
                    textResult = readStringFromClipboard()
                }
            case .image:
                if imageResult == nil {
                    imageResult = readImageFromClipboard(format: currentFormat)
                }
            case .files:
                if filesResult == nil {
                    filesResult = readFilesFromClipboard()
                }
            }
        }

        // Priority order matching upstream: image, files, text
        if let image = imageResult {
            return ClipboardItem(text: textResult, data: image)
        }
        if let files = filesResult {
            let joined = files.joined(separator: "\n")
            return ClipboardItem(text: joined, data: nil)
        }
        if let text = textResult {
            return ClipboardItem(text: text, data: nil)
        }
        return nil
    } ?? nil
}

// MARK: - Clipboard Helpers

public func withClipboard<T>(_ f: () -> T) -> T? {
    if cwin_win32_clipboard_open(nil) == 0 {
        defer { _ = cwin_win32_clipboard_close() }
        return f()
    }
    return nil
}

public func registerClipboardFormat(_ name: String) -> UInt32 {
    let wide = toWideString(name)
    return wide.withUnsafeBufferPointer { buf in
        cwin_win32_clipboard_register_format(buf.baseAddress)
    }
}

public func withFileNames(_ hdrop: WinHandle, _ f: (String) -> Void) {
    var filesPtr: UnsafeMutablePointer<UnsafeMutablePointer<UInt16>?>? = nil
    var count: Int = 0
    guard cwin_win32_clipboard_get_hdrop_files(hdrop, &filesPtr, &count) == 0,
          let files = filesPtr else {
        return
    }
    defer { cwin_win32_clipboard_free_hdrop_files(files, count) }
    for i in 0..<count {
        if let file = files[i] {
            var len = 0
            while file[len] != 0 {
                len += 1
            }
            let s = fromWideString(file, length: len)
            f(s)
        }
    }
}

public func writeStringToClipboard(_ text: String, metadata: String? = nil) {
    let wide = toWideString(text)
    wide.withUnsafeBufferPointer { buf in
        let byteCount = (text.utf16.count + 1) * MemoryLayout<UInt16>.size
        _ = cwin_win32_clipboard_set_binary_data(CF_UNICODETEXT, buf.baseAddress, byteCount)
    }
    if let metadata = metadata {
        var hasher = Hasher()
        hasher.combine(text)
        var hashVal = UInt64(bitPattern: Int64(hasher.finalize()))
        withUnsafeBytes(of: &hashVal) { hashBuf in
            _ = cwin_win32_clipboard_set_binary_data(CLIPBOARD_HASH_FORMAT, hashBuf.baseAddress, hashBuf.count)
        }
        let metaWide = toWideString(metadata)
        metaWide.withUnsafeBufferPointer { buf in
            let byteCount = (metadata.utf16.count + 1) * MemoryLayout<UInt16>.size
            _ = cwin_win32_clipboard_set_binary_data(CLIPBOARD_METADATA_FORMAT, buf.baseAddress, byteCount)
        }
    }
}

public func readStringFromClipboard() -> String? {
    var ptr: UnsafeMutableRawPointer? = nil
    var len: Int = 0
    guard cwin_win32_clipboard_get_binary_data(CF_UNICODETEXT, &ptr, &len) == 0,
          let dataPtr = ptr, len >= MemoryLayout<UInt16>.size else {
        return nil
    }
    defer { cwin_win32_clipboard_free_binary_data(dataPtr) }
    let u16Ptr = dataPtr.bindMemory(to: UInt16.self, capacity: len / MemoryLayout<UInt16>.size)
    let u16Count = len / MemoryLayout<UInt16>.size
    let actualCount = (u16Count > 0 && u16Ptr[u16Count - 1] == 0) ? u16Count - 1 : u16Count
    return fromWideString(u16Ptr, length: actualCount)
}

public func readImageFromClipboard(format: UInt32) -> Data? {
    var ptr: UnsafeMutableRawPointer? = nil
    var len: Int = 0
    guard cwin_win32_clipboard_get_binary_data(format, &ptr, &len) == 0,
          let dataPtr = ptr, len > 0 else {
        return nil
    }
    defer { cwin_win32_clipboard_free_binary_data(dataPtr) }
    let rawData = Data(bytes: dataPtr, count: len)
    if format == CF_DIB {
        return convertDibToBmp(rawData)
    }
    return rawData
}

public func readFilesFromClipboard() -> [String]? {
    var filesPtr: UnsafeMutablePointer<UnsafeMutablePointer<UInt16>?>? = nil
    var count: Int = 0
    guard cwin_win32_clipboard_get_files(&filesPtr, &count) == 0,
          let files = filesPtr, count > 0 else {
        return nil
    }
    defer { cwin_win32_clipboard_free_hdrop_files(files, count) }
    var filePaths: [String] = []
    filePaths.reserveCapacity(count)
    for i in 0..<count {
        if let file = files[i] {
            var len = 0
            while file[len] != 0 {
                len += 1
            }
            let s = fromWideString(file, length: len)
            filePaths.append(s)
        }
    }
    return filePaths.isEmpty ? nil : filePaths
}

/// Convert DIB data to BMP file format.
/// DIB is essentially BMP without a file header, so we just need to add the 14-byte BITMAPFILEHEADER.
public func convertDibToBmp(_ dibData: Data) -> Data? {
    guard dibData.count >= 40 else {
        return nil
    }

    let fileSize = UInt32(14 + dibData.count)

    let headerSize = dibData.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 0, as: UInt32.self) }
    let bitCount = dibData.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 14, as: UInt16.self) }
    let compression = dibData.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 16, as: UInt32.self) }

    let colorTableSize: UInt32
    if bitCount <= 8 {
        let colorsUsed = dibData.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 32, as: UInt32.self) }
        let numColors = (colorsUsed == 0) ? (UInt32(1) << Int(bitCount)) : colorsUsed
        colorTableSize = numColors * 4
    } else if compression == 3 { // BI_BITFIELDS
        colorTableSize = 12
    } else {
        colorTableSize = 0
    }

    let pixelDataOffset = 14 + headerSize + colorTableSize

    var bmpData = Data(capacity: Int(fileSize))
    bmpData.append(contentsOf: [0x42, 0x4D]) // "BM" signature

    var leFileSize = fileSize.littleEndian
    withUnsafeBytes(of: &leFileSize) { bmpData.append(contentsOf: $0) }

    bmpData.append(contentsOf: [0, 0, 0, 0]) // Reserved

    var lePixelOffset = pixelDataOffset.littleEndian
    withUnsafeBytes(of: &lePixelOffset) { bmpData.append(contentsOf: $0) }

    bmpData.append(dibData)

    return bmpData
}

#endif
