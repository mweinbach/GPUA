// Ported from: crates/rune-kit/src/budget.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! A cache bounded by bytes, not entries. What the last two commits used always stays, so a
//! screen showing many documents never thrashes; past the budget the least recently used of the
//! rest go first.

import Rune

struct Budget<K: Hashable, V> {
    struct Slot {
        var value: V
        var bytes: Int
        /// When it was last used, in lookups.
        var used: UInt64
        /// The `Rune.commitGeneration()` it was last used in.
        var commit: UInt64
    }

    var map: [K: Slot] = [:]
    var bytesCount: Int = 0
    let limit: Int
    var clock: UInt64 = 0

    init(_ limit: Int) {
        self.limit = limit
    }

    static func new(_ limit: Int) -> Budget<K, V> {
        Budget(limit)
    }

    mutating func get(_ key: K) -> V? {
        guard var slot = map[key] else { return nil }
        clock += 1
        slot.used = clock
        slot.commit = commitGeneration()
        map[key] = slot
        return slot.value
    }

    /// Looks `key` up without counting it as used.
    func peek(_ key: K) -> V? {
        map[key]?.value
    }

    /// Drops `key`, returning whether it was there.
    @discardableResult
    mutating func remove(_ key: K) -> Bool {
        guard let slot = map.removeValue(forKey: key) else { return false }
        bytesCount -= slot.bytes
        return true
    }

    /// Whether `key` was used in the commit running now (never outside one).
    func usedNow(_ key: K) -> Bool {
        let now = commitGeneration()
        guard now > 0, let slot = map[key] else { return false }
        return slot.commit == now
    }

    /// Estimated bytes held.
    func bytes() -> Int {
        bytesCount
    }

    mutating func insert(_ key: K, _ value: V, _ bytes: Int) {
        clock += 1
        let slot = Slot(value: value, bytes: bytes, used: clock, commit: commitGeneration())
        if let old = map.updateValue(slot, forKey: key) {
            bytesCount -= old.bytes
        }
        bytesCount += bytes
        if bytesCount > limit {
            evict()
        }
    }

    /// Drops the least recently used entries the last two commits didn't use, down to three
    /// quarters of the budget so the next few inserts don't evict again.
    private mutating func evict() {
        let now = commitGeneration()
        // Outside any commit (a test, a tool) nothing counts as on screen.
        func kept(_ s: Slot) -> Bool {
            now > 0 && s.commit + 1 >= now
        }
        var old: [(UInt64, Int)] = []
        old.reserveCapacity(map.count)
        for s in map.values where !kept(s) {
            old.append((s.used, s.bytes))
        }
        old.sort { $0.0 < $1.0 }
        let target = (limit / 4) * 3
        var currentBytes = bytesCount
        // Every lookup gets its own stamp, so evicting up to a stamp evicts exactly these.
        var last: UInt64? = nil
        for (used, b) in old {
            if currentBytes <= target {
                break
            }
            currentBytes -= b
            last = used
        }
        guard let cutoff = last else { return }
        map = map.filter { _, s in kept(s) || s.used > cutoff }
        bytesCount = currentBytes
    }
}
