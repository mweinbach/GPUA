// Ported from: crates/rune/src/platform/x11/xwayland.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! An overlay on XWayland, for a Wayland compositor without layer-shell (GNOME's Mutter): an
//! override-redirect ARGB window of the notification type on its own libxcb connection, with
//! an empty input shape, so it never takes focus or a click.

/// Parses `Xft.dpi` from the X11 `RESOURCE_MANAGER` string database as a scale; `1.0` when unset.
func parseXftScale(_ resourceManager: String) -> Float {
    for line in resourceManager.split(whereSeparator: \.isNewline) {
        if line.hasPrefix("Xft.dpi:") {
            let tail = line.dropFirst("Xft.dpi:".count)
            let trimmed = tail.drop { $0 == " " || $0 == "\t" }
            let endIdx = trimmed.firstIndex { $0 == " " || $0 == "\t" } ?? trimmed.endIndex
            if let dpi = Float(trimmed[..<endIdx]) {
                return min(max(dpi / 96.0, 1.0), 4.0)
            }
        }
    }
    return 1.0
}

#if os(Linux)
import CLinuxSys
import Foundation
import Glibc

final class XwaylandSurface {
    private let connection: OpaquePointer
    private let screen: Int32
    private let root: UInt32
    private var window: UInt32
    private let colormap: UInt32
    private let scaleFactor: Float

    private init(connection: OpaquePointer, screen: Int32, root: UInt32, window: UInt32, colormap: UInt32, scale: Float) {
        self.connection = connection
        self.screen = screen
        self.root = root
        self.window = window
        self.colormap = colormap
        self.scaleFactor = scale
    }

    static func create(name: String, at placement: OverlayPlacementSpec, options: OverlayOptions) -> XwaylandSurface? {
        guard let displayEnv = ProcessInfo.processInfo.environment["DISPLAY"], !displayEnv.isEmpty else {
            return nil
        }
        var screenNum: Int32 = 0
        guard let conn = xcb_connect(nil, &screenNum) else { return nil }
        guard xcb_connection_has_error(conn) == 0,
              x11CheckShapeVersion(conn),
              let setup = xcb_get_setup(conn)
        else {
            xcb_disconnect(conn)
            return nil
        }
        var rootIter = xcb_setup_roots_iterator(setup)
        for _ in 0..<max(0, screenNum) {
            if rootIter.rem <= 0 { break }
            xcb_screen_next(&rootIter)
        }
        guard rootIter.rem > 0, let rootScreen = rootIter.data else {
            xcb_disconnect(conn)
            return nil
        }
        let root = rootScreen.pointee.root

        var visualId: UInt32? = nil
        var depthIter = xcb_screen_allowed_depths_iterator(rootScreen)
        while depthIter.rem > 0 && visualId == nil {
            if let depthPtr = depthIter.data, depthPtr.pointee.depth == 32 {
                var visIter = xcb_depth_visuals_iterator(depthPtr)
                while visIter.rem > 0 {
                    if let vis = visIter.data?.pointee, vis._class == UInt8(XCB_VISUAL_CLASS_TRUE_COLOR.rawValue) {
                        visualId = vis.visual_id
                        break
                    }
                    xcb_visualtype_next(&visIter)
                }
            }
            xcb_depth_next(&depthIter)
        }
        guard let visual = visualId else {
            xcb_disconnect(conn)
            return nil
        }

        let scale = queryXftScale(conn, root: root)
        let cmap = xcb_generate_id(conn)
        let cmapCookie = xcb_create_colormap_checked(conn, UInt8(XCB_COLORMAP_ALLOC_NONE.rawValue), cmap, root, visual)
        if let err = xcb_request_check(conn, cmapCookie) {
            free(err)
            xcb_disconnect(conn)
            return nil
        }

        let wid = xcb_generate_id(conn)
        let surface = XwaylandSurface(connection: conn, screen: screenNum, root: root, window: 0, colormap: cmap, scale: scale)
        guard let (x, y, w, h) = surface.rect(at: placement, options: options) else {
            return nil
        }

        // Value mask order per X11 CreateWindow: BACK_PIXEL (2), BORDER_PIXEL (8), OVERRIDE_REDIRECT (512), COLORMAP (8192).
        let mask = UInt32(XCB_CW_BACK_PIXEL.rawValue)
            | UInt32(XCB_CW_BORDER_PIXEL.rawValue)
            | UInt32(XCB_CW_OVERRIDE_REDIRECT.rawValue)
            | UInt32(XCB_CW_COLORMAP.rawValue)
        let values: [UInt32] = [0, 0, 1, cmap]
        let createCookie = values.withUnsafeBufferPointer { buf in
            xcb_create_window_checked(
                conn,
                32,
                wid,
                root,
                x,
                y,
                w,
                h,
                0,
                UInt16(XCB_WINDOW_CLASS_INPUT_OUTPUT.rawValue),
                visual,
                mask,
                buf.baseAddress
            )
        }
        if let err = xcb_request_check(conn, createCookie) {
            free(err)
            return nil
        }
        surface.window = wid

        guard let kindAtom = internAtom(conn, "_NET_WM_WINDOW_TYPE"),
              let notifAtom = internAtom(conn, "_NET_WM_WINDOW_TYPE_NOTIFICATION")
        else {
            return nil
        }
        var notifVal = notifAtom
        _ = withUnsafePointer(to: &notifVal) { ptr in
            xcb_change_property(conn, UInt8(XCB_PROP_MODE_REPLACE.rawValue), wid, kindAtom, xcb_atom_t(XCB_ATOM_ATOM.rawValue), 32, 1, ptr)
        }
        let nameBytes = Array(name.utf8)
        _ = nameBytes.withUnsafeBufferPointer { buf in
            xcb_change_property(conn, UInt8(XCB_PROP_MODE_REPLACE.rawValue), wid, xcb_atom_t(XCB_ATOM_WM_NAME.rawValue), xcb_atom_t(XCB_ATOM_STRING.rawValue), 8, UInt32(buf.count), buf.baseAddress)
        }
        let appId = currentAppId() ?? name
        let classBytes = Array(appId.utf8) + [0] + Array(appId.utf8) + [0]
        _ = classBytes.withUnsafeBufferPointer { buf in
            xcb_change_property(conn, UInt8(XCB_PROP_MODE_REPLACE.rawValue), wid, xcb_atom_t(XCB_ATOM_WM_CLASS.rawValue), xcb_atom_t(XCB_ATOM_STRING.rawValue), 8, UInt32(buf.count), buf.baseAddress)
        }
        guard x11ShapeSetRectangles(conn, window: wid, rects: []) else {
            return nil
        }
        _ = xcb_map_window(conn, wid)
        let stackVals: [UInt32] = [UInt32(XCB_STACK_MODE_ABOVE.rawValue)]
        _ = stackVals.withUnsafeBufferPointer { buf in
            xcb_configure_window(conn, wid, UInt16(XCB_CONFIG_WINDOW_STACK_MODE.rawValue), buf.baseAddress)
        }
        guard xcb_flush(conn) > 0 else { return nil }
        return surface
    }

    func scale() -> Float { scaleFactor }

    func place(at placement: OverlayPlacementSpec, options: OverlayOptions) {
        guard let (x, y, w, h) = rect(at: placement, options: options) else { return }
        let mask = UInt16(XCB_CONFIG_WINDOW_X.rawValue)
            | UInt16(XCB_CONFIG_WINDOW_Y.rawValue)
            | UInt16(XCB_CONFIG_WINDOW_WIDTH.rawValue)
            | UInt16(XCB_CONFIG_WINDOW_HEIGHT.rawValue)
            | UInt16(XCB_CONFIG_WINDOW_STACK_MODE.rawValue)
        let vals: [UInt32] = [
            UInt32(bitPattern: Int32(x)),
            UInt32(bitPattern: Int32(y)),
            UInt32(w),
            UInt32(h),
            UInt32(XCB_STACK_MODE_ABOVE.rawValue),
        ]
        _ = vals.withUnsafeBufferPointer { buf in
            xcb_configure_window(connection, window, mask, buf.baseAddress)
        }
        _ = xcb_flush(connection)
    }

    func drain() {
        while let ev = xcb_poll_for_event(connection) {
            free(ev)
        }
    }

    func rawXcbHandles() -> (OpaquePointer, Int32, UInt32)? {
        guard window != 0 else { return nil }
        return (connection, screen, window)
    }

    private func rect(at placement: OverlayPlacementSpec, options: OverlayOptions) -> (Int16, Int16, UInt16, UInt16)? {
        var monErr: UnsafeMutablePointer<xcb_generic_error_t>? = nil
        let cookie = xcb_randr_get_monitors(connection, root, 1)
        guard let reply = xcb_randr_get_monitors_reply(connection, cookie, &monErr) else {
            if let monErr { free(monErr) }
            return nil
        }
        defer { free(reply) }
        var monitors: [xcb_randr_monitor_info_t] = []
        var bounds: [[Double]] = []
        var primaryIdx: Int? = nil
        var iter = xcb_randr_get_monitors_monitors_iterator(reply)
        while iter.rem > 0 {
            if let m = iter.data?.pointee {
                if m.primary != 0 && primaryIdx == nil {
                    primaryIdx = monitors.count
                }
                monitors.append(m)
                let mx = Double(m.x)
                let my = Double(m.y)
                bounds.append([mx, my, mx + Double(m.width), my + Double(m.height)])
            }
            xcb_randr_monitor_info_next(&iter)
        }
        let pointer: (Double, Double)?
        if options.display == .underPointer {
            var ptrErr: UnsafeMutablePointer<xcb_generic_error_t>? = nil
            let ptrCookie = xcb_query_pointer(connection, root)
            if let ptrReply = xcb_query_pointer_reply(connection, ptrCookie, &ptrErr) {
                let same = ptrReply.pointee.same_screen != 0
                let rx = Double(ptrReply.pointee.root_x)
                let ry = Double(ptrReply.pointee.root_y)
                free(ptrReply)
                pointer = same ? (rx, ry) : nil
            } else {
                if let ptrErr { free(ptrErr) }
                pointer = nil
            }
        } else {
            pointer = nil
        }
        guard let idx = overlayChooseDisplay(bounds, primaryIdx, nil, pointer) else {
            return nil
        }
        let mon = monitors[idx]
        let s = scaleFactor
        let area = (Float(mon.width) / s, Float(mon.height) / s)
        let r = overlayLocalRect(placement, options.placement, area)
        let px: (Float) -> Float = { ($0 * s).rounded() }
        let x = Int16(min(max(Float(mon.x) + px(r[0]), Float(Int16.min)), Float(Int16.max)))
        let y = Int16(min(max(Float(mon.y) + px(r[1]), Float(Int16.min)), Float(Int16.max)))
        let w = UInt16(min(max(px(r[2]), 1.0), Float(UInt16.max)))
        let h = UInt16(min(max(px(r[3]), 1.0), Float(UInt16.max)))
        return (x, y, w, h)
    }

    deinit {
        if window != 0 {
            _ = xcb_destroy_window(connection, window)
        }
        _ = xcb_free_colormap(connection, colormap)
        _ = xcb_flush(connection)
        xcb_disconnect(connection)
    }
}

private func internAtom(_ conn: OpaquePointer, _ name: String) -> UInt32? {
    let bytes = Array(name.utf8)
    var err: UnsafeMutablePointer<xcb_generic_error_t>? = nil
    let cookie = bytes.withUnsafeBufferPointer { buf in
        buf.baseAddress!.withMemoryRebound(to: CChar.self, capacity: buf.count) { cPtr in
            xcb_intern_atom(conn, 0, UInt16(buf.count), cPtr)
        }
    }
    guard let reply = xcb_intern_atom_reply(conn, cookie, &err) else {
        if let err { free(err) }
        return nil
    }
    let atom = reply.pointee.atom
    free(reply)
    return atom
}

private func queryXftScale(_ conn: OpaquePointer, root: UInt32) -> Float {
    var err: UnsafeMutablePointer<xcb_generic_error_t>? = nil
    let cookie = xcb_get_property(
        conn,
        0,
        root,
        xcb_atom_t(XCB_ATOM_RESOURCE_MANAGER.rawValue),
        xcb_atom_t(XCB_ATOM_STRING.rawValue),
        0,
        1 << 16
    )
    guard let reply = xcb_get_property_reply(conn, cookie, &err) else {
        if let err { free(err) }
        return 1.0
    }
    defer { free(reply) }
    let len = Int(xcb_get_property_value_length(reply))
    guard len > 0, let rawVal = xcb_get_property_value(reply) else { return 1.0 }
    let slice = UnsafeBufferPointer(start: rawVal.assumingMemoryBound(to: UInt8.self), count: len)
    return parseXftScale(String(decoding: slice, as: UTF8.self))
}
#endif
