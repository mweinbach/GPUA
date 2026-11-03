// Tests ported from: crates/rune/src/runtime/web/a11y.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("WebA11yTests")
struct WebA11yTests {
    @Test("accessibilityTree maps headings, buttons, expanded state, and redacts unrevealed secure inputs")
    func accessibilityTreeProjectsRolesStatesAndRedactsSecrets() {
        var secret = TextEdit.new("hunter2")
        secret.setSecure(true)

        let rt = Runtime.new(false, { expanded, _ in
            var h1 = text("Release notes").key("title").role("heading")
            h1.a11yLevel = 1

            var toggle = row().key("fold").h(28.0).role("button").label(expanded ? "Hide details" : "Show details")
                .onPress { (open: inout Bool, _) in open.toggle() }
            toggle.a11yExpanded = expanded

            var inertBox = el().key("hidden").label("Hidden")
            inertBox.inertFlag = true

            return col().wFull().gap(8.0)
                .child(h1)
                .child(toggle)
                .child(textInput(secret, tok.type_.BODY).key("pw"))
                .child(inertBox)
        }, (480.0, 320.0), Env())

        _ = rt.frame(0.0)
        let tree = rt.accessibilityTree()!
        #expect(tree.children.count == 3) // `inertBox` is excluded
        #expect(tree.children[0].role == "heading")
        #expect(tree.children[0].level == 1)
        #expect(tree.children[0].value == "Release notes")

        #expect(tree.children[1].role == "button")
        #expect(tree.children[1].label == "Show details")
        #expect(tree.children[1].expanded == false)

        // Secure password input never leaks cleartext in A11y value
        #expect(tree.children[2].secure == true)
        #expect(tree.children[2].value != "hunter2")
        #expect(tree.children[2].value?.count == 7)

        rtClick(rt, "fold")
        _ = rt.frame(0.0)
        let updated = rt.accessibilityTree()!
        #expect(updated.children[1].expanded == true)
        #expect(updated.children[1].label == "Hide details")
    }
}
