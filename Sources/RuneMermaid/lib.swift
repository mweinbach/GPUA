// Ported from: crates/rune-mermaid/src/lib.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Native ```` ```mermaid ```` diagrams: flowcharts, sequence, state, class and
//! entity-relationship diagrams, gantt and pie charts, mindmaps, timelines, user journeys, git
//! graphs, quadrant and XY charts, sankey, block, requirement and C4 diagrams, parsed and laid out
//! in Swift and drawn with `Rune.Shape`s and text, so they theme with the app and stay crisp at
//! any scale. No JavaScript, web view or network.

import Rune

/// Colours and type a diagram draws with.
public struct DiagramStyle: Sendable, Equatable, Hashable {
    public var text: Color
    public var muted: Color
    public var surface: Color
    public var surfaceBorder: Color
    public var nodeFill: Color
    public var nodeBorder: Color
    public var line: Color
    public var clusterFill: Color
    public var noteFill: Color
    public var noteBorder: Color
    public var font: TextStyle
    public var maxWidth: Float

    public init(
        text: Color,
        muted: Color,
        surface: Color,
        surfaceBorder: Color,
        nodeFill: Color,
        nodeBorder: Color,
        line: Color,
        clusterFill: Color,
        noteFill: Color,
        noteBorder: Color,
        font: TextStyle,
        maxWidth: Float
    ) {
        self.text = text
        self.muted = muted
        self.surface = surface
        self.surfaceBorder = surfaceBorder
        self.nodeFill = nodeFill
        self.nodeBorder = nodeBorder
        self.line = line
        self.clusterFill = clusterFill
        self.noteFill = noteFill
        self.noteBorder = noteBorder
        self.font = font
        self.maxWidth = maxWidth
    }

    public func hash(into hasher: inout Hasher) {
        for c in [
            text, muted, surface, surfaceBorder, nodeFill, nodeBorder,
            line, clusterFill, noteFill, noteBorder,
        ] {
            hasher.combine(c)
        }
        hasher.combine(font)
        let bits: UInt32
        if maxWidth == 0.0 {
            bits = 0
        } else if maxWidth.isNaN {
            bits = Float.nan.bitPattern
        } else {
            bits = maxWidth.bitPattern
        }
        hasher.combine(bits)
    }

    /// Neutral light or dark colours derived from Rune's core tokens.
    public static func neutral(_ dark: Bool) -> DiagramStyle {
        let t = tok.theme(dark)
        return DiagramStyle(
            text: t.text,
            muted: t.textSecondary,
            surface: t.bg,
            surfaceBorder: t.separator,
            nodeFill: t.card,
            nodeBorder: t.text.alpha(0.2),
            line: t.text.alpha(0.42),
            clusterFill: t.text.alpha(dark ? 0.04 : 0.025),
            noteFill: oklcha(dark ? 0.3 : 0.95, 0.04, 80.0, 1.0),
            noteBorder: oklch(dark ? 0.4 : 0.85, 0.08, 80.0),
            font: TextStyle.new(13.0, 400.0).lh(18.0),
            maxWidth: 680.0
        )
    }
}

/// `src` drawn as a diagram card in `style`, or `nil` when it is outside the supported subset.
public func render(_ src: String, _ style: DiagramStyle) -> El? {
    renderWithHover(src, style, .edges, style.text.alpha(0.9))
}

/// `render`, with `hover` lighting up in `color` while the pointer is over a flowchart, state
/// or class diagram node; an edge, or its label, lights itself and its label whatever `hover` is
/// short of `Hover.off`.
public func renderWithHover(_ src: String, _ style: DiagramStyle, _ hover: Hover, _ color: Color) -> El? {
    renderInner(src, style, hover, color, .still)
}

/// `renderWithHover` for a source still arriving (pass only its complete lines): each node,
/// edge and frame new since the last build comes in on its own, and the rest glide into place.
/// The diagram only grows: what's drawn keeps its order and place, as far as what's new leaves
/// room, and no gap closes.
public func renderStreaming(_ src: String, _ style: DiagramStyle, _ hover: Hover, _ color: Color) -> El? {
    renderInner(src, style, hover, color, .growing)
}

/// `renderStreaming` for the whole source once it has all arrived: laid out as
/// `renderWithHover` lays it out, so the diagram settles there in one glide, while what's
/// new since the last build still comes in on its own.
public func renderStreamed(_ src: String, _ style: DiagramStyle, _ hover: Hover, _ color: Color) -> El? {
    renderInner(src, style, hover, color, .settled)
}

// PORT NOTE: Dual-engine vector snapshot entry point exposing the laid-out `Scene` as a
// framework-agnostic `DiagramScene` so GPUAUI can paint identical geometry via GPUI.
public func renderScene(_ src: String, _ style: DiagramStyle) -> DiagramScene? {
    scenes.built(src, style, nil, nil).0?.diagramScene()
}

private enum RenderMode: Equatable {
    /// Laid out afresh and drawn the frame it mounts.
    case still
    /// Laid out afresh; what's new comes in on its own.
    case settled
    /// Held to the build one line shorter (`steady`); what's new comes in on its own.
    case growing
}

private func renderInner(
    _ src: String,
    _ style: DiagramStyle,
    _ hover: Hover,
    _ color: Color,
    _ mode: RenderMode
) -> El? {
    let hoverArg: (Hover, Color)? = hover != .off ? (hover, color) : nil
    let s: Scene?
    if mode == .growing {
        s = scenes.growing(src, style, hoverArg)
    } else {
        s = scenes.built(src, style, hoverArg, nil).0
    }
    return s?.el(style, mode != .still)
}

/// Whether `src` parses as a supported diagram.
public func supported(_ src: String) -> Bool {
    parse(src) != nil
}

enum Diagram {
    case flowchart(flowchart.Flowchart)
    case sequence(sequence.Sequence)
    case state(state.StateDiagram)
    case `class`(`class`.ClassDiagram)
    case er(er.ErDiagram)
    case gantt(gantt.Gantt)
    case pie(pie.Pie)
    case mindmap(mindmap.Mindmap)
    case timeline(timeline.Timeline)
    case journey(journey.Journey)
    case git(git.GitGraph)
    case quadrant(quadrant.Quadrant)
    case xyChart(xychart.XyChart)
    case sankey(sankey.Sankey)
    case block(block.BlockDiagram)
    case requirement(requirement.Requirements)
    case c4(c4.C4)
}

struct Parsed {
    var title: String?
    var diagram: Diagram
}

/// Diagrams bigger than this are left as source: they would be unreadable at markdown width.
let MAX_ITEMS: Int = 400

/// How deep subgraphs, composite states, frames and other blocks may nest.
let MAX_DEPTH: Int = 8

/// Whether `src`, the complete lines of a diagram still arriving, may draw once more arrive: it
/// has no header yet (only blank lines, comments or front matter), or its header names a type
/// this crate draws.
public func mayDraw(_ src: String) -> Bool {
    let (_, lines) = cleaned(src)
    guard let (_, header) = lines.first else {
        return true
    }
    let firstWord: String
    if let (h, _) = header.splitOnceWhere({ isUnicodeWS($0) || $0 == ";" }) {
        firstWord = String(h)
    } else {
        firstWord = header
    }
    return KINDS.contains(firstWord)
}

/// Every diagram type `parse` reads, by its header's first word.
private let KINDS: Set<String> = [
    "graph", "flowchart", "sequenceDiagram", "stateDiagram", "stateDiagram-v2", "classDiagram",
    "erDiagram", "gantt", "pie", "mindmap", "timeline", "journey", "gitGraph", "gitGraph:",
    "quadrantChart", "xychart-beta", "xychart", "sankey-beta", "sankey", "block-beta", "block",
    "requirementDiagram", "C4Context", "C4Container", "C4Component", "C4Dynamic", "C4Deployment",
]

/// `src`'s front-matter title, and its lines with their indents, without comments, directives
/// and front matter.
private func cleaned(_ src: String) -> (String?, [(Int, String)]) {
    var out: [(Int, String)] = []
    var inDirective = false
    for raw in src.rustLines() {
        let l = String(raw.trimmed())
        if inDirective {
            if let (_, after) = l.splitOnce("}%%") {
                inDirective = false
                let rest = String(after.trimmed())
                if !rest.isEmpty && !rest.hasPrefix("%%") {
                    out.append((0, rest))
                }
            }
            continue
        }
        if l.hasPrefix("%%{") {
            if let (_, after) = l.splitOnce("}%%") {
                let rest = String(after.trimmed())
                if !rest.isEmpty && !rest.hasPrefix("%%") {
                    out.append((0, rest))
                }
            } else {
                inDirective = true
            }
            continue
        }
        if !l.isEmpty && !l.hasPrefix("%%") {
            // Mindmaps nest by indentation.
            let indent = raw.utf8.count - raw.trimmedStart().utf8.count
            out.append((indent, l))
        }
    }
    var idx = 0
    var fmTitle: String? = nil
    // A front-matter block (`---` … `---`) may carry `title: …` and config.
    if idx < out.count && out[idx].1 == "---" {
        idx += 1
        while idx < out.count {
            let l = out[idx].1
            idx += 1
            if l == "---" {
                break
            }
            if let rest = l.stripPrefix("title:") {
                let t = cleanQuoted(String(rest))
                if !t.isEmpty {
                    fmTitle = t
                }
            }
        }
    }
    return (fmTitle, Array(out[idx...]))
}

func parse(_ src: String) -> Parsed? {
    let (fmTitle, lines) = cleaned(src)
    guard let (_, header) = lines.first else {
        return nil
    }
    let kind: String
    let rest: String
    if let (k, r) = header.splitOnceWhere({ isUnicodeWS($0) || $0 == ";" }) {
        kind = String(k)
        rest = String(r)
    } else {
        kind = header
        rest = ""
    }
    let remaining = lines.dropFirst()
    let indents = remaining.map { $0.0 }
    let body = remaining.map { $0.1 }

    let bodyTitle: String?
    let diagram: Diagram
    switch kind {
    case "graph", "flowchart":
        guard let f = flowchart.parse(rest, body) else { return nil }
        bodyTitle = f.title
        diagram = .flowchart(f)
    case "sequenceDiagram":
        guard let s = sequence.parse(rest, body) else { return nil }
        bodyTitle = s.title
        diagram = .sequence(s)
    case "stateDiagram", "stateDiagram-v2":
        guard let s = state.parse(rest, body) else { return nil }
        bodyTitle = s.title
        diagram = .state(s)
    case "classDiagram":
        guard let c = `class`.parse(rest, body) else { return nil }
        bodyTitle = c.title
        diagram = .class(c)
    case "erDiagram":
        guard let e = er.parse(rest, body) else { return nil }
        bodyTitle = e.title
        diagram = .er(e)
    case "gantt":
        guard let g = gantt.parse(rest, body) else { return nil }
        bodyTitle = g.title
        diagram = .gantt(g)
    case "pie":
        guard let p = pie.parse(rest, body) else { return nil }
        bodyTitle = p.title
        diagram = .pie(p)
    case "mindmap":
        guard let m = mindmap.parse(body, indents) else { return nil }
        bodyTitle = nil
        diagram = .mindmap(m)
    case "timeline":
        guard let t = timeline.parse(rest, body) else { return nil }
        bodyTitle = t.title
        diagram = .timeline(t)
    case "journey":
        guard let j = journey.parse(body) else { return nil }
        bodyTitle = j.title
        diagram = .journey(j)
    case "gitGraph", "gitGraph:":
        guard let g = git.parse(rest, body) else { return nil }
        bodyTitle = nil
        diagram = .git(g)
    case "quadrantChart":
        guard let q = quadrant.parse(body) else { return nil }
        bodyTitle = q.title
        diagram = .quadrant(q)
    case "xychart-beta", "xychart":
        guard let x = xychart.parse(rest, body) else { return nil }
        bodyTitle = x.title
        diagram = .xyChart(x)
    case "sankey-beta", "sankey":
        guard let s = sankey.parse(body) else { return nil }
        bodyTitle = nil
        diagram = .sankey(s)
    case "block-beta", "block":
        guard let b = block.parse(body) else { return nil }
        bodyTitle = nil
        diagram = .block(b)
    case "requirementDiagram":
        guard let r = requirement.parse(body) else { return nil }
        bodyTitle = nil
        diagram = .requirement(r)
    case "C4Context", "C4Container", "C4Component", "C4Dynamic", "C4Deployment":
        guard let c = c4.parse(kind, body) else { return nil }
        bodyTitle = c.title
        diagram = .c4(c)
    default:
        return nil
    }
    return Parsed(title: bodyTitle ?? fmTitle, diagram: diagram)
}

func buildScene(_ src: String, _ paint: DiagramStyle, _ hover: (Hover, Color)?) -> Scene? {
    guard let parsed = parse(src) else { return nil }
    let s: Scene?
    switch parsed.diagram {
    case .flowchart(let f): s = flowchart.draw(f, paint, hover)
    case .sequence(let seq): s = sequence.draw(seq, paint)
    case .state(let st): s = state.draw(st, paint, hover)
    case .class(let cls): s = `class`.draw(cls, paint, hover)
    case .er(let e): s = er.draw(e, paint, hover)
    case .gantt(let g): s = gantt.draw(g, paint)
    case .pie(let p): s = pie.draw(p, paint)
    case .mindmap(let m): s = mindmap.draw(m, paint)
    case .timeline(let t): s = timeline.draw(t, paint)
    case .journey(let j): s = journey.draw(j, paint)
    case .git(let g): s = git.draw(g, paint)
    case .quadrant(let q): s = quadrant.draw(q, paint)
    case .xyChart(let x): s = xychart.draw(x, paint)
    case .sankey(let sk): s = sankey.draw(sk, paint)
    case .block(let b): s = block.draw(b, paint)
    case .requirement(let r): s = requirement.draw(r, paint, hover)
    case .c4(let c): s = c4.draw(c, paint, hover)
    }
    return s?.withTitle(parsed.title)
}

/// Strips one pair of surrounding `"…"` quotes (unescaping `\"`), then runs `clean`.
func cleanQuoted(_ s: String) -> String {
    let t = s.trimmed()
    if let afterOpen = t.stripPrefix("\""), let inner = afterOpen.stripSuffix("\"") {
        let unescaped = replaceSubstring(String(inner), "\\\"", "\"")
        return clean(unescaped)
    }
    return clean(String(t))
}

/// Mermaid label markup to plain text: `<br>` and `\n` breaks, entity codes, markdown-string backticks.
func clean(_ raw: String) -> String {
    let trimmed = raw.trimmed()
    let sSub: Substring
    if let a = trimmed.stripPrefix("`"), let b = a.stripSuffix("`") {
        sSub = b
    } else {
        sSub = trimmed
    }
    let scalars = Array(sSub.unicodeScalars)
    var outScalars: [Unicode.Scalar] = []
    outScalars.reserveCapacity(scalars.count)
    var i = 0
    let n = scalars.count

    func matchesCI(_ offset: Int, _ target: StaticString) -> Bool {
        let utf8 = target.utf8Start
        let len = target.utf8CodeUnitCount
        guard offset + len <= n else { return false }
        for k in 0..<len {
            let v = scalars[offset + k].value
            guard v < 128 else { return false }
            let lower = (v >= 65 && v <= 90) ? (v + 32) : v
            if UInt8(lower) != utf8[k] {
                return false
            }
        }
        return true
    }

    func matchesExact(_ offset: Int, _ target: StaticString) -> Bool {
        let utf8 = target.utf8Start
        let len = target.utf8CodeUnitCount
        guard offset + len <= n else { return false }
        for k in 0..<len {
            if scalars[offset + k].value != UInt32(utf8[k]) {
                return false
            }
        }
        return true
    }

    while i < n {
        let sc = scalars[i]
        if sc == "<" || sc == "#" || sc == "&" || sc == "\\" {
            if matchesCI(i, "<br>") {
                outScalars.append("\n")
                i += 4
                continue
            } else if matchesCI(i, "<br/>") {
                outScalars.append("\n")
                i += 5
                continue
            } else if matchesCI(i, "<br />") {
                outScalars.append("\n")
                i += 6
                continue
            } else if matchesExact(i, "\\n") {
                outScalars.append("\n")
                i += 2
                continue
            } else if matchesExact(i, "#quot;") {
                outScalars.append("\"")
                i += 6
                continue
            } else if matchesExact(i, "#59;") {
                outScalars.append(";")
                i += 4
                continue
            } else if matchesExact(i, "#35;") {
                outScalars.append("#")
                i += 4
                continue
            } else if matchesExact(i, "&amp;") {
                outScalars.append("&")
                i += 5
                continue
            } else if matchesExact(i, "&lt;") {
                outScalars.append("<")
                i += 4
                continue
            } else if matchesExact(i, "&gt;") {
                outScalars.append(">")
                i += 4
                continue
            } else if matchesExact(i, "&quot;") {
                outScalars.append("\"")
                i += 6
                continue
            } else if matchesExact(i, "&apos;") || matchesExact(i, "#apos;") {
                outScalars.append("'")
                i += 6
                continue
            }
        }
        outScalars.append(sc)
        i += 1
    }
    var built = ""
    built.unicodeScalars.append(contentsOf: outScalars)
    return built.rustLines().map { String($0.trimmed()) }.joined(separator: "\n")
}

/// Optional CSS-like node colours from `style` or `classDef`.
struct NodeStyle: Sendable, Equatable {
    var fill: Color? = nil
    var stroke: Color? = nil
    var color: Color? = nil

    func merge(_ over: NodeStyle) -> NodeStyle {
        NodeStyle(
            fill: over.fill ?? fill,
            stroke: over.stroke ?? stroke,
            color: over.color ?? color
        )
    }

    /// Resolves `(fill, border, text)` against `paint` in Oklab so light-mode Mermaid hex fills
    /// (like `fill:#dcf5dc`) read cleanly in both dark and light themes without washing out text.
    func resolve(_ paint: DiagramStyle) -> (Color, Color, Color) {
        let resolvedFill = fill.map { adaptFill(paint.nodeFill, $0, 0.055, 0.035) } ?? paint.nodeFill
        let resolvedBorder = (stroke ?? fill).map {
            adaptStroke(paint.nodeBorder, $0, paint.nodeFill.toOklab()[0] < 0.5)
        } ?? paint.nodeBorder
        let resolvedText: Color
        if let c = color, abs(c.toOklab()[0] - resolvedFill.toOklab()[0]) > 0.35 {
            resolvedText = c
        } else {
            resolvedText = paint.text
        }
        return (resolvedFill, resolvedBorder, resolvedText)
    }
}

/// Optional edge overrides from `linkStyle`.
struct EdgeStyle: Sendable, Equatable {
    var stroke: Color? = nil
    var width: Float? = nil

    func merge(_ over: EdgeStyle) -> EdgeStyle {
        EdgeStyle(stroke: over.stroke ?? stroke, width: over.width ?? width)
    }
}

/// Accumulates `classDef`, `class` / `:::class`, and `style` rules and resolves a node's `NodeStyle`.
struct StyleSheet {
    var defs: [String: NodeStyle] = [:]
    var classes: [String: [String]] = [:]
    var inline: [String: NodeStyle] = [:]

    @discardableResult
    mutating func classDef(_ rest: String) -> Bool {
        guard let (names, props) = rest.trimmed().splitOnceWhere({ isUnicodeWS($0) }) else {
            return false
        }
        let st = parseStyleProps(String(props))
        for rawName in names.split(separator: ",", omittingEmptySubsequences: false) {
            let name = String(rawName.trimmed())
            if !name.isEmpty {
                defs[name] = st
            }
        }
        return true
    }

    @discardableResult
    mutating func assignClasses(_ rest: String) -> Bool {
        guard let (targets, clsPart) = rest.trimmed().splitOnceWhere({ isUnicodeWS($0) }) else {
            return false
        }
        let clsList = clsPart
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { String($0.trimmed()) }
            .filter { !$0.isEmpty }
        for rawId in targets.split(separator: ",", omittingEmptySubsequences: false) {
            let id = String(rawId.trimmed())
            if !id.isEmpty {
                for cls in clsList {
                    addClass(id, cls)
                }
            }
        }
        return true
    }

    @discardableResult
    mutating func style(_ rest: String) -> Bool {
        guard let (targets, props) = rest.trimmed().splitOnceWhere({ isUnicodeWS($0) }) else {
            return false
        }
        let st = parseStyleProps(String(props))
        for rawId in targets.split(separator: ",", omittingEmptySubsequences: false) {
            let id = String(rawId.trimmed())
            if !id.isEmpty {
                addStyle(id, st)
            }
        }
        return true
    }

    mutating func addClass(_ id: String, _ cls: String) {
        if !id.isEmpty && !cls.isEmpty {
            classes[id, default: []].append(cls)
        }
    }

    mutating func addStyle(_ id: String, _ st: NodeStyle) {
        if !id.isEmpty {
            let cur = inline[id] ?? NodeStyle()
            inline[id] = cur.merge(st)
        }
    }

    /// Strips a trailing `:::class` from `raw`, recording the class assignment.
    mutating func stripInline(_ raw: String) -> String? {
        if let (idSub, clsSub) = raw.splitOnce(":::") {
            let id = String(idSub.trimmed())
            let cls = String(clsSub.trimmed())
            if id.isEmpty || cls.isEmpty {
                return nil
            }
            addClass(id, cls)
            return id
        }
        return String(raw.trimmed())
    }

    func get(_ id: String) -> NodeStyle {
        var st = NodeStyle()
        if let clsList = classes[id] {
            for cls in clsList {
                if let cs = defs[cls] {
                    st = st.merge(cs)
                }
            }
        }
        if let inl = inline[id] {
            st = st.merge(inl)
        }
        return st
    }
}

/// Adapts a user colour `c` into a subtle Oklab fill harmonious with `base`.
func adaptFill(_ base: Color, _ c: Color, _ darkLift: Float, _ lightDrop: Float) -> Color {
    let baseL = base.toOklab()[0]
    let dark = baseL < 0.5
    let lab = c.toOklab()
    let a = lab[1]
    let b = lab[2]
    let chroma = mHypot(a, b)
    if chroma < 0.01 {
        return oklabMix(base, c, 0.2)
    }
    let scale = clampF(chroma * 0.9, 0.032, 0.075) / chroma
    let l = dark ? min(baseL + darkLift, 0.42) : max(baseL - lightDrop, 0.82)
    return Color.fromOklab([l, a * scale, b * scale, base.a])
}

func adaptStroke(_ base: Color, _ c: Color, _ dark: Bool) -> Color {
    let lab = c.toOklab()
    let a = lab[1]
    let b = lab[2]
    let chroma = mHypot(a, b)
    if chroma < 0.01 {
        return oklabMix(base, c, 0.35)
    }
    let scale = clampF(chroma * 1.1, 0.07, 0.13) / chroma
    return Color.fromOklab([dark ? 0.58 : 0.60, a * scale, b * scale, 1.0])
}

func oklabMix(_ aCol: Color, _ bCol: Color, _ t: Float) -> Color {
    let a = aCol.toOklab()
    let b = bCol.toOklab()
    return Color.fromOklab([
        a[0] + (b[0] - a[0]) * t,
        a[1] + (b[1] - a[1]) * t,
        a[2] + (b[2] - a[2]) * t,
        a[3],
    ])
}

func parseStyleProps(_ props: String) -> NodeStyle {
    var out = NodeStyle()
    for part in props.split(whereSeparator: { $0 == "," || $0 == ";" }) {
        guard let (k, vRaw) = part.splitOnce(":") else { continue }
        let v = String(vRaw.trimmed().trimEndMatches("!important").trimmed())
        switch k.trimmed() {
        case "fill": out.fill = parseColorSpec(v)
        case "stroke": out.stroke = parseColorSpec(v)
        case "color": out.color = parseColorSpec(v)
        default: break
        }
    }
    return out
}

func parseEdgeStyleProps(_ props: String) -> EdgeStyle {
    var out = EdgeStyle()
    for part in props.split(whereSeparator: { $0 == "," || $0 == ";" }) {
        guard let (k, vRaw) = part.splitOnce(":") else { continue }
        let v = String(vRaw.trimmed().trimEndMatches("!important").trimmed())
        switch k.trimmed() {
        case "stroke":
            out.stroke = parseColorSpec(v)
        case "stroke-width":
            let numStr = String(v.trimEndMatches("px").trimmed())
            if let w = Float(numStr), w.isFinite {
                out.width = clampF(w, 0.75, 5.0)
            }
        default:
            break
        }
    }
    return out
}

/// `#hex`, `rgb(r, g, b)`, `rgba(r, g, b, a)`, or a common CSS colour word.
func parseColorSpec(_ s: String) -> Color? {
    let t = String(s.trimmed())
    if let c = Rune.color.hex(t) {
        return c
    }
    let lower = t.asciiLower()
    let rgbInner: Substring? = (lower.stripPrefix("rgb(") ?? lower.stripPrefix("rgba("))?.stripSuffix(")")
    if let inner = rgbInner {
        let nums: [Float] = inner
            .split(separator: ",", omittingEmptySubsequences: false)
            .compactMap { part in
                guard let v = Float(String(part.trimmed())), v.isFinite else { return nil }
                return v
            }
        if nums.count >= 3 {
            let r = Rune.color.srgbDecode(clampF(nums[0] / 255.0, 0.0, 1.0))
            let g = Rune.color.srgbDecode(clampF(nums[1] / 255.0, 0.0, 1.0))
            let b = Rune.color.srgbDecode(clampF(nums[2] / 255.0, 0.0, 1.0))
            let a = clampF(nums.count > 3 ? nums[3] : 1.0, 0.0, 1.0)
            return Color(r: r, g: g, b: b, a: a)
        }
    }
    let hexCode: String
    switch lower {
    case "red", "crimson", "salmon", "lightcoral", "pink": hexCode = "#ef4444"
    case "green", "lightgreen", "palegreen", "emerald", "lime": hexCode = "#22c55e"
    case "blue", "lightblue", "skyblue", "dodgerblue": hexCode = "#3b82f6"
    case "yellow", "lightyellow", "gold", "amber", "orange": hexCode = "#eab308"
    case "purple", "violet", "lavender", "magenta": hexCode = "#a855f7"
    case "cyan", "aqua", "teal", "turquoise": hexCode = "#06b6d4"
    case "gray", "grey", "lightgray", "lightgrey", "silver": hexCode = "#9ca3af"
    default: return nil
    }
    return Rune.color.hex(hexCode)
}

/// What follows keyword `w` and a space, trimmed.
func word(_ l: String, _ w: String) -> String? {
    guard let r = l.stripPrefix(w) else { return nil }
    guard r.isEmpty || (r.unicodeScalars.first?.properties.isWhitespace == true) else {
        return nil
    }
    return String(r.trimmed())
}

/// A line split at `;` outside quotes and brackets (and never at an HTML entity's `;`).
func statements(_ line: String) -> [String] {
    var out: [Substring] = []
    var start = line.unicodeScalars.startIndex
    var quoted = false
    var escaped = false
    var brackets = 0
    var idx = line.unicodeScalars.startIndex
    while idx < line.unicodeScalars.endIndex {
        let c = line.unicodeScalars[idx]
        let nextIdx = line.unicodeScalars.index(after: idx)
        if escaped {
            escaped = false
            idx = nextIdx
            continue
        }
        if quoted {
            if c == "\\" {
                escaped = true
            } else if c == "\"" {
                quoted = false
            }
            idx = nextIdx
            continue
        }
        switch c {
        case "\"":
            quoted = true
        case "[", "(", "{":
            brackets += 1
        case "]", ")", "}":
            brackets = max(0, brackets - 1)
        case ";" where brackets == 0:
            out.append(line[start..<idx])
            start = nextIdx
        default:
            break
        }
        idx = nextIdx
    }
    out.append(line[start...])
    return out
        .map { String($0.trimmed()) }
        .filter { !$0.isEmpty && !$0.hasPrefix("%%") }
}

/// A scalar cursor over one statement, matching Rust `Cur<'a>` byte-for-scalar semantics.
struct Cur {
    let s: String
    var i: String.UnicodeScalarIndex

    init(_ s: String) {
        self.s = s
        self.i = s.unicodeScalars.startIndex
    }

    func rest() -> Substring {
        s[i...]
    }

    func restString() -> String {
        String(s[i...])
    }

    func peek() -> Unicode.Scalar? {
        i < s.unicodeScalars.endIndex ? s.unicodeScalars[i] : nil
    }

    func peek2() -> Unicode.Scalar? {
        guard i < s.unicodeScalars.endIndex else { return nil }
        let next = s.unicodeScalars.index(after: i)
        return next < s.unicodeScalars.endIndex ? s.unicodeScalars[next] : nil
    }

    mutating func bump() {
        if i < s.unicodeScalars.endIndex {
            i = s.unicodeScalars.index(after: i)
        }
    }

    mutating func eat(_ t: String) -> Bool {
        let rem = s.unicodeScalars[i...]
        let target = t.unicodeScalars
        var rIdx = rem.startIndex
        for sc in target {
            guard rIdx < rem.endIndex, rem[rIdx] == sc else {
                return false
            }
            rIdx = rem.index(after: rIdx)
        }
        i = rIdx
        return true
    }

    mutating func skipWs() {
        while let c = peek(), c.properties.isWhitespace {
            bump()
        }
    }

    func done() -> Bool {
        i >= s.unicodeScalars.endIndex
    }
}

// MARK: - Pure-Swift String / Substring Helpers (no Foundation dependency)

@inline(__always)
func isUnicodeWS(_ ch: Character) -> Bool {
    ch.unicodeScalars.allSatisfy { $0.properties.isWhitespace }
}

func replaceSubstring(_ s: String, _ target: String, _ replacement: String) -> String {
    guard !target.isEmpty else { return s }
    var out = ""
    var rem: Substring = s[...]
    while let (before, after) = rem.splitOnce(target) {
        out += before
        out += replacement
        rem = after
    }
    out += rem
    return out
}

extension StringProtocol {
    func trimmedStart() -> SubSequence {
        var idx = startIndex
        while idx < endIndex && isUnicodeWS(self[idx]) {
            idx = index(after: idx)
        }
        return self[idx...]
    }

    func trimmedEnd() -> SubSequence {
        var idx = endIndex
        while idx > startIndex {
            let prev = index(before: idx)
            if isUnicodeWS(self[prev]) {
                idx = prev
            } else {
                break
            }
        }
        return self[..<idx]
    }

    func trimmed() -> SubSequence {
        trimmedStart().trimmedEnd()
    }

    func stripPrefix(_ prefix: String) -> SubSequence? {
        guard hasPrefix(prefix) else { return nil }
        return dropFirst(prefix.count)
    }

    func stripSuffix(_ suffix: String) -> SubSequence? {
        guard hasSuffix(suffix) else { return nil }
        return dropLast(suffix.count)
    }

    func trimEndMatches(_ suffix: String) -> SubSequence {
        guard !suffix.isEmpty else { return self[...] }
        var cur = self[...]
        while cur.hasSuffix(suffix) {
            cur = cur.dropLast(suffix.count)
        }
        return cur
    }

    func splitOnce(_ sep: Character) -> (SubSequence, SubSequence)? {
        guard let idx = firstIndex(of: sep) else { return nil }
        return (self[..<idx], self[index(after: idx)...])
    }

    func splitOnce(_ sep: String) -> (SubSequence, SubSequence)? {
        guard !sep.isEmpty else { return (self[..<startIndex], self[...]) }
        var idx = startIndex
        while idx < endIndex {
            if self[idx...].hasPrefix(sep) {
                let after = index(idx, offsetBy: sep.count)
                return (self[..<idx], self[after...])
            }
            idx = index(after: idx)
        }
        return nil
    }

    func splitOnceWhere(_ predicate: (Character) -> Bool) -> (SubSequence, SubSequence)? {
        guard let idx = firstIndex(where: predicate) else { return nil }
        return (self[..<idx], self[index(after: idx)...])
    }

    func rsplitOnce(_ sep: Character) -> (SubSequence, SubSequence)? {
        guard let idx = lastIndex(of: sep) else { return nil }
        return (self[..<idx], self[index(after: idx)...])
    }

    func rsplitOnce(_ sep: String) -> (SubSequence, SubSequence)? {
        guard !sep.isEmpty else { return (self[...], self[endIndex...]) }
        var found: Index? = nil
        var idx = startIndex
        while idx < endIndex {
            if self[idx...].hasPrefix(sep) {
                found = idx
            }
            idx = index(after: idx)
        }
        guard let f = found else { return nil }
        let after = index(f, offsetBy: sep.count)
        return (self[..<f], self[after...])
    }

    func asciiLower() -> String {
        var out = ""
        out.unicodeScalars.reserveCapacity(unicodeScalars.count)
        for sc in unicodeScalars {
            if sc.value >= 65 && sc.value <= 90 {
                out.unicodeScalars.append(Unicode.Scalar(sc.value + 32)!)
            } else {
                out.unicodeScalars.append(sc)
            }
        }
        return out
    }

    /// Matches Rust `str::lines()`: splits on `\n` or `\r\n`, yields `[]` for `""`, and drops a single trailing newline.
    func rustLines() -> [String] {
        guard !isEmpty else { return [] }
        var lines: [String] = []
        var cur = ""
        var i = unicodeScalars.startIndex
        let end = unicodeScalars.endIndex
        var endedWithNewline = false
        while i < end {
            let sc = unicodeScalars[i]
            let next = unicodeScalars.index(after: i)
            if sc == "\n" {
                lines.append(cur)
                cur = ""
                endedWithNewline = (next == end)
                i = next
            } else if sc == "\r" && next < end && unicodeScalars[next] == "\n" {
                lines.append(cur)
                cur = ""
                let afterCRLF = unicodeScalars.index(after: next)
                endedWithNewline = (afterCRLF == end)
                i = afterCRLF
            } else {
                cur.unicodeScalars.append(sc)
                endedWithNewline = false
                i = next
            }
        }
        if !endedWithNewline {
            lines.append(cur)
        }
        return lines
    }
}
