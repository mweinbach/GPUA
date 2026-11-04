// Ported from: crates/rune-kit/src/field.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Field (`@opencode/ui` forms/field): label (with optional info icon), prefix, control, suffix.

import Rune

public let FIELD_INFO = Icon(
    name: "kit-field-info",
    view: 16.0,
    body: #"<path fill-rule="evenodd" d="M13 13H3V3H13V13ZM6.46777 6.81641V7.81641H7.5791V11.3721H8.5791V6.81641H6.46777ZM7.30078 4.62891V5.62891H8.85645V4.62891H7.30078Z" fill="currentColor"/>"#
)

public struct Field {
    public static let INFO = FIELD_INFO

    private var labelVal: String?
    private var infoVal: Bool
    private var prefixVal: String?
    private var suffixVal: String?
    private var controlVal: El?

    public init() {
        self.labelVal = nil
        self.infoVal = false
        self.prefixVal = nil
        self.suffixVal = nil
        self.controlVal = nil
    }

    public static func new() -> Field {
        Field()
    }

    public static var `default`: Field {
        Field()
    }

    public func label(_ l: String) -> Field {
        var copy = self
        copy.labelVal = l
        return copy
    }

    /// Show the info icon after the label (its tooltip is a `Tooltip` the app mounts).
    public func info() -> Field {
        var copy = self
        copy.infoVal = true
        return copy
    }

    public func prefix(_ p: String) -> Field {
        var copy = self
        copy.prefixVal = p
        return copy
    }

    public func suffix(_ s: String) -> Field {
        var copy = self
        copy.suffixVal = s
        return copy
    }

    /// The field's control (a `TextInput`, `TextArea`, …), built with `invalid` set as needed.
    public func control(_ c: El) -> Field {
        var copy = self
        copy.controlVal = c
        return copy
    }

    public func build(_ k: Kit) -> El {
        let c = k.c
        var root = col().role("group").gap(8.0).wFull().itemsStart()
        if let l = labelVal {
            var lab = row().key("label").wFull().minH(16.0).gap(4.0).centerY().child(
                text(l).key("text").font(k.ty.uiMedium.lh(16.0)).color(c.textBase)
            )
            if infoVal {
                lab = lab.child(icon(FIELD_INFO, 16.0).key("info").color(c.iconMuted))
            }
            root = root.child(lab)
        }
        func aside(_ key: String, _ s: String) -> El {
            text(s).key(key).wFull().minH(11.0).font(k.ty.small.lh(11.0)).color(c.textMuted)
        }
        if let p = prefixVal {
            root = root.child(aside("prefix", p))
        }
        if let control = controlVal {
            root = root.child(control)
        }
        if let s = suffixVal {
            root = root.child(aside("suffix", s))
        }
        return root
    }
}

/// Namespace mirroring `rune_kit::field` module exports.
public enum field {
    public static let INFO = FIELD_INFO
    public static let info = FIELD_INFO
    public typealias Field = RuneKit.Field
}
