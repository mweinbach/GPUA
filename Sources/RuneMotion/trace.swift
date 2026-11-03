// Ported from: crates/rune-motion/src/trace.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Foundation

/// Byte sink for ``MotionTrace`` (Swift counterpart to `std::io::Write + Send`).
public protocol TraceWriter: Sendable {
    mutating func write(_ bytes: [UInt8]) throws
    mutating func flush() throws
}

private struct Channel {
    var name: String
    var kind: String
    var value: Double?
    var previous: Double?
    var described: Bool
    var owner: (UInt32, String)?
}

/// Delta-encoded motion-lint scalar channels. Values hold until sampled again or removed.
// PORT NOTE: `TraceChannels` is mutated on a single render thread inside `MotionTrace` / `Scene`,
// matching Rust's `&mut TraceChannels`.
public final class TraceChannels: @unchecked Sendable {
    private var ids: [String: Int] = [:]
    private var channels: [Channel] = []

    public init() {}

    /// `kind` is motion-lint's `position`, `level`, or `phase`. Non-finite samples are ignored.
    public func sample(_ name: String, _ kind: String, _ value: Float) {
        if !value.isFinite {
            return
        }
        precondition(
            kind == "position" || kind == "level" || kind == "phase",
            "unknown trace channel kind"
        )
        let i: Int
        if let existing = ids[name] {
            i = existing
        } else {
            i = channels.count
            ids[name] = i
            channels.append(
                Channel(
                    name: name,
                    kind: kind,
                    value: nil,
                    previous: nil,
                    described: false,
                    owner: nil
                )
            )
        }
        if channels[i].kind != kind {
            channels[i].kind = kind
            channels[i].described = false
        }
        channels[i].value = (Double(value) * 1e4).rounded() / 1e4
    }

    public func remove(_ name: String) {
        if let i = ids[name] {
            channels[i].value = nil
        }
    }

    /// Associates an effect channel with its element for visibility gating.
    public func owner(_ name: String, _ owner: UInt32, _ unit: String) {
        if let i = ids[name] {
            let changed: Bool
            if let existing = channels[i].owner {
                changed = existing.0 != owner || existing.1 != unit
            } else {
                changed = true
            }
            if changed {
                channels[i].owner = (owner, unit)
                channels[i].described = false
            }
        }
    }

    /// Appends optional `cm`, `c`, and `cg` fields to an open JSON object.
    public func writeJson(_ line: inout String) {
        var metas = ""
        var values = ""
        var gone = ""
        for i in 0..<channels.count {
            let id = i + 1
            if let value = channels[i].value {
                if !channels[i].described {
                    if !metas.isEmpty { metas.append(",") }
                    metas += "{\"id\":\(id),\"name\":\(jsonStr(channels[i].name)),\"kind\":\(jsonStr(channels[i].kind))"
                    if let (owner, unit) = channels[i].owner {
                        metas += ", \"owner\":\(owner),\"unit\":\(jsonStr(unit))"
                    }
                    metas.append("}")
                    channels[i].described = true
                }
                if channels[i].previous != value {
                    if !values.isEmpty { values.append(",") }
                    values += "[\(id),\(fmtNum(value))]"
                }
            } else if channels[i].previous != nil {
                if !gone.isEmpty { gone.append(",") }
                gone += "\(id)"
            }
            channels[i].previous = channels[i].value
        }
        for (key, str) in [("cm", metas), ("c", values), ("cg", gone)] {
            if !str.isEmpty {
                line += ",\"\(key)\":[\(str)]"
            }
        }
    }
}

/// motion-lint element flag bits (motion-lint's `Flags`).
public enum flags {
    public static let animated: UInt32 = 1
    public static let ancestorAnimated: UInt32 = 2
    public static let scrolling: UInt32 = 4
    public static let clipped: UInt32 = 8
    public static let filtered: UInt32 = 16
    public static let occluded: UInt32 = 32
    /// Draws nothing and holds nothing: a hit or hover zone, a spacer.
    public static let blank: UInt32 = 64
}

/// motion-lint intent classes (motion-lint's `Intent`): in flags at `<< 8` (own) and `<< 16`
/// (ancestor), and in `ai` intent records.
public enum Intent {
    public static let position: UInt32 = 1
    public static let size: UInt32 = 2
    public static let opacity: UInt32 = 4
    public static let shape: UInt32 = 8
    public static let transition: UInt32 = 16
    public static let reveal: UInt32 = 32
    public static let contents: UInt32 = 64

    /// The intent class a built-in property's animation declares.
    public static func forProp(_ p: PropId) -> UInt32 {
        if p == prop.frame.id || p == prop.travel.id {
            return position | size
        } else if p == prop.offset.id || p == prop.rotation.id || p == prop.scroll.id {
            return position
        } else if p == prop.opacity.id {
            return opacity
        } else if p == prop.scale.id {
            return size | transition
        } else if p == prop.blur.id {
            return transition
        } else if p == prop.radius.id {
            return shape
        } else if p == prop.fill.id {
            return contents
        } else if p == prop.mask.id {
            return reveal
        } else if p == prop.presence.id {
            return transition | opacity
        } else {
            return contents
        }
    }
}

/// The trace's header line.
public struct TraceHeader: Sendable, Equatable {
    public var launch: String
    public var width: Float
    public var height: Float
    public var hz: Float
    public var scale: Float

    public init(launch: String, width: Float, height: Float, hz: Float, scale: Float) {
        self.launch = launch
        self.width = width
        self.height = height
        self.hz = hz
        self.scale = scale
    }
}

/// A `TraceWriter` that keeps everything in shared memory, for tests (`buf.contents()`).
// PORT NOTE: Synchronized with `NSLock` on multi-threaded platforms (matching `Arc<Mutex<Vec<u8>>>`)
// and uncontended on single-threaded WASI.
public final class SharedBuffer: TraceWriter, @unchecked Sendable {
    private var storage: [UInt8] = []
    #if !os(WASI)
    private let lock = NSLock()
    #endif

    public init() {}

    public func contents() -> String {
        #if !os(WASI)
        lock.lock()
        defer { lock.unlock() }
        #endif
        return String(decoding: storage, as: UTF8.self)
    }

    public func write(_ bytes: [UInt8]) throws {
        #if !os(WASI)
        lock.lock()
        defer { lock.unlock() }
        #endif
        storage.append(contentsOf: bytes)
    }

    public func flush() throws {}
}

#if !os(WASI)
// PORT NOTE: Wraps `FileHandle` for `MotionTrace.fromEnv` on platforms with host filesystem I/O.
private final class FileTraceWriter: TraceWriter, @unchecked Sendable {
    private let handle: FileHandle

    init?(path: String) {
        _ = FileManager.default.createFile(atPath: path, contents: nil)
        guard let fh = FileHandle(forWritingAtPath: path) else {
            return nil
        }
        self.handle = fh
    }

    func write(_ bytes: [UInt8]) throws {
        try handle.write(contentsOf: Data(bytes))
    }

    func flush() throws {
        try handle.synchronize()
    }
}
#endif

private struct TraceState12: Sendable {
    var s0: Float = 0.0
    var s1: Float = 0.0
    var s2: Float = 0.0
    var s3: Float = 0.0
    var s4: Float = 0.0
    var s5: Float = 0.0
    var s6: Float = 0.0
    var s7: Float = .nan
    var s8: Float = 0.0
    var s9: Float = 0.0
    var s10: Float = 0.0
    var s11: Float = 0.0

    @inline(__always)
    subscript(_ i: Int) -> Float {
        get {
            switch i {
            case 0: return s0
            case 1: return s1
            case 2: return s2
            case 3: return s3
            case 4: return s4
            case 5: return s5
            case 6: return s6
            case 7: return s7
            case 8: return s8
            case 9: return s9
            case 10: return s10
            case 11: return s11
            default: preconditionFailure("TraceState12 index out of bounds")
            }
        }
        set {
            switch i {
            case 0: s0 = newValue
            case 1: s1 = newValue
            case 2: s2 = newValue
            case 3: s3 = newValue
            case 4: s4 = newValue
            case 5: s5 = newValue
            case 6: s6 = newValue
            case 7: s7 = newValue
            case 8: s8 = newValue
            case 9: s9 = newValue
            case 10: s10 = newValue
            case 11: s11 = newValue
            default: preconditionFailure("TraceState12 index out of bounds")
            }
        }
    }

    func rounded2() -> TraceState12 {
        var r = self
        for i in 0..<12 {
            let v = r[i]
            if !v.isNaN {
                r[i] = (v * 100.0).rounded() / 100.0
            }
        }
        return r
    }
}

private func sameState(_ a: TraceState12, _ b: TraceState12) -> Bool {
    for i in 0..<12 {
        let x = a[i]
        let y = b[i]
        if !(x == y || (x.isNaN && y.isNaN)) {
            return false
        }
    }
    return true
}

private struct DescribedEntry: Equatable {
    var name: String?
    var nsClass: String?
    var nsHost: String?
}

/// Writes one JSONL line per frame. Only elements whose presented state changed are written;
/// unmounted ones go in `g`.
// PORT NOTE: `MotionTrace` is owned by `Scene` on a single render thread (matching Rust's
// `MotionTrace` holding `Box<dyn Write + Send>`), so it is a `final class` marked `@unchecked Sendable`.
public final class MotionTrace: @unchecked Sendable {
    private var out: any TraceWriter
    private var ids: [UInt64: UInt32] = [:]
    private var states: [UInt32: TraceState12] = [:]
    private var lastT: Double? = nil
    private var hz: Double
    private var timeScale: Float = 1.0
    private var line: String = ""
    private var names: [UInt64: String] = [:]
    private var described: [UInt64: DescribedEntry] = [:]
    private var namespaces: [UInt64: (String, String)] = [:]
    private var traceClass: String = "rune"
    private var traceHost: String = "scene"
    private let channels = TraceChannels()
    private var pendingEvents: [String] = []

    public init(_ out: any TraceWriter, _ header: TraceHeader) throws {
        var writer = out
        let headerLine =
            "{\"type\":\"header\",\"launch\":\(jsonStr(header.launch)),\"width\":\(fmtNum(Double(header.width))),\"height\":\(fmtNum(Double(header.height))),\"hz\":\(fmtNum(Double(header.hz))),\"scale\":\(fmtNum(Double(header.scale))),\"platform\":\"rune\",\"units\":\"pt\",\"clock\":\"virtual\"}\n"
        try writer.write(Array(headerLine.utf8))
        self.out = writer
        self.hz = Double(max(header.hz, 1.0))
    }

    public static func new(_ out: any TraceWriter, _ header: TraceHeader) throws -> MotionTrace {
        try MotionTrace(out, header)
    }

    /// Opens `$RUNE_MOTION_TRACE` if it is set (one env read).
    public static func fromEnv(_ header: TraceHeader) -> MotionTrace? {
        #if os(WASI)
        return nil
        #else
        guard let path = ProcessInfo.processInfo.environment["RUNE_MOTION_TRACE"], !path.isEmpty else {
            return nil
        }
        guard let writer = FileTraceWriter(path: path) else {
            return nil
        }
        return try? MotionTrace(writer, header)
        #endif
    }

    /// An in-memory trace and a handle to read it back.
    public static func inMemory(_ header: TraceHeader) -> (MotionTrace, SharedBuffer) {
        let buf = SharedBuffer()
        let trace = try! MotionTrace(buf, header)
        return (trace, buf)
    }

    /// The clock's time scale, written as `sc` so motion-lint counts the app's own frames.
    public func setTimeScale(_ sc: Float) {
        timeScale = sc
    }

    /// Set before the first frame when comparing against another host (for example `pill`).
    @discardableResult
    public func host(_ host: String) -> MotionTrace {
        traceHost = host
        return self
    }

    /// The comparison class. motion-lint pairs named elements by both `nm` and `cls`.
    /// Use the reference writer's class (e.g. `gpui`) for cross-renderer comparisons.
    @discardableResult
    public func `class`(_ cls: String) -> MotionTrace {
        traceClass = cls
        return self
    }

    /// Overrides this node's class and host; `nil` restores the writer's defaults.
    @discardableResult
    public func namespace(_ node: NodeId, _ namespace: (String, String)?) -> Bool {
        if let ns = namespace {
            let prev = namespaces.updateValue(ns, forKey: node.rawValue)
            return prev == nil || prev!.0 != ns.0 || prev!.1 != ns.1
        } else {
            return namespaces.removeValue(forKey: node.rawValue) != nil
        }
    }

    /// Stable display name, independent of reconciliation identity. `nil` restores the `NodeId`.
    @discardableResult
    public func name(_ node: NodeId, _ name: String?) -> Bool {
        if let n = name {
            return names.updateValue(n, forKey: node.rawValue) != n
        } else {
            return names.removeValue(forKey: node.rawValue) != nil
        }
    }

    public func channel(_ name: String, _ kind: String, _ value: Float) {
        channels.sample(name, kind, value)
    }

    public func removeChannel(_ name: String) {
        channels.remove(name)
    }

    /// Recorded once, on the next frame.
    public func event(_ event: some CustomStringConvertible) {
        pendingEvents.append(event.description)
    }

    private func id(_ node: NodeId) -> UInt32 {
        if let existing = ids[node.rawValue] {
            return existing
        }
        let next = UInt32(ids.count + 1)
        ids[node.rawValue] = next
        return next
    }

    /// Writes one frame. `t` is animation time in seconds.
    public func frame(
        _ t: Double,
        _ presented: [Presented],
        _ gone: [NodeId],
        _ events: [MotionEvent],
        _ intents: [(NodeId, UInt32, Float)]
    ) {
        let tMs = t * 1000.0
        let n: UInt64
        if let last = lastT {
            n = UInt64(max(((tMs - last) / (1000.0 / hz)).rounded(), 1.0))
        } else {
            n = 1
        }
        lastT = tMs
        line.removeAll(keepingCapacity: true)
        line += "{\"t\":\(fmtNum(r3(tMs))),\"n\":\(n),\"sc\":\(fmtNum(Double(timeScale)))"
        if !events.isEmpty || !pendingEvents.isEmpty {
            line += ",\"ev\":["
            for (k, e) in events.enumerated() {
                if k > 0 { line.append(",") }
                let s: String
                switch e {
                case .settled(_, let node, let prop):
                    s = "settled \(node.rawValue):\(prop.rawValue)"
                case .completed(let token, _, _, let finished):
                    s = "completed #\(token)\(finished ? "" : " (replaced)")"
                }
                line += jsonStr(s)
            }
            for (k, ev) in pendingEvents.enumerated() {
                if k > 0 || !events.isEmpty { line.append(",") }
                line += jsonStr(ev)
            }
            pendingEvents.removeAll(keepingCapacity: true)
            line.append("]")
        }

        var metas = ""
        var elems = ""
        for p in presented {
            let elemId = id(p.node)
            let nodeName = names[p.node.rawValue]
            let ns = namespaces[p.node.rawValue]
            let entry = DescribedEntry(name: nodeName, nsClass: ns?.0, nsHost: ns?.1)
            if described.updateValue(entry, forKey: p.node.rawValue) != entry {
                if !metas.isEmpty { metas.append(",") }
                let displayName = nodeName ?? String(p.node.rawValue)
                let cls = ns?.0 ?? traceClass
                let hst = ns?.1 ?? traceHost
                metas += "{\"id\":\(elemId),\"cls\":\(jsonStr(cls)),\"nm\":\(jsonStr(displayName)),\"host\":\(jsonStr(hst))"
                if let parent = p.parent {
                    let pv = id(parent)
                    metas += ",\"pv\":\(pv)"
                }
                metas.append("}")
            }
            let r = p.rect
            let ins = p.mask.inset
            var s = TraceState12(
                s0: r.x,
                s1: r.y,
                s2: r.w,
                s3: r.h,
                s4: p.opacity,
                s5: p.radius[0],
                s6: Float(p.flags),
                s7: .nan,
                s8: 0.0,
                s9: 0.0,
                s10: 0.0,
                s11: 0.0
            )
            if ins[0] > 0.25 || ins[1] > 0.25 || ins[2] > 0.25 || ins[3] > 0.25 {
                s[7] = r.x + ins[0]
                s[8] = r.y + ins[1]
                s[9] = max(r.w - ins[0] - ins[2], 0.0)
                s[10] = max(r.h - ins[1] - ins[3], 0.0)
            }
            let rounded = s.rounded2()
            if let old = states[elemId], sameState(old, rounded) {
                continue
            }
            states[elemId] = rounded
            if !elems.isEmpty { elems.append(",") }
            elems += "[\(elemId),\(fmtNum(r2(r.x))),\(fmtNum(r2(r.y))),\(fmtNum(r2(r.w))),\(fmtNum(r2(r.h))),\(fmtNum(r3(Double(p.opacity)))),\(fmtNum(r2(p.radius[0]))),\(p.flags)"
            if !s[7].isNaN {
                elems += ",\(fmtNum(r2(s[7]))),\(fmtNum(r2(s[8]))),\(fmtNum(r2(s[9]))),\(fmtNum(r2(s[10])))"
            }
            elems.append("]")
        }

        if !intents.isEmpty {
            line += ",\"ai\":["
            for (k, (node, bits, secs)) in intents.enumerated() {
                let elemId = id(node)
                let rect = presented.first(where: { $0.node == node })?.rect ?? .zero
                if k > 0 { line.append(",") }
                line += "[\(elemId),\(fmtNum(r2(rect.x))),\(fmtNum(r2(rect.y))),\(fmtNum(r2(rect.w))),\(fmtNum(r2(rect.h))),\(bits),\(fmtNum(Double((secs * 1000.0).rounded())))]"
            }
            line.append("]")
        }
        if !metas.isEmpty {
            line += ",\"m\":[\(metas)]"
        }
        if !elems.isEmpty {
            line += ",\"e\":[\(elems)]"
        }
        if !gone.isEmpty {
            line += ",\"g\":["
            for (k, node) in gone.enumerated() {
                let elemId = id(node)
                states.removeValue(forKey: elemId)
                if k > 0 { line.append(",") }
                line += "\(elemId)"
            }
            line.append("]")
        }
        channels.writeJson(&line)
        line += "}\n"
        try? out.write(Array(line.utf8))
    }

    public func flush() throws {
        try out.flush()
    }

    deinit {
        try? out.flush()
    }
}

@inline(__always)
private func r2(_ v: Float) -> Double {
    (Double(v) * 100.0).rounded() / 100.0
}

@inline(__always)
private func r3(_ v: Double) -> Double {
    (v * 1000.0).rounded() / 1000.0
}

@inline(__always)
private func fmtNum(_ v: Double) -> String {
    if v.isFinite && v == v.rounded(.towardZero) && abs(v) < 1e15 {
        return String(Int64(v))
    }
    return String(v)
}

private func jsonStr(_ s: String) -> String {
    var out = "\""
    out.reserveCapacity(s.utf8.count + 2)
    for scalar in s.unicodeScalars {
        switch scalar {
        case "\"":
            out += "\\\""
        case "\\":
            out += "\\\\"
        case "\n":
            out += "\\n"
        default:
            if scalar.value < 0x20 {
                let hex = String(scalar.value, radix: 16)
                let padded = String(repeating: "0", count: max(0, 4 - hex.count)) + hex
                out += "\\u\(padded)"
            } else {
                out.unicodeScalars.append(scalar)
            }
        }
    }
    out.append("\"")
    return out
}
