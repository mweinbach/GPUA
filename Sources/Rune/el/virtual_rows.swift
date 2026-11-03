// Ported from: crates/rune/src/el/virtual_rows.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Index-built virtual rows: ``El/virtualRows(_:_:_:_:)`` gives a virtual
//! list a row count, a key per index and a builder per index.

typealias VirtualRowKeyFn = (StatesRef, Int) -> String
typealias VirtualRowBuildFn = (StatesRef, Int) -> El

/// The rows of an index-built list, built at layout time from the window's state.
final class RowSource {
    let count: Int
    let key: VirtualRowKeyFn
    let build: VirtualRowBuildFn

    init<S>(
        count: Int,
        key: @escaping (S, Int) -> String,
        build: @escaping (S, Int) -> El
    ) {
        self.count = count
        self.key = { statesRef, i in
            guard let state = statesRef.cast(S.self) else {
                preconditionFailure("virtual rows registered for a different state type than the window's")
            }
            return key(state, i)
        }
        self.build = { statesRef, i in
            guard let state = statesRef.cast(S.self) else {
                preconditionFailure("virtual rows registered for a different state type than the window's")
            }
            return build(state, i)
        }
    }
}

extension El {
    /// Window keyed rows of a growth stack directly inside a vertical scroll viewport.
    /// Unvisited rows use an estimated height; measurement preserves the visible anchor.
    public func virtualize(
        _ estimatedRowHeight: Float,
        file: StaticString = #fileID,
        line: UInt = #line
    ) -> El {
        var copy = self
        copy.virtualEstimate = max(estimatedRowHeight, 1.0)
        copy.hasVirtual = true
        #if DEBUG
        copy.virtualSourceString = "\(file):\(line)"
        #endif
        return copy
    }

    /// ``virtualize(_:file:line:)`` with rows built by index: `count` rows, row `i` keyed `key(s, i)` and
    /// built by `build(s, i)`.
    public func virtualRows<S>(
        _ count: Int,
        _ estimatedRowHeight: Float,
        _ key: @escaping (S, Int) -> String,
        _ build: @escaping (S, Int) -> El,
        file: StaticString = #fileID,
        line: UInt = #line
    ) -> El {
        var copy = self
        copy.virtualRowsSource = RowSource(count: count, key: key, build: build)
        return copy.virtualize(estimatedRowHeight, file: file, line: line)
    }

    /// Tells ``virtualRows(_:_:_:_:file:line:)`` its keys are those of the last commit that gave the same
    /// `version`, so layout skips calling `key` for every row to find out.
    public func virtualRowsVersion<V: Hashable>(_ version: V) -> El {
        var copy = self
        var hasher = Hasher()
        version.hash(into: &hasher)
        copy.virtualRowsVersionHash = UInt64(bitPattern: Int64(hasher.finalize()))
        return copy
    }

    /// On a virtual list (``virtualize(_:file:line:)`` or ``virtualRows(_:_:_:_:file:line:)``), called with the index
    /// range `start..<end` of rows currently visible in its scroll viewport.
    public func onVisibleRows<S>(
        _ f: @escaping (inout S, Range<Int>) -> Bool,
        file: StaticString = #fileID,
        line: UInt = #line
    ) -> El {
        var copy = self
        copy.handlers.modify { h in
            h.onVisibleRows = { states, r in
                states.withMutable { (state: inout S) in
                    f(&state, r)
                } ?? false
            }
            #if DEBUG
            h.sites.visibleRows = "\(file):\(line)"
            #endif
        }
        return copy
    }
}
