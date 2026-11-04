// Ported from: crates/rune/src/platform/x11/pointer.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! XI2 raw motion on a private connection. Idle overlays have no polling deadline.

#if os(Linux)
import CLinuxSys
import Foundation
import Glibc

// PORT NOTE: Owns a private `xcb_connection_t` with its reader thread woken on drop via `shutdown(fd, SHUT_RDWR)`.
final class X11MouseWatch: @unchecked Sendable {
    private let connection: OpaquePointer
    private let observer: PlatformPointerObserver
    private let runningLock = LiveLock()
    private var running: Bool = true
    private let root: UInt32

    private init(connection: OpaquePointer, observer: PlatformPointerObserver, root: UInt32) {
        self.connection = connection
        self.observer = observer
        self.root = root
    }

    static func create(_ wake: Waker?) -> X11MouseWatch? {
        var screenNum: Int32 = 0
        guard let conn = xcb_connect(nil, &screenNum) else { return nil }
        if xcb_connection_has_error(conn) != 0 {
            xcb_disconnect(conn)
            return nil
        }
        guard let setup = xcb_get_setup(conn) else {
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
        let root = screenPtr.pointee.root

        var verErr: UnsafeMutablePointer<xcb_generic_error_t>? = nil
        let verCookie = xcb_input_xi_query_version(conn, 2, 0)
        guard let verReply = xcb_input_xi_query_version_reply(conn, verCookie, &verErr) else {
            if let verErr { free(verErr) }
            xcb_disconnect(conn)
            return nil
        }
        free(verReply)

        struct RawMotionMask {
            var header: xcb_input_event_mask_t
            var mask: UInt32
        }
        var eventMask = RawMotionMask(
            header: xcb_input_event_mask_t(
                deviceid: UInt16(XCB_INPUT_DEVICE_ALL_MASTER.rawValue),
                mask_len: 1
            ),
            mask: UInt32(XCB_INPUT_XI_EVENT_MASK_RAW_MOTION.rawValue)
        )
        let selectCookie = withUnsafePointer(to: &eventMask) { ptr in
            ptr.withMemoryRebound(to: xcb_input_event_mask_t.self, capacity: 1) { maskPtr in
                xcb_input_xi_select_events_checked(conn, root, 1, maskPtr)
            }
        }
        if let err = xcb_request_check(conn, selectCookie) {
            free(err)
            xcb_disconnect(conn)
            return nil
        }
        guard xcb_flush(conn) > 0 else {
            xcb_disconnect(conn)
            return nil
        }

        let obs = PlatformPointerObserver(wake: wake)
        let watch = X11MouseWatch(connection: conn, observer: obs, root: root)
        let connBits = Int(bitPattern: conn)
        Thread.detachNewThread { [weak watch] in
            guard let conn = OpaquePointer(bitPattern: connBits) else { return }
            while let rawEv = xcb_wait_for_event(conn) {
                defer { free(rawEv) }
                let responseType = rawEv.pointee.response_type & ~0x80
                if responseType == XCB_GE_GENERIC {
                    let ge = UnsafeRawPointer(rawEv).assumingMemoryBound(to: xcb_ge_generic_event_t.self).pointee
                    if ge.event_type == UInt16(XCB_INPUT_RAW_MOTION) {
                        var ptrErr: UnsafeMutablePointer<xcb_generic_error_t>? = nil
                        let cookie = xcb_query_pointer(conn, root)
                        if let reply = xcb_query_pointer_reply(conn, cookie, &ptrErr) {
                            let same = reply.pointee.same_screen != 0
                            let rx = Int32(reply.pointee.root_x)
                            let ry = Int32(reply.pointee.root_y)
                            free(reply)
                            if same {
                                obs.observe((rx, ry))
                            }
                        } else if let ptrErr {
                            free(ptrErr)
                        }
                    }
                }
            }
            watch?.runningLock.withLock {
                watch?.running = false
            }
        }
        return watch
    }

    func supported() -> Bool {
        runningLock.withLock { running }
    }

    func take() -> (Int32, Int32)? {
        observer.take()
    }

    func geometry(_ canvas: [Int32], _ follow: Bool) {
        guard observer.needsGeometry(canvas, follow) else { return }
        var displays: [[Int32]] = []
        if follow {
            var monErr: UnsafeMutablePointer<xcb_generic_error_t>? = nil
            let cookie = xcb_randr_get_monitors(connection, root, 1)
            if let reply = xcb_randr_get_monitors_reply(connection, cookie, &monErr) {
                var iter = xcb_randr_get_monitors_monitors_iterator(reply)
                while iter.rem > 0 {
                    if let m = iter.data?.pointee {
                        let mx = Int32(m.x)
                        let my = Int32(m.y)
                        displays.append([mx, my, mx + Int32(m.width), my + Int32(m.height)])
                    }
                    xcb_randr_monitor_info_next(&iter)
                }
                free(reply)
            } else if let monErr {
                free(monErr)
            }
        }
        observer.configure(canvas, displays, follow)
        var ptrErr: UnsafeMutablePointer<xcb_generic_error_t>? = nil
        let cookie = xcb_query_pointer(connection, root)
        if let reply = xcb_query_pointer_reply(connection, cookie, &ptrErr) {
            let same = reply.pointee.same_screen != 0
            let rx = Int32(reply.pointee.root_x)
            let ry = Int32(reply.pointee.root_y)
            free(reply)
            if same {
                observer.observe((rx, ry))
            }
        } else if let ptrErr {
            free(ptrErr)
        }
    }

    deinit {
        let fd = xcb_get_file_descriptor(connection)
        if fd >= 0 {
            _ = Glibc.shutdown(fd, Int32(SHUT_RDWR))
        }
        xcb_disconnect(connection)
    }
}
#endif
