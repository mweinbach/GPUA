// Ported from: crates/rune/src/overlay/placement.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Display selection and overlay origin/size calculation (`crates/rune/src/overlay/placement.rs`).

extension OverlayPlacement {
    func resolve(size: (Float, Float)) -> OverlayPlacementSpec {
        switch self {
        case .edge(let edge, let margin, let align, let inset):
            return OverlayPlacementSpec(
                size: size,
                edge: edge,
                margin: margin,
                align: align,
                inset: inset
            )
        case .rect(let x, let y, let width, let height):
            return OverlayPlacementSpec(
                size: (max(width, 1.0), max(height, 1.0)),
                edge: .top,
                margin: y,
                align: .start,
                inset: x
            )
        case .fullScreen:
            return OverlayPlacementSpec(
                size: size,
                edge: .top,
                margin: 0.0,
                align: .start,
                inset: 0.0
            )
        }
    }
}

func overlayMacWindowLevel(_ level: OverlayLevel, override: Int?) -> Int {
    if let override {
        return override
    }
    switch level {
    case .status:
        return 25
    case .aboveStatus:
        return 26
    case .aboveOverlays:
        return 27
    }
}

/// Resolves a `DisplayTarget` against the connected `displays` list and optional pointer position.
func resolveOverlayDisplay(
    target: DisplayTarget,
    displays: [Display],
    pointer: (Int32, Int32)?
) -> Display? {
    guard !displays.isEmpty else { return nil }
    let primaryIdx = displays.firstIndex(where: \.primary) ?? 0

    switch target {
    case .primary:
        return displays[primaryIdx]

    case .id(let targetId):
        if let idx = displays.firstIndex(where: { $0.id == targetId }) {
            return displays[idx]
        }
        return displays[primaryIdx]

    case .native(let nativeId):
        if let idx = displays.firstIndex(where: { $0.nativeId() == nativeId }) {
            return displays[idx]
        }
        return displays[primaryIdx]

    case .underPointer:
        let bounds = displays.map { $0.nativeBounds() }
        let ptrDouble = pointer.map { (Double($0.0), Double($0.1)) }
        if let chosen = overlayChooseDisplay(bounds, primaryIdx, nil, ptrDouble) {
            return displays[chosen]
        }
        return displays[primaryIdx]
    }
}

/// Computes physical desktop top-left coordinates `(x, y)` for `spec` on `display`.
func computeOverlayOrigin(spec: OverlayPlacementSpec, display: Display) -> (Int32, Int32) {
    let scale = max(display.scale, 0.25)
    let areaPoints = (
        Float(Double(display.size.0) / scale),
        Float(Double(display.size.1) / scale)
    )
    let local = overlayLocalRect(spec, nil, areaPoints)
    let px = display.position.0 + Int32((Double(local[0]) * scale).rounded())
    let py = display.position.1 + Int32((Double(local[1]) * scale).rounded())
    return (px, py)
}

struct ComputedOverlayBounds: Sendable, Equatable {
    var position: (Int32, Int32)
    var physicalSize: (UInt32, UInt32)
    var logicalSize: (Float, Float)
    var scale: Double

    static func == (lhs: ComputedOverlayBounds, rhs: ComputedOverlayBounds) -> Bool {
        lhs.position.0 == rhs.position.0
            && lhs.position.1 == rhs.position.1
            && lhs.physicalSize.0 == rhs.physicalSize.0
            && lhs.physicalSize.1 == rhs.physicalSize.1
            && lhs.logicalSize.0 == rhs.logicalSize.0
            && lhs.logicalSize.1 == rhs.logicalSize.1
            && lhs.scale == rhs.scale
    }
}

func computeOverlayBounds(
    at: OverlayPlacementSpec,
    placement: OverlayPlacement?,
    target: DisplayTarget,
    displays: [Display],
    pointer: (Int32, Int32)?
) -> ComputedOverlayBounds {
    let disp = resolveOverlayDisplay(target: target, displays: displays, pointer: pointer) ?? Display()
    var scale = max(disp.scale, 0.25)
    let areaPoints = (
        Float(Double(disp.size.0) / scale),
        Float(Double(disp.size.1) / scale)
    )
    let local = overlayLocalRect(at, placement, areaPoints)

    // On multi-DPI global `.rect(...)`, pick the backing scale of the display holding most of the frame
    if case .rect = placement, displays.count > 1 {
        let globalFrame = [
            Double(disp.position.0) + Double(local[0]) * scale,
            Double(disp.position.1) + Double(local[1]) * scale,
            Double(local[2]) * scale,
            Double(local[3]) * scale,
        ]
        let candidates = displays.map { ($0.nativeBounds(), max($0.scale, 0.25)) }
        if let underScale = overlayScaleUnder(globalFrame, candidates) {
            scale = underScale
        }
    }

    let pos = (
        disp.position.0 + Int32((Double(local[0]) * max(disp.scale, 0.25)).rounded()),
        disp.position.1 + Int32((Double(local[1]) * max(disp.scale, 0.25)).rounded())
    )
    let physSize = (
        max(UInt32((Double(local[2]) * scale).rounded()), 1),
        max(UInt32((Double(local[3]) * scale).rounded()), 1)
    )
    return ComputedOverlayBounds(
        position: pos,
        physicalSize: physSize,
        logicalSize: (max(local[2], 1.0), max(local[3], 1.0)),
        scale: scale
    )
}

extension Overlay {
    func currentOverlayPointer() -> (Int32, Int32)? {
        if let sim = simulatedPointer {
            return sim
        }
        #if os(Windows)
        return win32PointerPosition()
        #elseif os(Linux)
        return x11PointerPosition()
        #else
        return nil
        #endif
    }

    func repositionOverlay(displays: [Display]) {
        guard let window else { return }
        let bounds = computeOverlayBounds(
            at: at,
            placement: options.placement,
            target: options.display,
            displays: displays,
            pointer: currentOverlayPointer()
        )
        let oldPos = window.outerPosition()
        let oldSize = window.innerSize()
        let oldScale = window.scaleFactor()

        if oldPos.0 != bounds.position.0 || oldPos.1 != bounds.position.1 {
            window.setOuterPosition(bounds.position)
        }
        if oldScale != bounds.scale {
            window.setScaleFactor(bounds.scale)
            rt.hostSetScale(Float(bounds.scale))
        }
        if oldSize.0 != bounds.physicalSize.0 || oldSize.1 != bounds.physicalSize.1 {
            window.setInnerSize(bounds.physicalSize)
            config.width = bounds.physicalSize.0
            config.height = bounds.physicalSize.1
            configureWindowSurface(&config, &surfaceMeter)
            surfaceMeter.reconfigured()
            presented.invalidate()
        }
        rt.hostSetViewport(bounds.logicalSize.0, bounds.logicalSize.1)
        rt.hostSetWindowOrigin(
            Float(bounds.position.0) / Float(max(bounds.scale, 0.25)),
            Float(bounds.position.1) / Float(max(bounds.scale, 0.25))
        )
    }
}
