// Ported from: crates/rune-mermaid/src/sequence.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Sequence diagrams: the parser for `sequenceDiagram` sources and their drawing.

import Rune

enum sequence {
    struct Participant {
        var id: String
        var label: String
        var kind: Kind
        var group: Int?
    }

    /// How a participant's head draws: `actor`, or a v11 `participant A@{ "type": "…" }`.
    enum Kind: Sendable, Equatable {
        case box
        case actor
        case boundary
        case control
        case entity
        case database
        case collections
        case queue
    }

    struct ParticipantBox {
        var title: String
        var color: Color?
    }

    enum Tip: Sendable, Equatable {
        case none
        case filled
        case open
        case cross
    }

    struct Message {
        var from: Int
        var to: Int
        var text: String
        var dotted: Bool
        var tip: Tip
        var both: Bool
        var activate: Bool
        var deactivate: Bool
    }

    enum NotePos: Sendable, Equatable {
        case left(Int)
        case right(Int)
        case over(Int, Int)
    }

    enum Event {
        case message(Message)
        case note(NotePos, String)
        case activate(Int)
        case deactivate(Int)
        /// `create`: the participant's head draws here instead of at the top.
        case create(Int)
        /// `destroy`: the participant's lifeline ends after its next message.
        case destroy(Int)
        /// `autonumber [start [step]]` from here on, or `autonumber off` (`nil`).
        case number((UInt32, UInt32)?)
        /// A frame (`kind != nil`) or a `rect` highlight band (`kind == nil`, with optional colour).
        case open(kind: String?, label: String, fill: Color?)
        case `else`(String)
        case end
    }

    struct Sequence {
        var title: String?
        var participants: [Participant]
        var boxes: [ParticipantBox]
        var events: [Event]
        var autonumber: Bool
    }

    static func draw(_ s: Sequence, _ paint: DiagramStyle) -> Scene? {
        sequenceDraw.draw(s, paint)
    }

    static func parse(_ header: String, _ body: [String]) -> Sequence? {
        _ = header
        var p = Parser(
            s: Sequence(title: nil, participants: [], boxes: [], events: [], autonumber: false),
            ids: [:],
            depth: 0,
            activeBox: nil
        )
        // A line that doesn't read is skipped; one past the bounds leaves the whole diagram as source.
        for line in body {
            let people = p.s.participants.count
            let events = p.s.events.count
            if !p.line(line) {
                // Whatever the line added before it failed goes too.
                if p.s.participants.count > people {
                    p.s.participants.removeSubrange(people...)
                }
                if p.s.events.count > events {
                    p.s.events.removeSubrange(events...)
                }
                p.ids = p.ids.filter { $0.value < people }
            }
            if p.s.participants.count > 40 || p.s.events.count > MAX_ITEMS || p.depth > MAX_DEPTH {
                return nil
            }
        }
        // Frames still open at the end close there.
        if p.depth > 0 {
            for _ in 0..<p.depth {
                p.s.events.append(.end)
            }
        }
        return p.s.participants.isEmpty ? nil : p.s
    }

    private static let ARROWS: [(String, Bool, Tip, Bool)] = [
        ("<<-->>", true, .filled, true),
        ("<<->>", false, .filled, true),
        ("-->>", true, .filled, false),
        ("->>", false, .filled, false),
        ("--x", true, .cross, false),
        ("-x", false, .cross, false),
        ("--)", true, .open, false),
        ("-)", false, .open, false),
        ("-->", true, .none, false),
        ("->", false, .none, false),
    ]

    private struct Parser {
        var s: Sequence
        var ids: [String: Int]
        var depth: Int
        var activeBox: Int?

        mutating func line(_ rawLine: String) -> Bool {
            let l = String(rawLine.trimmed().trimEndMatches(";").trimmedEnd())
            let kw: String
            let rest: String
            if let (w, r) = l.splitOnceWhere({ isUnicodeWS($0) }) {
                kw = String(w)
                rest = String(r.trimmed())
            } else {
                kw = l
                rest = ""
            }
            let kwClean = String(kw.trimEndMatches(":"))
            switch kwClean {
            case "participant", "actor":
                return declare(rest, kw == "actor") != nil
            case "create":
                let kindStr: String
                let nameStr: String
                if let (w, r) = rest.splitOnceWhere({ isUnicodeWS($0) }) {
                    kindStr = String(w)
                    nameStr = String(r.trimmed())
                } else {
                    kindStr = rest
                    nameStr = ""
                }
                guard kindStr == "participant" || kindStr == "actor",
                      let i = declare(nameStr, kindStr == "actor")
                else { return false }
                s.events.append(.create(i))
            case "destroy":
                guard let i = id(rest) else { return false }
                s.events.append(.destroy(i))
            case "title":
                var afterTitle = l.dropFirst("title".count).trimmed()
                while afterTitle.first == ":" {
                    afterTitle = afterTitle.dropFirst()
                }
                let t = cleanQuoted(String(afterTitle))
                if !t.isEmpty {
                    s.title = t
                }
            case "accTitle", "accDescr", "link", "links", "properties", "details":
                break
            case "autonumber":
                let tokens = rest.split(whereSeparator: { isUnicodeWS($0) })
                let on: (UInt32, UInt32)?
                if rest == "off" {
                    on = nil
                } else if tokens.isEmpty {
                    on = (1, 1)
                } else if tokens.count == 1 {
                    guard let start = UInt32(tokens[0]) else { return false }
                    on = (start, 1)
                } else {
                    guard let start = UInt32(tokens[0]), let step = UInt32(tokens[1]) else { return false }
                    on = (start, step)
                }
                if on != nil {
                    s.autonumber = true
                }
                s.events.append(.number(on))
            case "activate":
                guard let i = id(rest) else { return false }
                s.events.append(.activate(i))
            case "deactivate":
                guard let i = id(rest) else { return false }
                s.events.append(.deactivate(i))
            case "Note", "note":
                return note(rest)
            case "loop", "alt", "opt", "par", "critical", "break":
                depth += 1
                s.events.append(.open(kind: kwClean, label: clean(rest), fill: nil))
            case "rect":
                depth += 1
                s.events.append(.open(kind: nil, label: "", fill: parseColorSpec(rest)))
            case "box":
                if activeBox != nil {
                    return false
                }
                let (col, title) = parseBoxHeader(rest)
                s.boxes.append(ParticipantBox(title: title, color: col))
                activeBox = s.boxes.count - 1
            case "else", "and", "option":
                if depth == 0 {
                    return false
                }
                s.events.append(.else(clean(rest)))
            case "end":
                if activeBox != nil {
                    activeBox = nil
                } else {
                    guard depth > 0 else { return false }
                    depth -= 1
                    s.events.append(.end)
                }
            default:
                return message(l)
            }
            return true
        }

        mutating func declare(_ rest: String, _ isActor: Bool) -> Int? {
            let restId: String
            let meta: String
            if let (idSub, metaSub) = rest.splitOnce("@{") {
                restId = String(idSub)
                meta = String(metaSub)
            } else {
                restId = rest
                meta = ""
            }
            let kind: Kind = isActor ? .actor : metaKind(meta)
            let pId: String
            let label: String
            if let (idSub, lblSub) = restId.splitOnce(" as ") {
                pId = String(idSub.trimmed())
                label = cleanQuoted(String(lblSub))
            } else {
                pId = String(restId.trimmed())
                label = cleanQuoted(restId)
            }
            guard let i = id(pId) else { return nil }
            s.participants[i].label = label
            s.participants[i].kind = kind
            if s.participants[i].group == nil {
                s.participants[i].group = activeBox
            }
            return i
        }

        mutating func id(_ rawName: String) -> Int? {
            var nameSub = rawName.trimmed()
            while nameSub.first == "\"" { nameSub = nameSub.dropFirst() }
            while nameSub.last == "\"" { nameSub = nameSub.dropLast() }
            let name = String(nameSub)
            if name.isEmpty || name.contains(":") || name.contains(",") {
                return nil
            }
            if let existing = ids[name] {
                return existing
            }
            s.participants.append(
                Participant(id: name, label: clean(name), kind: .box, group: activeBox)
            )
            let idx = s.participants.count - 1
            ids[name] = idx
            return idx
        }

        mutating func note(_ rest: String) -> Bool {
            guard let (placeRaw, textRaw) = rest.splitOnce(":") else { return false }
            let place = String(placeRaw.trimmed())
            let lower = place.asciiLower()
            let pos: NotePos
            if lower.hasPrefix("left of ") {
                let who = String(place.dropFirst("left of ".count))
                guard let a = id(who) else { return false }
                pos = .left(a)
            } else if lower.hasPrefix("right of ") {
                let who = String(place.dropFirst("right of ".count))
                guard let a = id(who) else { return false }
                pos = .right(a)
            } else if lower.hasPrefix("over ") {
                let who = String(place.dropFirst("over ".count))
                if let (aSub, bSub) = who.splitOnce(",") {
                    guard let a = id(String(aSub)), let b = id(String(bSub)) else { return false }
                    pos = .over(min(a, b), max(a, b))
                } else {
                    guard let a = id(who) else { return false }
                    pos = .over(a, a)
                }
            } else {
                return false
            }
            s.events.append(.note(pos, cleanQuoted(String(textRaw))))
            return true
        }

        mutating func message(_ l: String) -> Bool {
            let lhs: String
            let text: String
            if let (lhsSub, textSub) = l.splitOnce(":") {
                lhs = String(lhsSub)
                text = String(textSub)
            } else {
                lhs = l
                text = ""
            }
            var found: (String.Index, (String, Bool, Tip, Bool))? = nil
            var idx = lhs.startIndex
            while idx < lhs.endIndex {
                let ch = lhs[idx]
                if ch == "-" || ch == "<" {
                    let rem = lhs[idx...]
                    if let arrow = ARROWS.first(where: { rem.hasPrefix($0.0) }) {
                        found = (idx, arrow)
                        break
                    }
                }
                idx = lhs.index(after: idx)
            }
            guard let (at, (tok, dotted, tip, both)) = found else { return false }
            let fromRaw = String(lhs[..<at].trimmed())
            let afterArrow = lhs.index(at, offsetBy: tok.count)
            let restSub = lhs[afterArrow...].trimmedStart()
            let activate: Bool
            let deactivate: Bool
            let toRaw: String
            if restSub.first == "+" {
                activate = true
                deactivate = false
                toRaw = String(restSub.dropFirst())
            } else if restSub.first == "-" {
                activate = false
                deactivate = true
                toRaw = String(restSub.dropFirst())
            } else {
                activate = false
                deactivate = false
                toRaw = String(restSub)
            }
            guard let from = id(fromRaw), let to = id(toRaw) else { return false }
            s.events.append(
                .message(
                    Message(
                        from: from,
                        to: to,
                        text: clean(text),
                        dotted: dotted,
                        tip: tip,
                        both: both,
                        activate: activate,
                        deactivate: deactivate
                    )
                )
            )
            return true
        }
    }

    /// The kind a v11 `@{ "type": "database" }` names; anything else is a plain box.
    private static func metaKind(_ meta: String) -> Kind {
        guard let (_, after) = meta.splitOnce("type") else { return .box }
        let trimmed = after.drop { ch in ch == "\"" || ch == ":" || isUnicodeWS(ch) }
        let name = String(trimmed.prefix { ch in
            ch.isASCII && ((ch >= "a" && ch <= "z") || (ch >= "A" && ch <= "Z"))
        })
        switch name {
        case "actor": return .actor
        case "boundary": return .boundary
        case "control": return .control
        case "entity": return .entity
        case "database": return .database
        case "collections": return .collections
        case "queue": return .queue
        default: return .box
        }
    }

    private static func parseBoxHeader(_ raw: String) -> (Color?, String) {
        let rest = String(raw.trimmed())
        if rest.isEmpty {
            return (nil, "")
        }
        if let afterParen = rest.stripPrefix("rgb(") ?? rest.stripPrefix("rgba("),
           let closeIdx = afterParen.firstIndex(of: ")")
        {
            let afterClose = rest.index(after: closeIdx)
            let colSpec = String(rest[..<afterClose])
            let tail = String(rest[afterClose...])
            return (parseColorSpec(colSpec), cleanQuoted(tail))
        }
        let first: String
        let tail: String
        if let (f, t) = rest.splitOnceWhere({ isUnicodeWS($0) }) {
            first = String(f)
            tail = String(t)
        } else {
            first = rest
            tail = ""
        }
        if first.asciiLower() == "transparent" {
            return (nil, cleanQuoted(tail))
        }
        if let c = parseColorSpec(first) {
            return (c, cleanQuoted(tail))
        }
        return (nil, cleanQuoted(rest))
    }
}
