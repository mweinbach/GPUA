// Ported from: crates/rune/src/text/span.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! What an app styles a text element's byte ranges with: spans, links, highlights and pills.

/// Brush carried through layout: 0 is the element's own colour, n is `spans[n - 1]`.
public struct Ink: Sendable, Equatable, Hashable {
    public var rawValue: UInt16
    public init(_ rawValue: UInt16 = 0) {
        self.rawValue = rawValue
    }
}

/// A styled UTF-8 byte range of a text element (markdown inline code, bold, links).
public struct Span: Sendable, Equatable {
    public var start: UInt32
    public var end: UInt32
    public var weight: Float?
    public var mono: Bool
    public var size: Float?
    public var color: Color?
    public var bg: Color?
    public var bgPad: Float
    public var underline: Color?
    public var italic: Bool

    public init(
        start: Int = 0,
        end: Int = 0,
        weight: Float? = nil,
        mono: Bool = false,
        size: Float? = nil,
        color: Color? = nil,
        bg: Color? = nil,
        bgPad: Float = 0.0,
        underline: Color? = nil,
        italic: Bool = false
    ) {
        self.start = UInt32(max(start, 0))
        self.end = UInt32(max(end, 0))
        self.weight = weight
        self.mono = mono
        self.size = size
        self.color = color
        self.bg = bg
        self.bgPad = bgPad
        self.underline = underline
        self.italic = italic
    }

    public static func new(_ start: Int, _ end: Int) -> Span {
        Span(start: start, end: end)
    }

    public func weight(_ weight: Float) -> Span {
        var copy = self
        copy.weight = weight
        return copy
    }

    public func bold() -> Span {
        weight(600.0)
    }

    public func italic(_ enabled: Bool = true) -> Span {
        var copy = self
        copy.italic = enabled
        return copy
    }

    public func mono(_ enabled: Bool = true) -> Span {
        var copy = self
        copy.mono = enabled
        return copy
    }

    public func size(_ size: Float) -> Span {
        var copy = self
        copy.size = size
        return copy
    }

    public func color(_ color: Color) -> Span {
        var copy = self
        copy.color = color
        return copy
    }

    public func bg(_ color: Color, _ pad: Float) -> Span {
        var copy = self
        copy.bg = color
        copy.bgPad = pad
        return copy
    }

    public func underline(_ color: Color) -> Span {
        var copy = self
        copy.underline = color
        return copy
    }
}

struct PillChip: Sendable, Equatable {
    var start: UInt32
    var end: UInt32
    var icon: Icon?
    var bg: Color?
    var fg: Color?
}

struct PillMetrics: Sendable, Equatable {
    var margin: Float
    var pad: Float
    var icon: Float
    var iconGap: Float

    init(_ size: Float) {
        self.margin = max(size * 0.12, 1.5)
        self.pad = max(size * 0.36, 3.0)
        self.icon = (size * 0.95).rounded()
        self.iconGap = max(size * 0.22, 2.0)
    }

    func lead(_ hasIcon: Bool) -> Float {
        margin + pad + (hasIcon ? icon + iconGap : 0.0)
    }

    func trail() -> Float {
        pad + margin
    }
}

let PILL_BOX: UInt64 = 1 << 62

func flattenSpans(_ spans: [Span]) -> [Span] {
    if spans.count <= 1 || zip(spans, spans.dropFirst()).allSatisfy({ $0.0.start < $0.0.end && $0.0.end <= $0.1.start }) {
        return spans.filter { $0.start < $0.end }
    }
    var bounds: [UInt32] = []
    bounds.reserveCapacity(spans.count * 2)
    var order: [Int] = []
    order.reserveCapacity(spans.count)
    for (i, s) in spans.enumerated() where s.start < s.end {
        bounds.append(s.start)
        bounds.append(s.end)
        order.append(i)
    }
    bounds.sort()
    var uniqueBounds: [UInt32] = []
    for b in bounds where uniqueBounds.last != b {
        uniqueBounds.append(b)
    }
    order.sort { spans[$0].start < spans[$1].start }

    var active: [Int] = []
    var next = 0
    var out: [Span] = []
    guard uniqueBounds.count >= 2 else { return out }
    for idx in 0..<(uniqueBounds.count - 1) {
        let a = uniqueBounds[idx]
        let b = uniqueBounds[idx + 1]
        active.removeAll { spans[$0].end <= a }
        while next < order.count && spans[order[next]].start <= a {
            let i = order[next]
            let at = active.firstIndex(where: { $0 >= i }) ?? active.count
            active.insert(i, at: at)
            next += 1
        }
        var merged: Span? = nil
        for i in active {
            let s = spans[i]
            var m = merged ?? Span.new(Int(a), Int(b))
            if let w = s.weight { m.weight = w }
            m.mono = m.mono || s.mono
            if let sz = s.size { m.size = sz }
            if let c = s.color { m.color = c }
            if let bg = s.bg {
                m.bg = bg
                m.bgPad = s.bgPad
            }
            if let u = s.underline { m.underline = u }
            m.italic = m.italic || s.italic
            merged = m
        }
        if let m = merged {
            if let last = out.last,
               last.end == m.start,
               last.weight == m.weight,
               last.mono == m.mono,
               last.size == m.size,
               last.color == m.color,
               last.bg == m.bg,
               last.bgPad == m.bgPad,
               last.underline == m.underline,
               last.italic == m.italic
            {
                out[out.count - 1].end = m.end
            } else {
                out.append(m)
            }
        }
    }
    return out
}

/// A link's look in one state, painted over its resting span style without reshaping.
public struct LinkPaint: Sendable, Equatable {
    var colorValue: Color?
    var bgValue: Color?
    var ringValue: (Color, Float)?
    var underlineValue: Color?

    public init() {
        self.colorValue = nil
        self.bgValue = nil
        self.ringValue = nil
        self.underlineValue = nil
    }

    public static func new() -> LinkPaint {
        LinkPaint()
    }

    public static func == (lhs: LinkPaint, rhs: LinkPaint) -> Bool {
        guard lhs.colorValue == rhs.colorValue,
              lhs.bgValue == rhs.bgValue,
              lhs.underlineValue == rhs.underlineValue
        else { return false }
        switch (lhs.ringValue, rhs.ringValue) {
        case (nil, nil): return true
        case (let l?, let r?): return l.0 == r.0 && l.1 == r.1
        default: return false
        }
    }

    public func color(_ c: Color) -> LinkPaint {
        var copy = self
        copy.colorValue = c
        return copy
    }

    public func bg(_ c: Color) -> LinkPaint {
        var copy = self
        copy.bgValue = c
        return copy
    }

    public func ring(_ c: Color, _ width: Float) -> LinkPaint {
        var copy = self
        copy.ringValue = (width > 0.0 && width.isFinite) ? (c, width) : nil
        return copy
    }

    public func underline(_ c: Color) -> LinkPaint {
        var copy = self
        copy.underlineValue = c
        return copy
    }

    var isEmpty: Bool {
        colorValue == nil && bgValue == nil && ringValue == nil && underlineValue == nil
    }
}

/// A pressable byte range of a text element.
public struct Link: Sendable, Equatable {
    var start: UInt32
    var end: UInt32
    var id: String
    var roleName: String
    var labelText: String?
    var hoverPaint: LinkPaint
    var pressedPaint: LinkPaint?
    var focusedPaint: LinkPaint?

    public init(_ range: Range<Int>, _ id: String) {
        self.start = UInt32(max(range.lowerBound, 0))
        self.end = UInt32(max(range.upperBound, 0))
        self.id = id
        self.roleName = "link"
        self.labelText = nil
        self.hoverPaint = LinkPaint()
        self.pressedPaint = nil
        self.focusedPaint = nil
    }

    public static func new(_ range: Range<Int>, _ id: String) -> Link {
        Link(range, id)
    }

    public func role(_ role: String) -> Link {
        var copy = self
        copy.roleName = role
        return copy
    }

    public func label(_ label: String) -> Link {
        var copy = self
        copy.labelText = label
        return copy
    }

    public func hover(_ paint: LinkPaint) -> Link {
        var copy = self
        copy.hoverPaint = paint
        return copy
    }

    public func pressed(_ paint: LinkPaint) -> Link {
        var copy = self
        copy.pressedPaint = paint
        return copy
    }

    public func focused(_ paint: LinkPaint) -> Link {
        var copy = self
        copy.focusedPaint = paint
        return copy
    }
}

/// A paint-only highlight over `start..<end` UTF-8 bytes of a `text` element.
public struct TextHighlight: Sendable, Equatable {
    var start: UInt32
    var end: UInt32
    var bg: Color
    var fg: Color?
    var ringValue: (Color, Float)?
    var padValue: Float
    var keyValue: String?

    public init(_ range: Range<Int>, _ bg: Color) {
        self.start = UInt32(min(max(range.lowerBound, 0), Int(UInt32.max)))
        self.end = UInt32(min(max(range.upperBound, 0), Int(UInt32.max)))
        self.bg = bg
        self.fg = nil
        self.ringValue = nil
        self.padValue = 1.5
        self.keyValue = nil
    }

    public static func new(_ range: Range<Int>, _ bg: Color) -> TextHighlight {
        TextHighlight(range, bg)
    }

    public static func == (lhs: TextHighlight, rhs: TextHighlight) -> Bool {
        guard lhs.start == rhs.start,
              lhs.end == rhs.end,
              lhs.bg == rhs.bg,
              lhs.fg == rhs.fg,
              lhs.padValue == rhs.padValue,
              lhs.keyValue == rhs.keyValue
        else { return false }
        switch (lhs.ringValue, rhs.ringValue) {
        case (nil, nil): return true
        case (let l?, let r?): return l.0 == r.0 && l.1 == r.1
        default: return false
        }
    }

    public func color(_ c: Color) -> TextHighlight {
        var copy = self
        copy.fg = c
        return copy
    }

    public func ring(_ c: Color, _ width: Float) -> TextHighlight {
        var copy = self
        copy.ringValue = (width > 0.0 && width.isFinite) ? (c, width) : nil
        return copy
    }

    public func pad(_ pad: Float) -> TextHighlight {
        var copy = self
        copy.padValue = pad
        return copy
    }

    public func key(_ key: String) -> TextHighlight {
        var copy = self
        copy.keyValue = key
        return copy
    }

    public func range() -> Range<Int> {
        Int(start)..<Int(end)
    }

    public func withRange(_ range: Range<Int>) -> TextHighlight {
        var copy = self
        copy.start = UInt32(min(max(range.lowerBound, 0), Int(UInt32.max)))
        copy.end = UInt32(min(max(range.upperBound, 0), Int(UInt32.max)))
        return copy
    }
}
