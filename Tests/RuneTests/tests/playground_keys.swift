// Tests ported from: crates/rune/tests/playground_keys.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

private struct PgKeysReal {
    var scene: String = ""
    var palette: Bool = false
    var typed: String = ""
}

private func pgKeysRealView(_ s: PgKeysReal, _: Cx<PgKeysReal>) -> El {
    text("\(s.scene) \(s.palette) \(s.typed)").key("real")
}

private func pgKeysOnKey(_ s: inout PgKeysReal, _ ev: KeyEvent, _: inout Tx) -> Bool {
    switch ev.key {
    case .command("k") where ev.mods.cmd:
        s.palette.toggle()
        return true
    case .escape where s.palette:
        s.palette = false
        return true
    case .text(let t):
        s.typed.append(t)
        return true
    default:
        return false
    }
}

private func pgKeysScenes() -> [(String, (inout PgKeysReal) -> Void)] {
    [
        ("Launch", { s in s.scene = "launch" }),
        ("Palette/Search", { s in s.scene = "search" }),
    ]
}

private func pgKeysRuntime() -> Runtime<PgKeysReal> {
    var spec = AppSpec.new("keys", (900.0, 600.0), { PgKeysReal() }, pgKeysRealView)
    spec.scenes = pgKeysScenes()
    spec.onKey = pgKeysOnKey
    let rt = App.new(spec)
        .playground(Playground<PgKeysReal>.new())
        .headlessRuntime((900.0, 600.0), Env.new(false, 1.0))
    rt.openPlayground("Launch", nil)
    return rt
}

private func pgKeysPressWith(_ rt: Runtime<PgKeysReal>, _ key: Key, _ mods: Mods) {
    _ = rt.hostKey(KeyEvent(key: key, mods: mods))
    _ = rt.frame(1.0 / 60.0)
}

private func pgKeysPress(_ rt: Runtime<PgKeysReal>, _ key: Key) {
    pgKeysPressWith(rt, key, Mods())
}

private func pgKeysTyped(_ rt: Runtime<PgKeysReal>, _ s: String) {
    pgKeysPress(rt, .text(s))
}

private func pgKeysCommandK(_ rt: Runtime<PgKeysReal>) {
    pgKeysPressWith(rt, .command("k"), Mods(cmd: true))
}

private func pgKeysStage(_ rt: Runtime<PgKeysReal>) -> (String, Bool, String) {
    guard let s = rt.playgroundState(PgKeysReal.self) else {
        preconditionFailure("a scene on the stage")
    }
    return (s.scene, s.palette, s.typed)
}

private func pgKeysShown(_ rt: Runtime<PgKeysReal>, _ key: String) -> Bool {
    rt.hostElements().contains { $0.key == key && !$0.exiting }
}

private func pgKeysHint(_ rt: Runtime<PgKeysReal>) -> String {
    (rt.hostElements().first { $0.key == "playground-hint" }?.text ?? "")
        .replacingOccurrences(of: "\u{a0}", with: " ")
}

@Suite("PlaygroundKeysIntegrationTests")
struct PlaygroundKeysIntegrationTests {
    @Test func aStoryOpenedFromTheListHearsTheKeysTheListLeaves() {
        let rt = pgKeysRuntime()
        pgKeysPress(rt, .down)
        pgKeysPress(rt, .down)
        #expect(pgKeysStage(rt).0 == "search")
        #expect(pgKeysHint(rt).hasPrefix("↑↓ stories"))
        pgKeysCommandK(rt)
        #expect(pgKeysStage(rt).1)
        pgKeysTyped(rt, "3")
        #expect(pgKeysStage(rt).2 == "3")
        let realState = rt.state
        #expect(!realState.palette && realState.typed.isEmpty)
        pgKeysPress(rt, .escape)
        #expect(pgKeysStage(rt).1 == false)
        pgKeysTyped(rt, "k")
        let st1 = pgKeysStage(rt)
        #expect(st1.0 == "launch" && st1.1 == false && st1.2.isEmpty)
        pgKeysPress(rt, .down)
        pgKeysPress(rt, .down)
        pgKeysPress(rt, .up)
        pgKeysPress(rt, .up)
        let st2 = pgKeysStage(rt)
        #expect(st2.0 == "launch" && st2.1 == false && st2.2.isEmpty)
        pgKeysPress(rt, .tab)
        pgKeysCommandK(rt)
        #expect(pgKeysStage(rt).1)
        pgKeysPress(rt, .escape)
        #expect(pgKeysStage(rt).1 && pgKeysHint(rt).hasPrefix("↑↓ stories"))
        pgKeysPress(rt, .escape)
        #expect(!pgKeysStage(rt).1)
        pgKeysPress(rt, .escape)
        let closed = rt.playgroundState(PgKeysReal.self) == nil
        #expect(closed)
    }

    @Test func typingInTheFilterFilters() {
        let rt = pgKeysRuntime()
        pgKeysTyped(rt, "/")
        pgKeysTyped(rt, "sea")
        pgKeysTyped(rt, "2")
        #expect(!pgKeysShown(rt, "playground-item-0") && !pgKeysShown(rt, "playground-item-1"))
        let st = pgKeysStage(rt)
        #expect(st.0 == "launch" && st.1 == false && st.2.isEmpty)
        pgKeysPress(rt, .backspace)
        #expect(pgKeysShown(rt, "playground-item-1") && !pgKeysShown(rt, "playground-item-0"))
        pgKeysCommandK(rt)
        #expect(pgKeysStage(rt).1)
        pgKeysPress(rt, .enter)
        #expect(pgKeysStage(rt).0 == "search")
    }
}
