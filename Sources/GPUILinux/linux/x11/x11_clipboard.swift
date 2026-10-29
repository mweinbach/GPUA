// Ported from: crates/gpui_linux/src/linux/x11/clipboard.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(Linux)
import Foundation
import GPUI
import CLinuxSys
import Glibc

public enum ClipboardKind: Sendable, Hashable {
    case clipboard
    case primary
    case secondary
}

public enum WaitConfig: Sendable, Hashable {
    case wait
    case noWait
}

public enum Error: Swift.Error, CustomStringConvertible, Sendable {
    case unknownError(String)
    case unsupported
    case timeout

    public var description: String {
        switch self {
        case .unknownError(let msg): return "Clipboard error: \(msg)"
        case .unsupported: return "Clipboard unsupported"
        case .timeout: return "Clipboard timeout"
        }
    }

    public static func unknown(_ message: String) -> Error {
        .unknownError(message)
    }
}

public enum X11ClipboardModule {
// PORT NOTE: ServerConnectionBox safely owns the XCB connection lifecycle across the detached server thread and Clipboard deinit.
final class ServerConnectionBox: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var conn: OpaquePointer?
    private(set) var win: UInt32
    private(set) var ownsConnection: Bool
    private(set) var isStopped: Bool = false
    private(set) var hasServerThread: Bool = false

    init(conn: OpaquePointer?, win: UInt32, ownsConnection: Bool) {
        self.conn = conn
        self.win = win
        self.ownsConnection = ownsConnection
    }

    func update(conn: OpaquePointer?, win: UInt32, ownsConnection: Bool) {
        lock.lock()
        defer { lock.unlock() }
        self.conn = conn
        self.win = win
        self.ownsConnection = ownsConnection
    }

    func setOwnsConnection(_ owns: Bool) {
        lock.lock()
        defer { lock.unlock() }
        self.ownsConnection = owns
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }
        isStopped = true
    }

    var stopped: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isStopped
    }

    func markServerThreadStarted() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if hasServerThread { return false }
        hasServerThread = true
        return true
    }

    func closeIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        if ownsConnection, let c = conn {
            if win != 0 {
                xcb_destroy_window(c, win)
                xcb_flush(c)
                win = 0
            }
            xcb_disconnect(c)
            conn = nil
            ownsConnection = false
        }
    }

    deinit {
        closeIfNeeded()
    }
}

// PORT NOTE: Clipboard manages X11 selection storage and protocol interactions.
public final class Clipboard: @unchecked Sendable {
    private let lock = NSLock()
    private let connectionBox: ServerConnectionBox
    private var storage: [ClipboardKind: ClipboardItem] = [:]
    private var isOwnerMap: [ClipboardKind: Bool] = [:]
    private var rootWin: UInt32 = 0

    public var serverConn: OpaquePointer? {
        connectionBox.conn
    }
    public var serverWin: UInt32 {
        connectionBox.win
    }
    public var ownsConnection: Bool {
        get { connectionBox.ownsConnection }
        set { connectionBox.setOwnsConnection(newValue) }
    }

    // Cached Atoms
    public private(set) var atomClipboard: UInt32 = 0
    public private(set) var atomPrimary: UInt32 = 0
    public private(set) var atomSecondary: UInt32 = 0
    public private(set) var atomTargets: UInt32 = 0
    public private(set) var atomUtf8String: UInt32 = 0
    public private(set) var atomTextPlain: UInt32 = 0
    public private(set) var atomTextPlainUtf8: UInt32 = 0
    public private(set) var atomString: UInt32 = 0
    public private(set) var atomText: UInt32 = 0
    public private(set) var atomAtom: UInt32 = 0
    public private(set) var atomClipboardProp: UInt32 = 0

    public init(
        connection: OpaquePointer? = nil,
        window: UInt32 = 0,
        rootWindow: UInt32 = 0,
        ownsConnection: Bool = false
    ) {
        self.connectionBox = ServerConnectionBox(conn: connection, win: window, ownsConnection: ownsConnection)
        self.rootWin = rootWindow
        if let conn = connection {
            self.initAtoms(conn: conn)
            if ownsConnection {
                self.startServerLoop()
            }
        }
    }

    public static func openXcbClipboardConnection() throws -> (conn: OpaquePointer, win: UInt32, root: UInt32) {
        var screenNum: Int32 = 0
        guard let conn = xcb_connect(nil, &screenNum) else {
            throw Error.unknown("Failed to connect to X11 server for clipboard")
        }
        if xcb_connection_has_error(conn) != 0 {
            xcb_disconnect(conn)
            throw Error.unknown("X11 connection error for clipboard")
        }
        let setup = xcb_get_setup(conn)
        var iter = xcb_setup_roots_iterator(setup)
        for _ in 0..<screenNum {
            xcb_screen_next(&iter)
        }
        let root = iter.data.pointee.root
        let win = xcb_generate_id(conn)
        let mask = UInt32(XCB_CW_EVENT_MASK.rawValue)
        let values: [UInt32] = [UInt32(XCB_EVENT_MASK_PROPERTY_CHANGE.rawValue | XCB_EVENT_MASK_STRUCTURE_NOTIFY.rawValue)]
        _ = values.withUnsafeBufferPointer { buf in
            xcb_create_window(
                conn,
                0,
                win,
                root,
                0, 0, 1, 1, 0,
                UInt16(XCB_WINDOW_CLASS_INPUT_ONLY.rawValue),
                0,
                mask,
                buf.baseAddress
            )
        }
        xcb_flush(conn)
        return (conn, win, root)
    }

    public convenience init() {
        if let (conn, win, root) = try? Clipboard.openXcbClipboardConnection() {
            self.init(
                connection: conn,
                window: win,
                rootWindow: root,
                ownsConnection: true
            )
        } else {
            self.init(connection: nil, window: 0, rootWindow: 0, ownsConnection: false)
        }
    }

    deinit {
        connectionBox.stop()
        if !connectionBox.hasServerThread {
            connectionBox.closeIfNeeded()
        }
    }

    public static func new() throws -> Clipboard {
        let (conn, win, root) = try openXcbClipboardConnection()
        return Clipboard(connection: conn, window: win, rootWindow: root, ownsConnection: true)
    }

    private func ensureConnected() {
        if connectionBox.conn == nil {
            if let (conn, win, root) = try? Clipboard.openXcbClipboardConnection() {
                self.connectionBox.update(conn: conn, win: win, ownsConnection: true)
                self.rootWin = root
                self.initAtoms(conn: conn)
                self.startServerLoop()
            }
        }
    }

    private func initAtoms(conn: OpaquePointer) {
        self.atomClipboard = internAtom(conn: conn, name: "CLIPBOARD")
        self.atomPrimary = internAtom(conn: conn, name: "PRIMARY")
        self.atomSecondary = internAtom(conn: conn, name: "SECONDARY")
        self.atomTargets = internAtom(conn: conn, name: "TARGETS")
        self.atomUtf8String = internAtom(conn: conn, name: "UTF8_STRING")
        self.atomTextPlain = internAtom(conn: conn, name: "text/plain")
        self.atomTextPlainUtf8 = internAtom(conn: conn, name: "text/plain;charset=utf-8")
        self.atomString = internAtom(conn: conn, name: "STRING")
        self.atomText = internAtom(conn: conn, name: "TEXT")
        self.atomAtom = internAtom(conn: conn, name: "ATOM")
        self.atomClipboardProp = internAtom(conn: conn, name: "GPUA_CLIPBOARD_PROP")
    }

    private func internAtom(conn: OpaquePointer, name: String) -> UInt32 {
        name.withCString { cStr in
            let cookie = xcb_intern_atom(conn, 0, UInt16(name.utf8.count), cStr)
            if let reply = xcb_intern_atom_reply(conn, cookie, nil) {
                defer { free(reply) }
                return reply.pointee.atom
            }
            return 0
        }
    }

    public func atomFor(kind: ClipboardKind) -> UInt32 {
        switch kind {
        case .clipboard: return atomClipboard
        case .primary: return atomPrimary
        case .secondary: return atomSecondary
        }
    }

    public func kindFor(atom: UInt32) -> ClipboardKind? {
        if atom == atomClipboard { return .clipboard }
        if atom == atomPrimary { return .primary }
        if atom == atomSecondary { return .secondary }
        return nil
    }

    public func setText(
        _ message: String,
        selection: ClipboardKind = .clipboard,
        wait: WaitConfig = .noWait
    ) throws {
        lock.lock()
        defer { lock.unlock() }

        ensureConnected()
        guard let conn = serverConn, serverWin != 0 else {
            storage[selection] = ClipboardItem(text: message)
            isOwnerMap[selection] = true
            return
        }

        storage[selection] = ClipboardItem(text: message)
        let atom = atomFor(kind: selection)
        xcb_set_selection_owner(conn, serverWin, atom, UInt32(XCB_CURRENT_TIME))
        xcb_flush(conn)

        let cookie = xcb_get_selection_owner(conn, atom)
        if let reply = xcb_get_selection_owner_reply(conn, cookie, nil) {
            let owner = reply.pointee.owner
            free(reply)
            isOwnerMap[selection] = (owner == serverWin)
        } else {
            isOwnerMap[selection] = true
        }
    }

    public func setImage(
        _ image: Image,
        selection: ClipboardKind = .clipboard,
        wait: WaitConfig = .noWait
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        ensureConnected()
        storage[selection] = ClipboardItem(text: "")
        isOwnerMap[selection] = true
    }

    public func isOwner(selection: ClipboardKind = .clipboard) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let conn = serverConn, serverWin != 0 else {
            return isOwnerMap[selection] ?? false
        }
        let atom = atomFor(kind: selection)
        let cookie = xcb_get_selection_owner(conn, atom)
        if let reply = xcb_get_selection_owner_reply(conn, cookie, nil) {
            defer { free(reply) }
            let owner = reply.pointee.owner
            let ours = (owner == serverWin)
            isOwnerMap[selection] = ours
            return ours
        }
        return isOwnerMap[selection] ?? false
    }

    public func getAny(selection: ClipboardKind = .clipboard) throws -> ClipboardItem {
        // Fast path: if local window owns the selection, return directly from cache
        if isOwner(selection: selection) {
            lock.lock()
            defer { lock.unlock() }
            return storage[selection] ?? ClipboardItem(text: "")
        }

        // Slow path: convert selection over X11 server from current owner
        var screenNum: Int32 = 0
        guard let readerConn = xcb_connect(nil, &screenNum) else {
            throw Error.unknown("Failed to connect to X11 server for clipboard read")
        }
        defer { xcb_disconnect(readerConn) }

        let setup = xcb_get_setup(readerConn)
        var iter = xcb_setup_roots_iterator(setup)
        for _ in 0..<screenNum {
            xcb_screen_next(&iter)
        }
        let root = iter.data.pointee.root
        let readerWin = xcb_generate_id(readerConn)
        let mask = UInt32(XCB_CW_EVENT_MASK.rawValue)
        let values: [UInt32] = [UInt32(XCB_EVENT_MASK_PROPERTY_CHANGE.rawValue)]
        _ = values.withUnsafeBufferPointer { buf in
            xcb_create_window(
                readerConn,
                0,
                readerWin,
                root,
                0, 0, 1, 1, 0,
                UInt16(XCB_WINDOW_CLASS_INPUT_ONLY.rawValue),
                0,
                mask,
                buf.baseAddress
            )
        }
        defer {
            xcb_destroy_window(readerConn, readerWin)
            xcb_flush(readerConn)
        }

        let selAtom = atomFor(kind: selection) != 0 ? atomFor(kind: selection) : internAtom(conn: readerConn, name: selection == .primary ? "PRIMARY" : "CLIPBOARD")
        let targetAtom = atomUtf8String != 0 ? atomUtf8String : internAtom(conn: readerConn, name: "UTF8_STRING")
        let propAtom = atomClipboardProp != 0 ? atomClipboardProp : internAtom(conn: readerConn, name: "GPUA_CLIPBOARD_PROP")

        xcb_delete_property(readerConn, readerWin, propAtom)
        xcb_convert_selection(
            readerConn,
            readerWin,
            selAtom,
            targetAtom,
            propAtom,
            UInt32(XCB_CURRENT_TIME)
        )
        xcb_flush(readerConn)

        let deadline = Date().addingTimeInterval(2.0)
        while Date() < deadline {
            if let eventPtr = xcb_poll_for_event(readerConn) {
                defer { free(eventPtr) }
                let responseType = eventPtr.pointee.response_type & ~0x80
                if Int32(responseType) == XCB_SELECTION_NOTIFY {
                    let ev = eventPtr.withMemoryRebound(to: xcb_selection_notify_event_t.self, capacity: 1) { $0.pointee }
                    if ev.property != 0 {
                        let cookie = xcb_get_property(
                            readerConn,
                            1,
                            readerWin,
                            ev.property,
                            UInt32(XCB_ATOM_ANY.rawValue),
                            0,
                            UInt32.max
                        )
                        if let reply = xcb_get_property_reply(readerConn, cookie, nil) {
                            defer { free(reply) }
                            let len = Int(xcb_get_property_value_length(reply))
                            if len > 0, let valPtr = xcb_get_property_value(reply) {
                                let bytes = valPtr.bindMemory(to: UInt8.self, capacity: len)
                                let data = Data(bytes: bytes, count: len)
                                if let str = String(data: data, encoding: .utf8) {
                                    return ClipboardItem(text: str)
                                }
                            }
                        }
                    }
                    return ClipboardItem(text: "")
                }
            }
            usleep(1000)
        }

        return ClipboardItem(text: "")
    }

    public func handleSelectionRequest(_ ev: xcb_selection_request_event_t, connection: OpaquePointer?) {
        guard let conn = connection ?? serverConn else { return }
        lock.lock()
        defer { lock.unlock() }

        guard let kind = kindFor(atom: ev.selection) else {
            sendSelectionNotify(conn: conn, ev: ev, property: 0)
            return
        }

        if ev.target == atomTargets {
            let targets: [UInt32] = [
                atomTargets,
                atomUtf8String,
                atomTextPlain,
                atomTextPlainUtf8,
                atomString,
                atomText
            ].filter { $0 != 0 }

            _ = targets.withUnsafeBufferPointer { buf in
                xcb_change_property(
                    conn,
                    UInt8(XCB_PROP_MODE_REPLACE.rawValue),
                    ev.requestor,
                    ev.property,
                    atomAtom != 0 ? atomAtom : UInt32(XCB_ATOM_ATOM.rawValue),
                    32,
                    UInt32(buf.count),
                    buf.baseAddress
                )
            }
            sendSelectionNotify(conn: conn, ev: ev, property: ev.property)
        } else if ev.target == atomUtf8String ||
                    ev.target == atomTextPlain ||
                    ev.target == atomTextPlainUtf8 ||
                    ev.target == atomString ||
                    ev.target == atomText {
            let text = storage[kind]?.text ?? ""
            _ = text.withCString { cStr in
                xcb_change_property(
                    conn,
                    UInt8(XCB_PROP_MODE_REPLACE.rawValue),
                    ev.requestor,
                    ev.property,
                    ev.target,
                    8,
                    UInt32(text.utf8.count),
                    cStr
                )
            }
            sendSelectionNotify(conn: conn, ev: ev, property: ev.property)
        } else {
            sendSelectionNotify(conn: conn, ev: ev, property: 0)
        }
    }

    private func sendSelectionNotify(conn: OpaquePointer, ev: xcb_selection_request_event_t, property: UInt32) {
        var notify = xcb_selection_notify_event_t()
        notify.response_type = UInt8(XCB_SELECTION_NOTIFY)
        notify.sequence = ev.sequence
        notify.time = ev.time
        notify.requestor = ev.requestor
        notify.selection = ev.selection
        notify.target = ev.target
        notify.property = property

        _ = withUnsafePointer(to: &notify) { ptrMsg in
            ptrMsg.withMemoryRebound(to: CChar.self, capacity: MemoryLayout<xcb_selection_notify_event_t>.size) { charPtr in
                xcb_send_event(conn, 0, ev.requestor, 0, charPtr)
            }
        }
        xcb_flush(conn)
    }

    public func handleSelectionClear(_ ev: xcb_selection_clear_event_t) {
        lock.lock()
        defer { lock.unlock() }
        if let kind = kindFor(atom: ev.selection) {
            isOwnerMap[kind] = false
            storage[kind] = nil
        }
    }

    private func startServerLoop() {
        guard let conn = connectionBox.conn else { return }
        guard connectionBox.markServerThreadStarted() else { return }
        let fd = xcb_get_file_descriptor(conn)
        let box = connectionBox
        Thread.detachNewThread { [weak self, box] in
            guard let workerConn = box.conn else { return }
            while true {
                guard let self = self, !box.stopped else {
                    box.closeIfNeeded()
                    return
                }
                var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
                let pollRes = poll(&pfd, 1, 10)
                if pollRes > 0 {
                    while let eventPtr = xcb_poll_for_event(workerConn) {
                        defer { free(eventPtr) }
                        let responseType = eventPtr.pointee.response_type & ~0x80
                        if Int32(responseType) == XCB_SELECTION_REQUEST {
                            let ev = eventPtr.withMemoryRebound(to: xcb_selection_request_event_t.self, capacity: 1) { $0.pointee }
                            self.handleSelectionRequest(ev, connection: workerConn)
                        } else if Int32(responseType) == XCB_SELECTION_CLEAR {
                            let ev = eventPtr.withMemoryRebound(to: xcb_selection_clear_event_t.self, capacity: 1) { $0.pointee }
                            self.handleSelectionClear(ev)
                        } else if Int32(responseType) == XCB_DESTROY_NOTIFY {
                            box.closeIfNeeded()
                            return
                        }
                    }
                }
            }
        }
    }
}
}

public typealias X11Clipboard = X11ClipboardModule.Clipboard
#endif
