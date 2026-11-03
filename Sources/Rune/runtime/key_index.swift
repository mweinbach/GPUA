// Ported from: crates/rune/src/runtime/key_index.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Fast lookup from element key or path segment to committed node index.

struct KeyIndex: Sendable {
    private var byKey: [String: [Int]] = [:]
    private var byPath: [String: Int] = [:]

    init() {}

    mutating func clear() {
        byKey.removeAll(keepingCapacity: true)
        byPath.removeAll(keepingCapacity: true)
    }

    mutating func rebuild(_ nodes: [Node]) {
        clear()
        for i in nodes.indices {
            byPath[nodes[i].path] = i
            if let key = nodes[i].key {
                byKey[key, default: []].append(i)
            }
        }
    }

    func nodeByPath(_ path: String) -> Int? {
        byPath[path]
    }

    func firstByKey(_ key: String) -> Int? {
        if let idx = byPath[key] {
            return idx
        }
        return byKey[key]?.first
    }

    func allByKey(_ key: String) -> [Int] {
        byKey[key] ?? []
    }

    func findMatching(_ needle: String, in nodes: [Node]) -> Int? {
        if let exact = byPath[needle] {
            return exact
        }
        if let keyed = byKey[needle]?.first {
            return keyed
        }
        for i in nodes.indices {
            if selectsKeyPath(needle, nodes[i].path, nodes[i].key) {
                return i
            }
        }
        return nil
    }
}
