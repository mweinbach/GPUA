// Ported from: crates/rune/src/system_material/macos.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

#if os(macOS)
import AppKit
import Foundation
import QuartzCore
import RuneMotion

/// The host view: flipped so frames come straight from Rune's top-left points, and never hit
/// so clicks fall through to the content view behind it in the hit-test order.
@objc(RuneMaterialHost)
final class RuneMaterialHost: NSView {
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private struct MaterialShape: Equatable {
    var frame: [Double]
    var radius: Double
    var continuous: Bool
}

private struct MaterialSlot {
    var view: NSView
    var material: SystemMaterial
    /// `NSGlassEffectView`, which rounds itself; the effect views round their layer.
    var glass: Bool
    /// The element it showed last, which keeps it while it stays mounted.
    var owner: NodeId?
    /// Frame, corner radius and curve last set, and the alpha (`nil` once hidden).
    var shape: MaterialShape?
    var shown: Double?
}

/// Shared mutable `PresentFlag` cell matching upstream `Rc<Cell<PresentFlag>>`.
// PORT NOTE: Synchronized with `LiveLock` so `NSNotificationCenter` observer blocks satisfy Swift 6 `Sendable`.
final class PresentFlagCell: @unchecked Sendable {
    private let lock = LiveLock()
    private var flag = PresentFlag()

    init() {}

    func get() -> PresentFlag {
        lock.withLock { flag }
    }

    func set(_ newValue: PresentFlag) {
        lock.withLock { flag = newValue }
    }

    func update(_ body: (inout PresentFlag) -> Bool?) -> Bool? {
        lock.withLock { body(&flag) }
    }
}

extension SystemMaterialMode {
    /// The material actually shown: `Glass` falls back to the popover effect view before
    /// macOS 26 and in legacy mode.
    func resolve(_ material: SystemMaterial) -> SystemMaterial {
        if material == .glass && (self == .legacy || NSClassFromString("NSGlassEffectView") == nil) {
            return .popover
        }
        return material
    }
}

/// Turns `presentsWithTransaction` off when AppKit ends the user's live resize: idle windows
/// draw no frame after mouse-up unless `NSWindowDidEndLiveResizeNotification` clears the flag.
func watchLiveEnd(
    window: AnyObject,
    layer: CAMetalLayer,
    flag: PresentFlagCell
) -> any NSObjectProtocol {
    // PORT NOTE: Weak reference to `CAMetalLayer` mutated only on the main thread when live resize ends.
    final class WeakMetalLayer: @unchecked Sendable {
        weak var layer: CAMetalLayer?
        init(_ layer: CAMetalLayer) { self.layer = layer }
    }
    let weakLayer = WeakMetalLayer(layer)
    let name = NSNotification.Name("NSWindowDidEndLiveResizeNotification")
    return NotificationCenter.default.addObserver(
        forName: name,
        object: window,
        queue: nil
    ) { _ in
        if let on = flag.update({ $0.live(false) }),
           let target = weakLayer.layer {
            target.presentsWithTransaction = on
        }
    }
}

func unwatchLiveEnd(_ token: any NSObjectProtocol) {
    NotificationCenter.default.removeObserver(token)
}

@MainActor
private func makeMaterialView(_ material: SystemMaterial, host: NSView) -> MaterialSlot? {
    let isGlass = material == .glass
    let view: NSView
    if isGlass {
        guard let glassClass = NSClassFromString("NSGlassEffectView") as? NSView.Type else {
            return nil
        }
        view = glassClass.init(frame: .zero)
        view.wantsLayer = true
        let setStyleSel = NSSelectorFromString("setStyle:")
        if view.responds(to: setStyleSel) {
            view.setValue(0, forKey: "style")
        }
    } else {
        let effectView = NSVisualEffectView(frame: .zero)
        effectView.wantsLayer = true
        switch material {
        case .popover, .glass:
            effectView.material = .popover
        case .sidebar:
            effectView.material = .sidebar
        case .hudWindow:
            effectView.material = .hudWindow
        case .menu:
            effectView.material = .menu
        case .underWindowBackground:
            effectView.material = .underWindowBackground
        case .titlebar:
            effectView.material = .titlebar
        }
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.layer?.masksToBounds = true
        view = effectView
    }
    // Built visible at zero alpha: AppKit skips a hidden glass view's backdrop layers until
    // its first visible frame, which then shows unrefracted.
    view.alphaValue = 0.0
    host.addSubview(view)
    view.displayIfNeeded()
    return MaterialSlot(
        view: view,
        material: material,
        glass: isGlass,
        owner: nil,
        shape: nil,
        shown: nil
    )
}

private func surfaceMetalLayer(_ surface: MetalSurface) -> CAMetalLayer? {
    surface.layer
}

private func setSurfacePresentsWithTransaction(_ surface: MetalSurface, _ on: Bool) {
    surface.layer?.presentsWithTransaction = on
}

/// One window's material views.
// PORT NOTE: Owned and mutated exclusively on the window/main thread like upstream `Materials` (`Rc<Cell<PresentFlag>>`).
final class Materials: @unchecked Sendable {
    var mode: SystemMaterialMode
    /// Native views are on: elements skip their fill, and in synced modes the Metal layer
    /// presents with transactions.
    private(set) var active: Bool = false
    private var view: NSView? = nil
    private var hostView: NSView? = nil
    private var metal: CAMetalLayer? = nil
    let flag = PresentFlagCell()
    private var liveEnd: (any NSObjectProtocol)? = nil
    private var slots: [MaterialSlot] = []

    init(mode: SystemMaterialMode = .fromEnv()) {
        self.mode = mode
    }

    deinit {
        if let token = liveEnd {
            unwatchLiveEnd(token)
        }
        if let host = hostView, Thread.isMainThread {
            MainActor.assumeIsolated {
                host.removeFromSuperview()
            }
        }
    }

    /// Whether this frame's elements should leave their interior to native views.
    func native() -> Bool {
        active
    }

    /// Whether `present` would only present: no material views to move with the drawable, and
    /// the layer presents without transactions, so the present can happen on another thread.
    func presentsPlainly() -> Bool {
        !active && slots.allSatisfy({ $0.shown == nil }) && !flag.get().written()
    }

    /// A window frame animation started or stopped: it presents with transactions while it
    /// moves, and native materials keep them on after it lands.
    func setMoving(_ surface: MetalSurface, _ on: Bool) {
        if let changed = flag.update({ $0.moving(on) }) {
            setSurfacePresentsWithTransaction(surface, changed)
        }
    }

    /// The user started or stopped dragging the window's edge.
    func setLive(window: AnyObject?, surface: MetalSurface, _ on: Bool) {
        if on, liveEnd == nil, let win = window, let layer = surfaceMetalLayer(surface) {
            liveEnd = watchLiveEnd(window: win, layer: layer, flag: flag)
        }
        if let changed = flag.update({ $0.live(on) }) {
            setSurfacePresentsWithTransaction(surface, changed)
        }
    }

    /// After a build: switches native views on when a transparent window's frame found material
    /// elements, and off when it found none. Returns `true` when it switched them on.
    func update(
        transparent: Bool,
        found: Bool,
        contentView: NSView?,
        surface: MetalSurface
    ) -> Bool {
        if active && !found {
            active = false
            if let changed = flag.update({ $0.materials(false) }) {
                setSurfacePresentsWithTransaction(surface, changed)
            }
            return false
        }
        if active || !found || !transparent || mode == .off {
            return false
        }
        guard let contentView, let layer = surfaceMetalLayer(surface) else {
            return false
        }
        if mode != .unsynced, let changed = flag.update({ $0.materials(true) }) {
            setSurfacePresentsWithTransaction(surface, changed)
        }
        self.view = contentView
        self.metal = layer
        self.active = true
        return true
    }

    /// Presents the frame with the material views matching `draws`: in one transaction with
    /// the drawable when synced, or just before it otherwise.
    func present(_ draws: [MaterialDraw], scale: Float, _ presentFn: () -> Void) {
        if !active && slots.allSatisfy({ $0.shown == nil }) {
            presentFn()
            return
        }
        let effectiveDraws = active ? draws : []
        let synced = mode != .unsynced
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        MainActor.assumeIsolated {
            sync(effectiveDraws, scale: scale)
        }
        if !synced {
            CATransaction.commit()
        }
        presentFn()
        if synced {
            CATransaction.commit()
        }
    }

    @MainActor
    func sync(_ draws: [MaterialDraw], scale: Float) {
        let capped = Array(draws.prefix(MAX_NATIVE_MATERIALS))
        if capped.isEmpty && slots.allSatisfy({ $0.shown == nil }) {
            return
        }
        guard let host = ensureHost() else { return }
        let wanted = capped.map { (mode.resolve($0.material), $0.id) }
        let existing = slots.map { ($0.material, $0.owner) }
        let assignments = assignMaterialViews(existing, wanted)
        var taken = [Bool](repeating: false, count: slots.count)

        for (idx, draw) in capped.enumerated() {
            let (material, id) = wanted[idx]
            let slotIndex: Int
            if let assigned = assignments[idx] {
                slotIndex = assigned
            } else {
                guard let newSlot = makeMaterialView(material, host: host) else { continue }
                slots.append(newSlot)
                taken.append(false)
                slotIndex = slots.count - 1
            }
            taken[slotIndex] = true
            slots[slotIndex].owner = id
            let (pts, radius) = draw.points(scale)
            let newShape = MaterialShape(frame: pts, radius: radius, continuous: draw.continuous)
            let alpha = Double(min(max(draw.opacity, 0.0), 1.0))
            let slotView = slots[slotIndex].view
            if slots[slotIndex].shown != alpha {
                slotView.alphaValue = alpha
            }
            if slots[slotIndex].shape != newShape {
                if pts.count >= 4 {
                    slotView.frame = CGRect(x: pts[0], y: pts[1], width: pts[2], height: pts[3])
                }
                if slots[slotIndex].glass {
                    let setCornerSel = NSSelectorFromString("setCornerRadius:")
                    if slotView.responds(to: setCornerSel) {
                        slotView.setValue(radius, forKey: "cornerRadius")
                    }
                } else if let layer = slotView.layer {
                    layer.cornerRadius = radius
                    layer.cornerCurve = draw.continuous ? .continuous : .circular
                }
                slotView.layoutSubtreeIfNeeded()
                slotView.displayIfNeeded()
            }
            slots[slotIndex].shape = newShape
            slots[slotIndex].shown = alpha
        }

        for i in 0..<slots.count where !taken[i] && slots[i].shown != nil {
            slots[i].view.alphaValue = 0.0
            slots[i].shown = nil
            slots[i].owner = nil
        }

        // At most one spare view per material: unmounting several elements needn't keep all their views.
        var k = slots.count
        while k > 0 {
            k -= 1
            if slots[k].shown == nil && slots[0..<k].contains(where: { $0.shown == nil && $0.material == slots[k].material }) {
                let removed = slots.remove(at: k)
                removed.view.removeFromSuperview()
            }
        }
    }

    @MainActor
    private func ensureHost() -> NSView? {
        guard let contentView = view else { return nil }
        if hostView == nil {
            let host = RuneMaterialHost(frame: contentView.bounds)
            host.autoresizingMask = [.width, .height]
            host.wantsLayer = true
            contentView.addSubview(host, positioned: .below, relativeTo: nil)
            hostView = host
        }
        guard let host = hostView else { return nil }
        if let rootLayer = contentView.layer, let hostLayer = host.layer, let metalLayer = metal {
            let sublayers = rootLayer.sublayers ?? []
            if !sublayers.contains(where: { $0 === metalLayer }) {
                rootLayer.insertSublayer(metalLayer, above: hostLayer)
            }
            metalLayer.zPosition = 1.0
        }
        return host
    }
}
#endif
