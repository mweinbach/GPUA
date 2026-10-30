// Ported from: crates/util/src/rel_path.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Foundation
import GPUIUtil

// MARK: - StripPrefixError

public struct StripPrefixError: Error, Equatable, Sendable, CustomStringConvertible {
    public init() {}
    public var description: String { "prefix does not match" }
}

public struct RelPathError: Error, Equatable, Sendable, CustomStringConvertible {
    public var message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
}

// MARK: - RelPath

/// A file system path that is guaranteed to be relative and normalized.
public struct RelPath: Hashable, Comparable, Sendable, CustomStringConvertible, ExpressibleByStringLiteral, Codable {
    public var raw: String

    public init(raw: String) {
        self.raw = raw
    }

    public init(stringLiteral value: String) {
        self.raw = value
    }

    public init(_ path: String, _ pathStyle: PathStyle = .local()) throws {
        let cow = try RelPath.new(path, pathStyle)
        self = cow.value
    }

    public init(_ path: Path, _ pathStyle: PathStyle = .local()) throws {
        try self.init(path.rawValue, pathStyle)
    }

    public static func empty() -> RelPath {
        RelPath(raw: "")
    }

    public static func new(_ path: Path, _ pathStyle: PathStyle = .local()) throws -> ArcCow<RelPath> {
        try new(path.rawValue, pathStyle)
    }

    public static func new(_ path: String, _ pathStyle: PathStyle = .local()) throws -> ArcCow<RelPath> {
        var str = path
        var owned = false

        let prefixes: [String] = pathStyle == .posix ? ["./"] : ["./", ".\\"]
        let suffixes: [Character] = pathStyle == .posix ? ["/"] : ["/", "\\"]

        var strippedPrefix = true
        while strippedPrefix {
            strippedPrefix = false
            for prefix in prefixes {
                if str.hasPrefix(prefix) {
                    str = String(str.dropFirst(prefix.count))
                    strippedPrefix = true
                    break
                }
            }
        }

        while let last = str.last, suffixes.contains(last) && str.count > 1 {
            str = String(str.dropLast())
        }

        if is_absolute(str, pathStyle) {
            throw RelPathError("absolute path not allowed: \(path)")
        }

        if pathStyle == .windows && str.contains("\\") {
            str = str.replacingOccurrences(of: "\\", with: "/")
            owned = true
        }

        if !str.isEmpty {
            let comps = str.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            if comps.contains(where: { $0 == "" || $0 == "." || $0 == ".." }) {
                var normalized: [String] = []
                for comp in comps {
                    if comp.isEmpty || comp == "." {
                        continue
                    } else if comp == ".." {
                        if normalized.isEmpty {
                            throw RelPathError("path is not relative: \(path)")
                        }
                        normalized.removeLast()
                    } else {
                        normalized.append(comp)
                    }
                }
                str = normalized.joined(separator: "/")
                owned = true
            }
        }

        let rel = RelPath(raw: str)
        if owned {
            return .owned(rel)

        } else {
            return .borrowed(rel)
        }
    }

    public static func unix(_ path: Path) throws -> RelPath {
        try unix(path.rawValue)
    }

    public static func unix(_ path: String) throws -> RelPath {
        let cow = try RelPath.new(path, .posix)
        switch cow {
        case .borrowed(let p):
            return p
        case .owned:
            throw RelPathError("invalid relative path \(path)")
        }
    }

    public var isEmpty: Bool {
        raw.isEmpty
    }

    public func is_empty() -> Bool {
        isEmpty
    }

    public func components() -> RelPathComponents {
        RelPathComponents(raw)
    }

    public func ancestors() -> RelPathAncestors {
        RelPathAncestors(raw)
    }

    public func fileName() -> String? {
        var c = components()
        return c.next_back()
    }

    public func file_name() -> String? {
        fileName()
    }

    public func fileStem() -> String? {
        guard let name = fileName() else { return nil }
        if name.hasPrefix(".") {
            let afterDot = name.dropFirst()
            if let dotIdx = afterDot.lastIndex(of: ".") {
                return "." + String(afterDot[..<dotIdx])
            }
            return name
        }
        if let dotIdx = name.lastIndex(of: ".") {
            return String(name[..<dotIdx])
        }
        return name
    }

    public func file_stem() -> String? {
        fileStem()
    }

    public func `extension`() -> String? {
        guard let name = fileName() else { return nil }
        if name.hasPrefix(".") {
            let afterDot = name.dropFirst()
            if let dotIdx = afterDot.lastIndex(of: ".") {
                return String(afterDot[afterDot.index(after: dotIdx)...])
            }
            return nil
        }
        if let dotIdx = name.lastIndex(of: ".") {
            return String(name[name.index(after: dotIdx)...])
        }
        return nil
    }

    public func parent() -> RelPath? {
        var comps = components()
        guard comps.next_back() != nil else { return nil }
        return comps.rest()
    }

    public func startsWith(_ other: RelPath) -> Bool {
        (try? stripPrefix(other)) != nil
    }

    public func starts_with(_ other: RelPath) -> Bool {
        startsWith(other)
    }

    public func endsWith(_ other: RelPath) -> Bool {
        if raw.hasSuffix(other.raw) {
            let suffixLen = other.raw.count
            let prefix = raw.dropLast(suffixLen)
            if prefix.hasSuffix("/") || prefix.isEmpty {
                return true
            }
        }
        return false
    }

    public func ends_with(_ other: RelPath) -> Bool {
        endsWith(other)
    }

    public func stripPrefix(_ other: RelPath) throws -> RelPath {
        if other.isEmpty {
            return self
        }
        if raw.hasPrefix(other.raw) {
            let remainder = raw.dropFirst(other.raw.count)
            if remainder.hasPrefix("/") {
                return RelPath(raw: String(remainder.dropFirst()))
            } else if remainder.isEmpty {
                return RelPath.empty()
            }
        }
        throw StripPrefixError()
    }

    public func strip_prefix(_ other: RelPath) throws -> RelPath {
        try stripPrefix(other)
    }

    public func len() -> Int {
        if raw.isEmpty { return 0 }
        return raw.split(separator: "/").count
    }

    public func lastNComponents(_ count: Int) -> RelPath? {
        let length = len()
        if length >= count {
            var comps = components()
            for _ in 0..<(length - count) {
                guard comps.next() != nil else { return nil }
            }
            return comps.rest()
        }
        return nil
    }

    public func last_n_components(_ count: Int) -> RelPath? {
        lastNComponents(count)
    }

    public func join(_ other: RelPath) -> RelPath {
        if raw.isEmpty {
            return other
        } else if other.raw.isEmpty {
            return self
        } else {
            return RelPath(raw: "\(raw)/\(other.raw)")
        }
    }

    public func toRelPathBuf() -> RelPathBuf {
        RelPathBuf(raw)
    }

    public func to_rel_path_buf() -> RelPathBuf {
        toRelPathBuf()
    }

    public func intoArc() -> RelPath {
        self
    }

    public func into_arc() -> RelPath {
        self
    }

    public func toProto() -> String {
        raw
    }

    public func to_proto() -> String {
        raw
    }

    public static func fromProto(_ path: String) throws -> RelPath {
        try unix(path)
    }

    public static func from_proto(_ path: String) throws -> RelPath {
        try fromProto(path)
    }

    public func display(_ style: PathStyle) -> String {
        switch style {
        case .posix:
            return raw
        case .windows:
            return raw.replacingOccurrences(of: "/", with: "\\")
        }
    }

    public func asUnixStr() -> String {
        raw
    }

    public func as_unix_str() -> String {
        raw
    }

    public func asStdPath() -> Path {
        Path(raw)
    }

    public func as_std_path() -> Path {
        asStdPath()
    }

    public func asRelPath() -> RelPath {
        self
    }

    public func as_rel_path() -> RelPath {
        self
    }

    public var description: String {
        raw
    }

    public static func < (lhs: RelPath, rhs: RelPath) -> Bool {
        let compsL = Array(lhs.components())
        let compsR = Array(rhs.components())
        for (cL, cR) in zip(compsL, compsR) {
            if cL != cR {
                return cL < cR
            }
        }
        return compsL.count < compsR.count
    }

    public static func == (lhs: RelPath, rhs: String) -> Bool {
        lhs.raw == rhs
    }

    public static func == (lhs: String, rhs: RelPath) -> Bool {
        lhs == rhs.raw
    }
}

// PORT NOTE: Matches upstream `rel_path!` macro: caller passes a known-valid relative path, which cannot fail to parse as Unix relative path.
public func rel_path(_ path: String) -> RelPath {
    try! RelPath.unix(path)
}

// PORT NOTE: Matches upstream `rel_path!` macro: caller passes a known-valid relative path, which cannot fail to parse as Unix relative path.
public func relPath(_ path: String) -> RelPath {
    try! RelPath.unix(path)
}


// MARK: - RelPathBuf

public struct RelPathBuf: Hashable, Comparable, Sendable, CustomStringConvertible, ExpressibleByStringLiteral, Codable {
    public var raw: String

    public init() {
        self.raw = ""
    }

    public init(_ raw: String) {
        self.raw = raw
    }

    public init(_ path: RelPath) {
        self.raw = path.raw
    }

    public init(stringLiteral value: String) {
        self.raw = value
    }

    @discardableResult
    public mutating func pop() -> Bool {
        if let idx = raw.lastIndex(of: "/") {
            raw = String(raw[..<idx])
            return true
        } else if !raw.isEmpty {
            raw = ""
            return true
        } else {
            return false
        }
    }

    public mutating func push(_ path: RelPath) {
        push(path.raw)
    }

    public mutating func push(_ path: RelPathBuf) {
        push(path.raw)
    }

    public mutating func push(_ string: String) {
        if !raw.isEmpty {
            raw += "/"
        }
        raw += string
    }

    public mutating func setExtension(_ ext: String) -> Bool {
        guard let fname = fileName() else { return false }
        let p = Path(fname)
        let stem = p.fileStem() ?? fname
        let newFname = ext.isEmpty ? stem : "\(stem).\(ext)"
        pop()
        push(newFname)
        return true
    }

    public mutating func set_extension(_ ext: String) -> Bool {
        setExtension(ext)
    }

    public func asRelPath() -> RelPath {
        RelPath(raw: raw)
    }

    public func as_rel_path() -> RelPath {
        asRelPath()
    }

    public var isEmpty: Bool {
        raw.isEmpty
    }

    public func is_empty() -> Bool {
        isEmpty
    }

    public func fileName() -> String? {
        asRelPath().fileName()
    }

    public func file_name() -> String? {
        fileName()
    }

    public func fileStem() -> String? {
        asRelPath().fileStem()
    }

    public func file_stem() -> String? {
        fileStem()
    }

    public func `extension`() -> String? {
        asRelPath().extension()
    }

    public func parent() -> RelPath? {
        asRelPath().parent()
    }

    public var description: String {
        raw
    }

    public static func < (lhs: RelPathBuf, rhs: RelPathBuf) -> Bool {
        lhs.asRelPath() < rhs.asRelPath()
    }

    public static func == (lhs: RelPathBuf, rhs: RelPath) -> Bool {
        lhs.raw == rhs.raw
    }

    public static func == (lhs: RelPath, rhs: RelPathBuf) -> Bool {
        lhs.raw == rhs.raw
    }
}

// MARK: - RelPathComponents

public struct RelPathComponents: Sequence, IteratorProtocol, Collection, BidirectionalCollection {
    private var raw: String
    private var elements: [String]

    public init(_ raw: String) {
        self.raw = raw
        if raw.isEmpty {
            self.elements = []
        } else {
            self.elements = raw.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        }
    }

    public func rest() -> RelPath {
        RelPath(raw: raw)
    }

    public mutating func next() -> String? {
        if raw.isEmpty {
            return nil
        }
        if let idx = raw.firstIndex(of: "/") {
            let head = String(raw[..<idx])
            raw = String(raw[raw.index(after: idx)...])
            return head
        } else {
            let res = raw
            raw = ""
            return res
        }
    }

    public mutating func next_back() -> String? {
        if raw.isEmpty {
            return nil
        }
        if let idx = raw.lastIndex(of: "/") {
            let tail = String(raw[raw.index(after: idx)...])
            raw = String(raw[..<idx])
            return tail
        } else {
            let res = raw
            raw = ""
            return res
        }
    }

    public func rev() -> [String] {
        Array(elements.reversed())
    }

    // Collection conformance
    public typealias Index = Int
    public var startIndex: Int { elements.startIndex }
    public var endIndex: Int { elements.endIndex }
    public func index(after i: Int) -> Int { elements.index(after: i) }
    public func index(before i: Int) -> Int { elements.index(before: i) }
    public subscript(position: Int) -> String { elements[position] }
}

// MARK: - RelPathAncestors

public struct RelPathAncestors: Sequence, IteratorProtocol {
    private var current: String?

    public init(_ raw: String?) {
        self.current = raw
    }

    public mutating func next() -> RelPath? {
        guard let res = current else { return nil }
        if let idx = res.lastIndex(of: "/") {
            current = String(res[..<idx])
        } else if !res.isEmpty {
            current = ""
        } else {
            current = nil
        }
        return RelPath(raw: res)
    }
}
