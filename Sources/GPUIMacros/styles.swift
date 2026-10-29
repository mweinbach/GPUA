// Ported from: crates/gpui_macros/src/styles.rs
// Upstream commit: 650aab59d54f
// Port status: ported

import Foundation

/// Functional groups corresponding to upstream style helper macro expansions (`style_helpers!`).
public enum StyleMethodGroup: String, Sendable, CaseIterable {
    case margin
    case padding
    case position
    case overflow
    case cursor
    case border
    case boxShadow = "box_shadow"
    case visibility
    case layout
    case size
    case color
}

/// Metadata describing a style helper method available on styled elements.
public struct StyleHelperDescriptor: Sendable, Equatable, Hashable {
    public var name: String
    public var group: StyleMethodGroup
    public var documentation: String?

    public init(name: String, group: StyleMethodGroup, documentation: String? = nil) {
        self.name = name
        self.group = group
        self.documentation = documentation
    }
}

/// Registry of standard style methods generated for styled types.
public enum StyleDescriptorRegistry {
    public static let standardMethods: [StyleHelperDescriptor] = [
        StyleHelperDescriptor(name: "m", group: .margin, documentation: "Margin all sides"),
        StyleHelperDescriptor(name: "mx", group: .margin, documentation: "Horizontal margin"),
        StyleHelperDescriptor(name: "my", group: .margin, documentation: "Vertical margin"),
        StyleHelperDescriptor(name: "p", group: .padding, documentation: "Padding all sides"),
        StyleHelperDescriptor(name: "px", group: .padding, documentation: "Horizontal padding"),
        StyleHelperDescriptor(name: "py", group: .padding, documentation: "Vertical padding"),
        StyleHelperDescriptor(name: "relative", group: .position, documentation: "Relative position"),
        StyleHelperDescriptor(name: "absolute", group: .position, documentation: "Absolute position"),
        StyleHelperDescriptor(name: "overflowHidden", group: .overflow, documentation: "Hide overflow"),
        StyleHelperDescriptor(name: "cursorPointer", group: .cursor, documentation: "Pointer cursor"),
        StyleHelperDescriptor(name: "border", group: .border, documentation: "Border width"),
        StyleHelperDescriptor(name: "shadow", group: .boxShadow, documentation: "Box shadow"),
        StyleHelperDescriptor(name: "invisible", group: .visibility, documentation: "Hide visibility"),
        StyleHelperDescriptor(name: "visible", group: .visibility, documentation: "Show visibility"),
        StyleHelperDescriptor(name: "flex", group: .layout, documentation: "Flex layout"),
        StyleHelperDescriptor(name: "flexCol", group: .layout, documentation: "Column flex layout"),
        StyleHelperDescriptor(name: "flexRow", group: .layout, documentation: "Row flex layout"),
    ]

    public static func methods(for group: StyleMethodGroup) -> [StyleHelperDescriptor] {
        standardMethods.filter { $0.group == group }
    }
}
