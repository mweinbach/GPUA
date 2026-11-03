// Ported from: crates/rune/src/input/keycaps.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import RuneMotion
import Taffy

/// Typing within this many seconds of the last key joins its cap.
private let KEYCAP_BURST: Double = 1.0
/// A cap stays this long after its last key, then fades out.
private let KEYCAP_HOLD: Double = 1.5
/// Caps on screen at once; older ones leave early.
private let KEYCAP_SHOWN: Int = 3
/// Typed characters a cap shows before eliding the oldest.
private let KEYCAP_TYPED: Int = 24
/// A ripple holds this long before it expands and fades.
private let KEYCAP_RIPPLE: Double = 0.12
private let KEYCAP_MARGIN: Float = 24.0

/// Where the screencast keycaps sit.
internal enum KeycapsCorner: Sendable, Equatable {
    case bottomLeft
    case bottom
    case bottomRight
    case topLeft
    case top
    case topRight

    internal init() {
        self = .bottomLeft
    }

    internal static func parse(_ s: String) -> KeycapsCorner? {
        switch s {
        case "bottom-left": return .bottomLeft
        case "bottom": return .bottom
        case "bottom-right": return .bottomRight
        case "top-left": return .topLeft
        case "top": return .top
        case "top-right": return .topRight
        default: return nil
        }
    }
}

/// One keycap: a burst of typing, or a chord with its repeat count.
internal struct KeycapEntry: Sendable, Equatable {
    internal var id: UInt64
    internal var text: String
    internal var typing: Bool
    internal var count: UInt32
    internal var last: Double

    internal func label() -> String {
        if typing {
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let n = min(text.count, KEYCAP_TYPED)
                return String(repeating: "␣", count: n)
            }
            let chars = Array(text)
            if chars.count <= KEYCAP_TYPED {
                return text
            }
            let suffix = String(chars[(chars.count - (KEYCAP_TYPED - 1))...])
            return "…\(suffix)"
        }
        if count > 1 {
            return "\(text) ×\(count)"
        }
        return text
    }
}

/// Groups key presses into screencast-style caps.
internal struct Keycaps: Sendable {
    internal var caps: [KeycapEntry] = []
    internal var next: UInt64 = 0

    internal init() {}

    /// A logical key from the script or host.
    internal mutating func key(_ t: Double, _ ev: KeyEvent) {
        if case .modifier(_, pressed: false) = ev.key {
            return
        }
        let (label, typing) = keycapKeyLabel(ev)
        push(t, label, typing)
    }

    /// A chord given its canonical key name and modifiers.
    internal mutating func chord(_ t: Double, keyName: String, mods: Mods) {
        let label = "\(keycapModGlyphs(mods))\(keycapNamedGlyph(keyName))"
        push(t, label, false)
    }

    /// Parses a shortcut accelerator string (such as `"cmd+space"`, `"alt+shift+k"`, `"alt+f12"`) and records its chord.
    @discardableResult
    internal mutating func chord(_ t: Double, accelerator: String) -> Bool {
        guard let (keyName, mods) = parseKeycapAccelerator(accelerator) else {
            return false
        }
        chord(t, keyName: keyName, mods: mods)
        return true
    }

    private mutating func push(_ t: Double, _ label: String, _ typing: Bool) {
        if !caps.isEmpty {
            let lastIdx = caps.count - 1
            if t - caps[lastIdx].last <= KEYCAP_BURST
                && caps[lastIdx].typing == typing
                && (typing || caps[lastIdx].text == label) {
                if typing {
                    caps[lastIdx].text += label
                } else {
                    caps[lastIdx].count += 1
                }
                caps[lastIdx].last = t
                return
            }
        }
        caps.append(KeycapEntry(id: next, text: label, typing: typing, count: 1, last: t))
        next += 1
    }

    /// The caps on screen at `t`, oldest first; forgets those that have left.
    internal mutating func visible(_ t: Double) -> [KeycapEntry] {
        caps.removeAll { t - $0.last >= KEYCAP_HOLD }
        let skip = max(0, caps.count - KEYCAP_SHOWN)
        return Array(caps[skip...])
    }
}

private func parseKeycapAccelerator(_ s: String) -> (String, Mods)? {
    let parts = s.split(separator: "+", omittingEmptySubsequences: false).map { $0.lowercased() }
    guard let keyPart = parts.last, !keyPart.isEmpty else { return nil }
    var mods = Mods()
    for mod in parts.dropLast() {
        switch mod {
        case "ctrl", "control":
            mods.ctrl = true
        case "alt", "opt", "option":
            mods.alt = true
        case "shift":
            mods.shift = true
        case "super", "meta", "win", "command":
            mods.logo = true
        case "cmd", "cmdorctrl":
            #if os(macOS)
            mods.logo = true
            mods.cmd = true
            #else
            mods.ctrl = true
            mods.cmd = true
            #endif
        default:
            return nil
        }
    }
    return (keyPart, mods)
}

/// Apple's order: Control, Option, Shift, Command. `cmd` is Ctrl off macOS.
internal func keycapModGlyphs(_ m: Mods) -> String {
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

/// The cap text for a key, and whether it is plain typing (no ⌘, ⌃ or ⌥).
internal func keycapKeyLabel(_ ev: KeyEvent) -> (String, Bool) {
    let m = ev.mods
    let isChord = m.cmd || m.ctrl || m.alt || m.logo
    let keyStr: String
    switch ev.key {
    case .text(let s) where !isChord:
        return (s, true)
    case .text(let s) where s == " ":
        keyStr = "␣"
    case .text(let s):
        keyStr = keycapTitle(s)
    case .command(let c):
        var cmdMods = m
        cmdMods.cmd = true
        let label = (c == " ") ? "␣" : keycapTitle(String(c))
        return ("\(keycapModGlyphs(cmdMods))\(label)", false)
    case .enter:
        keyStr = "↩"
    case .backspace:
        keyStr = "⌫"
    case .delete:
        keyStr = "⌦"
    case .left:
        keyStr = "←"
    case .right:
        keyStr = "→"
    case .up:
        keyStr = "↑"
    case .down:
        keyStr = "↓"
    case .home:
        keyStr = "↖"
    case .end:
        keyStr = "↘"
    case .pageUp:
        keyStr = "⇞"
    case .pageDown:
        keyStr = "⇟"
    case .escape:
        keyStr = "⎋"
    case .tab:
        keyStr = "⇥"
    case .function(let n):
        keyStr = "F\(n)"
    case .contextMenu:
        keyStr = "≣"
    case .modifier(.fn, _):
        keyStr = "fn"
    case .modifier:
        return (keycapModGlyphs(m), false)
    }
    return ("\(keycapModGlyphs(m))\(keyStr)", false)
}

internal func keycapNamedGlyph(_ name: String) -> String {
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
    default: return keycapTitle(name)
    }
}

/// As on a keycap: `"k"` draws as `"K"` and `"capslock"` as `"Capslock"`. A capital that doesn't
/// lower-case back to the same letter (Turkish `"ı"` -> `"I"`) stays as typed.
internal func keycapTitle(_ name: String) -> String {
    guard let first = name.first else { return "" }
    let firstStr = String(first)
    let upper = firstStr.uppercased()
    let resolvedFirst = (upper.lowercased() == firstStr) ? upper : firstStr
    let rest = String(name.dropFirst()).lowercased()
    return "\(resolvedFirst)\(rest)"
}

/// `--keys-theme`: dark (`true`) or light (`false`) caps, or `nil` (`"auto"`) matching the app's theme.
internal func parseKeycapsTheme(_ s: String) -> Bool?? {
    switch s {
    case "auto": return .some(nil)
    case "light": return .some(false)
    case "dark": return .some(true)
    default: return nil
    }
}

internal struct KeycapsScene: Sendable, Equatable {
    internal var caps: [(UInt64, String)] = []
    internal var ripples: [(UInt64, Float, Float)] = []
    internal var corner: KeycapsCorner = .bottomLeft
    internal var dark: Bool = false

    internal static func == (lhs: KeycapsScene, rhs: KeycapsScene) -> Bool {
        guard lhs.corner == rhs.corner,
              lhs.dark == rhs.dark,
              lhs.caps.count == rhs.caps.count,
              lhs.ripples.count == rhs.ripples.count else {
            return false
        }
        for (a, b) in zip(lhs.caps, rhs.caps) where a.0 != b.0 || a.1 != b.1 {
            return false
        }
        for (a, b) in zip(lhs.ripples, rhs.ripples) where a.0 != b.0 || a.1 != b.1 || a.2 != b.2 {
            return false
        }
        return true
    }
}

/// Separate overlay runtime drawing screencast keycaps and pointer click ripples.
internal final class KeycapsOverlay {
    internal let rt: Runtime<KeycapsScene>
    private var keys: Keycaps?
    private var ripples: ([(UInt64, Float, Float, Double)], UInt64)?
    private let theme: Bool?

    internal init(
        size: (Float, Float),
        scale: Float,
        keys: KeycapsCorner?,
        theme: Bool?,
        pointer: Bool
    ) {
        var scene = KeycapsScene()
        if let keys { scene.corner = keys }
        self.rt = Runtime(scene, keycapsOverlayView, size, Env.new(true, scale))
        self.keys = keys != nil ? Keycaps() : nil
        self.ripples = pointer ? ([], 0) : nil
        self.theme = theme
    }

    internal func key(_ t: Double, _ ev: KeyEvent) {
        keys?.key(t, ev)
    }

    internal func chord(_ t: Double, keyName: String, mods: Mods) {
        keys?.chord(t, keyName: keyName, mods: mods)
    }

    internal func chord(_ t: Double, accelerator: String) {
        _ = keys?.chord(t, accelerator: accelerator)
    }

    internal func press(_ t: Double, _ x: Float, _ y: Float) {
        guard var r = ripples else { return }
        r.0.append((r.1, x, y, t))
        r.1 += 1
        ripples = r
    }

    @discardableResult
    internal func frame(_ t: Double, _ dt: Double, _ appDark: Bool) -> Runtime<KeycapsScene> {
        let dark = theme ?? appDark
        let visibleCaps: [(UInt64, String)]
        if var k = keys {
            visibleCaps = k.visible(t).map { ($0.id, $0.label()) }
            keys = k
        } else {
            visibleCaps = []
        }
        let visibleRipples: [(UInt64, Float, Float)]
        if var r = ripples {
            r.0.removeAll { t - $0.3 >= KEYCAP_RIPPLE }
            visibleRipples = r.0.map { ($0.0, $0.1, $0.2) }
            ripples = r
        } else {
            visibleRipples = []
        }

        var nextScene = rt.state
        nextScene.caps = visibleCaps
        nextScene.ripples = visibleRipples
        nextScene.dark = dark
        if rt.state != nextScene {
            rt.update { s, _ in
                s = nextScene
            }
        }
        _ = rt.frame(dt)
        return rt
    }
}

private func keycapsOverlayView(_ s: KeycapsScene, _ cx: Cx<KeycapsScene>) -> El {
    _ = cx
    var caps = col().gap(8.0).children(s.caps.map { keycapBox($0.0, $0.1, s.dark) })
    let m: Float? = KEYCAP_MARGIN
    switch s.corner {
    case .bottomLeft:
        caps = pinKeycaps(alignItems(caps, .flexStart), left: m, top: nil, right: nil, bottom: m)
    case .bottom:
        caps = pinKeycaps(caps.itemsCenter(), left: 0.0, top: nil, right: 0.0, bottom: m)
    case .bottomRight:
        caps = pinKeycaps(alignItems(caps, .flexEnd), left: nil, top: nil, right: m, bottom: m)
    case .topLeft:
        caps = pinKeycaps(alignItems(caps, .flexStart), left: m, top: m, right: nil, bottom: nil)
    case .top:
        caps = pinKeycaps(caps.itemsCenter(), left: 0.0, top: m, right: 0.0, bottom: nil)
    case .topRight:
        caps = pinKeycaps(alignItems(caps, .flexEnd), left: nil, top: m, right: m, bottom: nil)
    }
    return el().wFull().hFull().child(caps).children(s.ripples.map { keycapRipple($0.0, $0.1, $0.2) })
}

private func alignItems(_ node: El, _ alignment: AlignItems) -> El {
    var copy = node
    copy.style.alignItems = alignment
    return copy
}

private func pinKeycaps(_ node: El, left: Float?, top: Float?, right: Float?, bottom: Float?) -> El {
    var copy = node
    copy.style.position = .absolute
    copy.style.inset = Taffy.Rect(
        left: left.map { .length($0) } ?? .auto(),
        right: right.map { .length($0) } ?? .auto(),
        top: top.map { .length($0) } ?? .auto(),
        bottom: bottom.map { .length($0) } ?? .auto()
    )
    return copy
}

private func keycapBox(_ id: UInt64, _ label: String, _ dark: Bool) -> El {
    let fill: Color
    let border: Color
    let ink: Color
    let shadowAlpha: Float
    if dark {
        fill = oklcha(0.22, 0.0, 0.0, 0.96)
        border = oklcha(1.0, 0.0, 0.0, 0.16)
        ink = .WHITE
        shadowAlpha = 0.4
    } else {
        fill = oklcha(0.99, 0.0, 0.0, 0.96)
        border = oklcha(0.0, 0.0, 0.0, 0.12)
        ink = oklcha(0.2, 0.0, 0.0, 1.0)
        shadowAlpha = 0.18
    }
    return el()
        .key("cap-\(id)")
        .padXY(12.0, 6.0)
        .rounded(9.0)
        .bg(fill)
        .border(1.0, border)
        .boxShadow(Shadow(x: 0.0, y: 4.0, blur: 14.0, spread: 0.0, color: oklcha(0.0, 0.0, 0.0, shadowAlpha), inset: false))
        .child(text(label).font(TextStyle.new(18.0, 600.0)).color(ink))
        .transition(Transition.asymmetric(Transition.scale(0.85), Transition.opacity()).holdLayout())
}

private func keycapRipple(_ id: UInt64, _ x: Float, _ y: Float) -> El {
    let r: Float = 14.0
    return pinKeycaps(el().key("ripple-\(id)"), left: x - r, top: y - r, right: nil, bottom: nil)
        .size(2.0 * r, 2.0 * r)
        .rounded(r)
        .bg(oklcha(0.5, 0.0, 0.0, 0.3))
        .border(2.0, oklcha(1.0, 0.0, 0.0, 0.95))
        .boxShadow(Shadow(x: 0.0, y: 0.0, blur: 6.0, spread: 0.0, color: oklcha(0.0, 0.0, 0.0, 0.55), inset: false))
        .transition(Transition.asymmetric(Transition.scale(0.4), Transition.scale(2.2)))
}
