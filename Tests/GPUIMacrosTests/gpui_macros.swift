// Tests ported from: crates/gpui_macros/src/gpui_macros.rs (#[cfg(test)] items)
// Upstream commit: 650aab59d54f
// Port status: ported

import Testing
import Foundation
@testable import GPUIMacros

@Suite("GPUIMacros Core Tests")
struct GPUIMacrosCoreTests {
    @Test("ActionDescriptor qualified name calculation")
    func test_action_descriptor() {
        let action1 = ActionDescriptor(name: "Save", namespace: "editor")
        #expect(action1.qualifiedName == "editor.Save")

        let action2 = ActionDescriptor(name: "Quit")
        #expect(action2.qualifiedName == "Quit")

        struct MockAction {}
        let desc = defaultActionDescriptor(for: MockAction.self, namespace: "test")
        #expect(desc.qualifiedName == "test.MockAction")
    }

    @Test("ActionRegistry registration, builder and lookup")
    func test_action_registry() throws {
        let registry = ActionRegistry()
        let desc = ActionDescriptor(
            name: "Copy",
            namespace: "edit",
            deprecatedAliases: ["edit.Duplicate"]
        )

        registry.register(descriptor: desc) { data in
            "built: \(String(data: data ?? Data(), encoding: .utf8) ?? "")"
        }

        #expect(registry.descriptor(for: "edit.Copy")?.name == "Copy")
        #expect(registry.descriptor(for: "edit.Duplicate")?.name == "Copy")
        #expect(registry.descriptor(for: "unknown") == nil)

        let result = try registry.build(name: "edit.Copy", data: Data("content".utf8)) as? String
        #expect(result == "built: content")
    }

    @Test("InspectorReflectionRegistry registers and queries properties")
    func test_inspector_reflection_registry() {
        let registry = InspectorReflectionRegistry()
        let props = [
            InspectorProperty(name: "width", category: "layout", typeDescription: "Pixels"),
            InspectorProperty(name: "background", category: "color", typeDescription: "Hsla"),
        ]

        registry.registerProperties(props, forTypeName: "Div")
        let queried = registry.properties(forTypeName: "Div")

        #expect(queried.count == 2)
        #expect(queried[0].name == "width")
        #expect(queried[1].category == "color")
    }

    @Test("StyleDescriptorRegistry groupings")
    func test_style_descriptor_registry() {
        let marginMethods = StyleDescriptorRegistry.methods(for: .margin)
        #expect(marginMethods.contains { $0.name == "m" })
        #expect(marginMethods.contains { $0.name == "mx" })
        #expect(marginMethods.contains { $0.name == "my" })

        let layoutMethods = StyleDescriptorRegistry.methods(for: .layout)
        #expect(layoutMethods.contains { $0.name == "flex" })
    }

    @Test("ComponentWrapper and DefaultRenderable")
    func test_component_and_renderable() {
        struct SampleView: Sendable, DefaultRenderable {
            typealias RenderOutput = EmptyRenderOutput
        }
        let view = SampleView()
        let wrapper = ComponentWrapper(view)
        #expect(type(of: wrapper.component) == SampleView.self)
        #expect(view.renderDefault() == EmptyRenderOutput())
    }
}
