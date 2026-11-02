// Ported from: crates/rune/src/memo.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! `memo`: reuse a subtree whose inputs haven't changed instead of building it again.

import Foundation

final class MemoShared {
    var children: [El]
    var focusedInput: Bool
    var duplicateKeys: Bool
    var hasVirtual: Bool
    var reusable: Bool

    init(
        children: [El],
        focusedInput: Bool = false,
        duplicateKeys: Bool = false,
        hasVirtual: Bool = false,
        reusable: Bool = true
    ) {
        self.children = children
        self.focusedInput = focusedInput
        self.duplicateKeys = duplicateKeys
        self.hasVirtual = hasVirtual
        self.reusable = reusable
    }
}

private let memoBuiltIdLock = LiveLock()
// PORT NOTE: Guarded by `memoBuiltIdLock` for unique monotonic `MemoBuilt` ids.
nonisolated(unsafe) private var nextMemoBuiltId: UInt64 = 1

final class MemoBuilt {
    let id: UInt64
    let reusable: Bool
    let root: El
    let shared: MemoShared

    init(reusable: Bool, root: El, shared: MemoShared) {
        self.id = memoBuiltIdLock.withLock {
            let v = nextMemoBuiltId
            nextMemoBuiltId &+= 1
            return v
        }
        self.reusable = reusable
        self.root = root
        self.shared = shared
    }

    func placeholder(_ key: String) -> El {
        var el = root
        el.key = key
        el.hasVirtual = el.hasVirtual || shared.hasVirtual
        el.memoChildren = shared
        el.memoBuilt = self
        return el
    }
}

enum MemoRead {
    case caret(String, [Float]?)
    case layout(String, [Float]?)
    case layoutWith(String, ([Float]?, [Float]?) -> Bool, [Float]?)
    case selection([[Float]])
}

private struct MemoEntry {
    var version: Int
    var built: MemoBuilt
    var reads: [MemoRead]
    var nested: [String]
    var pass: UInt64
}

final class MemoCache {
    fileprivate var entries: [String: MemoEntry] = [:]
    var pass: UInt64 = 0
    var builds: Int = 0
    var layoutRects: [String: [Float]] = [:]
    var windowRects: [String: [Float]] = [:]
    var caretRect: (String, [Float])? = nil
    var selectionRects: [[Float]] = []

    init() {}

    func clear() {
        entries.removeAll()
    }

    func nextPass() -> UInt64 {
        pass &+ 1
    }

    func keepSince(_ since: UInt64) {
        guard pass >= since else { return }
        entries = entries.filter { $0.value.pass >= since }
    }
}

private final class MemoScope {
    var cache: MemoCache
    var envHash: Int
    var scale: Float
    var path: [String] = []
    var nested: [[String]] = []
    var reads: [[MemoRead]] = []
    var recordedLayoutKeys: Set<String> = []
    var recordedCaret: Bool = false

    init(cache: MemoCache, envHash: Int, scale: Float) {
        self.cache = cache
        self.envHash = envHash
        self.scale = scale
    }

    func holds(_ read: MemoRead) -> Bool {
        switch read {
        case .caret(let key, let prev):
            let cur = (cache.caretRect?.0 == key) ? cache.caretRect?.1 : nil
            return cur == prev
        case .layout(let key, let prev):
            let cur = lookupRect(key)
            return cur == prev
        case .layoutWith(let key, let eq, let prev):
            let cur = lookupRect(key)
            return eq(prev, cur)
        case .selection(let prev):
            return cache.selectionRects == prev
        }
    }

    func lookupRect(_ key: String) -> [Float]? {
        if key.hasPrefix("@win:") {
            let sub = String(key.dropFirst(5))
            return cache.windowRects[sub] ?? cache.layoutRects[sub]
        }
        return cache.layoutRects[key]
    }
}

#if os(WASI)
// PORT NOTE: WASI (`wasm32-unknown-wasip1`) is single-threaded; `memoScopesWasi` is accessed on the sole execution thread.
nonisolated(unsafe) private var memoScopesWasi: [MemoScope] = []
#endif
private let memoScopesKey = "gpua.rune.memo.scopes"

private func withMemoScopes<R>(_ body: (inout [MemoScope]) -> R) -> R {
    #if os(WASI)
    return body(&memoScopesWasi)
    #else
    let dict = Thread.current.threadDictionary
    var scopes = (dict[memoScopesKey] as? [MemoScope]) ?? []
    let result = body(&scopes)
    dict[memoScopesKey] = scopes
    return result
    #endif
}

func enterMemoScope(
    _ cache: MemoCache,
    env: Env,
    reducedMotion: Bool,
    srgbBlend: Bool
) -> () -> (Set<String>, Bool) {
    cache.pass &+= 1
    var hasher = Hasher()
    hasher.combine(env.systemDark)
    hasher.combine(env.scale.bitPattern)
    hasher.combine(reducedMotion)
    hasher.combine(srgbBlend)
    let scope = MemoScope(cache: cache, envHash: hasher.finalize(), scale: env.scale)
    withMemoScopes { $0.append(scope) }
    var finished = false
    return {
        guard !finished else { return ([], false) }
        finished = true
        return withMemoScopes { scopes in
            guard let popped = scopes.popLast() else { return ([], false) }
            return (popped.recordedLayoutKeys, popped.recordedCaret)
        }
    }
}

func recordMemoLayoutRead(_ key: String, _ rect: [Float]?) {
    withMemoScopes { scopes in
        guard let s = scopes.last else { return }
        s.recordedLayoutKeys.insert(key)
        if !s.reads.isEmpty {
            s.reads[s.reads.count - 1].append(.layout(key, rect))
        }
    }
}

func recordMemoCaretRead(_ key: String, _ rect: [Float]?) {
    withMemoScopes { scopes in
        guard let s = scopes.last else { return }
        s.recordedCaret = true
        if !s.reads.isEmpty {
            s.reads[s.reads.count - 1].append(.caret(key, rect))
        }
    }
}

private enum MemoDecision {
    case plain
    case reuse(MemoBuilt)
    case build(name: String, combinedVersion: Int, store: Bool)
}

/// The subtree `build` returns, keyed `id`, built again only when `version` (or the window's
/// environment) differs from the last build's.
public func memo<V: Hashable>(_ id: String, _ version: V, _ build: () -> El) -> El {
    var vHasher = Hasher()
    version.hash(into: &vHasher)
    let rawVersion = vHasher.finalize()

    let decision: MemoDecision = withMemoScopes { scopes in
        guard let s = scopes.last else { return .plain }
        var combined = Hasher()
        combined.combine(rawVersion)
        combined.combine(s.envHash)
        let versionKey = combined.finalize()
        let name = s.path.last.map { "\($0)/\(id)" } ?? id
        let pass = s.cache.pass
        var store = true
        if var existing = s.cache.entries[name] {
            if existing.pass == pass {
                store = false
            } else if existing.version == versionKey && existing.reads.allSatisfy({ s.holds($0) }) {
                existing.pass = pass
                s.cache.entries[name] = existing
                for r in existing.reads {
                    switch r {
                    case .caret: s.recordedCaret = true
                    case .layout(let k, _), .layoutWith(let k, _, _): s.recordedLayoutKeys.insert(k)
                    case .selection: s.recordedLayoutKeys.insert("@selection")
                    }
                }
                if !s.reads.isEmpty && !existing.reads.isEmpty {
                    s.reads[s.reads.count - 1].append(contentsOf: existing.reads)
                }
                if !existing.nested.isEmpty {
                    var queue = existing.nested
                    while let nid = queue.popLast() {
                        if var ne = s.cache.entries[nid], ne.pass != pass {
                            ne.pass = pass
                            s.cache.entries[nid] = ne
                            queue.append(contentsOf: ne.nested)
                        }
                    }
                }
                if !s.nested.isEmpty {
                    s.nested[s.nested.count - 1].append(name)
                }
                return .reuse(existing.built)
            }
        }
        if !s.nested.isEmpty {
            s.nested[s.nested.count - 1].append(name)
        }
        s.path.append(name)
        s.nested.append([])
        s.reads.append([])
        return .build(name: name, combinedVersion: versionKey, store: store)
    }

    switch decision {
    case .plain:
        return build().key(id)
    case .reuse(let built):
        return built.placeholder(id)
    case .build(let name, let combinedVersion, let store):
        var builtEl = build().key(id)
        return withMemoScopes { scopes in
            guard let s = scopes.last else { return builtEl }
            _ = s.path.popLast()
            let nested = s.nested.popLast() ?? []
            let reads = s.reads.popLast() ?? []
            if !s.reads.isEmpty && !reads.isEmpty {
                s.reads[s.reads.count - 1].append(contentsOf: reads)
            }
            s.cache.builds += 1
            guard store else { return builtEl }
            let keyName = builtEl.key ?? id
            builtEl.key = nil
            builtEl.expandMemo()
            let kids = builtEl.children
            builtEl.children = []
            let hasFocused = kids.contains(where: { elHasFocusedInput($0) })
            let hasVirt = kids.contains(where: { $0.hasVirtual })
            let shared = MemoShared(
                children: kids,
                focusedInput: hasFocused,
                duplicateKeys: false,
                hasVirtual: hasVirt,
                reusable: !hasVirt
            )
            let built = MemoBuilt(reusable: !hasVirt, root: builtEl, shared: shared)
            s.cache.entries[name] = MemoEntry(
                version: combinedVersion,
                built: built,
                reads: reads,
                nested: nested,
                pass: s.cache.pass
            )
            return built.placeholder(keyName)
        }
    }
}

func elHasFocusedInput(_ el: El) -> Bool {
    if let input = el.input, input.edit.focused {
        return true
    }
    if let shared = el.memoChildren, shared.focusedInput {
        return true
    }
    return el.children.contains(where: { elHasFocusedInput($0) })
}

/// Namespace mirroring `rune::memo::*` layout read helpers.
public enum memoNamespace {
    public static func layout(_ key: String) -> [Float]? {
        withMemoScopes { scopes in
            guard let s = scopes.last else { return nil }
            let rect = s.lookupRect(key)
            s.recordedLayoutKeys.insert(key)
            if !s.reads.isEmpty {
                s.reads[s.reads.count - 1].append(.layout(key, rect))
            }
            return rect
        }
    }

    public static func layoutWith<T: Equatable>(_ key: String, _ f: @escaping ([Float]) -> T) -> T? {
        withMemoScopes { scopes in
            guard let s = scopes.last else { return nil }
            let rect = s.lookupRect(key)
            s.recordedLayoutKeys.insert(key)
            if !s.reads.isEmpty {
                let eq: ([Float]?, [Float]?) -> Bool = { a, b in
                    a.map(f) == b.map(f)
                }
                s.reads[s.reads.count - 1].append(.layoutWith(key, eq, rect))
            }
            return rect.map(f)
        }
    }

    public static func layoutSize(_ key: String) -> [Float]? {
        layoutWith(key) { [$0[2] - $0[0], $0[3] - $0[1]] }
    }

    public static func windowLayout(_ key: String) -> [Float]? {
        layout("@win:\(key)")
    }

    public static func windowLayoutWith<T: Equatable>(_ key: String, _ f: @escaping ([Float]) -> T) -> T? {
        layoutWith("@win:\(key)", f)
    }
}
