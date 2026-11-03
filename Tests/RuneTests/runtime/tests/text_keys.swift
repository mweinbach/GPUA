// Tests ported from: crates/rune/src/runtime/tests/text_keys.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

private func rtTextKeysView(_: Int, _: Cx<Int>) -> El {
    let style = TextStyle.new(14.0, 400.0)
    var plain = text("Plain words that wrap at the column width").font(style).key("plain")
    plain.textSpec?.value.wrap = true

    var cased = text("cased").font(style).key("cased")
    cased.textSpec?.value.textCase = .uppercase

    var anywhere = text("a-long-token-without-spaces-that-exceeds-narrow-width").font(style).key("anywhere")
    anywhere.textSpec?.value.wrap = true
    anywhere.textSpec?.value.wrapAnywhere = true

    var secret = text("hunter2").font(style).key("secret")
    secret.textSpec?.value.redacted = true

    return col().wFull()
        .child(plain)
        .child(cased)
        .child(anywhere)
        .child(secret)
}

@Suite struct RtTextKeysTests {
    @Test
    func textsTransformCaseWrapLongTokensAndKeepNoSecretPlaintextInCache() {
        let rt = Runtime.new(0, rtTextKeysView, (160.0, 400.0), Env.new(true, 2.0))
        _ = rt.frame(0.0)

        let casedContent = rt.nodes.first { $0.key == "cased" }?.textSpec?.content
        let casedElText = rtElement(rt, "cased")?.text
        #expect(casedContent == "CASED")
        #expect(casedElText == "CASED")

        let anywhereLines = rt.nodes.first { $0.key == "anywhere" }?.textLayout?.lines.count ?? 0
        #expect(anywhereLines >= 2)

        // Secure text stores no plaintext in `ElementInfo` or `textLayoutCache`
        let secretElText = rtElement(rt, "secret")?.text
        #expect(secretElText == nil)
        let cacheHasPlaintext = rt.textLayoutCache.keys.contains { $0.content.contains("hunter2") }
        #expect(!cacheHasPlaintext)
    }
}
