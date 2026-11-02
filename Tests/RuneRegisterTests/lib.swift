// Tests ported from: crates/rune-register/src/lib.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import RuneRegister

private struct Scene: Equatable, Sendable {
    var name: String
    init(_ name: String) { self.name = name }
}

@Test
func doc_example_scene_registration_and_collection() {
    let scenes = slice(Scene.self)
    register(scenes, module: "app::chat", [Scene("chat-1")])
    let names = collect(scenes).map(\.name)
    #expect(names == ["chat-1"])
}

@Test
func concurrent_registration_orders_deterministically_by_module() async {
    let registry = Registry<Scene>()
    await withTaskGroup(of: Void.self) { group in
        for index in (0..<16).reversed() {
            let modName = String(format: "mod_%02d", index)
            let itemName = String(format: "scene_%02d", index)
            group.addTask {
                registry.register(modName, [Scene(itemName)])
            }
        }
    }
    #expect(registry.count == 16)
    let collected = collect(registry).map(\.name)
    let expected = (0..<16).map { String(format: "scene_%02d", $0) }
    #expect(collected == expected)
}
