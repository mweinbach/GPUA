// Tests ported from: crates/rune-register/src/tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import RuneRegister

private struct Item: Equatable, Sendable {
    var name: String
    var value: UInt32

    init(_ name: String, _ value: UInt32) {
        self.name = name
        self.value = value
    }
}

private func part(_ module: String, _ items: [Item]) -> Part<Item> {
    Part(module: module, items: items)
}

@Test
func orders_by_module_then_own_order() {
    let parts = [
        part("app::b", [Item("b1", 0), Item("b2", 0)]),
        part("app::a", [Item("a1", 0)]),
    ]
    let names = collect(parts).map(\.name)
    #expect(names == ["a1", "b1", "b2"])
}

@Test
func empty_slice_is_empty() {
    let empty: [Part<Item>] = []
    #expect(collect(empty).isEmpty)
}

@Test
func merge_joins_by_name_and_keeps_footer_last() {
    let own = [Item("one", 1), Item("two", 2), Item("footer", 9)]
    let more = [Item("two", 20), Item("new", 5)]
    let out = merge(own, more, { $0.name }, { o, m in o.value += m.value })
    #expect(out == [Item("one", 1), Item("two", 22), Item("new", 5), Item("footer", 9)])
}

@Test
func merge_into_empty_own() {
    let out = merge([Item](), [Item("x", 1)], { $0.name }, { _, _ in })
    #expect(out == [Item("x", 1)])
}

private let testSlice: Registry<Item> = {
    let s = slice(Item.self)
    // Registered out of lexicographical order to verify module sorting ("tests::one" < "tests::two").
    register(s, module: "tests::two", [Item("w", 3)])
    register(s, module: "tests::one", [Item("z", 1), Item("y", 2)])
    return s
}()

@Test
func registered_parts_are_collected_in_module_order() {
    let names = collect(testSlice).map(\.name)
    #expect(names == ["z", "y", "w"])
}

// PORT NOTE: Upstream's `linkme` fallback disables registration on `wasm32`; in Swift `Registry(enabled: false)` models a disabled slice while default `Registry` works across all targets including WASI.
@Test
func wasm_lists_are_empty() {
    let disabledSlice = slice(Item.self, enabled: false)
    register(disabledSlice, module: "tests::one", [Item("z", 1), Item("y", 2)])
    register(disabledSlice, module: "tests::two", [Item("w", 3)])
    #expect(collect(disabledSlice).isEmpty)
}
