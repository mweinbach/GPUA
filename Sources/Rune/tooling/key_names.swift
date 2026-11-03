// Ported from: crates/rune/src/tooling/key_names.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Key names, modifiers and unmodified characters in headless scripts and `--keys`.

import Taffy

func keyNamed(_ name: String) -> Key? {
    switch name {
    case "Enter": return .enter
    case "Backspace": return .backspace
    case "Delete": return .delete
    case "Left": return .left
    case "Right": return .right
    case "Up": return .up
    case "Down": return .down
    case "Home": return .home
    case "End": return .end
    case "PageUp": return .pageUp
    case "PageDown": return .pageDown
    case "Escape": return .escape
    case "Tab": return .tab
    case "ContextMenu": return .contextMenu
    default:
        if name.count > 1, name.hasPrefix("F"),
           let n = UInt8(name.dropFirst()), (1...24).contains(n)
        {
            return .function(n)
        }
        if name.count == 1 {
            return .text(name)
        }
        return nil
    }
}

/// A script step's modifier flags.
func scriptMods(_ e: ToolingJson) -> Mods {
    func flag(_ k: String) -> Bool { e[k].boolValue ?? false }
    return Mods(
        shift: flag("shift"),
        cmd: flag("cmd"),
        alt: flag("alt"),
        ctrl: flag("ctrl"),
        logo: flag("logo")
    )
}

/// A script key's `Tx.keyBase`: its `"base"`, else a one-character name typed without Shift
/// or Option (which change the character the key types), lowercased.
func scriptKeyBase(_ e: ToolingJson, _ name: String, _ mods: Mods) -> Character? {
    func one(_ s: String) -> Character? {
        guard s.count == 1 else { return nil }
        return s.first
    }
    if let base = e["base"].stringValue {
        return one(base)
    }
    guard !mods.shift && !mods.alt, let ch = one(name) else { return nil }
    if ch.isASCII {
        return Character(String(ch).lowercased())
    }
    return ch
}

// MARK: - Headless `--keys` and `--pointer` Screencast Overlay

private let keycapBurst: Double = 1.0
private let keycapHold: Double = 1.5
private let keycapShown: Int = 3
private let keycapTypedMax: Int = 24
private let rippleHold: Double = 0.12
private let keycapMargin: Float = 24.0

struct ToolingKeycap: Sendable, Equatable {
    var id: UInt64
    var text: String
    var typing: Bool
    var count: UInt32
    var last: Double

    func label() -> String {
        if typing {
            if trimAsciiWhitespace(text).isEmpty {
                return String(repeating: "␣", count: min(text.count, keycapTypedMax))
            }
            let chars = Array(text)
            if chars.count <= keycapTypedMax {
                return text
            }
            return "…" + String(chars[(chars.count - (keycapTypedMax - 1))...])
        }
        return count > 1 ? "\(text) ×\(count)" : text
    }
}

struct ToolingKeycaps: Sendable {
    private var caps: [ToolingKeycap] = []
    private var nextId: UInt64 = 0

    mutating func key(_ t: Double, _ ev: KeyEvent) {
        if case .modifier(_, pressed: false) = ev.key { return }
        let (lbl, typing) = toolingKeycapLabel(ev)
        push(t, lbl, typing)
    }

    mutating func chord(_ t: Double, _ shortcut: Shortcut) {
        let name = shortcut.description
        let keyPart = name.split(separator: "+").last.map(String.init) ?? ""
        push(t, "\(toolingModGlyphs(shortcut.modifiers()))\(toolingNamedGlyph(keyPart))", false)
    }

    private mutating func push(_ t: Double, _ label: String, _ typing: Bool) {
        if let lastIdx = caps.indices.last,
           t - caps[lastIdx].last <= keycapBurst,
           caps[lastIdx].typing == typing,
           (typing || caps[lastIdx].text == label)
        {
            if typing {
                caps[lastIdx].text += label
            } else {
                caps[lastIdx].count += 1
            }
            caps[lastIdx].last = t
            return
        }
        caps.append(ToolingKeycap(id: nextId, text: label, typing: typing, count: 1, last: t))
        nextId += 1
    }

    mutating func visible(_ t: Double) -> [ToolingKeycap] {
        caps.removeAll { t - $0.last >= keycapHold }
        let skip = max(0, caps.count - keycapShown)
        return Array(caps[skip...])
    }
}

private func toolingModGlyphs(_ m: Mods) -> String {
    #if os(macOS)
    let mac = true
    #else
    let mac = false
    #endif
    let held: [(Bool, String)] = [
        (m.ctrl || (!mac && m.cmd), "⌃"),
        (m.alt, "⌥"),
        (m.shift, "⇧"),
        (m.logo || (mac && m.cmd), "⌘"),
    ]
    return held.compactMap { $0.0 ? $0.1 : nil }.joined()
}

func toolingKeycapTitle(_ name: String) -> String {
    guard let first = name.first else { return "" }
    let firstStr = String(first)
    let upper = firstStr.uppercased()
    let head = (upper.lowercased() == firstStr) ? upper : firstStr
    return head + String(name.dropFirst()).lowercased()
}

private func toolingKeycapLabel(_ ev: KeyEvent) -> (String, Bool) {
    let m = ev.mods
    let chord = m.cmd || m.ctrl || m.alt || m.logo
    let keyStr: String
    switch ev.key {
    case .text(let s) where !chord:
        return (s, true)
    case .text(let s) where s == " ":
        keyStr = "␣"
    case .text(let s):
        keyStr = toolingKeycapTitle(s)
    case .command(let c):
        var mods = m
        mods.cmd = true
        let lbl = (c == " ") ? "␣" : toolingKeycapTitle(String(c))
        return ("\(toolingModGlyphs(mods))\(lbl)", false)
    case .enter: keyStr = "↩"
    case .backspace: keyStr = "⌫"
    case .delete: keyStr = "⌦"
    case .left: keyStr = "←"
    case .right: keyStr = "→"
    case .up: keyStr = "↑"
    case .down: keyStr = "↓"
    case .home: keyStr = "↖"
    case .end: keyStr = "↘"
    case .pageUp: keyStr = "⇞"
    case .pageDown: keyStr = "⇟"
    case .escape: keyStr = "⎋"
    case .tab: keyStr = "⇥"
    case .function(let n): keyStr = "F\(n)"
    case .contextMenu: keyStr = "≣"
    case .modifier(let mod, _):
        if mod == .fn {
            keyStr = "fn"
        } else {
            return (toolingModGlyphs(m), false)
        }
    }
    return ("\(toolingModGlyphs(m))\(keyStr)", false)
}

private func toolingNamedGlyph(_ name: String) -> String {
    switch name {
    case "space": return "␣"
    case "enter": return "↩"
    case "escape": return "⎋"
    case "tab": return "⇥"
    case "backspace": return "⌫"
    case "delete": return "⌦"
    case "left": return "←"
    case "right": return "→"
    case "up": return "↑"
    case "down": return "↓"
    case "home": return "↖"
    case "end": return "↘"
    case "pageup": return "⇞"
    case "pagedown": return "⇟"
    case "insert": return "Ins"
    case "minus": return "-"
    case "equal": return "="
    case "comma": return ","
    case "period": return "."
    case "slash": return "/"
    case "semicolon": return ";"
    case "quote": return "'"
    case "bracketleft": return "["
    case "bracketright": return "]"
    case "backslash": return "\\"
    case "backquote": return "`"
    default: return toolingKeycapTitle(name)
    }
}

private struct ToolingOverlayScene: Equatable {
    var caps: [(UInt64, String)] = []
    var ripples: [(UInt64, Float, Float)] = []
    var corner: ToolingKeycapCorner = .bottomLeft
    var dark: Bool = true

    static func == (lhs: ToolingOverlayScene, rhs: ToolingOverlayScene) -> Bool {
        guard lhs.corner == rhs.corner, lhs.dark == rhs.dark,
              lhs.caps.count == rhs.caps.count,
              lhs.ripples.count == rhs.ripples.count
        else { return false }
        for i in lhs.caps.indices where lhs.caps[i] != rhs.caps[i] { return false }
        for i in lhs.ripples.indices where lhs.ripples[i] != rhs.ripples[i] { return false }
        return true
    }
}

final class ToolingKeycapOverlay {
    private let rt: Runtime<ToolingOverlayScene>
    private var keys: ToolingKeycaps?
    private var ripples: ([(UInt64, Float, Float, Double)], UInt64)?
    private let theme: Bool?

    init(size: (Float, Float), scale: Float, keys: ToolingKeycapCorner?, theme: Bool?, pointer: Bool) {
        let scene = ToolingOverlayScene(corner: keys ?? .bottomLeft)
        self.rt = Runtime(scene, toolingOverlayView, size, Env.new(true, scale))
        self.rt.transparent = true
        self.keys = keys != nil ? ToolingKeycaps() : nil
        self.ripples = pointer ? ([], 0) : nil
        self.theme = theme
    }

    func setSrgbBlend(_ enabled: Bool) {
        rt.srgbBlend = enabled
    }

    func key(_ t: Double, _ ev: KeyEvent) {
        keys?.key(t, ev)
    }

    func chord(_ t: Double, _ shortcut: Shortcut) {
        keys?.chord(t, shortcut)
    }

    func press(_ t: Double, _ x: Float, _ y: Float) {
        guard var r = ripples else { return }
        r.0.append((r.1, x, y, t))
        r.1 += 1
        ripples = r
    }

    func frame(_ t: Double, _ dt: Double, _ appDark: Bool) -> ([Instance], ImageAtlas) {
        let dark = theme ?? appDark
        let visCaps = keys?.visible(t).map { ($0.id, $0.label()) } ?? []
        var visRipples: [(UInt64, Float, Float)] = []
        if var r = ripples {
            r.0.removeAll { t - $0.3 >= rippleHold }
            visRipples = r.0.map { ($0.0, $0.1, $0.2) }
            ripples = r
        }
        let next = ToolingOverlayScene(caps: visCaps, ripples: visRipples, corner: rt.state.corner, dark: dark)
        if rt.state != next {
            rt.update { s, _ in s = next }
        }
        let (insts, _, _) = rt.hostFrame(dt)
        return (insts, rt.images)
    }
}

private func toolingPin(_ el: El, left: Float?, top: Float?, right: Float?, bottom: Float?, align: AlignItems) -> El {
    var copy = el
    copy.style.position = .absolute
    copy.style.alignItems = align
    copy.style.inset = Taffy.Rect(
        left: left.map(LengthPercentageAuto.length) ?? .auto(),
        right: right.map(LengthPercentageAuto.length) ?? .auto(),
        top: top.map(LengthPercentageAuto.length) ?? .auto(),
        bottom: bottom.map(LengthPercentageAuto.length) ?? .auto()
    )
    return copy
}

private func toolingAbsolute(_ el: El, _ x: Float, _ y: Float) -> El {
    var copy = el
    copy.style.position = .absolute
    copy.style.inset = Taffy.Rect(
        left: .length(x),
        right: .auto(),
        top: .length(y),
        bottom: .auto()
    )
    return copy
}

private func toolingOverlayView(_ s: ToolingOverlayScene, _ cx: Cx<ToolingOverlayScene>) -> El {
    _ = cx
    let rawCaps = col().gap(8.0).children(s.caps.map { toolingCapEl($0.0, $0.1, s.dark) })
    let m: Float? = keycapMargin
    let caps: El
    switch s.corner {
    case .bottomLeft: caps = toolingPin(rawCaps, left: m, top: nil, right: nil, bottom: m, align: .flexStart)
    case .bottom: caps = toolingPin(rawCaps, left: 0.0, top: nil, right: 0.0, bottom: m, align: .center)
    case .bottomRight: caps = toolingPin(rawCaps, left: nil, top: nil, right: m, bottom: m, align: .flexEnd)
    case .topLeft: caps = toolingPin(rawCaps, left: m, top: m, right: nil, bottom: nil, align: .flexStart)
    case .top: caps = toolingPin(rawCaps, left: 0.0, top: m, right: 0.0, bottom: nil, align: .center)
    case .topRight: caps = toolingPin(rawCaps, left: nil, top: m, right: m, bottom: nil, align: .flexEnd)
    }
    return el()
        .wFull()
        .hFull()
        .child(caps)
        .children(s.ripples.map { toolingRippleEl($0.0, $0.1, $0.2) })
}

private func toolingCapEl(_ id: UInt64, _ label: String, _ dark: Bool) -> El {
    let (fill, border, ink, shadowAlpha): (Color, Color, Color, Float) = dark
        ? (oklcha(0.22, 0.0, 0.0, 0.96), oklcha(1.0, 0.0, 0.0, 0.16), .WHITE, 0.4)
        : (oklcha(0.99, 0.0, 0.0, 0.96), oklcha(0.0, 0.0, 0.0, 0.12), oklcha(0.2, 0.0, 0.0, 1.0), 0.18)
    return el()
        .key("cap-\(id)")
        .padXY(12.0, 6.0)
        .rounded(9.0)
        .bg(fill)
        .border(1.0, border)
        .boxShadow(Shadow(x: 0.0, y: 4.0, blur: 14.0, spread: 0.0, color: oklcha(0.0, 0.0, 0.0, shadowAlpha)))
        .child(text(label).font(TextStyle.new(18.0, 600.0)).color(ink))
        .transition(Transition.asymmetric(Transition.scale(0.85), Transition.opacity()).holdLayout())
}

private func toolingRippleEl(_ id: UInt64, _ x: Float, _ y: Float) -> El {
    let r: Float = 14.0
    return toolingAbsolute(el().key("ripple-\(id)"), x - r, y - r)
        .size(2.0 * r, 2.0 * r)
        .rounded(r)
        .bg(oklcha(0.5, 0.0, 0.0, 0.3))
        .border(2.0, oklcha(1.0, 0.0, 0.0, 0.95))
        .boxShadow(Shadow(x: 0.0, y: 0.0, blur: 6.0, spread: 0.0, color: oklcha(0.0, 0.0, 0.0, 0.55)))
        .transition(Transition.asymmetric(Transition.scale(0.4), Transition.scale(2.2)))
}
