// Ported from: crates/rune/src/runtime/layout_read.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Layout rectangle snapshots (`Cx.layout`, `Cx.windowLayout`, `Cx.caret`) and fixpoint comparison.

func approxRectEqual(_ a: [Float]?, _ b: [Float]?, eps: Float = 1e-3) -> Bool {
    switch (a, b) {
    case (nil, nil):
        return true
    case (let ra?, let rb?):
        guard ra.count == rb.count else { return false }
        for i in ra.indices {
            if abs(ra[i] - rb[i]) > eps {
                return false
            }
        }
        return true
    default:
        return false
    }
}

struct LayoutWithCheck {
    var key: String
    var windowSpace: Bool
    var lastRect: [Float]?
    var equals: ([Float]?, [Float]?) -> Bool
}

struct LayoutReadSnapshot: Sendable, Equatable {
    var layoutRects: [String: [Float]] = [:]
    var windowRects: [String: [Float]] = [:]
    var caret: (String, [Float])? = nil

    static func == (lhs: LayoutReadSnapshot, rhs: LayoutReadSnapshot) -> Bool {
        guard lhs.layoutRects.count == rhs.layoutRects.count,
              lhs.windowRects.count == rhs.windowRects.count
        else { return false }
        for (k, v) in lhs.layoutRects {
            if !approxRectEqual(v, rhs.layoutRects[k]) { return false }
        }
        for (k, v) in lhs.windowRects {
            if !approxRectEqual(v, rhs.windowRects[k]) { return false }
        }
        switch (lhs.caret, rhs.caret) {
        case (nil, nil):
            return true
        case (let lc?, let rc?):
            return lc.0 == rc.0 && approxRectEqual(lc.1, rc.1)
        default:
            return false
        }
    }

    func differs(for keys: Set<String>, caretRead: Bool, from previous: LayoutReadSnapshot) -> Bool {
        if caretRead {
            switch (caret, previous.caret) {
            case (nil, nil):
                break
            case (let lc?, let rc?):
                if lc.0 != rc.0 || !approxRectEqual(lc.1, rc.1) {
                    return true
                }
            default:
                return true
            }
        }
        for key in keys {
            if key.hasPrefix("@win:") {
                let raw = String(key.dropFirst(5))
                let cur = windowRects[raw] ?? layoutRects[raw]
                let prev = previous.windowRects[raw] ?? previous.layoutRects[raw]
                if !approxRectEqual(cur, prev) {
                    return true
                }
            } else if key.hasPrefix("@size:") {
                let raw = String(key.dropFirst(6))
                let curSize = layoutRects[raw].map { [$0[2], $0[3]] }
                let prevSize = previous.layoutRects[raw].map { [$0[2], $0[3]] }
                if !approxRectEqual(curSize, prevSize) {
                    return true
                }
            } else {
                if !approxRectEqual(layoutRects[key], previous.layoutRects[key]) {
                    return true
                }
            }
        }
        return false
    }

    func differsPredicates(_ predicates: [LayoutWithCheck]) -> Bool {
        for p in predicates {
            let cur = p.windowSpace ? (windowRects[p.key] ?? layoutRects[p.key]) : layoutRects[p.key]
            if !p.equals(p.lastRect, cur) {
                return true
            }
        }
        return false
    }
}

extension Runtime {
    public func layoutRect(_ key: String) -> [Float]? {
        ensureClean()
        return lastLayoutSnapshot.layoutRects[key]
    }

    public func windowLayoutRect(_ key: String) -> [Float]? {
        ensureClean()
        return lastLayoutSnapshot.windowRects[key] ?? lastLayoutSnapshot.layoutRects[key]
    }
}
