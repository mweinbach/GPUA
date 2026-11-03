// Ported from: crates/rune/src/platform/x11/overlay.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! X11 input SHAPE regions. The visual surface stays intact; only pointer ownership changes.

#if os(Linux)
import CLinuxSys
import Foundation
import Glibc
#endif

func x11PointerPosition() -> (Int32, Int32)? {
    #if os(Linux)
    var screenNum: Int32 = 0
    guard let conn = xcb_connect(nil, &screenNum) else { return nil }
    defer { xcb_disconnect(conn) }
    guard xcb_connection_has_error(conn) == 0, let setup = xcb_get_setup(conn) else { return nil }
    var iter = xcb_setup_roots_iterator(setup)
    for _ in 0..<max(0, screenNum) {
        if iter.rem <= 0 { break }
        xcb_screen_next(&iter)
    }
    guard iter.rem > 0, let screenPtr = iter.data else { return nil }
    var err: UnsafeMutablePointer<xcb_generic_error_t>? = nil
    let cookie = xcb_query_pointer(conn, screenPtr.pointee.root)
    guard let reply = xcb_query_pointer_reply(conn, cookie, &err) else {
        if let err { free(err) }
        return nil
    }
    let same = reply.pointee.same_screen != 0
    let pos = (Int32(reply.pointee.root_x), Int32(reply.pointee.root_y))
    free(reply)
    return same ? pos : nil
    #else
    return nil
    #endif
}

func x11OutputCrtc(_ output: UInt32) -> UInt32? {
    #if os(Linux)
    var screenNum: Int32 = 0
    guard let conn = xcb_connect(nil, &screenNum) else { return nil }
    defer { xcb_disconnect(conn) }
    guard xcb_connection_has_error(conn) == 0 else { return nil }
    var err: UnsafeMutablePointer<xcb_generic_error_t>? = nil
    let cookie = xcb_randr_get_output_info(conn, output, xcb_timestamp_t(XCB_CURRENT_TIME))
    guard let reply = xcb_randr_get_output_info_reply(conn, cookie, &err) else {
        if let err { free(err) }
        return nil
    }
    let crtc = reply.pointee.crtc
    free(reply)
    return crtc != 0 ? crtc : nil
    #else
    _ = output
    return nil
    #endif
}

#if os(Linux)
private struct X11ShapeLib {
    typealias QueryVersionFn = @convention(c) (OpaquePointer?) -> xcb_generic_cookie_t
    typealias QueryVersionReplyFn = @convention(c) (OpaquePointer?, xcb_generic_cookie_t, UnsafeMutablePointer<UnsafeMutablePointer<xcb_generic_error_t>?>?) -> UnsafeMutableRawPointer?
    typealias RectanglesCheckedFn = @convention(c) (OpaquePointer?, UInt8, UInt8, UInt8, xcb_window_t, Int16, Int16, UInt32, UnsafePointer<xcb_rectangle_t>?) -> xcb_void_cookie_t
    typealias MaskCheckedFn = @convention(c) (OpaquePointer?, UInt8, UInt8, xcb_window_t, Int16, Int16, xcb_pixmap_t) -> xcb_void_cookie_t

    let queryVersion: QueryVersionFn
    let queryVersionReply: QueryVersionReplyFn
    let rectanglesChecked: RectanglesCheckedFn
    let maskChecked: MaskCheckedFn

    static func load() -> X11ShapeLib? {
        guard let handle = dlopen("libxcb-shape.so.0", RTLD_LAZY) ?? dlopen("libxcb-shape.so", RTLD_LAZY),
              let qv = dlsym(handle, "xcb_shape_query_version"),
              let qvr = dlsym(handle, "xcb_shape_query_version_reply"),
              let rc = dlsym(handle, "xcb_shape_rectangles_checked"),
              let mc = dlsym(handle, "xcb_shape_mask_checked")
        else {
            return nil
        }
        return X11ShapeLib(
            queryVersion: unsafeBitCast(qv, to: QueryVersionFn.self),
            queryVersionReply: unsafeBitCast(qvr, to: QueryVersionReplyFn.self),
            rectanglesChecked: unsafeBitCast(rc, to: RectanglesCheckedFn.self),
            maskChecked: unsafeBitCast(mc, to: MaskCheckedFn.self)
        )
    }
}

func x11CheckShapeVersion(_ conn: OpaquePointer) -> Bool {
    guard let shape = X11ShapeLib.load() else { return false }
    var err: UnsafeMutablePointer<xcb_generic_error_t>? = nil
    let cookie = shape.queryVersion(conn)
    guard let rawReply = shape.queryVersionReply(conn, cookie, &err) else {
        if let err { free(err) }
        return false
    }
    // `xcb_shape_query_version_reply_t`: response_type(1), pad0(1), sequence(2), length(4), major_version(2), minor_version(2).
    let major = rawReply.load(fromByteOffset: 8, as: UInt16.self)
    let minor = rawReply.load(fromByteOffset: 10, as: UInt16.self)
    free(rawReply)
    return (major > 1) || (major == 1 && minor >= 1)
}

func x11ShapeSetRectangles(_ conn: OpaquePointer, window: UInt32, rects: [xcb_rectangle_t]) -> Bool {
    guard let shape = X11ShapeLib.load() else { return false }
    let cookie = rects.withUnsafeBufferPointer { buf in
        // SO::SET = 0, SK::INPUT = 2, ClipOrdering::UNSORTED = 0
        shape.rectanglesChecked(conn, 0, 2, 0, window, 0, 0, UInt32(buf.count), buf.baseAddress)
    }
    if let err = xcb_request_check(conn, cookie) {
        free(err)
        return false
    }
    return true
}

func x11ShapeClearMask(_ conn: OpaquePointer, window: UInt32) -> Bool {
    guard let shape = X11ShapeLib.load() else { return false }
    // SO::SET = 0, SK::INPUT = 2, XCB_NONE = 0
    let cookie = shape.maskChecked(conn, 0, 2, window, 0, 0, 0)
    if let err = xcb_request_check(conn, cookie) {
        free(err)
        return false
    }
    return true
}

private let x11ShownLock = LiveLock()
// PORT NOTE: Guarded by `x11ShownLock` on the window thread (matching `thread_local! SHOWN` in `platform/x11/overlay.rs`).
nonisolated(unsafe) private var x11ShownWindows: [(UInt32, OverlayLevel)] = []

final class X11InputWindow {
    private var watch: X11MouseWatch? = nil
    private let wake: Waker?
    private var visible: Bool = false
    private var follow: Bool
    private var input: OverlayInput
    private let connection: OpaquePointer
    private let root: UInt32
    private let window: UInt32
    private var last: [xcb_rectangle_t]? = nil

    private init(connection: OpaquePointer, root: UInt32, window: UInt32, wake: Waker?, input: OverlayInput, follow: Bool) {
        self.connection = connection
        self.root = root
        self.window = window
        self.wake = wake
        self.input = input
        self.follow = follow
    }

    static func create(windowId: UInt32, wake: Waker?, input: OverlayInput, follow: Bool) -> X11InputWindow? {
        var screenNum: Int32 = 0
        guard let conn = xcb_connect(nil, &screenNum) else { return nil }
        guard xcb_connection_has_error(conn) == 0,
              x11CheckShapeVersion(conn),
              let setup = xcb_get_setup(conn)
        else {
            xcb_disconnect(conn)
            return nil
        }
        var iter = xcb_setup_roots_iterator(setup)
        for _ in 0..<max(0, screenNum) {
            if iter.rem <= 0 { break }
            xcb_screen_next(&iter)
        }
        guard iter.rem > 0, let screenPtr = iter.data else {
            xcb_disconnect(conn)
            return nil
        }
        return X11InputWindow(
            connection: conn,
            root: screenPtr.pointee.root,
            window: windowId,
            wake: wake,
            input: input,
            follow: follow
        )
    }

    func show(_ level: OverlayLevel) {
        visible = true
        refreshWatch()
        let win = window
        let windows = x11ShownLock.withLock { () -> [(UInt32, OverlayLevel)] in
            x11ShownWindows.removeAll { $0.0 == win }
            x11ShownWindows.append((win, level))
            return x11ShownWindows
        }
        var values: [UInt32] = [UInt32(XCB_STACK_MODE_ABOVE.rawValue)]
        for lvl in [OverlayLevel.status, .aboveStatus, .aboveOverlays] {
            for (wid, at) in windows where at == lvl {
                _ = values.withUnsafeBufferPointer { buf in
                    xcb_configure_window(connection, wid, UInt16(XCB_CONFIG_WINDOW_STACK_MODE.rawValue), buf.baseAddress)
                }
            }
        }
        _ = xcb_flush(connection)
    }

    func hide() {
        visible = false
        watch = nil
        let win = window
        x11ShownLock.withLock {
            x11ShownWindows.removeAll { $0.0 == win }
        }
    }

    func globalPointer() -> OverlaySupport {
        if input != .regions && !follow { return .supported }
        return (watch?.supported() == true) ? .supported : .failed
    }

    func setFollowPointer(_ nextFollow: Bool) {
        follow = nextFollow
        refreshWatch()
    }

    private func refreshWatch() {
        if visible && (input == .regions || follow) {
            if watch == nil {
                watch = X11MouseWatch.create(wake)
            }
            updateGeometry()
        } else {
            watch = nil
        }
    }

    func updateGeometry() {
        guard let watch else { return }
        var trErr: UnsafeMutablePointer<xcb_generic_error_t>? = nil
        let trCookie = xcb_translate_coordinates(connection, window, root, 0, 0)
        guard let trReply = xcb_translate_coordinates_reply(connection, trCookie, &trErr) else {
            if let trErr { free(trErr) }
            return
        }
        let dstX = Int32(trReply.pointee.dst_x)
        let dstY = Int32(trReply.pointee.dst_y)
        free(trReply)

        var geoErr: UnsafeMutablePointer<xcb_generic_error_t>? = nil
        let geoCookie = xcb_get_geometry(connection, window)
        guard let geoReply = xcb_get_geometry_reply(connection, geoCookie, &geoErr) else {
            if let geoErr { free(geoErr) }
            return
        }
        let w = Int32(geoReply.pointee.width)
        let h = Int32(geoReply.pointee.height)
        free(geoReply)

        watch.geometry([dstX, dstY, dstX + w, dstY + h], follow)
    }

    func setInput(_ nextInput: OverlayInput) {
        input = nextInput
        refreshWatch()
        last = nil
        switch nextInput {
        case .all:
            _ = x11ShapeClearMask(connection, window: window)
        case .none:
            regions([], scale: 1.0)
        default:
            break
        }
    }

    func takePointer(scale: Float) -> ((Float, Float), (Int32, Int32))? {
        guard let desktop = watch?.take() else { return nil }
        var trErr: UnsafeMutablePointer<xcb_generic_error_t>? = nil
        let trCookie = xcb_translate_coordinates(connection, window, root, 0, 0)
        guard let trReply = xcb_translate_coordinates_reply(connection, trCookie, &trErr) else {
            if let trErr { free(trErr) }
            return nil
        }
        let dstX = Int32(trReply.pointee.dst_x)
        let dstY = Int32(trReply.pointee.dst_y)
        free(trReply)
        return ((Float(desktop.0 - dstX) / scale, Float(desktop.1 - dstY) / scale), desktop)
    }

    func regions(_ rects: [[Float]], scale: Float) {
        var xcbRects: [xcb_rectangle_t] = []
        xcbRects.reserveCapacity(rects.count)
        for r in rects where r.count >= 4 {
            let x = Int16(min(max((r[0] * scale).rounded(.down), 0.0), Float(Int16.max)))
            let y = Int16(min(max((r[1] * scale).rounded(.down), 0.0), Float(Int16.max)))
            let w = UInt16(min(max((r[2] * scale).rounded(.up) - Float(x), 0.0), Float(UInt16.max)))
            let h = UInt16(min(max((r[3] * scale).rounded(.up) - Float(y), 0.0), Float(UInt16.max)))
            if w > 0 && h > 0 {
                xcbRects.append(xcb_rectangle_t(x: x, y: y, width: w, height: h))
            }
        }
        if let last, last.count == xcbRects.count,
           zip(last, xcbRects).allSatisfy({ $0.x == $1.x && $0.y == $1.y && $0.width == $1.width && $0.height == $1.height })
        {
            return
        }
        if x11ShapeSetRectangles(connection, window: window, rects: xcbRects) {
            last = xcbRects
        }
    }

    deinit {
        hide()
        xcb_disconnect(connection)
    }
}
#endif
