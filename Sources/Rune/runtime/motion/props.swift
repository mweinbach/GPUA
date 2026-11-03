// Ported from: crates/rune/src/runtime/motion/props.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Custom `RuneMotion.Prop` descriptors owned by the retained runtime for paint, hover, press,
//! shadows, gradients, outlines, icon turn, scale, and group-opacity tracks.

import RuneMotion

struct Shadow4Lanes: Animatable, Sendable, Equatable {
    var lanesValue: [Float]

    static let lanes: Int = 16

    init(_ lanesValue: [Float] = Array(repeating: 0.0, count: 16)) {
        if lanesValue.count >= 16 {
            self.lanesValue = Array(lanesValue.prefix(16))
        } else {
            self.lanesValue = lanesValue + Array(repeating: 0.0, count: 16 - lanesValue.count)
        }
    }

    func writeLanes(_ out: UnsafeMutableBufferPointer<Float>) {
        for i in 0..<16 {
            out[i] = lanesValue[i]
        }
    }

    static func readLanes(_ l: UnsafeBufferPointer<Float>) -> Shadow4Lanes {
        var vals: [Float] = []
        vals.reserveCapacity(16)
        for i in 0..<16 {
            vals.append(l[i])
        }
        return Shadow4Lanes(vals)
    }
}

struct Gradient10Lanes: Animatable, Sendable, Equatable {
    var lanesValue: [Float]

    static let lanes: Int = 10

    init(_ lanesValue: [Float] = Array(repeating: 0.0, count: 10)) {
        if lanesValue.count >= 10 {
            self.lanesValue = Array(lanesValue.prefix(10))
        } else {
            self.lanesValue = lanesValue + Array(repeating: 0.0, count: 10 - lanesValue.count)
        }
    }

    func writeLanes(_ out: UnsafeMutableBufferPointer<Float>) {
        for i in 0..<10 {
            out[i] = lanesValue[i]
        }
    }

    static func readLanes(_ l: UnsafeBufferPointer<Float>) -> Gradient10Lanes {
        var vals: [Float] = []
        vals.reserveCapacity(10)
        for i in 0..<10 {
            vals.append(l[i])
        }
        return Gradient10Lanes(vals)
    }
}

struct Outline6Lanes: Animatable, Sendable, Equatable {
    var lanesValue: [Float]

    static let lanes: Int = 6

    init(_ lanesValue: [Float] = Array(repeating: 0.0, count: 6)) {
        if lanesValue.count >= 6 {
            self.lanesValue = Array(lanesValue.prefix(6))
        } else {
            self.lanesValue = lanesValue + Array(repeating: 0.0, count: 6 - lanesValue.count)
        }
    }

    func writeLanes(_ out: UnsafeMutableBufferPointer<Float>) {
        for i in 0..<6 {
            out[i] = lanesValue[i]
        }
    }

    static func readLanes(_ l: UnsafeBufferPointer<Float>) -> Outline6Lanes {
        var vals: [Float] = []
        vals.reserveCapacity(6)
        for i in 0..<6 {
            vals.append(l[i])
        }
        return Outline6Lanes(vals)
    }
}

struct Radial12Lanes: Animatable, Sendable, Equatable {
    var lanesValue: [Float]

    static let lanes: Int = 12

    init(_ lanesValue: [Float] = Array(repeating: 0.0, count: 12)) {
        if lanesValue.count >= 12 {
            self.lanesValue = Array(lanesValue.prefix(12))
        } else {
            self.lanesValue = lanesValue + Array(repeating: 0.0, count: 12 - lanesValue.count)
        }
    }

    func writeLanes(_ out: UnsafeMutableBufferPointer<Float>) {
        for i in 0..<12 {
            out[i] = lanesValue[i]
        }
    }

    static func readLanes(_ l: UnsafeBufferPointer<Float>) -> Radial12Lanes {
        var vals: [Float] = []
        vals.reserveCapacity(12)
        for i in 0..<12 {
            vals.append(l[i])
        }
        return Radial12Lanes(vals)
    }
}

let P_FILL = Prop<Color>.custom(64, .color)
let P_BORDER = Prop<Color>.custom(65, .color)
let P_TEXT = Prop<Color>.custom(66, .color)
let P_HOVER_C = Prop<Color>.custom(67, .color)
let P_PRESS_C = Prop<Color>.custom(68, .color)
let P_SHADOWS = Prop<Shadow4Lanes>.custom(69, .color)
let P_HOVER = Prop<Float>.custom(70, .opacity)
let P_PRESS = Prop<Float>.custom(71, .opacity)
let P_GRADIENT = Prop<Gradient10Lanes>.custom(72, .color)
let P_OUTLINE = Prop<Outline6Lanes>.custom(73, .color)
let P_BORDER_BOTTOM = Prop<Color>.custom(74, .color)
let P_PRESS_SCALE = Prop<Float>.custom(75, .scale)
let P_RADIAL = Prop<Radial12Lanes>.custom(76, .color)
let P_ICON_TURN = Prop<Float>.custom(77, .rotation)
let P_SCALE = Prop<Float>.custom(78, .scale)
let P_SHADOW_GEO = Prop<Shadow4Lanes>.custom(79, .spatial)
let P_GROUP_REST = Prop<Float>.custom(80, .opacity)
let P_ROW_SLIDE = Prop<Float>.custom(81, .spatial)

func propName(_ id: PropId) -> String {
    switch id.rawValue {
    case 0: return "opacity"
    case 1: return "frame"
    case 2: return "offset"
    case 3: return "scale"
    case 4: return "rotation"
    case 5: return "blur"
    case 6: return "radius"
    case 7: return "fill"
    case 8: return "mask"
    case 9: return "scroll"
    case 10: return "presence"
    case 11: return "travel"
    case 64: return "paint.fill"
    case 65: return "paint.border"
    case 66: return "paint.text"
    case 67: return "paint.hoverColor"
    case 68: return "paint.pressColor"
    case 69: return "paint.shadows"
    case 70: return "hover"
    case 71: return "press"
    case 72: return "paint.gradient"
    case 73: return "paint.outline"
    case 74: return "paint.borderBottom"
    case 75: return "pressScale"
    case 76: return "paint.radial"
    case 77: return "iconTurn"
    case 78: return "nodeScale"
    case 79: return "paint.shadowGeo"
    case 80: return "groupRest"
    default: return "prop(\(id.rawValue))"
    }
}

func paintPoseSpringing(_ scene: Scene, _ id: RuneMotion.NodeId) -> Bool {
    guard scene.contains(id) else { return false }
    if let p = scene.presented(id), p.flags != 0 {
        return true
    }
    return false
}

@discardableResult
func setGroupRest(
    _ scene: Scene,
    _ id: RuneMotion.NodeId,
    _ group: Float?,
    _ motion: Anim?,
    _ spring: Spring,
    _ quiet: Bool,
    _ groupFading: inout Set<RuneMotion.NodeId>
) -> Bool {
    let store = scene.store()
    let had = store.has(id, P_GROUP_REST)
    let resolvedMotion = motion ?? Anim(spring)
    let isQuiet = quiet || (resolvedMotion.curve == .instant)
    let settled = !store.isAnimating(id, P_GROUP_REST) && store.get(id, P_GROUP_REST) == 1.0
    let to = min(max(group ?? 1.0, 0.0), 1.0)
    if group == nil && (!had || isQuiet || settled) {
        if had {
            store.remove(id, P_GROUP_REST)
        }
        groupFading.remove(id)
        return false
    }
    if isQuiet {
        scene.set(id, P_GROUP_REST, to)
    } else if !had {
        scene.set(id, P_GROUP_REST, 1.0)
        scene.animate(id, P_GROUP_REST, to, resolvedMotion)
    } else if store.target(id, P_GROUP_REST) != to {
        scene.animate(id, P_GROUP_REST, to, resolvedMotion)
    }
    if group == nil {
        groupFading.insert(id)
        return true
    } else {
        groupFading.remove(id)
        return false
    }
}

func landGroupFades(_ scene: Scene, _ groupFading: inout Set<RuneMotion.NodeId>) {
    guard !groupFading.isEmpty else { return }
    let store = scene.store()
    var still: Set<RuneMotion.NodeId> = []
    for id in groupFading {
        guard scene.contains(id) else { continue }
        if store.isAnimating(id, P_GROUP_REST) {
            still.insert(id)
        } else {
            store.remove(id, P_GROUP_REST)
        }
    }
    groupFading = still
}

func groupFactor(_ scene: Scene, _ id: RuneMotion.NodeId, _ fallback: Float) -> Float {
    min(max(scene.get(id, P_GROUP_REST) ?? fallback, 0.0), 1.0)
}
