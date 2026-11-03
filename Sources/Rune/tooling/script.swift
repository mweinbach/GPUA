// Ported from: crates/rune/src/tooling/script.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Parsing a `--script`'s JSON into input events, plus portable JSON value parsing/serialization.

#if !os(WASI)
import Foundation
#endif

// MARK: - Portable Pure-Swift JSON Value (`ToolingJson`)

/// Pure-Swift JSON representation so `--script`, `--tree`, and `--trace` work identically across macOS, Linux, Windows, Android, and WASI.
enum ToolingJson: Sendable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case int(Int64)
    case string(String)
    case array([ToolingJson])
    case object([(String, ToolingJson)])

    static func == (lhs: ToolingJson, rhs: ToolingJson) -> Bool {
        switch (lhs, rhs) {
        case (.null, .null): return true
        case (.bool(let a), .bool(let b)): return a == b
        case (.int(let a), .int(let b)): return a == b
        case (.number(let a), .number(let b)): return a == b
        case (.int(let a), .number(let b)): return Double(a) == b
        case (.number(let a), .int(let b)): return a == Double(b)
        case (.string(let a), .string(let b)): return a == b
        case (.array(let a), .array(let b)): return a == b
        case (.object(let a), .object(let b)):
            guard a.count == b.count else { return false }
            for (k, v) in a {
                guard let bv = b.first(where: { $0.0 == k })?.1, bv == v else { return false }
            }
            return true
        default:
            return false
        }
    }

    var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    var isNumber: Bool {
        switch self {
        case .number, .int: return true
        default: return false
        }
    }

    var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    var doubleValue: Double? {
        switch self {
        case .number(let d): return d
        case .int(let i): return Double(i)
        default: return nil
        }
    }

    var intValue: Int64? {
        switch self {
        case .int(let i): return i
        case .number(let d): return Int64(exactly: d)
        default: return nil
        }
    }

    var arrayValue: [ToolingJson]? {
        if case .array(let a) = self { return a }
        return nil
    }

    var objectEntries: [(String, ToolingJson)]? {
        if case .object(let o) = self { return o }
        return nil
    }

    subscript(_ key: String) -> ToolingJson {
        get {
            guard case .object(let entries) = self else { return .null }
            return entries.first(where: { $0.0 == key })?.1 ?? .null
        }
        set {
            guard case .object(var entries) = self else { return }
            if let idx = entries.firstIndex(where: { $0.0 == key }) {
                entries[idx] = (key, newValue)
            } else {
                entries.append((key, newValue))
            }
            self = .object(entries)
        }
    }

    func get(_ key: String) -> ToolingJson? {
        guard case .object(let entries) = self else { return nil }
        return entries.first(where: { $0.0 == key })?.1
    }

    mutating func removeKey(_ key: String) {
        guard case .object(var entries) = self else { return }
        entries.removeAll { $0.0 == key }
        self = .object(entries)
    }

    static func fromAny(_ value: Any) -> ToolingJson {
        if let j = value as? ToolingJson { return j }
        if let b = value as? Bool { return .bool(b) }
        if let i = value as? Int { return .int(Int64(i)) }
        if let i = value as? Int64 { return .int(i) }
        if let i = value as? Int32 { return .int(Int64(i)) }
        if let u = value as? UInt32 { return .int(Int64(u)) }
        if let u = value as? UInt64 { return .int(Int64(clamping: u)) }
        if let f = value as? Float { return .number(Double(f)) }
        if let d = value as? Double { return .number(d) }
        if let s = value as? String { return .string(s) }
        if let arr = value as? [Any] {
            return .array(arr.map { fromAny($0) })
        }
        if let dict = value as? [String: Any] {
            let sorted = dict.keys.sorted().map { k in (k, fromAny(dict[k]!)) }
            return .object(sorted)
        }
        return .null
    }

    func toAny() -> Any {
        switch self {
        case .null: return Optional<Any>.none as Any
        case .bool(let b): return b
        case .int(let i): return i
        case .number(let d): return d
        case .string(let s): return s
        case .array(let a): return a.map { $0.toAny() }
        case .object(let entries):
            var dict: [String: Any] = [:]
            for (k, v) in entries {
                dict[k] = v.toAny()
            }
            return dict
        }
    }

    func serialized(pretty: Bool = false) -> String {
        var out = ""
        writeJson(into: &out, indent: pretty ? 0 : nil)
        return out
    }

    private func writeJson(into out: inout String, indent: Int?) {
        switch self {
        case .null:
            out += "null"
        case .bool(let b):
            out += b ? "true" : "false"
        case .int(let i):
            out += "\(i)"
        case .number(let d):
            if !d.isFinite {
                out += "null"
            } else if let exact = Int64(exactly: d), abs(d) < 1e15, String(d).hasSuffix(".0") {
                out += "\(exact).0"
            } else {
                var s = String(d)
                if s == "-0.0" { s = "0.0" }
                out += s
            }
        case .string(let s):
            out += toolingEscapeJsonString(s)
        case .array(let items):
            if items.isEmpty {
                out += "[]"
                return
            }
            if let indent {
                let childPad = String(repeating: " ", count: (indent + 1) * 2)
                let closePad = String(repeating: " ", count: indent * 2)
                out += "[\n"
                for (idx, item) in items.enumerated() {
                    if idx > 0 { out += ",\n" }
                    out += childPad
                    item.writeJson(into: &out, indent: indent + 1)
                }
                out += "\n\(closePad)]"
            } else {
                out += "["
                for (idx, item) in items.enumerated() {
                    if idx > 0 { out += "," }
                    item.writeJson(into: &out, indent: nil)
                }
                out += "]"
            }
        case .object(let entries):
            if entries.isEmpty {
                out += "{}"
                return
            }
            if let indent {
                let childPad = String(repeating: " ", count: (indent + 1) * 2)
                let closePad = String(repeating: " ", count: indent * 2)
                out += "{\n"
                for (idx, (k, v)) in entries.enumerated() {
                    if idx > 0 { out += ",\n" }
                    out += "\(childPad)\(toolingEscapeJsonString(k)): "
                    v.writeJson(into: &out, indent: indent + 1)
                }
                out += "\n\(closePad)}"
            } else {
                out += "{"
                for (idx, (k, v)) in entries.enumerated() {
                    if idx > 0 { out += "," }
                    out += "\(toolingEscapeJsonString(k)):"
                    v.writeJson(into: &out, indent: nil)
                }
                out += "}"
            }
        }
    }

    static func parse(_ text: String) throws -> ToolingJson {
        var parser = ToolingJsonParser(Array(text.utf8))
        let val = try parser.parseValue()
        parser.skipWhitespace()
        guard parser.atEnd else {
            throw ToolingCliError("trailing characters in JSON at byte \(parser.pos)")
        }
        return val
    }
}

func toolingEscapeJsonString(_ s: String) -> String {
    var out = "\""
    out.reserveCapacity(s.utf8.count + 2)
    for scalar in s.unicodeScalars {
        switch scalar.value {
        case 0x22: out += "\\\""
        case 0x5C: out += "\\\\"
        case 0x08: out += "\\b"
        case 0x0C: out += "\\f"
        case 0x0A: out += "\\n"
        case 0x0D: out += "\\r"
        case 0x09: out += "\\t"
        case 0x00...0x1F:
            let hex = String(scalar.value, radix: 16)
            out += "\\u" + String(repeating: "0", count: max(0, 4 - hex.count)) + hex
        default:
            out.unicodeScalars.append(scalar)
        }
    }
    out += "\""
    return out
}

private struct ToolingJsonParser {
    let bytes: [UInt8]
    var pos: Int = 0

    init(_ bytes: [UInt8]) {
        self.bytes = bytes
    }

    var atEnd: Bool { pos >= bytes.count }

    mutating func skipWhitespace() {
        while pos < bytes.count {
            let b = bytes[pos]
            if b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D {
                pos += 1
            } else {
                break
            }
        }
    }

    mutating func parseValue() throws -> ToolingJson {
        skipWhitespace()
        guard pos < bytes.count else {
            throw ToolingCliError("unexpected end of JSON")
        }
        switch bytes[pos] {
        case UInt8(ascii: "{"): return try parseObject()
        case UInt8(ascii: "["): return try parseArray()
        case UInt8(ascii: "\""): return .string(try parseString())
        case UInt8(ascii: "t"):
            try expectLiteral("true")
            return .bool(true)
        case UInt8(ascii: "f"):
            try expectLiteral("false")
            return .bool(false)
        case UInt8(ascii: "n"):
            try expectLiteral("null")
            return .null
        default:
            return try parseNumber()
        }
    }

    private mutating func expectLiteral(_ lit: StaticString) throws {
        let count = lit.utf8CodeUnitCount
        guard pos + count <= bytes.count else {
            throw ToolingCliError("unexpected end of JSON")
        }
        let ok = lit.withUTF8Buffer { buf in
            for k in 0..<count where bytes[pos + k] != buf[k] {
                return false
            }
            return true
        }
        guard ok else {
            throw ToolingCliError("invalid JSON literal at byte \(pos)")
        }
        pos += count
    }

    private mutating func parseObject() throws -> ToolingJson {
        pos += 1 // '{'
        skipWhitespace()
        var entries: [(String, ToolingJson)] = []
        if pos < bytes.count && bytes[pos] == UInt8(ascii: "}") {
            pos += 1
            return .object(entries)
        }
        while true {
            skipWhitespace()
            guard pos < bytes.count, bytes[pos] == UInt8(ascii: "\"") else {
                throw ToolingCliError("expected object key at byte \(pos)")
            }
            let key = try parseString()
            skipWhitespace()
            guard pos < bytes.count, bytes[pos] == UInt8(ascii: ":") else {
                throw ToolingCliError("expected ':' at byte \(pos)")
            }
            pos += 1
            let val = try parseValue()
            if let existing = entries.firstIndex(where: { $0.0 == key }) {
                entries[existing] = (key, val)
            } else {
                entries.append((key, val))
            }
            skipWhitespace()
            guard pos < bytes.count else {
                throw ToolingCliError("unterminated JSON object")
            }
            if bytes[pos] == UInt8(ascii: "}") {
                pos += 1
                return .object(entries)
            }
            guard bytes[pos] == UInt8(ascii: ",") else {
                throw ToolingCliError("expected ',' or '}' at byte \(pos)")
            }
            pos += 1
        }
    }

    private mutating func parseArray() throws -> ToolingJson {
        pos += 1 // '['
        skipWhitespace()
        var items: [ToolingJson] = []
        if pos < bytes.count && bytes[pos] == UInt8(ascii: "]") {
            pos += 1
            return .array(items)
        }
        while true {
            items.append(try parseValue())
            skipWhitespace()
            guard pos < bytes.count else {
                throw ToolingCliError("unterminated JSON array")
            }
            if bytes[pos] == UInt8(ascii: "]") {
                pos += 1
                return .array(items)
            }
            guard bytes[pos] == UInt8(ascii: ",") else {
                throw ToolingCliError("expected ',' or ']' at byte \(pos)")
            }
            pos += 1
        }
    }

    private mutating func parseString() throws -> String {
        pos += 1 // '"'
        var utf8Out: [UInt8] = []
        while pos < bytes.count {
            let b = bytes[pos]
            pos += 1
            if b == UInt8(ascii: "\"") {
                return String(decoding: utf8Out, as: UTF8.self)
            }
            if b == UInt8(ascii: "\\") {
                guard pos < bytes.count else {
                    throw ToolingCliError("unterminated JSON escape")
                }
                let esc = bytes[pos]
                pos += 1
                switch esc {
                case UInt8(ascii: "\""): utf8Out.append(0x22)
                case UInt8(ascii: "\\"): utf8Out.append(0x5C)
                case UInt8(ascii: "/"): utf8Out.append(0x2F)
                case UInt8(ascii: "b"): utf8Out.append(0x08)
                case UInt8(ascii: "f"): utf8Out.append(0x0C)
                case UInt8(ascii: "n"): utf8Out.append(0x0A)
                case UInt8(ascii: "r"): utf8Out.append(0x0D)
                case UInt8(ascii: "t"): utf8Out.append(0x09)
                case UInt8(ascii: "u"):
                    let code = try parseHex4()
                    if (0xD800...0xDBFF).contains(code),
                       pos + 6 <= bytes.count,
                       bytes[pos] == UInt8(ascii: "\\"),
                       bytes[pos + 1] == UInt8(ascii: "u")
                    {
                        pos += 2
                        let lo = try parseHex4()
                        let combined = 0x10000 + ((UInt32(code - 0xD800) << 10) | UInt32(lo - 0xDC00))
                        if let sc = UnicodeScalar(combined) {
                            utf8Out.append(contentsOf: String(sc).utf8)
                        }
                    } else if let sc = UnicodeScalar(UInt32(code)) {
                        utf8Out.append(contentsOf: String(sc).utf8)
                    }
                default:
                    throw ToolingCliError("invalid JSON escape")
                }
            } else {
                utf8Out.append(b)
            }
        }
        throw ToolingCliError("unterminated JSON string")
    }

    private mutating func parseHex4() throws -> UInt16 {
        guard pos + 4 <= bytes.count else {
            throw ToolingCliError("short \\u escape")
        }
        var acc: UInt16 = 0
        for _ in 0..<4 {
            let b = bytes[pos]
            pos += 1
            let nib: UInt16
            switch b {
            case UInt8(ascii: "0")...UInt8(ascii: "9"): nib = UInt16(b - UInt8(ascii: "0"))
            case UInt8(ascii: "a")...UInt8(ascii: "f"): nib = UInt16(b - UInt8(ascii: "a") + 10)
            case UInt8(ascii: "A")...UInt8(ascii: "F"): nib = UInt16(b - UInt8(ascii: "A") + 10)
            default: throw ToolingCliError("invalid hex in \\u escape")
            }
            acc = (acc << 4) | nib
        }
        return acc
    }

    private mutating func parseNumber() throws -> ToolingJson {
        let start = pos
        var isFloat = false
        if pos < bytes.count && bytes[pos] == UInt8(ascii: "-") { pos += 1 }
        while pos < bytes.count && bytes[pos] >= UInt8(ascii: "0") && bytes[pos] <= UInt8(ascii: "9") {
            pos += 1
        }
        if pos < bytes.count && bytes[pos] == UInt8(ascii: ".") {
            isFloat = true
            pos += 1
            while pos < bytes.count && bytes[pos] >= UInt8(ascii: "0") && bytes[pos] <= UInt8(ascii: "9") {
                pos += 1
            }
        }
        if pos < bytes.count && (bytes[pos] == UInt8(ascii: "e") || bytes[pos] == UInt8(ascii: "E")) {
            isFloat = true
            pos += 1
            if pos < bytes.count && (bytes[pos] == UInt8(ascii: "+") || bytes[pos] == UInt8(ascii: "-")) {
                pos += 1
            }
            while pos < bytes.count && bytes[pos] >= UInt8(ascii: "0") && bytes[pos] <= UInt8(ascii: "9") {
                pos += 1
            }
        }
        guard pos > start else {
            throw ToolingCliError("expected JSON value at byte \(start)")
        }
        let s = String(decoding: bytes[start..<pos], as: UTF8.self)
        if !isFloat, let iv = Int64(s) {
            return .int(iv)
        }
        guard let dv = Double(s), dv.isFinite else {
            throw ToolingCliError("invalid JSON number \(s)")
        }
        return .number(dv)
    }
}

// MARK: - Script Parsing (`crates/rune/src/tooling/script.rs`)

/// `{"text": ..., "html": ..., "rtf": ..., "png": "path/to/image.png"}`, each optional.
func toolingPasteContent(_ e: ToolingJson) throws -> ClipboardContent {
    var content = ClipboardContent.new(e["text"].stringValue ?? "")
    if let html = e["html"].stringValue {
        content = content.withHtml(html)
    }
    if let rtf = e["rtf"].stringValue {
        content = content.withRtf(rtf)
    }
    if let path = e["png"].stringValue {
        #if os(WASI)
        throw ToolingCliError("paste png \(path): filesystem unavailable on WASI")
        #else
        let bytes: [UInt8]
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            bytes = [UInt8](data)
        } catch {
            throw ToolingCliError("paste png \(path): \(error)")
        }
        guard let image = ClipboardImage.fromPng(bytes) else {
            throw ToolingCliError("paste png \(path): not a PNG, or over clipboard::MAX_IMAGE_BYTES")
        }
        content = content.withImage(image)
        #endif
    }
    return content.untrusted()
}

func toolingScriptPhase(_ e: ToolingJson) throws -> GesturePhase {
    switch e["phase"].stringValue ?? "moved" {
    case "began": return .started
    case "moved": return .moved
    case "ended": return .ended
    case let other:
        throw ToolingCliError("unknown gesture phase \(other); use began, moved or ended")
    }
}

func toolingTryParseScript(_ list: ToolingJson) throws -> [ToolingEv] {
    guard let items = list.arrayValue else {
        throw ToolingCliError("script must be an array of events or {\"events\": [...]}")
    }
    var out: [ToolingEv] = []
    for e in items {
        let t = e["t"].doubleValue ?? 0.0
        if let focused = e["focus"].boolValue {
            out.append(ToolingEv(t: t, kind: .focus(focused), pos: .rel(0.0, 0.0)))
            continue
        }
        if let item = e["menu"].stringValue {
            out.append(ToolingEv(t: t, kind: .menu(item), pos: .rel(0.0, 0.0)))
            continue
        }
        if e["reopen"].boolValue == true {
            out.append(ToolingEv(t: t, kind: .reopen, pos: .rel(0.0, 0.0)))
            continue
        }
        if let chordStr = e["physical"].stringValue {
            let chord: Shortcut
            do {
                chord = try Shortcut.parse(chordStr).get()
            } catch {
                throw ToolingCliError("\(error)")
            }
            let rep = e["repeat"].boolValue ?? false
            for pressed in [true, false] {
                out.append(
                    ToolingEv(
                        t: t,
                        kind: .physical(
                            .key(
                                key: chord.physicalKey(),
                                mods: chord.modifiers(),
                                pressed: pressed,
                                repeat: rep && pressed
                            )
                        ),
                        pos: .rel(0.0, 0.0)
                    )
                )
            }
            if chord.modifiers() != Mods() {
                out.append(
                    ToolingEv(
                        t: t,
                        kind: .physical(.modifiers(Mods())),
                        pos: .rel(0.0, 0.0)
                    )
                )
            }
            continue
        }
        if let shortcutStr = e["shortcut"].stringValue {
            let shortcut: Shortcut
            do {
                shortcut = try Shortcut.parse(shortcutStr).get()
            } catch {
                throw ToolingCliError("\(error)")
            }
            out.append(ToolingEv(t: t, kind: .shortcut(shortcut), pos: .rel(0.0, 0.0)))
            continue
        }
        if !e["paste"].isNull {
            let pasteObj: ToolingJson
            if let str = e["paste"].stringValue {
                pasteObj = .object([("text", .string(str))])
            } else {
                pasteObj = e["paste"]
            }
            out.append(ToolingEv(t: t, kind: .paste(try toolingPasteContent(pasteObj)), pos: .rel(0.0, 0.0)))
            continue
        }
        if try toolingParseFiles(e, t: t, out: &out) {
            continue
        }
        if e["type"].stringValue == "shortcut" {
            guard let chordStr = e["chord"].stringValue else {
                throw ToolingCliError("a \"shortcut\" event needs a \"chord\", like \"cmd+space\"")
            }
            let chord: Shortcut
            do {
                chord = try Shortcut.parse(chordStr).get()
            } catch {
                throw ToolingCliError("\(error)")
            }
            out.append(ToolingEv(t: t, kind: .shortcut(chord), pos: .rel(0.0, 0.0)))
            continue
        }

        let pos: ToolingPos
        if let k = e["key"].stringValue {
            pos = .key(k)
        } else if let x = e["x"].doubleValue, let y = e["y"].doubleValue {
            pos = .xy(Float(x), Float(y))
        } else {
            pos = .rel(0.0, 0.0)
        }

        let ty = e["type"].stringValue ?? "tap"
        let button: PointerButton
        switch e["button"].stringValue ?? "primary" {
        case "primary": button = .primary
        case "secondary": button = .secondary
        case "middle": button = .middle
        case "back": button = .back
        case "forward": button = .forward
        case let other:
            throw ToolingCliError("unknown button \(other)")
        }

        let (downKind, upKind): (ToolingKind, ToolingKind)
        switch button {
        case .primary: (downKind, upKind) = (.down, .up)
        case .secondary: (downKind, upKind) = (.secondaryDown, .secondaryUp)
        default: (downKind, upKind) = (.buttonDown(button), .buttonUp(button))
        }

        func gestureAt(_ pos: ToolingPos) {
            if case .rel = pos { return }
            out.append(ToolingEv(t: t, kind: .move, pos: pos))
        }

        switch ty {
        case "move":
            out.append(ToolingEv(t: t, kind: .move, pos: pos))
        case "down":
            out.append(ToolingEv(t: t, kind: .move, pos: pos))
            out.append(ToolingEv(t: t, kind: downKind, pos: pos))
        case "up":
            out.append(ToolingEv(t: t, kind: upKind, pos: pos))
        case "secondary-down":
            out.append(ToolingEv(t: t, kind: .secondaryDown, pos: pos))
        case "secondary-up":
            out.append(ToolingEv(t: t, kind: .secondaryUp, pos: pos))
        case "secondary-click":
            out.append(ToolingEv(t: t, kind: .secondaryDown, pos: pos))
            out.append(ToolingEv(t: t + (e["hold"].doubleValue ?? 0.08), kind: .secondaryUp, pos: pos))
        case "tap", "click":
            out.append(ToolingEv(t: t, kind: .move, pos: pos))
            out.append(ToolingEv(t: t, kind: downKind, pos: pos))
            out.append(ToolingEv(t: t + (e["hold"].doubleValue ?? 0.08), kind: upKind, pos: .rel(0.0, 0.0)))
        case "double-click", "double-tap", "triple-click":
            let hold = e["hold"].doubleValue ?? 0.06
            let gap = max(e["gap"].doubleValue ?? 0.15, hold + 0.01)
            let presses = (ty == "triple-click") ? 3 : 2
            for k in 0..<presses {
                let start = t + gap * Double(k)
                out.append(ToolingEv(t: start, kind: .move, pos: pos))
                out.append(ToolingEv(t: start, kind: .down, pos: pos))
                out.append(ToolingEv(t: start + hold, kind: .up, pos: .rel(0.0, 0.0)))
            }
        case "drag":
            let dx = Float(e["dx"].doubleValue ?? 0.0)
            let dy = Float(e["dy"].doubleValue ?? 0.0)
            let dur = max(e["dur"].doubleValue ?? 0.3, 0.01)
            out.append(ToolingEv(t: t, kind: .move, pos: pos))
            out.append(ToolingEv(t: t, kind: downKind, pos: pos))
            let steps = max(1, Int((dur * 120.0).rounded(.up)))
            for s in 1...steps {
                let u = Float(s) / Float(steps)
                let f = u * u * (3.0 - 2.0 * u)
                out.append(
                    ToolingEv(
                        t: t + dur * Double(s) / Double(steps),
                        kind: .move,
                        pos: .rel(dx * f, dy * f)
                    )
                )
            }
            out.append(ToolingEv(t: t + dur + 0.02, kind: upKind, pos: .rel(dx, dy)))
        case "type":
            let txt = e["text"].stringValue ?? ""
            let every = e["every"].doubleValue ?? 0.035
            for (k, ch) in txt.enumerated() {
                let ev = KeyEvent(key: .text(String(ch)), mods: Mods())
                out.append(ToolingEv(t: t + every * Double(k), kind: .key(ev, false), pos: .rel(0.0, 0.0)))
            }
        case "key", "key-up":
            let name = e["name"].stringValue ?? ""
            let mods = scriptMods(e)
            let key: Key
            if mods.cmd && name.utf8.count == 1, let first = name.first {
                let lower = first.isASCII ? Character(String(first).lowercased()) : first
                key = .command(lower)
            } else if let parsed = keyNamed(name) {
                key = parsed
            } else {
                throw ToolingCliError("unknown key \(name)")
            }
            let rep = e["repeat"].boolValue ?? false
            if let codeStr = e["code"].stringValue {
                let code: PhysicalKeyCode
                do {
                    code = try Shortcut.parse(codeStr).get().physicalKey()
                } catch {
                    throw ToolingCliError("\(error)")
                }
                let base = scriptKeyBase(e, name, mods)
                func press(_ pressed: Bool) -> ScriptPhysicalInput {
                    .key(key: code, mods: mods, pressed: pressed, repeat: rep && pressed)
                }
                if ty == "key-up" {
                    out.append(ToolingEv(t: t, kind: .physicalKey(press(false), KeyEvent(key: key, mods: mods), base), pos: .rel(0.0, 0.0)))
                } else {
                    out.append(ToolingEv(t: t, kind: .physicalKey(press(true), KeyEvent(key: key, mods: mods), base), pos: .rel(0.0, 0.0)))
                    out.append(ToolingEv(t: t, kind: .physical(press(false)), pos: .rel(0.0, 0.0)))
                }
                continue
            }
            let kind: ToolingKind = (ty == "key-up")
                ? .keyUp(KeyEvent(key: key, mods: mods))
                : .key(KeyEvent(key: key, mods: mods), rep)
            out.append(ToolingEv(t: t, kind: kind, pos: .rel(0.0, 0.0)))
        case "wheel":
            let dx = Float(e["dx"].doubleValue ?? 0.0)
            let dy = Float(e["dy"].doubleValue ?? 0.0)
            _ = try toolingScriptPhase(e)
            gestureAt(pos)
            let ev = WheelEvent(
                x: 0.0,
                y: 0.0,
                dx: dx,
                dy: dy,
                precise: e["precise"].boolValue ?? true,
                mods: scriptMods(e)
            )
            out.append(ToolingEv(t: t, kind: .wheelEvent(ev), pos: pos))
        case "magnify":
            gestureAt(pos)
            let ev = MagnifyEvent(
                x: 0.0,
                y: 0.0,
                delta: Float(e["delta"].doubleValue ?? 0.0),
                phase: try toolingScriptPhase(e),
                mods: scriptMods(e)
            )
            out.append(ToolingEv(t: t, kind: .magnify(ev), pos: pos))
        case "rotate":
            gestureAt(pos)
            let ev = RotateEvent(
                x: 0.0,
                y: 0.0,
                delta: Float(e["degrees"].doubleValue ?? 0.0),
                phase: try toolingScriptPhase(e),
                mods: scriptMods(e)
            )
            out.append(ToolingEv(t: t, kind: .rotate(ev), pos: pos))
        case "smart-magnify":
            gestureAt(pos)
            out.append(ToolingEv(t: t, kind: .smartMagnify, pos: pos))
        case "paste":
            out.append(ToolingEv(t: t, kind: .paste(try toolingPasteContent(e)), pos: .rel(0.0, 0.0)))
        case "scroll":
            toolingSwipe(out: &out, e: e, t: t, pos: pos)
        case "resize":
            toolingResize(out: &out, e: e, t: t)
        case "fling":
            let vx = Float(e["vx"].doubleValue ?? 0.0)
            let vy = Float(e["v"].doubleValue ?? 0.0)
            out.append(ToolingEv(t: t, kind: .fling(vx, vy), pos: pos))
        case "menu-pick":
            guard let id = e["id"].stringValue else {
                throw ToolingCliError("menu-pick needs an \"id\"")
            }
            out.append(ToolingEv(t: t, kind: .popupMenu(id), pos: .rel(0.0, 0.0)))
        case "menu-cancel":
            out.append(ToolingEv(t: t, kind: .popupMenu(nil), pos: .rel(0.0, 0.0)))
        case "file-dialog":
            guard let path = e["path"].stringValue else {
                throw ToolingCliError("file-dialog needs a \"path\" (file-dialog-cancel cancels)")
            }
            out.append(ToolingEv(t: t, kind: .fileDialog(path), pos: .rel(0.0, 0.0)))
        case "file-dialog-cancel":
            out.append(ToolingEv(t: t, kind: .fileDialog(nil), pos: .rel(0.0, 0.0)))
        case "mark":
            guard let name = e["name"].stringValue, !name.isEmpty else {
                throw ToolingCliError("a mark needs a \"name\"")
            }
            out.append(ToolingEv(t: t, kind: .mark(name), pos: pos))
        case let other:
            throw ToolingCliError("unknown event type \(other)")
        }
    }
    // Stable sort by timestamp
    let indexed = out.enumerated().sorted { lhs, rhs in
        if lhs.element.t != rhs.element.t {
            return lhs.element.t < rhs.element.t
        }
        return lhs.offset < rhs.offset
    }
    return indexed.map(\.element)
}

func toolingParseScript(_ list: ToolingJson) -> [ToolingEv] {
    do {
        return try toolingTryParseScript(list)
    } catch let err as ToolingCliError {
        toolingDie(err.message)
    } catch {
        toolingDie("\(error)")
    }
}

func toolingParseFiles(_ e: ToolingJson, t: Double, out: inout [ToolingEv]) throws -> Bool {
    let spec: ToolingJson
    let isDrop: Bool
    if let s = e.get("drag_files") {
        spec = s
        isDrop = false
    } else if let s = e.get("drop_files") {
        spec = s
        isDrop = true
    } else {
        return false
    }
    if !isDrop && spec.stringValue == "leave" {
        out.append(ToolingEv(t: t, kind: .files(.leave), pos: .rel(0.0, 0.0)))
        return true
    }
    let name = isDrop ? "drop_files" : "drag_files"
    guard let arr = spec["paths"].arrayValue else {
        throw ToolingCliError("\(name) needs \"paths\": [\"a file\", …]")
    }
    var paths: [String] = []
    paths.reserveCapacity(arr.count)
    for item in arr {
        guard let p = item.stringValue else {
            throw ToolingCliError("\(name): paths are strings")
        }
        paths.append(p)
    }
    let pos: ToolingPos
    if let at = spec["at"].arrayValue, at.count == 2, at.allSatisfy(\.isNumber) {
        pos = .xy(Float(at[0].doubleValue ?? 0.0), Float(at[1].doubleValue ?? 0.0))
    } else if spec.get("at") == nil, let key = spec["key"].stringValue {
        pos = .key(key)
    } else {
        throw ToolingCliError("\(name) needs \"at\": [x, y] or \"key\"")
    }
    out.append(ToolingEv(t: t, kind: .files(.hover(paths)), pos: pos))
    if isDrop {
        let hover = max(spec["hover"].doubleValue ?? 0.0, 0.0)
        out.append(ToolingEv(t: t + hover, kind: .files(.drop(paths)), pos: pos))
    }
    return true
}
