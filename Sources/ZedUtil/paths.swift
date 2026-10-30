// Ported from: crates/util/src/paths.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Foundation
import GPUICollections
import GPUIUtil

// MARK: - Ordering

/// A three-way ordering enum mirroring Rust's `std::cmp::Ordering`.
public enum Ordering: Sendable, Equatable, Hashable, CustomStringConvertible {
    case less
    case equal
    case greater

    public static let Less = Ordering.less
    public static let Equal = Ordering.equal
    public static let Greater = Ordering.greater

    public var isEq: Bool { self == .equal }

    public var description: String {
        switch self {
        case .less: return "Less"
        case .equal: return "Equal"
        case .greater: return "Greater"
        }
    }

    @inlinable
    public func then(_ other: Ordering) -> Ordering {
        if self == .equal {
            return other
        }
        return self
    }

    @inlinable
    public func thenWith(_ other: () -> Ordering) -> Ordering {
        if self == .equal {
            return other()
        }
        return self
    }
}

extension Comparable {
    @inlinable
    public func cmp(_ other: Self) -> Ordering {
        if self < other {
            return .less
        } else if self > other {
            return .greater
        } else {
            return .equal
        }
    }
}

extension Bool {
    @inlinable
    public func cmp(_ other: Bool) -> Ordering {
        switch (self, other) {
        case (false, true): return .less
        case (true, false): return .greater
        default: return .equal
        }
    }
}

// MARK: - Path and PathBuf

/// Cross-platform filesystem path type matching Rust's `Path` / `PathBuf`.
public struct Path: Hashable, Comparable, Sendable, CustomStringConvertible, ExpressibleByStringLiteral, Codable {
    public var rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }

    public static func from(_ string: String) -> Path {
        Path(string)
    }

    public static func new(_ string: String = "") -> Path {
        Path(string)
    }

    public var description: String {
        rawValue
    }

    public func asPath() -> Path {
        self
    }

    public func as_path() -> Path {
        self
    }

    public func asOsStr() -> String {
        rawValue
    }

    public func as_os_str() -> String {
        rawValue
    }

    public func toStr() -> String? {
        rawValue
    }

    public func to_str() -> String? {
        rawValue
    }

    public func toString() -> String {
        rawValue
    }

    public func to_string() -> String {
        rawValue
    }

    public func toPathBuf() -> Path {
        self
    }

    public func to_path_buf() -> Path {
        self
    }

    public var isEmpty: Bool {
        rawValue.isEmpty
    }

    public func fileName() -> String? {
        if rawValue.isEmpty { return nil }
        if rawValue == "/" { return "/" }
        let trimmed = rawValue.hasSuffix("/") || rawValue.hasSuffix("\\") ? String(rawValue.dropLast()) : rawValue
        if let idx = trimmed.lastIndex(where: { $0 == "/" || $0 == "\\" }) {
            let name = String(trimmed[trimmed.index(after: idx)...])
            return name.isEmpty ? nil : name
        }
        return trimmed
    }

    public func file_name() -> String? {
        fileName()
    }

    public func fileStem() -> String? {
        guard let name = fileName() else { return nil }
        if name == "/" || name == "\\" { return name }
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

    public func components() -> [String] {
        if rawValue.isEmpty { return [] }
        var parts: [String] = []
        var remaining = rawValue[...]

        if remaining.hasPrefix("/") {
            parts.append("/")
            while remaining.hasPrefix("/") {
                remaining = remaining.dropFirst()
            }
        } else if remaining.count >= 2,
                  let first = remaining.first, first.isASCII && first.isLetter,
                  remaining[remaining.index(remaining.startIndex, offsetBy: 1)] == ":" {
            let driveEnd = remaining.index(remaining.startIndex, offsetBy: 2)
            let drive = String(remaining[..<driveEnd])
            remaining = remaining[driveEnd...]
            if remaining.hasPrefix("\\") || remaining.hasPrefix("/") {
                let sep = String(remaining.first!)
                parts.append(drive + sep)
                while remaining.hasPrefix("\\") || remaining.hasPrefix("/") {
                    remaining = remaining.dropFirst()
                }
            } else {
                parts.append(drive)
            }
        }

        while !remaining.isEmpty {
            if let idx = remaining.firstIndex(where: { $0 == "/" || $0 == "\\" }) {
                let comp = String(remaining[..<idx])
                if !comp.isEmpty {
                    parts.append(comp)
                }
                remaining = remaining[idx...]
                while remaining.hasPrefix("/") || remaining.hasPrefix("\\") {
                    remaining = remaining.dropFirst()
                }
            } else {
                parts.append(String(remaining))
                break
            }
        }
        return parts
    }

    public mutating func push(_ component: String) {
        if rawValue.isEmpty {
            rawValue = component
        } else if rawValue.hasSuffix("/") || rawValue.hasSuffix("\\") {
            rawValue += component
        } else {
            #if os(Windows)
            rawValue += "\\" + component
            #else
            rawValue += "/" + component
            #endif
        }
    }

    public mutating func push(_ component: Path) {
        push(component.rawValue)
    }

    @discardableResult
    public mutating func pop() -> Bool {
        if let idx = rawValue.lastIndex(where: { $0 == "/" || $0 == "\\" }) {
            rawValue = String(rawValue[..<idx])
            return true
        } else if !rawValue.isEmpty {
            rawValue = ""
            return true
        } else {
            return false
        }
    }

    public func join<P: CustomStringConvertible>(_ other: P) -> Path {
        let otherStr = other.description
        if otherStr.isEmpty { return self }
        if rawValue.isEmpty { return Path(otherStr) }
        let sep = (rawValue.hasSuffix("/") || rawValue.hasSuffix("\\")) ? "" : "/"
        return Path("\(rawValue)\(sep)\(otherStr)")
    }

    public func parent() -> Path? {
        if let idx = rawValue.lastIndex(where: { $0 == "/" || $0 == "\\" }) {
            if idx == rawValue.startIndex {
                return Path(String(rawValue[...idx]))
            }
            return Path(String(rawValue[..<idx]))
        }
        return nil
    }

    public func startsWith(_ prefix: Path) -> Bool {
        rawValue.hasPrefix(prefix.rawValue)
    }

    public func starts_with(_ prefix: Path) -> Bool {
        startsWith(prefix)
    }

    public func endsWith(_ suffix: Path) -> Bool {
        path_ends_with(self, suffix)
    }

    public func ends_with(_ suffix: Path) -> Bool {
        endsWith(suffix)
    }

    public func stripPrefix(_ base: Path) throws -> Path {
        if base.rawValue.isEmpty { return self }
        if rawValue.hasPrefix(base.rawValue) {
            let remainder = String(rawValue.dropFirst(base.rawValue.count))
            if remainder.hasPrefix("/") || remainder.hasPrefix("\\") {
                return Path(String(remainder.dropFirst()))
            } else if remainder.isEmpty {
                return Path("")
            }
        }
        throw StripPrefixError()
    }

    public func strip_prefix(_ base: Path) throws -> Path {
        try stripPrefix(base)
    }

    public static func < (lhs: Path, rhs: Path) -> Bool {
        let compsL = lhs.rawValue.split(whereSeparator: { $0 == "/" || $0 == "\\" })
        let compsR = rhs.rawValue.split(whereSeparator: { $0 == "/" || $0 == "\\" })
        for (cL, cR) in zip(compsL, compsR) {
            if cL != cR {
                return cL < cR
            }
        }
        return compsL.count < compsR.count
    }
}


public typealias PathBuf = Path

// MARK: - Home Directory

private let cachedHomeDir: Path = {
    #if DEBUG || TestSupport
        #if os(macOS)
        return Path("/Users/zed")
        #elseif os(Windows)
        return Path("C:\\Users\\zed")
        #else
        return Path("/home/zed")
        #endif
    #else
        return Path(FileManager.default.homeDirectoryForCurrentUser.path)
    #endif
}()

/// Returns the path to the user's home directory.
public func home_dir() -> Path {
    cachedHomeDir
}

public func homeDir() -> Path {
    cachedHomeDir
}

// MARK: - PathStyle

@frozen
public enum PathStyle: Sendable, Hashable, CustomStringConvertible {
    case posix
    case windows

    public static var Posix: PathStyle { .posix }
    public static var Windows: PathStyle { .windows }

    public static func local() -> PathStyle {
        #if os(Windows)
        return .windows
        #else
        return .posix
        #endif
    }

    public var primarySeparator: String {
        switch self {
        case .posix: return "/"
        case .windows: return "\\"
        }
    }

    public func primary_separator() -> String {
        primarySeparator
    }

    public var separators: [String] {
        switch self {
        case .posix: return ["/"]
        case .windows: return ["\\", "/"]
        }
    }

    public var separatorsCh: [Character] {
        switch self {
        case .posix: return ["/"]
        case .windows: return ["\\", "/"]
        }
    }

    public func separators_ch() -> [Character] {
        separatorsCh
    }

    public func isAbsolute(_ pathLike: String) -> Bool {
        if pathLike.hasPrefix("/") { return true }
        if self == .windows {
            if pathLike.hasPrefix("\\") { return true }
            if let first = pathLike.first, first.isASCII && first.isLetter {
                let rest = pathLike.dropFirst()
                if rest.hasPrefix(":") {
                    let afterColon = rest.dropFirst()
                    if afterColon.hasPrefix("/") || afterColon.hasPrefix("\\") {
                        return true
                    }
                }
            }
        }
        return false
    }

    public func is_absolute(_ pathLike: String) -> Bool {
        isAbsolute(pathLike)
    }

    public var isWindows: Bool { self == .windows }
    public func is_windows() -> Bool { isWindows }

    public var isPosix: Bool { self == .posix }
    public func is_posix() -> Bool { isPosix }

    public func join(_ left: String, _ right: String) -> String? {
        if isAbsolute(right) {
            return nil
        }
        if left.isEmpty {
            return right
        }
        let sep = left.hasSuffix(primarySeparator) ? "" : primarySeparator
        return "\(left)\(sep)\(right)"
    }

    public func join(_ left: Path, _ right: Path) -> String? {
        join(left.rawValue, right.rawValue)
    }

    public func split(_ pathLike: String) -> (String?, String) {
        guard let range = pathLike.range(of: primarySeparator, options: .backwards) else {
            return (nil, pathLike)
        }
        let dirEnd = range.upperBound
        return (String(pathLike[..<dirEnd]), String(pathLike[dirEnd...]))
    }

    public func stripPrefix(child: String, parent: String) -> ArcCow<RelPath>? {
        if parent.isEmpty {
            return try? RelPath.new(child, self)
        }
        var cleanParent = parent
        for sep in separators {
            if cleanParent.hasSuffix(sep) {
                cleanParent = String(cleanParent.dropLast(sep.count))
                break
            }
        }
        guard child.hasPrefix(cleanParent) else { return nil }
        let stripped = String(child.dropFirst(cleanParent.count))
        for sep in separators {
            if stripped.hasPrefix(sep) {
                let relative = String(stripped.dropFirst(sep.count))
                return try? RelPath.new(relative, self)
            }
        }
        if stripped.isEmpty {
            return .borrowed(RelPath.empty())
        }
        return nil
    }

    public func strip_prefix(_ child: Path, _ parent: Path) -> ArcCow<RelPath>? {
        stripPrefix(child: child.rawValue, parent: parent.rawValue)
    }

    public var description: String {
        switch self {
        case .posix: return "Posix"
        case .windows: return "Windows"
        }
    }
}

public func is_absolute(_ pathLike: String, _ pathStyle: PathStyle) -> Bool {
    pathStyle.isAbsolute(pathLike)
}

public func isAbsolute(_ pathLike: String, _ pathStyle: PathStyle) -> Bool {
    pathStyle.isAbsolute(pathLike)
}

// MARK: - RemotePathBuf

public struct RemotePathBuf: Sendable, CustomStringConvertible, Equatable, Hashable {
    public var string: String
    public var style: PathStyle

    public init(string: String, style: PathStyle) {
        self.string = string
        self.style = style
    }

    public static func fromStr(_ path: String, style: PathStyle) -> RemotePathBuf {
        RemotePathBuf(string: path, style: style)
    }

    public static func from_str(_ path: String, style: PathStyle) -> RemotePathBuf {
        fromStr(path, style: style)
    }

    public func pathStyle() -> PathStyle {
        style
    }

    public func path_style() -> PathStyle {
        style
    }

    public func toProto() -> String {
        string
    }

    public func to_proto() -> String {
        string
    }

    public var description: String {
        string
    }
}

// MARK: - Path Normalization

public struct NormalizeError: Error, Equatable, Sendable, CustomStringConvertible {
    public init() {}
    public var description: String {
        "parent reference `..` points outside of base directory"
    }
}

public func normalize_lexically(_ path: Path) throws -> Path {
    var parts: [String] = []
    let components = path.components()

    var rootPrefix = ""
    var startIdx = 0
    if let first = components.first {
        if first == "/" {
            rootPrefix = "/"
            startIdx = 1
        } else if first.hasSuffix(":\\") || first.hasSuffix(":/") {
            rootPrefix = first
            startIdx = 1
        }
    }

    for comp in components[startIdx...] {
        if comp == "." || comp.isEmpty {
            continue
        } else if comp == ".." {
            if !parts.isEmpty {
                parts.removeLast()
            } else if !rootPrefix.isEmpty {
                throw NormalizeError()
            } else {
                throw NormalizeError()
            }
        } else {
            parts.append(comp)
        }
    }

    if rootPrefix.isEmpty {
        if parts.isEmpty {
            return Path("")
        }
        return Path(parts.joined(separator: "/"))
    } else {
        if parts.isEmpty {
            return Path(rootPrefix)
        }
        let sep = (rootPrefix.hasSuffix("/") || rootPrefix.hasSuffix("\\")) ? "" : "/"
        return Path(rootPrefix + sep + parts.joined(separator: "/"))
    }
}

public func normalize_lexically(_ path: String) throws -> String {
    try normalize_lexically(Path(path)).rawValue
}

// MARK: - PathWithPosition

public struct PathWithPosition: CustomDebugStringConvertible, CustomStringConvertible, Hashable, Equatable, Sendable, Codable {
    public var path: Path
    public var row: UInt32?
    public var column: UInt32?

    public var description: String {
        to_string { $0.rawValue }
    }

    public var debugDescription: String {
        "PathWithPosition(path: \(path), row: \(String(describing: row)), column: \(String(describing: column)))"
    }

    public init(path: Path, row: UInt32? = nil, column: UInt32? = nil) {
        self.path = path
        self.row = row
        self.column = column
    }

    public static func fromPath(_ path: Path) -> PathWithPosition {
        PathWithPosition(path: path)
    }

    public static func from_path(_ path: Path) -> PathWithPosition {
        fromPath(path)
    }

    public static func parse_str(_ s: String) -> PathWithPosition {
        parseStr(s, style: .local())
    }

    public static func parse_str(_ s: String, style: PathStyle) -> PathWithPosition {
        parseStr(s, style: style)
    }

    public static func parseStr(_ s: String, style: PathStyle = .local()) -> PathWithPosition {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return PathWithPosition(path: Path(s))
        }

        // Find file name part using style separators
        let separators = style.separators_ch()
        let lastSepIndex = trimmed.lastIndex(where: { separators.contains($0) })
        let parentPart: String
        let fileNamePart: String
        if let lastSepIndex = lastSepIndex {
            parentPart = String(trimmed[...lastSepIndex])
            fileNamePart = String(trimmed[trimmed.index(after: lastSepIndex)...])
        } else {
            parentPart = ""
            fileNamePart = trimmed
        }

        // Upstream ROW_COL_CAPTURE_REGEX:
        // Branch 1: ([^\(]+)\:(?:\((\d+)[,:](\d+)\)|\((\d+)\)())(.*)$
        // Branch 2: ([^\(]+)(?:\((\d+)[,:](\d+)\)|\((\d+)\)())\:*$
        // Branch 3: (.+?)(?:\:+(\d+)\:(\d+)\:*$|\:+(\d+)\:*()$|\:+()()$)
        let pattern = #"^([^\(]+)\:(?:\((\d+)[,:](\d+)\)|\((\d+)\)())(.*)$|^([^\(]+)(?:\((\d+)[,:](\d+)\)|\((\d+)\)())\:*$|^(.+?)(?:\:+(\d+)\:(\d+)\:*$|\:+(\d+)\:*()$|\:+()()$)"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) {
            let nsStr = fileNamePart as NSString
            let matches = regex.matches(in: fileNamePart, options: [], range: NSRange(location: 0, length: nsStr.length))
            if let match = matches.first {
                let fileName: String?
                let row: UInt32?
                let col: UInt32?

                if match.range(at: 1).location != NSNotFound {
                    // Branch 1
                    fileName = nsStr.substring(with: match.range(at: 1))
                    let r = match.range(at: 2).location != NSNotFound ? nsStr.substring(with: match.range(at: 2)) :
                            match.range(at: 4).location != NSNotFound ? nsStr.substring(with: match.range(at: 4)) : nil
                    let c = match.range(at: 3).location != NSNotFound ? nsStr.substring(with: match.range(at: 3)) : nil
                    row = r.flatMap { UInt32($0) }
                    col = c.flatMap { UInt32($0) }
                } else if match.range(at: 7).location != NSNotFound {
                    // Branch 2
                    fileName = nsStr.substring(with: match.range(at: 7))
                    let r = match.range(at: 8).location != NSNotFound ? nsStr.substring(with: match.range(at: 8)) :
                            match.range(at: 10).location != NSNotFound ? nsStr.substring(with: match.range(at: 10)) : nil
                    let c = match.range(at: 9).location != NSNotFound ? nsStr.substring(with: match.range(at: 9)) : nil
                    row = r.flatMap { UInt32($0) }
                    col = c.flatMap { UInt32($0) }
                } else if match.range(at: 12).location != NSNotFound {
                    // Branch 3
                    fileName = nsStr.substring(with: match.range(at: 12))
                    let r = match.range(at: 13).location != NSNotFound ? nsStr.substring(with: match.range(at: 13)) :
                            match.range(at: 15).location != NSNotFound ? nsStr.substring(with: match.range(at: 15)) : nil
                    let c = match.range(at: 14).location != NSNotFound ? nsStr.substring(with: match.range(at: 14)) : nil
                    row = r.flatMap { UInt32($0) }
                    col = c.flatMap { UInt32($0) }
                } else {
                    fileName = nil
                    row = nil
                    col = nil
                }

                if let fileName = fileName {
                    var pathStr = parentPart + fileName
                    if style.is_windows() {
                        pathStr = pathStr.replacingOccurrences(of: "/", with: "\\")
                    }
                    return PathWithPosition(path: Path(pathStr), row: row, column: col)
                }
            }
        }

        // Fallback suffix parsing corresponding to upstream rsplitn(3, ':')
        let delimiter: Character = ":"
        let rawSplits = s.split(separator: delimiter, omittingEmptySubsequences: false).map(String.init)
        if rawSplits.count >= 3 {
            let last1 = rawSplits[rawSplits.count - 1]
            let last2 = rawSplits[rawSplits.count - 2]
            let rest = rawSplits.dropLast(2).joined(separator: ":")
            var pathString = rest
            var row: UInt32?
            var column: UInt32?
            if let parsedRow = UInt32(last2) {
                row = parsedRow
                if let parsedCol = UInt32(last1) {
                    column = parsedCol
                }
            } else {
                pathString += ":" + last2
                pathString += ":" + last1
            }
            var resultPath = pathString
            if style.is_windows() {
                resultPath = resultPath.replacingOccurrences(of: "/", with: "\\")
            }
            return PathWithPosition(path: Path(resultPath), row: row, column: column)
        } else if rawSplits.count == 2 {
            let last1 = rawSplits[1]
            let rest = rawSplits[0]
            var pathString = rest
            var row: UInt32?
            if let parsedRow = UInt32(last1) {
                row = parsedRow
            } else {
                pathString += ":" + last1
            }
            var resultPath = pathString
            if style.is_windows() {
                resultPath = resultPath.replacingOccurrences(of: "/", with: "\\")
            }
            return PathWithPosition(path: Path(resultPath), row: row, column: nil)
        }

        var resultPath = trimmed
        if style.is_windows() {
            resultPath = resultPath.replacingOccurrences(of: "/", with: "\\")
        }
        return PathWithPosition(path: Path(resultPath))
    }


    public func mapPath<E: Error>(_ mapping: (Path) throws(E) -> Path) throws(E) -> PathWithPosition {
        PathWithPosition(path: try mapping(path), row: row, column: column)
    }

    public func map_path<E: Error>(_ mapping: (Path) throws(E) -> Path) throws(E) -> PathWithPosition {
        try mapPath(mapping)
    }

    public func toString(_ pathToString: (Path) -> String) -> String {
        let pathString = pathToString(path)
        if let row = row {
            if let column = column {
                return "\(pathString):\(row):\(column)"
            } else {
                return "\(pathString):\(row)"
            }
        } else {
            return pathString
        }
    }

    public func to_string(_ pathToString: (Path) -> String) -> String {
        toString(pathToString)
    }
}

// MARK: - Natural Sort

public struct PeekableIterator<I: IteratorProtocol>: IteratorProtocol {
    private var iterator: I
    private var peeked: I.Element?? = nil

    public init(_ iterator: I) {
        self.iterator = iterator
    }

    public mutating func peek() -> I.Element? {
        if let p = peeked {
            return p
        }
        let n = iterator.next()
        peeked = n
        return n
    }

    public mutating func next() -> I.Element? {
        if let p = peeked {
            peeked = nil
            return p
        }
        return iterator.next()
    }
}

private func fitsInU128(_ s: Substring) -> Bool {
    if s.count < 39 { return true }
    if s.count > 39 { return false }
    return s <= "340282366920938463463374607431768211455"
}

public func compare_numeric_segments<I: IteratorProtocol>(
    _ aIter: inout PeekableIterator<I>,
    _ bIter: inout PeekableIterator<I>
) -> Ordering where I.Element == Character {
    var aNumStr = ""
    var bNumStr = ""

    while let c = aIter.peek(), c.isASCII && c.isNumber {
        aNumStr.append(c)
        _ = aIter.next()
    }

    while let c = bIter.peek(), c.isASCII && c.isNumber {
        bNumStr.append(c)
        _ = bIter.next()
    }

    if aNumStr.count == bNumStr.count {
        return aNumStr.cmp(bNumStr)
    } else {
        let aTrimmed = aNumStr.drop(while: { $0 == "0" })
        let bTrimmed = bNumStr.drop(while: { $0 == "0" })

        if fitsInU128(aTrimmed) && fitsInU128(bTrimmed) {
            if aTrimmed.count != bTrimmed.count {
                return aTrimmed.count.cmp(bTrimmed.count)
            }
            if aTrimmed != bTrimmed {
                return aTrimmed.cmp(bTrimmed)
            }
            return aNumStr.count.cmp(bNumStr.count)
        } else {
            return aNumStr.cmp(bNumStr)
        }
    }
}


public func natural_sort(_ a: String, _ b: String) -> Ordering {
    var aIter = PeekableIterator(a.makeIterator())
    var bIter = PeekableIterator(b.makeIterator())

    while true {
        switch (aIter.peek(), bIter.peek()) {
        case (.none, .none):
            // Tie-breaker: b.cmp(a) ensures lowercase is sorted before uppercase
            return b.cmp(a)
        case (.none, .some):
            return .less
        case (.some, .none):
            return .greater
        case (.some(let aChar), .some(let bChar)):
            if aChar.isASCII && aChar.isNumber && bChar.isASCII && bChar.isNumber {
                let cmp = compare_numeric_segments(&aIter, &bIter)
                if cmp == .equal {
                    continue
                }
                return cmp
            } else {
                let aLower = String(aChar).lowercased()
                let bLower = String(bChar).lowercased()
                let cmp = aLower.cmp(bLower)
                if cmp == .equal {
                    _ = aIter.next()
                    _ = bIter.next()
                } else {
                    return cmp
                }
            }
        }
    }
}

public func naturalSort(_ a: String, _ b: String) -> Ordering {
    natural_sort(a, b)
}

public func natural_sort_no_tiebreak(_ a: String, _ b: String) -> Ordering {
    if a.caseInsensitiveCompare(b) == .orderedSame {
        return .equal
    } else {
        return natural_sort(a, b)
    }
}

public func stem_and_extension(_ filename: String) -> (String?, String?) {
    if filename.isEmpty {
        return (nil, nil)
    }
    if let dotIdx = filename.lastIndex(of: ".") {
        if dotIdx == filename.startIndex {
            return (filename, nil)
        }
        let stem = String(filename[..<dotIdx])
        let ext = String(filename[filename.index(after: dotIdx)...])
        return (stem, ext)
    } else {
        return (filename, nil)
    }
}

// MARK: - Sort Order & Mode

@frozen
public enum SortOrder: Sendable, Copyable, Hashable, DefaultInitializable {
    case `default`
    case upper
    case lower
    case unicode

    public init() {
        self = .default
    }
}

@frozen
public enum SortMode: Sendable, Copyable, Hashable, DefaultInitializable {
    case directoriesFirst
    case mixed
    case filesFirst

    public init() {
        self = .directoriesFirst
    }
}

private func case_group_key(_ name: String, _ order: SortOrder) -> UInt8 {
    guard let first = name.first else { return 0 }
    switch order {
    case .upper:
        return first.isLowercase ? 1 : 0
    case .lower:
        return first.isUppercase ? 1 : 0
    case .default, .unicode:
        return 0
    }
}

private func compare_strings(_ a: String, _ b: String, _ order: SortOrder) -> Ordering {
    switch order {
    case .unicode:
        return a.cmp(b)
    case .default, .upper, .lower:
        return natural_sort(a, b)
    }
}

private func compare_strings_no_tiebreak(_ a: String, _ b: String, _ order: SortOrder) -> Ordering {
    switch order {
    case .unicode:
        return a.cmp(b)
    case .default, .upper, .lower:
        return natural_sort_no_tiebreak(a, b)
    }
}

public func compare_rel_paths_by(
    _ a: (RelPath, Bool),
    _ b: (RelPath, Bool),
    _ mode: SortMode,
    _ order: SortOrder
) -> Ordering {
    let (pathA, aIsFile) = a
    let (pathB, bIsFile) = b
    let needsFinalTiebreak = mode != .directoriesFirst && pathA != pathB

    var compsA = pathA.components()
    var compsB = pathB.components()

    while true {
        let compA = compsA.next()
        let compB = compsB.next()

        switch (compA, compB) {
        case (.some(let cA), .some(let cB)):
            let aLeafFile = aIsFile && compsA.rest().isEmpty
            let bLeafFile = bIsFile && compsB.rest().isEmpty

            let fileDirOrdering: Ordering
            switch mode {
            case .directoriesFirst:
                fileDirOrdering = aLeafFile.cmp(bLeafFile)
            case .filesFirst:
                fileDirOrdering = bLeafFile.cmp(aLeafFile)
            case .mixed:
                fileDirOrdering = .equal
            }

            if !fileDirOrdering.isEq {
                return fileDirOrdering
            }

            let (aStem, aExt) = aLeafFile ? stem_and_extension(cA) : (nil, nil)
            let (bStem, bExt) = bLeafFile ? stem_and_extension(cB) : (nil, nil)
            let aKey = aLeafFile ? aStem : cA
            let bKey = bLeafFile ? bStem : cB

            let ordering: Ordering
            switch (aKey, bKey) {
            case (.some(let kA), .some(let kB)):
                var nameCmp = case_group_key(kA, order)
                    .cmp(case_group_key(kB, order))
                    .thenWith {
                        switch mode {
                        case .directoriesFirst:
                            return compare_strings(kA, kB, order)
                        case .mixed, .filesFirst:
                            return compare_strings_no_tiebreak(kA, kB, order)
                        }
                    }

                if mode == .mixed {
                    nameCmp = nameCmp.thenWith {
                        if kA.caseInsensitiveCompare(kB) == .orderedSame {
                            if aLeafFile && !bLeafFile {
                                return .greater
                            } else if !aLeafFile && bLeafFile {
                                return .less
                            }
                        }
                        return .equal
                    }
                }

                ordering = nameCmp.thenWith {
                    if aLeafFile && bLeafFile {
                        switch order {
                        case .unicode:
                            return (aExt ?? "").cmp(bExt ?? "")
                        case .default, .upper, .lower:
                            let aExtLower = (aExt ?? "").lowercased()
                            let bExtLower = (bExt ?? "").lowercased()
                            return aExtLower.cmp(bExtLower)
                        }
                    } else {
                        return .equal
                    }
                }
            case (.some, .none):
                ordering = .greater
            case (.none, .some):
                ordering = .less
            case (.none, .none):
                ordering = .equal
            }

            if !ordering.isEq {
                return ordering
            }

        case (.some, .none):
            return .greater
        case (.none, .some):
            return .less
        case (.none, .none):
            if needsFinalTiebreak {
                return compare_strings(pathA.as_unix_str(), pathB.as_unix_str(), order)
            }
            return .equal
        }
    }
}

public func compare_rel_paths(
    _ a: (RelPath, Bool),
    _ b: (RelPath, Bool)
) -> Ordering {
    compare_rel_paths_by(a, b, .directoriesFirst, .default)
}

public func compare_rel_paths_mixed(
    _ a: (RelPath, Bool),
    _ b: (RelPath, Bool)
) -> Ordering {
    compare_rel_paths_by(a, b, .mixed, .default)
}

public func compare_rel_paths_files_first(
    _ a: (RelPath, Bool),
    _ b: (RelPath, Bool)
) -> Ordering {
    compare_rel_paths_by(a, b, .filesFirst, .default)
}

public func compare_paths(
    _ a: (Path, Bool),
    _ b: (Path, Bool)
) -> Ordering {
    let (pathA, aIsFile) = a
    let (pathB, bIsFile) = b

    let compsA = pathA.components()
    let compsB = pathB.components()

    var idxA = 0
    var idxB = 0

    while idxA < compsA.count && idxB < compsB.count {
        let compA = compsA[idxA]
        let compB = compsB[idxB]

        let isLastA = (idxA + 1 == compsA.count)
        let isLastB = (idxB + 1 == compsB.count)

        let aFile = isLastA && aIsFile
        let bFile = isLastB && bIsFile

        let ordering = aFile.cmp(bFile).thenWith {
            let pA = Path(compA)
            let pB = Path(compB)

            let strA = aFile ? pA.fileStem() : pA.fileName()
            let strB = bFile ? pB.fileStem() : pB.fileName()

            let compCmp: Ordering
            switch (strA, strB) {
            case (.some(let sA), .some(let sB)):
                compCmp = natural_sort(sA, sB)
            case (.some, .none):
                compCmp = .greater
            case (.none, .some):
                compCmp = .less
            case (.none, .none):
                compCmp = .equal
            }

            return compCmp.thenWith {
                if aFile && bFile {
                    let extA = pA.extension() ?? ""
                    let extB = pB.extension() ?? ""
                    return extA.cmp(extB)
                } else {
                    return .equal
                }
            }
        }

        if !ordering.isEq {
            return ordering
        }

        idxA += 1
        idxB += 1
    }

    if idxA < compsA.count {
        return .greater
    } else if idxB < compsB.count {
        return .less
    } else {
        return .equal
    }
}

// MARK: - WSL Path

public struct WslPath: Sendable, Equatable, Hashable, CustomStringConvertible {
    public var distro: String
    public var path: String

    public init(distro: String, path: String) {
        self.distro = distro
        self.path = path
    }

    public static func from_path<P: CustomStringConvertible>(_ p: P) -> WslPath? {
        let str = p.description
        let normalized = str.replacingOccurrences(of: "/", with: "\\")
        let prefix1 = "\\\\wsl.localhost\\"
        let prefix2 = "\\\\wsl$\\"

        let remainder: String
        if normalized.lowercased().hasPrefix(prefix1.lowercased()) {
            remainder = String(normalized.dropFirst(prefix1.count))
        } else if normalized.lowercased().hasPrefix(prefix2.lowercased()) {
            remainder = String(normalized.dropFirst(prefix2.count))
        } else {
            return nil
        }

        let parts = remainder.split(separator: "\\", omittingEmptySubsequences: true).map(String.init)
        guard let distro = parts.first, !distro.isEmpty else {
            return nil
        }

        var result = ""
        for comp in parts.dropFirst() {
            if comp == "." {
                continue
            } else if comp == ".." {
                result += "/.."
            } else {
                result += "/" + comp
            }
        }
        if result.isEmpty {
            result = "/"
        }

        return WslPath(distro: distro, path: result)
    }

    public var description: String {
        "WslPath(distro: \(distro), path: \(path))"
    }
}

// MARK: - URL Extension

public struct PathConversionError: Error, Equatable, Sendable {}

public protocol UrlExt {
    func to_file_path_ext(_ pathStyle: PathStyle) -> Result<Path, PathConversionError>
}

extension URL: UrlExt {
    public static func parse(_ string: String) -> URL? {
        URL(string: string)
    }

    public func to_file_path_ext(_ sourcePathStyle: PathStyle) -> Result<Path, PathConversionError> {
        guard scheme == "file" else { return .failure(PathConversionError()) }

        let h = host
        if let h = h, !h.isEmpty, h != "localhost" {
            if sourcePathStyle == .posix {
                return .failure(PathConversionError())
            }
        }

        let pathStr = self.path

        switch sourcePathStyle {
        case .posix:
            if let h = h, !h.isEmpty && h != "localhost" {
                return .failure(PathConversionError())
            }
            var decoded = pathStr.removingPercentEncoding ?? pathStr
            if decoded.isEmpty {
                decoded = "/"
            }
            if decoded.count > 2 && decoded.dropFirst().first?.isLetter == true {
                let secondChar = decoded[decoded.index(decoded.startIndex, offsetBy: 2)]
                if (secondChar == ":" || secondChar == "|") && !decoded.hasSuffix("/") {
                    decoded += "/"
                }
            }
            return .success(Path(decoded))

        case .windows:
            if let h = h, !h.isEmpty && h != "localhost" {
                let decoded = pathStr.removingPercentEncoding ?? pathStr
                let unc = "\\\\" + h + decoded.replacingOccurrences(of: "/", with: "\\")
                return .success(Path(unc))
            } else {
                var p = pathStr
                if p.hasPrefix("/") {
                    p = String(p.dropFirst())
                }

                guard !p.isEmpty else { return .failure(PathConversionError()) }

                let firstComp: String
                let rest: String
                if let slashIdx = p.firstIndex(of: "/") {
                    firstComp = String(p[..<slashIdx])
                    rest = String(p[slashIdx...])
                } else {
                    firstComp = p
                    rest = ""
                }

                let driveLetter: String
                if firstComp.count == 2 && firstComp.first?.isLetter == true && firstComp.hasSuffix(":") {
                    driveLetter = firstComp
                } else if firstComp.count == 4 && firstComp.first?.isLetter == true {
                    let suffix = firstComp.dropFirst().lowercased()
                    if suffix == "%3a" {
                        driveLetter = String(firstComp.prefix(1)) + ":"
                    } else {
                        return .failure(PathConversionError())
                    }
                } else {
                    return .failure(PathConversionError())
                }

                let decodedRest = rest.removingPercentEncoding ?? rest
                var winPath = driveLetter + decodedRest.replacingOccurrences(of: "/", with: "\\")
                if rest.isEmpty && self.absoluteString.hasSuffix("/") && !winPath.hasSuffix("\\") {
                    winPath += "\\"
                }
                return .success(Path(winPath))
            }
        }
    }
}


// MARK: - SanitizedPath

public struct SanitizedPath: Hashable, Comparable, Sendable, CustomStringConvertible, Codable {
    public var path: Path

    public init(_ path: Path) {
        let raw = path.rawValue
        if raw.hasPrefix("\\\\?\\") {
            self.path = Path(String(raw.dropFirst(4)))
        } else {
            self.path = path
        }
    }

    public init(_ raw: String) {
        self.init(Path(raw))
    }

    public static func new<T: CustomStringConvertible>(_ path: T) -> SanitizedPath {
        SanitizedPath(Path(path.description))
    }

    public static func unchecked_new<T: CustomStringConvertible>(_ path: T) -> SanitizedPath {
        SanitizedPath(Path(path.description))
    }

    public static func from_arc(_ path: Path) -> SanitizedPath {
        SanitizedPath(path)
    }

    public static func new_arc<T: CustomStringConvertible>(_ path: T) -> SanitizedPath {
        SanitizedPath(Path(path.description))
    }

    public static func cast_arc(_ path: SanitizedPath) -> Path {
        path.path
    }

    public static func cast_arc_ref(_ path: SanitizedPath) -> Path {
        path.path
    }

    public var description: String {
        path.rawValue
    }

    public func as_path() -> Path {
        path
    }

    public func asPath() -> Path {
        path
    }

    public func to_path_buf() -> Path {
        path
    }

    public func toPathBuf() -> Path {
        path
    }

    public func to_str() -> String? {
        path.toStr()
    }

    public func toStr() -> String? {
        path.toStr()
    }

    public func starts_with(_ prefix: SanitizedPath) -> Bool {
        path.startsWith(prefix.path)
    }

    public func startsWith(_ prefix: SanitizedPath) -> Bool {
        path.startsWith(prefix.path)
    }

    public func file_name() -> String? {
        path.fileName()
    }

    public func fileName() -> String? {
        path.fileName()
    }

    public func extension_name() -> String? {
        path.extension()
    }

    public func `extension`() -> String? {
        path.extension()
    }

    public func join<P: CustomStringConvertible>(_ other: P) -> Path {
        path.join(other)
    }

    public func parent() -> SanitizedPath? {
        path.parent().map(SanitizedPath.init)
    }

    public func strip_prefix(_ base: SanitizedPath) throws -> Path {
        try path.stripPrefix(base.path)
    }

    public static func < (lhs: SanitizedPath, rhs: SanitizedPath) -> Bool {
        lhs.path < rhs.path
    }
}

// MARK: - Path Ext Trait & Helpers

public protocol PathExt {
    func compact() -> Path
    func extension_or_hidden_file_name() -> String?
    func local_to_wsl() -> Path?
    func multiple_extensions() -> String?
    func try_shell_safe(_ shellKind: ShellKind) throws -> String
}

extension Path: PathExt {
    public func compact() -> Path {
        #if os(macOS) || os(Linux)
        let home = home_dir().rawValue
        if rawValue.hasPrefix(home) {
            let relative = String(rawValue.dropFirst(home.count))
            if relative.hasPrefix("/") {
                return Path("~" + relative)
            } else if relative.isEmpty {
                return Path("~")
            }
        }
        return self
        #else
        return self
        #endif
    }

    public func extension_or_hidden_file_name() -> String? {
        guard let name = fileName() else { return nil }
        if name.hasPrefix(".") {
            return String(name.dropFirst())
        }
        if let ext = self.extension() {
            return ext
        }
        return fileStem()
    }

    public func local_to_wsl() -> Path? {
        let comps = components()
        var wsl = ""
        for comp in comps {
            if comp.count >= 2 && comp.hasSuffix(":") {
                let letter = String(comp.dropLast()).lowercased()
                wsl += "/mnt/\(letter)"
            } else if comp.count >= 3 && (comp.hasSuffix(":\\") || comp.hasSuffix(":/")) {
                let letter = String(comp.prefix(1)).lowercased()
                wsl += "/mnt/\(letter)"
            } else if comp == "/" || comp == "\\" {
                continue
            } else if comp == "." {
                wsl += "/."
            } else if comp == ".." {
                wsl += "/.."
            } else {
                wsl += "/\(comp)"
            }
        }
        return wsl.isEmpty ? nil : Path(wsl)
    }

    public func multiple_extensions() -> String? {
        guard let name = fileName() else { return nil }
        let parts = name.split(separator: ".").map(String.init)
        if parts.count < 3 {
            return nil
        }
        return parts.dropFirst().joined(separator: ".")
    }

    public func try_shell_safe(_ shellKind: ShellKind) throws -> String {
        guard let quoted = shellKind.tryQuote(rawValue) else {
            throw NormalizeError()
        }
        return quoted
    }
}

public func strip_path_suffix(_ base: Path, _ suffix: Path) -> Path? {
    let baseStr = base.rawValue
    let suffixStr = suffix.rawValue

    if baseStr.hasSuffix(suffixStr) {
        let remainder = String(baseStr.dropLast(suffixStr.count))
        if remainder.isEmpty {
            return Path("")
        } else if remainder.hasSuffix("/") || remainder.hasSuffix("\\") {
            return Path(String(remainder.dropLast()))
        }
    }
    return nil
}

public func path_ends_with(_ base: Path, _ suffix: Path) -> Bool {
    strip_path_suffix(base, suffix) != nil
}

// MARK: - PathMatcher

public struct PathMatcher: Sendable, Equatable {
    private var sourcesList: [(String, RelPath, Bool)]
    private var regexes: [NSRegularExpression]
    public var pathStyle: PathStyle

    public init(globs: [String], pathStyle: PathStyle = .local()) throws {
        self.pathStyle = pathStyle
        self.sourcesList = []
        var compiled: [NSRegularExpression] = []

        for glob in globs {
            let trailing = glob.hasSuffix("/") || glob.hasSuffix("\\")
            let rel = try? RelPath.unix(glob)
            if let rel = rel {
                sourcesList.append((glob, rel, trailing))
            }

            // Convert glob pattern to regex pattern
            var pattern = "^"
            var i = glob.startIndex
            while i < glob.endIndex {
                let c = glob[i]
                if c == "*" {
                    let next = glob.index(after: i)
                    if next < glob.endIndex && glob[next] == "*" {
                        pattern += ".*"
                        i = glob.index(after: next)
                        continue
                    } else {
                        pattern += pathStyle.isPosix ? "[^/]*" : "[^/\\\\]*"
                    }
                } else if c == "?" {
                    pattern += pathStyle.isPosix ? "[^/]" : "[^/\\\\]"
                } else if [".", "+", "(", ")", "{", "}", "^", "$", "|", "\\"].contains(c) {
                    pattern += "\\" + String(c)
                } else {
                    pattern.append(c)
                }
                i = glob.index(after: i)
            }
            pattern += "$"
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                compiled.append(regex)
            }
        }
        self.regexes = compiled
    }

    public static func new(_ globs: [String], _ pathStyle: PathStyle) throws -> PathMatcher {
        try PathMatcher(globs: globs, pathStyle: pathStyle)
    }

    public func sources() -> [String] {
        sourcesList.map { $0.0 }
    }

    public func is_match(_ other: RelPath) -> Bool {
        for (_, source, _) in sourcesList {
            if other.startsWith(source) || other.endsWith(source) {
                return true
            }
        }
        let displayed = other.display(pathStyle)
        let ns = displayed as NSString
        let range = NSRange(location: 0, length: ns.length)
        for regex in regexes {
            if regex.firstMatch(in: displayed, options: [], range: range) != nil {
                return true
            }
        }
        let displayedWithSep = displayed + pathStyle.primarySeparator
        let nsSep = displayedWithSep as NSString
        let rangeSep = NSRange(location: 0, length: nsSep.length)
        for regex in regexes {
            if regex.firstMatch(in: displayedWithSep, options: [], range: rangeSep) != nil {
                return true
            }
        }
        return false
    }

    public func is_match_std_path(_ other: Path) -> Bool {
        if let rel = try? RelPath.unix(other.rawValue) {
            return is_match(rel)
        }
        return false
    }

    public static func == (lhs: PathMatcher, rhs: PathMatcher) -> Bool {
        lhs.sourcesList.map { $0.0 } == rhs.sourcesList.map { $0.0 }
    }
}
