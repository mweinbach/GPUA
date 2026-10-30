// Ported from: crates/util/src/path_list.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Foundation
import GPUICollections

/// A list of absolute paths, with an associated display order.
///
/// Two `PathList` values are considered equal if they contain the same paths,
/// regardless of the order in which those paths were originally provided.
///
/// The paths can be retrieved in the original order using `ordered_paths()`.
public struct PathList: DefaultInitializable, Equatable, Hashable, Sendable, Codable, CustomStringConvertible {
    /// The paths, in lexicographic order.
    private var _paths: [Path]
    /// The order in which the paths were provided.
    private var _order: [Int]

    public init() {
        self._paths = []
        self._order = []
    }

    public init<P: CustomStringConvertible>(_ paths: [P]) {
        var indexedPaths: [(Int, Path)] = paths.enumerated().map { (ix, p) in
            (ix, SanitizedPath.new(p.description).as_path())
        }
        indexedPaths.sort { $0.1 < $1.1 }
        self._order = indexedPaths.map { $0.0 }
        self._paths = indexedPaths.map { $0.1 }
    }

    public static func new<P: CustomStringConvertible>(_ paths: [P]) -> PathList {
        PathList(paths)
    }

    public var isEmpty: Bool {
        _paths.isEmpty
    }

    public func is_empty() -> Bool {
        isEmpty
    }

    /// Returns a new `PathList` with the given path removed.
    public func withoutPath(_ pathToRemove: Path) -> PathList {
        let remaining = orderedPaths().filter { $0 != pathToRemove }
        return PathList(remaining)
    }

    public func without_path(_ pathToRemove: Path) -> PathList {
        withoutPath(pathToRemove)
    }

    /// Get the paths in lexicographic order.
    public func paths() -> [Path] {
        _paths
    }

    /// Get the paths in lexicographic order.
    public func pathsOwned() -> [Path] {
        _paths
    }

    public func paths_owned() -> [Path] {
        _paths
    }

    /// Get the order in which the paths were provided.
    public func order() -> [Int] {
        _order
    }

    /// Get the paths in the original order.
    public func orderedPaths() -> [Path] {
        zip(_order, _paths)
            .sorted { $0.0 < $1.0 }
            .map { $0.1 }
    }

    public func ordered_paths() -> [Path] {
        orderedPaths()
    }

    public func isLexicographicallyOrdered() -> Bool {
        _order.enumerated().allSatisfy { (i, j) in i == j }
    }

    public func is_lexicographically_ordered() -> Bool {
        isLexicographicallyOrdered()
    }

    public static func deserialize(_ serialized: SerializedPathList) -> PathList {
        var paths: [Path] = serialized.paths.isEmpty
            ? []
            : serialized.paths.split(separator: "\n", omittingEmptySubsequences: false).map { Path(String($0)) }

        var order: [Int] = serialized.order
            .split(separator: ",", omittingEmptySubsequences: true)
            .compactMap { Int($0) }

        let isSorted = zip(paths, paths.dropFirst()).allSatisfy { $0 <= $1 }
        if !isSorted || order.count != paths.count {
            order = Array(0..<paths.count)
            paths.sort()
        }

        var list = PathList()
        list._paths = paths
        list._order = order
        return list
    }

    public func serialize() -> SerializedPathList {
        let pathsStr = _paths.map(\.rawValue).joined(separator: "\n")
        let orderStr = _order.map(String.init).joined(separator: ",")
        return SerializedPathList(paths: pathsStr, order: orderStr)
    }

    // Equatable & Hashable based on lexicographically sorted paths only.
    public static func == (lhs: PathList, rhs: PathList) -> Bool {
        lhs._paths == rhs._paths
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(_paths)
    }

    public var description: String {
        "PathList(paths: \(_paths), order: \(_order))"
    }
}

// MARK: - SerializedPathList

public struct SerializedPathList: CustomDebugStringConvertible, Sendable, Codable, Equatable, Hashable {
    public var paths: String
    public var order: String

    public init(paths: String, order: String) {
        self.paths = paths
        self.order = order
    }

    public var debugDescription: String {
        "SerializedPathList(paths: \(paths), order: \(order))"
    }
}

