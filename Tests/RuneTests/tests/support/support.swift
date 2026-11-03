// Tests ported from: crates/rune/tests/support/mod.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Foundation
import Taffy
@testable import Rune

extension El {
    func absolute(_ x: Float, _ y: Float) -> El {
        pgAbsolute(x, y)
    }

    func pin(_ left: Float?, _ top: Float?, _ right: Float?, _ bottom: Float?) -> El {
        var copy = self
        copy.style.position = .absolute
        copy.style.inset = Taffy.Rect(
            left: left.map { .length($0) } ?? .auto(),
            right: right.map { .length($0) } ?? .auto(),
            top: top.map { .length($0) } ?? .auto(),
            bottom: bottom.map { .length($0) } ?? .auto()
        )
        return copy
    }

    func wFrac(_ f: Float) -> El {
        var copy = self
        copy.style.size.width = .percent(f)
        return copy
    }

    func hFrac(_ f: Float) -> El {
        var copy = self
        copy.style.size.height = .percent(f)
        return copy
    }

    func padding(_ p: Float) -> El { pad(p) }

    func px(_ p: Float) -> El {
        var copy = self
        copy.style.padding.left = .length(p)
        copy.style.padding.right = .length(p)
        return copy
    }

    func py(_ p: Float) -> El {
        var copy = self
        copy.style.padding.top = .length(p)
        copy.style.padding.bottom = .length(p)
        return copy
    }

    func pt(_ p: Float) -> El {
        var copy = self
        copy.style.padding.top = .length(p)
        return copy
    }

    func pb(_ p: Float) -> El {
        var copy = self
        copy.style.padding.bottom = .length(p)
        return copy
    }

    func pl(_ p: Float) -> El {
        var copy = self
        copy.style.padding.left = .length(p)
        return copy
    }

    func pr(_ p: Float) -> El {
        var copy = self
        copy.style.padding.right = .length(p)
        return copy
    }

    func margin(_ m: Float) -> El {
        var copy = self
        let lm = LengthPercentageAuto.length(m)
        copy.style.margin = Taffy.Rect(left: lm, right: lm, top: lm, bottom: lm)
        return copy
    }

    func mx(_ m: Float) -> El {
        var copy = self
        copy.style.margin.left = .length(m)
        copy.style.margin.right = .length(m)
        return copy
    }

    func my(_ m: Float) -> El {
        var copy = self
        copy.style.margin.top = .length(m)
        copy.style.margin.bottom = .length(m)
        return copy
    }

    func ml(_ m: Float) -> El {
        var copy = self
        copy.style.margin.left = .length(m)
        return copy
    }

    func mr(_ m: Float) -> El {
        var copy = self
        copy.style.margin.right = .length(m)
        return copy
    }

    func mt(_ m: Float) -> El {
        var copy = self
        copy.style.margin.top = .length(m)
        return copy
    }

    func mb(_ m: Float) -> El {
        var copy = self
        copy.style.margin.bottom = .length(m)
        return copy
    }

    func itemsStart() -> El {
        var copy = self
        copy.style.alignItems = .flexStart
        return copy
    }

    func itemsEnd() -> El {
        var copy = self
        copy.style.alignItems = .flexEnd
        return copy
    }

    func selfStart() -> El {
        var copy = self
        copy.style.alignSelf = .flexStart
        return copy
    }

    func selfCenter() -> El {
        var copy = self
        copy.style.alignSelf = .center
        return copy
    }

    func selfEnd() -> El {
        var copy = self
        copy.style.alignSelf = .flexEnd
        return copy
    }

    func selfStretch() -> El {
        var copy = self
        copy.style.alignSelf = .stretch
        return copy
    }

    func justifyStart() -> El {
        var copy = self
        copy.style.justifyContent = .flexStart
        return copy
    }

    func justifyEnd() -> El {
        var copy = self
        copy.style.justifyContent = .flexEnd
        return copy
    }

    func justifyAround() -> El {
        var copy = self
        copy.style.justifyContent = .spaceAround
        return copy
    }

    func justifyEvenly() -> El {
        var copy = self
        copy.style.justifyContent = .spaceEvenly
        return copy
    }

    func fill(_ c: Color) -> El { bg(c) }
    func radius(_ r: Float) -> El { rounded(r) }
    func centerY() -> El { itemsCenter() }
    func center() -> El { itemsCenter().justifyCenter() }

    func inert(_ on: Bool = true) -> El {
        var copy = self
        copy.inertFlag = on
        return copy
    }

    func onHoverChange<S>(_ f: @escaping (inout S, Bool, inout Tx) -> Void) -> El {
        var copy = self
        copy.onHoverHandler = { states, inside, tx in
            _ = states.withMutable { (state: inout S) in
                f(&state, inside, &tx)
            }
        }
        return copy
    }

    func onEdit<S>(_ keyPath: WritableKeyPath<S, TextEdit>) -> El {
        pgOnEdit(EditAccess(keyPath))
    }

    func onSubmit<S>(_ f: @escaping (inout S, inout Tx) -> Void) -> El {
        pgOnSubmit(f)
    }
}

extension Tx {
    mutating func scrollToBottomInstant(_ key: String) {
        scrollToBottom(key, animated: false)
    }

    mutating func scrollToInstant(_ key: String, _ x: Float, _ y: Float) {
        scrollOffsetRequests.append(ScrollRequest(key: key, x: x, y: y, animated: false, spring: nil))
    }
}

extension Runtime {
    func testCenter(_ key: String) -> (Float, Float)? {
        guard let e = hostElements().first(where: { $0.key == key && !$0.exiting })
            ?? hostFind(key)
        else {
            return nil
        }
        return (e.rect[0] + e.rect[2] * 0.5, e.rect[1] + e.rect[3] * 0.5)
    }
}

enum IntegrationSupport {
    static func runtime<S>(
        _ state: S,
        _ view: @escaping (S, Cx<S>) -> El,
        _ viewport: (Float, Float),
        _ env: Env = Env()
    ) -> Runtime<S> {
        let spec = AppSpec.new("test", viewport, { state }, view)
        return App.new(spec).headlessRuntime(viewport, env)
    }
    static func find<S>(_ rt: Runtime<S>, _ key: String) -> ElementInfo {
        guard let found = rt.hostElements().first(where: { $0.key == key && !$0.exiting })
            ?? rt.hostElements().first(where: { $0.key == key })
        else {
            preconditionFailure(key)
        }
        return found
    }

    static func centre(_ e: ElementInfo) -> (Float, Float) {
        (e.rect[0] + e.rect[2] / 2.0, e.rect[1] + e.rect[3] / 2.0)
    }

    static func tick<S>(_ rt: Runtime<S>) {
        _ = rt.hostFrame(1.0 / 60.0)
    }

    static func wait<S>(_ rt: Runtime<S>) {
        _ = rt.hostFrame(1.0)
    }

    static func click<S>(_ rt: Runtime<S>, _ pos: (Float, Float)) {
        _ = rt.hostPointerMove(pos.0, pos.1)
        _ = rt.hostPointerDown(pos.0, pos.1)
        _ = rt.hostPointerUp(pos.0, pos.1)
        tick(rt)
    }

    static func drag<S>(_ rt: Runtime<S>, _ p0: (Float, Float), _ p1: (Float, Float)) {
        _ = rt.hostPointerMove(p0.0, p0.1)
        _ = rt.hostPointerDown(p0.0, p0.1)
        tick(rt)
        for k in 1...6 {
            let f = Float(k) / 6.0
            _ = rt.hostPointerMove(p0.0 + (p1.0 - p0.0) * f, p0.1 + (p1.1 - p0.1) * f)
            tick(rt)
        }
        _ = rt.hostPointerUp(p1.0, p1.1)
        tick(rt)
    }

    static func command<S>(_ rt: Runtime<S>, _ c: Character) {
        _ = rt.hostKey(KeyEvent(key: .command(c), mods: Mods(cmd: true)))
        tick(rt)
    }

    static func glyphs<S>(_ rt: Runtime<S>, _ key: String) -> [(Float, Float)] {
        glyphsAt(rt, find(rt, key).path)
    }

    static func glyphsAt<S>(_ rt: Runtime<S>, _ path: String) -> [(Float, Float)] {
        guard let e = rt.hostElements().first(where: { $0.path == path }) else {
            preconditionFailure(path)
        }
        let (instances, _, _) = rt.hostFrame(0.0)
        let scale = max(rt.env.scale, 1e-4)
        var out: [(Float, Float)] = instances
            .filter { $0.params[1] == KIND_GLYPH }
            .map { (($0.rect[0] + $0.rect[2] / 2.0) / scale, ($0.rect[1] + $0.rect[3] / 2.0) / scale) }
            .filter { x, y in
                x >= e.rect[0] && x <= e.rect[0] + e.rect[2] && y >= e.rect[1] && y <= e.rect[1] + e.rect[3]
            }
        out.sort { $0.1 < $1.1 }
        var row = (0, -Float.infinity)
        var rows: [(Int, (Float, Float))] = []
        for g in out {
            if g.1 - row.1 > 6.0 {
                row = (row.0 + 1, g.1)
            }
            rows.append((row.0, g))
        }
        rows.sort { a, b in
            if a.0 != b.0 { return a.0 < b.0 }
            return a.1.0 < b.1.0
        }
        return rows.map(\.1)
    }
}
