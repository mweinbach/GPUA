// Ported from: crates/rune/src/shortcuts/x11.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Checked `xcb_grab_key` requests on a private XCB connection, with lock-modifier variants.

let X11_BAD_ACCESS_ERROR_CODE: UInt8 = 10

func x11ShortcutReplyError(errorCode: UInt8, message: String = "") -> ShortcutError {
    if errorCode == X11_BAD_ACCESS_ERROR_CODE {
        return .conflict
    }
    return .backend(message.isEmpty ? "X11 error \(errorCode)" : message)
}

#if os(Linux)
import CLinuxSys
import Foundation
import Glibc

private struct X11Grab: Sendable {
    var root: UInt32
    var code: UInt8
    var mods: UInt16
}

// PORT NOTE: Access to XCB connection and grabs is synchronized between the registration caller and the dedicated X11 listener thread via `lock`.
final class X11ShortcutBackend: ShortcutBackend, @unchecked Sendable {
    private let connection: OpaquePointer
    private let lock = LiveLock()
    private var registrations: [ShortcutId: [X11Grab]] = [:]
    private var wakeReadFd: Int32
    private var wakeWriteFd: Int32
    private var stopped = false

    private init(connection: OpaquePointer, wakeReadFd: Int32, wakeWriteFd: Int32) {
        self.connection = connection
        self.wakeReadFd = wakeReadFd
        self.wakeWriteFd = wakeWriteFd
    }

    static func create(_ sink: @escaping ShortcutSink) -> Result<X11ShortcutBackend, ShortcutError> {
        var screenNum: Int32 = 0
        guard let conn = xcb_connect(nil, &screenNum) else {
            return .failure(.unsupported)
        }
        if xcb_connection_has_error(conn) != 0 {
            xcb_disconnect(conn)
            return .failure(.unsupported)
        }
        var fds: [Int32] = [-1, -1]
        guard pipe(&fds) == 0 else {
            xcb_disconnect(conn)
            return .failure(.backend("pipe failed"))
        }
        let backend = X11ShortcutBackend(connection: conn, wakeReadFd: fds[0], wakeWriteFd: fds[1])
        backend.startListener(sink)
        return .success(backend)
    }

    private func startListener(_ sink: @escaping ShortcutSink) {
        let conn = connection
        let readFd = wakeReadFd
        let xcbFd = xcb_get_file_descriptor(conn)
        Thread.detachNewThread { [weak self] in
            var repeats = X11ShortcutRepeats()
            var pollFds = [
                pollfd(fd: xcbFd, events: Int16(POLLIN), revents: 0),
                pollfd(fd: readFd, events: Int16(POLLIN), revents: 0),
            ]
            while true {
                while let rawEv = xcb_poll_for_event(conn) {
                    defer { free(rawEv) }
                    let responseType = rawEv.pointee.response_type & ~0x80
                    if responseType == XCB_KEY_RELEASE {
                        let ev = UnsafeRawPointer(rawEv).assumingMemoryBound(to: xcb_key_release_event_t.self).pointee
                        repeats.release(ev.detail, ev.time)
                    } else if responseType == XCB_KEY_PRESS {
                        let ev = UnsafeRawPointer(rawEv).assumingMemoryBound(to: xcb_key_press_event_t.self).pointee
                        if repeats.press(ev.detail, ev.time) {
                            let matchedId: ShortcutId? = self?.lock.withLock {
                                guard let self else { return nil }
                                let maskedMods = ev.state & 0xFF
                                for (sid, grabs) in self.registrations {
                                    if grabs.contains(where: { $0.root == ev.root && $0.code == ev.detail && $0.mods == maskedMods }) {
                                        return sid
                                    }
                                }
                                return nil
                            }
                            if let matchedId {
                                sink(matchedId, nil)
                            }
                        }
                    }
                }
                let rc = poll(&pollFds, 2, -1)
                if rc < 0 {
                    if errno == EINTR { continue }
                    break
                }
                if pollFds[1].revents != 0 {
                    var byte: UInt8 = 0
                    let n = Glibc.read(readFd, &byte, 1)
                    if n <= 0 || byte == 0 {
                        break
                    }
                }
                if (pollFds[0].revents & Int16(POLLERR | POLLHUP | POLLNVAL)) != 0 {
                    break
                }
            }
        }
    }

    func register(_ id: ShortcutId, _ shortcut: Shortcut) -> Result<Void, ShortcutError> {
        guard let scancode = linuxEvdevScancode(shortcut.physicalKey()),
              scancode <= 247
        else {
            return .failure(.invalidAccelerator(shortcut.description))
        }
        let code = UInt8(scancode + 8)
        guard let setup = xcb_get_setup(connection) else {
            return .failure(.backend("xcb_get_setup failed"))
        }
        guard code >= setup.pointee.min_keycode && code <= setup.pointee.max_keycode else {
            return .failure(.invalidAccelerator(shortcut.description))
        }

        var base: UInt16 = 0
        if (shortcut.mods & SHORTCUT_CTRL) != 0 { base |= 4 }
        if (shortcut.mods & SHORTCUT_ALT) != 0 { base |= 8 }
        if (shortcut.mods & SHORTCUT_SHIFT) != 0 { base |= 1 }
        if (shortcut.mods & SHORTCUT_SUPER) != 0 { base |= 64 }

        let numlock: UInt16 = 16 // Mod2Mask standard X11 NumLock
        let variants = Array(Set([base, base | 2, base | numlock, base | numlock | 2])).sorted()

        var grabbed: [X11Grab] = []
        var screenIter = xcb_setup_roots_iterator(setup)
        while screenIter.rem > 0 {
            let root = screenIter.data.pointee.root
            for mods in variants {
                let cookie = xcb_grab_key_checked(
                    connection,
                    0,
                    root,
                    mods,
                    code,
                    UInt8(XCB_GRAB_MODE_ASYNC.rawValue),
                    UInt8(XCB_GRAB_MODE_ASYNC.rawValue)
                )
                if let err = xcb_request_check(connection, cookie) {
                    let errCode = err.pointee.error_code
                    free(err)
                    _ = releaseGrabs(grabbed)
                    return .failure(x11ShortcutReplyError(errorCode: errCode))
                }
                grabbed.append(X11Grab(root: root, code: code, mods: mods))
            }
            xcb_screen_next(&screenIter)
        }

        lock.withLock {
            registrations[id] = grabbed
        }
        var wakeByte: UInt8 = 1
        _ = Glibc.write(wakeWriteFd, &wakeByte, 1)
        return .success(())
    }

    func unregister(_ id: ShortcutId) -> Result<Void, ShortcutError> {
        let grabs: [X11Grab]? = lock.withLock { registrations[id] }
        guard let grabs else {
            return .failure(.unknownId)
        }
        let res = releaseGrabs(grabs)
        lock.withLock {
            _ = registrations.removeValue(forKey: id)
        }
        return res
    }

    private func releaseGrabs(_ grabs: [X11Grab]) -> Result<Void, ShortcutError> {
        var result: Result<Void, ShortcutError> = .success(())
        for g in grabs {
            let cookie = xcb_ungrab_key_checked(connection, g.code, g.root, g.mods)
            if let err = xcb_request_check(connection, cookie) {
                let errCode = err.pointee.error_code
                free(err)
                result = .failure(x11ShortcutReplyError(errorCode: errCode))
            }
        }
        return result
    }

    deinit {
        var quitByte: UInt8 = 0
        _ = Glibc.write(wakeWriteFd, &quitByte, 1)
        Glibc.close(wakeWriteFd)
        Glibc.close(wakeReadFd)
        xcb_disconnect(connection)
    }
}

private func linuxEvdevScancode(_ key: PhysicalKeyCode) -> UInt32? {
    switch key {
    case .escape: return 1
    case .digit1: return 2
    case .digit2: return 3
    case .digit3: return 4
    case .digit4: return 5
    case .digit5: return 6
    case .digit6: return 7
    case .digit7: return 8
    case .digit8: return 9
    case .digit9: return 10
    case .digit0: return 11
    case .minus: return 12
    case .equal: return 13
    case .backspace: return 14
    case .tab: return 15
    case .keyQ: return 16
    case .keyW: return 17
    case .keyE: return 18
    case .keyR: return 19
    case .keyT: return 20
    case .keyY: return 21
    case .keyU: return 22
    case .keyI: return 23
    case .keyO: return 24
    case .keyP: return 25
    case .bracketLeft: return 26
    case .bracketRight: return 27
    case .enter: return 28
    case .keyA: return 30
    case .keyS: return 31
    case .keyD: return 32
    case .keyF: return 33
    case .keyG: return 34
    case .keyH: return 35
    case .keyJ: return 36
    case .keyK: return 37
    case .keyL: return 38
    case .semicolon: return 39
    case .quote: return 40
    case .backquote: return 41
    case .backslash: return 43
    case .keyZ: return 44
    case .keyX: return 45
    case .keyC: return 46
    case .keyV: return 47
    case .keyB: return 48
    case .keyN: return 49
    case .keyM: return 50
    case .comma: return 51
    case .period: return 52
    case .slash: return 53
    case .space: return 57
    case .f1: return 59
    case .f2: return 60
    case .f3: return 61
    case .f4: return 62
    case .f5: return 63
    case .f6: return 64
    case .f7: return 65
    case .f8: return 66
    case .f9: return 67
    case .f10: return 68
    case .f11: return 87
    case .f12: return 88
    case .home: return 102
    case .arrowUp: return 103
    case .pageUp: return 104
    case .arrowLeft: return 105
    case .arrowRight: return 106
    case .end: return 107
    case .arrowDown: return 108
    case .pageDown: return 109
    case .insert: return 110
    case .delete: return 111
    case .f13: return 183
    case .f14: return 184
    case .f15: return 185
    case .f16: return 186
    case .f17: return 187
    case .f18: return 188
    case .f19: return 189
    case .f20: return 190
    case .f21: return 191
    case .f22: return 192
    case .f23: return 193
    case .f24: return 194
    default: return nil
    }
}
#endif
