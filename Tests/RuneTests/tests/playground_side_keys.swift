// Tests ported from: crates/rune/tests/playground_side_keys.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

private struct PgSideKeysReal {
    var level: Int32 = 0
}

private func pgSideKeysRealView(_ s: PgSideKeysReal, _: Cx<PgSideKeysReal>) -> El {
    text("level \(s.level)").key("level")
}

private func pgSideKeysScenes() -> [(String, (inout PgSideKeysReal) -> Void)] {
    [
        ("Meter/High", { s in s.level = 50 }),
    ]
}

private struct PgSideKeysDial {
    var value: Int32 = 0
    var failed: Bool = false
}

private func pgSideKeysDialView(_ d: PgSideKeysDial, _: Cx<PgSideKeysDial>) -> El {
    text("dial \(d.value)").key("dial")
}

private func pgSideKeysDialKey(_ d: inout PgSideKeysDial, _ ev: KeyEvent, _: inout Tx) -> Bool {
    switch ev.key {
    case .up:
        d.value += 1
        return true
    case .down:
        d.value -= 1
        return true
    default:
        return false
    }
}

private func pgSideKeysRuntime() -> Runtime<PgSideKeysReal> {
    let pg = Playground<PgSideKeysReal>.new()
        .story(
            Story.new("Dials/Dial", { PgSideKeysDial() }, pgSideKeysDialView)
                .sideKeys(
                    { d, active, _ in text("\(active ? "active" : "idle") \(d.value)").key("dial-side") },
                    pgSideKeysDialKey
                )
                .trigger("f", "Fail") { d, _ in d.failed = true }
        )
        .story(
            Story.new("Dials/Plain", { PgSideKeysDial() }, pgSideKeysDialView)
                .side { d, _ in text("plain \(d.value)").key("plain-side") }
        )
        .sideKeys(
            "Meter/High",
            { s, active, _ in text("\(active ? "active" : "idle") \(s.level)").key("meter-side") },
            { s, ev, _ in
                if ev.key == .up {
                    s.level += 5
                    return true
                }
                return false
            }
        )
    var spec = AppSpec.new("dials", (800.0, 500.0), { PgSideKeysReal() }, pgSideKeysRealView)
    spec.scenes = pgSideKeysScenes()
    return App.new(spec).playground(pg).headlessRuntime((800.0, 500.0), Env.new(false, 1.0))
}

private func pgSideKeysPress(_ rt: Runtime<PgSideKeysReal>, _ key: Key) {
    _ = rt.hostKey(KeyEvent(key: key, mods: Mods()))
    _ = rt.frame(1.0 / 60.0)
}

private func pgSideKeysSays(_ rt: Runtime<PgSideKeysReal>, _ key: String) -> String {
    rt.hostElements().first { $0.key == key }?.text ?? ""
}

private func pgSideKeysDialState(_ rt: Runtime<PgSideKeysReal>) -> (Int32, Bool) {
    guard let d = rt.playgroundState(PgSideKeysDial.self) else {
        preconditionFailure("a dial story's state")
    }
    return (d.value, d.failed)
}

@Suite("PlaygroundSideKeysIntegrationTests")
struct PlaygroundSideKeysIntegrationTests {
    @Test func theSideViewKnowsWhenTheKeyboardIsOnIt() {
        let rt = pgSideKeysRuntime()
        rt.openPlayground("Dials/Dial", nil)
        #expect(pgSideKeysSays(rt, "dial-side") == "idle 0")
        pgSideKeysPress(rt, .right)
        #expect(pgSideKeysSays(rt, "dial-side") == "active 0")
        pgSideKeysPress(rt, .escape)
        #expect(pgSideKeysSays(rt, "dial-side") == "idle 0")
        let stillOpen = rt.playgroundState(PgSideKeysDial.self) != nil
        #expect(stillOpen)
        pgSideKeysPress(rt, .tab)
        #expect(pgSideKeysSays(rt, "dial-side") == "active 0")
        pgSideKeysPress(rt, .tab)
        #expect(pgSideKeysSays(rt, "dial-side") == "idle 0")
    }

    @Test func itsHookGetsKeysFirstAndLeftNoLongerLeaves() {
        let rt = pgSideKeysRuntime()
        rt.openPlayground("dials-dial", nil)
        pgSideKeysPress(rt, .right)
        pgSideKeysPress(rt, .up)
        pgSideKeysPress(rt, .up)
        pgSideKeysPress(rt, .down)
        #expect(pgSideKeysDialState(rt) == (1, false))
        pgSideKeysPress(rt, .left)
        #expect(pgSideKeysSays(rt, "dial-side") == "active 1")
        pgSideKeysPress(rt, .text("f"))
        _ = rt.frame(1.0 / 60.0)
        #expect(pgSideKeysDialState(rt) == (1, true))
    }

    @Test func aSideWithoutKeysKeepsTheOldKeys() {
        let rt = pgSideKeysRuntime()
        rt.openPlayground("Dials/Plain", nil)
        pgSideKeysPress(rt, .right)
        let foc1 = rt.hostElements().first(where: \.focused)?.key
        #expect(foc1?.hasPrefix("playground-trigger") == true)
        pgSideKeysPress(rt, .left)
        let foc2 = rt.hostElements().first(where: \.focused)?.key
        #expect(foc2 == nil)
    }

    @Test func aSceneTakesKeysOnItsStageState() {
        let rt = pgSideKeysRuntime()
        rt.openPlayground("meter-high", nil)
        pgSideKeysPress(rt, .right)
        pgSideKeysPress(rt, .up)
        #expect(pgSideKeysSays(rt, "meter-side") == "active 55")
        let realLevel = rt.state.level
        #expect(realLevel == 0)
    }
}
