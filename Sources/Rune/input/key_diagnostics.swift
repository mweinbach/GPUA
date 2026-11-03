// Ported from: crates/rune/src/input/key_diagnostics.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

#if !os(WASI)
import Foundation
#endif

/// A sibling key used twice under one parent.
internal struct DuplicateSiblingKey: Sendable, Equatable {
    internal var key: String
    internal var message: String
}

/// Deterministic 64-bit FNV-1a hash for fast allocation-light sibling uniqueness checks.
@inline(__always)
private func siblingKeyHash(_ key: String) -> UInt64 {
    var h: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in key.utf8 {
        h ^= UInt64(byte)
        h &*= 0x0000_0100_0000_01b3
    }
    return h
}

/// Whether no two of these siblings share a key.
private func uniqueSiblingKeys(_ shared: [El], _ own: [El], _ hashes: inout [UInt64]) -> Bool {
    var keys: [String] = []
    for c in shared {
        if let k = c.key { keys.append(k) }
    }
    for c in own {
        if let k = c.key { keys.append(k) }
    }
    let n = keys.count
    if n < 2 { return true }
    if n <= 8 {
        for i in 0..<(n - 1) {
            for j in (i + 1)..<n {
                if keys[i] == keys[j] { return false }
            }
        }
        return true
    }
    hashes.removeAll(keepingCapacity: true)
    hashes.reserveCapacity(n)
    for k in keys {
        hashes.append(siblingKeyHash(k))
    }
    hashes.sort()
    for i in 0..<(hashes.count - 1) {
        if hashes[i] == hashes[i + 1] { return false }
    }
    return true
}

/// The sibling sets under `el` that need checking: a memo's shared children were checked when
/// it built, and a virtual list's rows are checked as it windows them.
private func checksSiblings(_ el: El) -> Bool {
    el.virtualEstimate == nil && !(el.memoChildren != nil && el.children.isEmpty)
}

private func sharedChildren(_ el: El) -> [El] {
    el.memoChildren?.children ?? []
}

private func cleanWith(_ el: El, _ hashes: inout [UInt64]) -> Bool {
    if el.memoChildren?.duplicateKeys == true {
        return false
    }
    if checksSiblings(el) && !uniqueSiblingKeys(sharedChildren(el), el.children, &hashes) {
        return false
    }
    for child in el.children {
        if !cleanWith(child, &hashes) {
            return false
        }
    }
    return true
}

/// Whether no parent in `root` has two children with one key: skips clean memo subtrees.
internal func siblingKeysClean(_ root: El) -> Bool {
    var hashes: [UInt64] = []
    return cleanWith(root, &hashes)
}

/// Whether a memo's children, as built, hold duplicate keys anywhere below the memo's root.
internal func memoChildrenHaveDuplicates(_ root: El, _ children: [El]) -> Bool {
    var hashes: [UInt64] = []
    if root.virtualEstimate == nil && !uniqueSiblingKeys(children, [], &hashes) {
        return true
    }
    for child in children {
        if !cleanWith(child, &hashes) {
            return true
        }
    }
    return false
}

private func rootPath(_ root: El) -> String {
    root.key ?? "#0"
}

/// Finds all duplicate sibling keys under `root`, building diagnostic messages naming both call sites.
internal func findDuplicateSiblingKeys(_ root: El, path: String) -> [DuplicateSiblingKey] {
    func walk(_ el: El, _ currentPath: String, _ hashes: inout [UInt64], _ out: inout [DuplicateSiblingKey]) {
        let sharedDup = (el.memoChildren?.duplicateKeys == true)
        let combined = el.allChildren()
        if checksSiblings(el) || (sharedDup && el.virtualEstimate == nil) {
            var seen: [String: El] = [:]
            for child in combined {
                guard let k = child.key else { continue }
                if let first = seen[k] {
                    out.append(DuplicateSiblingKey(
                        key: k,
                        message: "duplicate sibling key \"\(k)\" under \"\(currentPath)\": first at \(first.keyLocation()), again at \(child.keyLocation()); give siblings unique keys"
                    ))
                } else {
                    seen[k] = child
                }
            }
        }
        for (index, child) in combined.enumerated() {
            if cleanWith(child, &hashes) { continue }
            let segment = child.key ?? "#\(index)"
            walk(child, "\(currentPath)/\(segment)", &hashes, &out)
        }
    }

    var out: [DuplicateSiblingKey] = []
    var hashes: [UInt64] = []
    walk(root, path, &hashes, &out)
    return out
}

internal func siblingKeyWarnings(_ root: El) -> [String] {
    findDuplicateSiblingKeys(root, path: rootPath(root)).map(\.message)
}

/// Renames each later copy of a key `key#dup1`, `key#dup2`, ... in order, skipping names
/// already taken, so the first keeps its key. Returns each renamed index with its old key.
@discardableResult
internal func renameDuplicateKeys(_ keys: inout [String]) -> [(Int, String)] {
    var taken = Set(keys)
    var kept = Set<String>()
    var renamed: [(Int, String)] = []
    for i in 0..<keys.count {
        let k = keys[i]
        if kept.insert(k).inserted {
            continue
        }
        var n = 1
        while true {
            let candidate = "\(k)#dup\(n)"
            if !taken.contains(candidate) {
                taken.insert(candidate)
                kept.insert(candidate)
                let old = keys[i]
                keys[i] = candidate
                renamed.append((i, old))
                break
            }
            n += 1
        }
    }
    return renamed
}

/// Renames duplicate keys in-place on `children` (`El.key`), skipping unkeyed children.
private func renameDuplicateChildKeys(_ children: inout [El]) {
    var keyedIndices: [Int] = []
    var keyedNames: [String] = []
    for (idx, child) in children.enumerated() {
        if let k = child.key {
            keyedIndices.append(idx)
            keyedNames.append(k)
        }
    }
    guard keyedNames.count >= 2 else { return }
    let changes = renameDuplicateKeys(&keyedNames)
    guard !changes.isEmpty else { return }
    for (pos, _) in changes {
        let childIdx = keyedIndices[pos]
        children[childIdx].key = keyedNames[pos]
    }
}

/// Makes sibling keys unique so the layout tree never sees two siblings share a node.
@discardableResult
internal func repairDuplicateSiblingKeys(_ root: inout El) -> [DuplicateSiblingKey] {
    if siblingKeysClean(root) { return [] }
    let path = rootPath(root)
    return repairDuplicateSiblingKeysAt(&root, path: path)
}

/// ``repairDuplicateSiblingKeys(_:)`` for a subtree whose root sits at `path`.
@discardableResult
internal func repairDuplicateSiblingKeysAt(_ root: inout El, path: String) -> [DuplicateSiblingKey] {
    if siblingKeysClean(root) { return [] }
    let found = findDuplicateSiblingKeys(root, path: path)
    if found.isEmpty { return found }

    func walk(_ el: inout El, _ hashes: inout [UInt64]) {
        let sharedDup = (el.memoChildren?.duplicateKeys == true)
        let siblingsDup = checksSiblings(el) && !uniqueSiblingKeys(sharedChildren(el), el.children, &hashes)
        if sharedDup || siblingsDup {
            el.expandMemo()
        }
        if siblingsDup || (sharedDup && el.virtualEstimate == nil) {
            renameDuplicateChildKeys(&el.children)
        }
        for i in 0..<el.children.count {
            if !cleanWith(el.children[i], &hashes) {
                walk(&el.children[i], &hashes)
            }
        }
    }

    var hashes: [UInt64] = []
    walk(&root, &hashes)
    return found
}

private let warnedDuplicateKeysLock = LiveLock()
// PORT NOTE: Guarded by `warnedDuplicateKeysLock` so each duplicate key logs once per process.
nonisolated(unsafe) private var warnedDuplicateKeys = Set<String>()

/// Prints each duplicate once per key for the life of the process.
internal func warnDuplicateSiblingKeysOnce(_ found: [DuplicateSiblingKey]) {
    guard !found.isEmpty else { return }
    warnedDuplicateKeysLock.withLock {
        for d in found {
            if warnedDuplicateKeys.insert(d.key).inserted {
                #if !os(WASI)
                let msg = "rune: \(d.message); the later one is renamed \"\(d.key)#dupN\"\n"
                FileHandle.standardError.write(Data(msg.utf8))
                #endif
            }
        }
    }
}
