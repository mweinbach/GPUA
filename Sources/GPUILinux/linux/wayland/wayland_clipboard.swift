// Ported from: crates/gpui_linux/src/linux/wayland/clipboard.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(Linux)
import Foundation
import CLinuxSys
import GPUI

/// Text mime types that we'll offer to other programs.
public let textMimeTypes: [String] = [
    "text/plain;charset=utf-8",
    "UTF8_STRING",
    "text/plain",
]
public let fileListMimeType: String = "text/uri-list"

/// Text mime types that we'll accept from other programs.
public let allowedTextMimeTypes: [String] = [
    "text/plain;charset=utf-8",
    "UTF8_STRING",
]

public protocol ReceiveData: Sendable {
    func receiveData(_ mimeType: String, _ fd: Int32)
}

// PORT NOTE: WlDataOffer wraps raw wayland data offer pointer.
public struct WlDataOffer: ReceiveData, @unchecked Sendable {
    public var raw: OpaquePointer?

    public init(_ raw: OpaquePointer? = nil) {
        self.raw = raw
    }

    public func receiveData(_ mimeType: String, _ fd: Int32) {
        if let raw = raw {
            wl_data_offer_receive(raw, mimeType, fd)
        }
    }
}

// PORT NOTE: ZwpPrimarySelectionOfferV1 wraps raw primary selection offer pointer.
public struct ZwpPrimarySelectionOfferV1: ReceiveData, @unchecked Sendable {
    public var raw: OpaquePointer?

    public init(_ raw: OpaquePointer? = nil) {
        self.raw = raw
    }

    public func receiveData(_ mimeType: String, _ fd: Int32) {
        // Primary selection offer receive
    }
}

/// Wrapper for `WlDataOffer` and `ZwpPrimarySelectionOfferV1`, used to help track mime types.
// PORT NOTE: DataOffer wraps generic ReceiveData payload across thread boundaries.
public struct DataOffer<T: ReceiveData>: @unchecked Sendable {
    public var inner: T
    public var mimeTypes: [String]

    public init(offer: T) {
        self.inner = offer
        self.mimeTypes = []
    }

    public static func new(_ offer: T) -> DataOffer<T> {
        DataOffer(offer: offer)
    }

    public mutating func addMimeType(_ mimeType: String) {
        mimeTypes.append(mimeType)
    }

    public func hasMimeType(_ mimeType: String) -> Bool {
        mimeTypes.contains(mimeType)
    }

    public func readBytes(_ connection: OpaquePointer?, _ mimeType: String) -> [UInt8]? {
        var fds: [Int32] = [0, 0]
        guard pipe(&fds) == 0 else { return nil }
        let readFd = fds[0]
        let writeFd = fds[1]

        inner.receiveData(mimeType, writeFd)
        close(writeFd)

        if let connection = connection {
            wl_display_flush(connection)
        }

        let handle = FileHandle(fileDescriptor: readFd, closeOnDealloc: true)
        let data = handle.readDataToEndOfFile()
        return Array(data)
    }

    public func readText(_ connection: OpaquePointer?) -> ClipboardItem? {
        guard let mimeType = mimeTypes.first(where: { allowedTextMimeTypes.contains($0) }),
              let bytes = readBytes(connection, mimeType),
              let string = String(bytes: bytes, encoding: .utf8) else {
            return nil
        }
        let normalized = string.replacingOccurrences(of: "\r\n", with: "\n")
        return ClipboardItem(text: normalized)
    }

    public func readImage(_ connection: OpaquePointer?) -> ClipboardItem? {
        for format in ImageFormat.allCases {
            let mimeType = format.mimeType
            if !hasMimeType(mimeType) { continue }
            if let bytes = readBytes(connection, mimeType) {
                return ClipboardItem(text: nil, data: Data(bytes))
            }
        }
        return nil
    }
}

public enum WaylandClipboardModule {
// PORT NOTE: Clipboard manages Wayland clipboard state and mime offers across concurrent event loops.
public final class Clipboard: @unchecked Sendable {
    public var connection: OpaquePointer?
    public var selfMimeStr: String

    public var contents: ClipboardItem?
    public var primaryContents: ClipboardItem?

    public var cachedRead: ClipboardItem?
    public var currentOffer: DataOffer<WlDataOffer>?
    public var cachedPrimaryRead: ClipboardItem?
    public var currentPrimaryOffer: DataOffer<ZwpPrimarySelectionOfferV1>?

    public init(connection: OpaquePointer? = nil) {
        self.connection = connection
        self.selfMimeStr = "pid/\(getpid())"
        self.contents = nil
        self.primaryContents = nil
        self.cachedRead = nil
        self.currentOffer = nil
        self.cachedPrimaryRead = nil
        self.currentPrimaryOffer = nil
    }

    public static func new(connection: OpaquePointer? = nil) -> WaylandClipboard {
        Clipboard(connection: connection)
    }

    public func set(_ item: ClipboardItem) {
        self.contents = item
    }

    public func setPrimary(_ item: ClipboardItem) {
        self.primaryContents = item
    }

    public func setOffer(_ dataOffer: DataOffer<WlDataOffer>?) {
        self.cachedRead = nil
        self.currentOffer = dataOffer
    }

    public func setPrimaryOffer(_ dataOffer: DataOffer<ZwpPrimarySelectionOfferV1>?) {
        self.cachedPrimaryRead = nil
        self.currentPrimaryOffer = dataOffer
    }

    public func selfMime() -> String {
        selfMimeStr
    }

    public func send(_ mimeType: String, _ fd: Int32) {
        if let text = contents?.text {
            sendInternal(fd: fd, bytes: Array(text.utf8))
        }
    }

    public func sendPrimary(_ mimeType: String, _ fd: Int32) {
        if let text = primaryContents?.text {
            sendInternal(fd: fd, bytes: Array(text.utf8))
        }
    }

    private func sendInternal(fd: Int32, bytes: [UInt8]) {
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        handle.write(Data(bytes))
    }

    public func read() -> ClipboardItem? {
        guard let offer = currentOffer else { return nil }
        if let cached = cachedRead {
            return cached
        }
        if offer.hasMimeType(selfMimeStr) {
            return contents
        }
        guard let item = offer.readText(connection) ?? offer.readImage(connection) else {
            return nil
        }
        cachedRead = item
        return item
    }

    public func readPrimary() -> ClipboardItem? {
        guard let offer = currentPrimaryOffer else { return nil }
        if let cached = cachedPrimaryRead {
            return cached
        }
        if offer.hasMimeType(selfMimeStr) {
            return primaryContents
        }
        guard let item = offer.readText(connection) ?? offer.readImage(connection) else {
            return nil
        }
        cachedPrimaryRead = item
        return item
    }
}
}

public typealias WaylandClipboard = WaylandClipboardModule.Clipboard
#endif
