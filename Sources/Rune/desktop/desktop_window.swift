// Ported from: crates/rune/src/desktop/window.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Virtual desktop window & overlay member adapter (`crates/rune/src/desktop/window.rs`).

struct DesktopChanges: Sendable, Equatable {
    var quit: Bool = false
    var wantsFocus: Bool = false
}

protocol DesktopMember: AnyObject {
    var id: String { get }
    var title: String { get }
    var isVisible: Bool { get }
    var zLevel: Int { get }
    var isNonactivatingPanel: Bool { get }
    var excludeFromCapture: Bool { get }

    func startMember(desktop: VirtualDesktop)
    func stepMember(dt: Double, desktop: VirtualDesktop) -> DesktopChanges
    func desktopBounds() -> [Int32]?
    func hitTestDesktop(px: Int32, py: Int32) -> Bool
    func pointerMoveDesktop(px: Int32, py: Int32)
    func pointerLeaveDesktop()
    func pointerDownDesktop(px: Int32, py: Int32, button: PointerButton) -> Bool
    func pointerUpDesktop(px: Int32, py: Int32, button: PointerButton)
    func keyDownDesktop(event: KeyEvent, base: Character?)
    func setKeyFocus(_ focused: Bool)
    func renderSlots(isKeyWindow: Bool) -> [DesktopSlot]
}

/// Adapts a typed `Host<S>` (plus its attached `Overlay`s) to `DesktopMember` (`crates/rune/src/desktop/window.rs`).
final class DesktopWindow<S>: DesktopMember {
    let id: String
    let host: Host<S>
    private var lastInstances: [Instance] = []
    private var started: Bool = false

    init(id: String, host: Host<S>, desktop: VirtualDesktop) {
        self.id = id
        self.host = host
        let primary = desktop.primaryDisplay()
        host.rt.hostSetScale(Float(primary.scale))
    }

    var title: String {
        host.spec.title
    }

    var isVisible: Bool {
        host.win?.visible == true
    }

    var zLevel: Int {
        if let explicit = host.macOptions.levelValue {
            return explicit
        }
        return host.options.alwaysOnTop ? WINDOW_LEVEL_ALWAYS_ON_TOP : WINDOW_LEVEL_NORMAL
    }

    var isNonactivatingPanel: Bool {
        host.macOptions.nonactivatingPanelFlag
    }

    var excludeFromCapture: Bool {
        host.macOptions.excludeFromCaptureFlag == true
    }

    func startMember(desktop: VirtualDesktop) {
        guard !started else { return }
        started = true
        host.startHost(hostIndex: 0, wakeHost: {}, wakeSink: { _ in }, displays: desktop.publicDisplays())
        if let win = host.win {
            // Center on primary display if no explicit position was configured
            if host.options.position == nil {
                let p = desktop.primaryDisplay()
                let sz = win.window.innerSize()
                let cx = p.position.0 + max(Int32(p.size.0) - Int32(sz.0), 0) / 2
                let cy = p.position.1 + max(Int32(p.size.1) - Int32(sz.1), 0) / 2
                host.applyPosition((cx, cy))
            } else if let pos = host.options.position {
                host.applyPosition(pos)
            }
        }
        let (insts, _, _) = host.rt.hostFrame(0.0)
        lastInstances = insts
    }

    func stepMember(dt: Double, desktop: VirtualDesktop) -> DesktopChanges {
        let displays = desktop.publicDisplays()
        let wasVisible = isVisible
        if host.drainShellRequests(displays: displays) {
            return DesktopChanges(quit: true, wantsFocus: false)
        }
        host.mountPendingOverlays(hostIndex: 0, displays: displays)

        let (insts, _, _) = host.rt.hostFrame(dt)
        lastInstances = insts
        if let win = host.win {
            syncPlatform(win: win, rt: host.rt, chrome: host.chrome, options: host.options)
        }
        for ov in host.overlays {
            ov.stepOverlay(now: .now(), displays: displays)
        }
        let quitAfter = host.drainShellRequests(displays: displays)
        let becameVisible = !wasVisible && isVisible
        return DesktopChanges(quit: quitAfter || !host.isAlive, wantsFocus: becameVisible)
    }

    func desktopBounds() -> [Int32]? {
        guard let win = host.win, win.visible else { return nil }
        let pos = win.window.outerPosition()
        let sz = win.window.innerSize()
        return [pos.0, pos.1, Int32(sz.0), Int32(sz.1)]
    }

    func hitTestDesktop(px: Int32, py: Int32) -> Bool {
        guard !host.options.clickThrough, let b = desktopBounds() else { return false }
        return px >= b[0] && px < b[0] + b[2] && py >= b[1] && py < b[1] + b[3]
    }

    private func toLocal(_ px: Int32, _ py: Int32) -> (Float, Float)? {
        guard let win = host.win else { return nil }
        let pos = win.window.outerPosition()
        let scale = max(Float(win.window.scaleFactor()), 0.25)
        return (Float(px - pos.0) / scale, Float(py - pos.1) / scale)
    }

    func pointerMoveDesktop(px: Int32, py: Int32) {
        guard let (lx, ly) = toLocal(px, py) else { return }
        _ = host.handleWindowEvent(.pointerMoved(lx, ly))
    }

    func pointerLeaveDesktop() {
        _ = host.handleWindowEvent(.pointerLeft)
    }

    func pointerDownDesktop(px: Int32, py: Int32, button: PointerButton) -> Bool {
        guard let (lx, ly) = toLocal(px, py) else { return false }
        _ = host.handleWindowEvent(.pointerDown(lx, ly, button))
        return true
    }

    func pointerUpDesktop(px: Int32, py: Int32, button: PointerButton) {
        guard let (lx, ly) = toLocal(px, py) else { return }
        _ = host.handleWindowEvent(.pointerUp(lx, ly, button))
    }

    func keyDownDesktop(event: KeyEvent, base: Character?) {
        _ = host.handleWindowEvent(.keyDown(event, base))
    }

    func setKeyFocus(_ focused: Bool) {
        _ = host.handleWindowEvent(.focused(focused))
    }

    func renderSlots(isKeyWindow: Bool) -> [DesktopSlot] {
        var slots: [DesktopSlot] = []
        if let win = host.win, win.visible, let b = desktopBounds() {
            let w = Int(max(b[2], 1))
            let h = Int(max(b[3], 1))
            let rgba = rasterizeSimpleInstances(
                width: w,
                height: h,
                clear: host.options.transparent
                    ? .TRANSPARENT
                    : (host.rt.hostElements().first?.fill ?? Color(0.08, 0.08, 0.09, 1.0)),
                instances: lastInstances
            )
            let cornerRad: Float
            if host.options.borderless {
                cornerRad = host.macOptions.cornerRadiusValue ?? 0.0
            } else {
                cornerRad = 10.0
            }
            let hasShadow = host.macOptions.shadowFlag ?? !host.options.borderless
            slots.append(
                DesktopSlot(
                    rect: b,
                    rgba: rgba,
                    shadow: hasShadow,
                    cornerRadius: cornerRad,
                    backdropBlur: 0.0,
                    keyWindow: isKeyWindow,
                    scale: host.rt.env.scale,
                    excludeFromCapture: excludeFromCapture
                )
            )
        }
        return slots
    }
}

/// Lightweight software rasterizer of rect/glyph instances for virtual desktop compositing tests.
func rasterizeSimpleInstances(
    width: Int,
    height: Int,
    clear: Color,
    instances: [Instance]
) -> [UInt8] {
    let w = max(width, 1)
    let h = max(height, 1)
    var buf = [UInt8](repeating: 0, count: w * h * 4)
    let cr = UInt8(clamping: Int((min(max(clear.r, 0.0), 1.0) * 255.0).rounded()))
    let cg = UInt8(clamping: Int((min(max(clear.g, 0.0), 1.0) * 255.0).rounded()))
    let cb = UInt8(clamping: Int((min(max(clear.b, 0.0), 1.0) * 255.0).rounded()))
    let ca = UInt8(clamping: Int((min(max(clear.a, 0.0), 1.0) * 255.0).rounded()))
    if ca > 0 {
        for p in 0..<(w * h) {
            let base = p * 4
            buf[base] = cr
            buf[base + 1] = cg
            buf[base + 2] = cb
            buf[base + 3] = ca
        }
    }

    for inst in instances where inst.rect.count == 4 && inst.fill.count == 4 {
        let kind = inst.params.count >= 2 ? inst.params[1] : KIND_RECT
        guard kind == KIND_RECT || kind == KIND_GLYPH || kind == KIND_IMAGE else { continue }
        let fa = min(max(inst.fill[3], 0.0), 1.0)
        guard fa > 0.0 else { continue }
        let fr = min(max(inst.fill[0], 0.0), 1.0)
        let fg = min(max(inst.fill[1], 0.0), 1.0)
        let fb = min(max(inst.fill[2], 0.0), 1.0)

        let x0 = max(0, Int(inst.rect[0].rounded(.down)))
        let y0 = max(0, Int(inst.rect[1].rounded(.down)))
        let x1 = min(w, Int((inst.rect[0] + inst.rect[2]).rounded(.up)))
        let y1 = min(h, Int((inst.rect[1] + inst.rect[3]).rounded(.up)))
        guard x1 > x0 && y1 > y0 else { continue }

        for py in y0..<y1 {
            for px in x0..<x1 {
                let idx = (py * w + px) * 4
                let dr = Float(buf[idx]) / 255.0
                let dg = Float(buf[idx + 1]) / 255.0
                let db = Float(buf[idx + 2]) / 255.0
                let da = Float(buf[idx + 3]) / 255.0
                let inv = 1.0 - fa
                buf[idx] = UInt8(clamping: Int(((fr * fa + dr * inv) * 255.0).rounded()))
                buf[idx + 1] = UInt8(clamping: Int(((fg * fa + dg * inv) * 255.0).rounded()))
                buf[idx + 2] = UInt8(clamping: Int(((fb * fa + db * inv) * 255.0).rounded()))
                buf[idx + 3] = UInt8(clamping: Int(((fa + da * inv) * 255.0).rounded()))
            }
        }
    }
    return buf
}
