// Ported from: crates/rune/src/runtime/web/a11y.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Accessibility / ARIA shadow-DOM node projection for web & headless accessibility inspection.

public struct A11yNode: Sendable, Equatable {
    public var path: String
    public var key: String?
    public var role: String
    public var label: String?
    public var value: String?
    public var rect: [Float]
    public var focusable: Bool
    public var focused: Bool
    public var disabled: Bool
    public var secure: Bool
    public var level: UInt32?
    public var expanded: Bool?
    public var selected: Bool
    public var children: [A11yNode]

    public init(
        path: String,
        key: String? = nil,
        role: String = "group",
        label: String? = nil,
        value: String? = nil,
        rect: [Float] = [0, 0, 0, 0],
        focusable: Bool = false,
        focused: Bool = false,
        disabled: Bool = false,
        secure: Bool = false,
        level: UInt32? = nil,
        expanded: Bool? = nil,
        selected: Bool = false,
        children: [A11yNode] = []
    ) {
        self.path = path
        self.key = key
        self.role = role
        self.label = label
        self.value = value
        self.rect = rect
        self.focusable = focusable
        self.focused = focused
        self.disabled = disabled
        self.secure = secure
        self.level = level
        self.expanded = expanded
        self.selected = selected
        self.children = children
    }
}

/// Map a Rune semantic role name to its WAI-ARIA role string.
public func ariaRole(for runeRole: String) -> String {
    switch runeRole {
    case "text": return "paragraph"
    case "icon": return "img"
    case "window": return "application"
    default: return runeRole
    }
}

extension Runtime {
    public func accessibilityTree() -> A11yNode? {
        ensureClean()
        guard !nodes.isEmpty else { return nil }
        return buildA11ySubtree(nodeIdx: 0)
    }

    private func buildA11ySubtree(nodeIdx: Int) -> A11yNode? {
        let n = nodes[nodeIdx]
        if n.inert {
            return nil
        }

        var childNodes: [A11yNode] = []
        for cIdx in n.children {
            if let built = buildA11ySubtree(nodeIdx: cIdx) {
                childNodes.append(built)
            }
        }

        let val: String? = {
            if let inp = n.input {
                if inp.edit.isSecure() && !inp.edit.isRevealed() {
                    return String(repeating: "•", count: inp.edit.text.count)
                }
                return inp.edit.text
            }
            return n.textSpec?.content
        }()

        return A11yNode(
            path: n.path,
            key: n.key,
            role: ariaRole(for: n.role),
            label: n.label,
            value: val,
            rect: n.presentedRect,
            focusable: n.focusSpec.enabled || n.input != nil,
            focused: focusedPath == n.path,
            disabled: n.inert,
            secure: n.a11ySecure,
            level: n.a11yLevel,
            expanded: n.a11yExpanded,
            selected: n.focusSpec.selected,
            children: childNodes
        )
    }
}
