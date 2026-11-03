// Ported from: crates/rune-fx/src/binds.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import CWebGPU

//! Bind groups kept across frames, keyed on the resources they bind.

/// This frame's bind groups, indexed by `Prepared.bind`, plus last frame's for reuse.
/// A frame keeps at most its own groups and the previous frame's, so the set stays bounded.
// PORT NOTE: `WGPUBindGroup` is an opaque C pointer managed on the renderer's thread (`FxRenderer`).
struct BindSet<K>: @unchecked Sendable {
    private var now: [(K, WGPUBindGroup)] = []
    private var last: [(K, WGPUBindGroup)] = []

    init() {}

    /// Start a frame: last frame's groups become reusable, the older ones are dropped.
    mutating func begin(release: (WGPUBindGroup) -> Void = { _ in }) {
        for (_, bg) in last {
            release(bg)
        }
        last.removeAll(keepingCapacity: true)
        swap(&now, &last)
    }

    /// The index of a group whose key passes `isMatch`, reusing this or last frame's before calling `make`.
    mutating func find(
        _ isMatch: (K) -> Bool,
        _ make: () -> (K, WGPUBindGroup)
    ) -> Int {
        if let idx = now.firstIndex(where: { isMatch($0.0) }) {
            return idx
        }
        let entry: (K, WGPUBindGroup)
        if let idx = last.firstIndex(where: { isMatch($0.0) }) {
            let lastIndex = last.count - 1
            if idx != lastIndex {
                last.swapAt(idx, lastIndex)
            }
            entry = last.removeLast()
        } else {
            entry = make()
        }
        now.append(entry)
        return now.count - 1
    }

    func get(_ i: Int) -> WGPUBindGroup {
        now[i].1
    }

    mutating func releaseAll(_ release: (WGPUBindGroup) -> Void) {
        for (_, bg) in now { release(bg) }
        for (_, bg) in last { release(bg) }
        now.removeAll()
        last.removeAll()
    }
}
