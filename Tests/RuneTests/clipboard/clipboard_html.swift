// Tests ported from: crates/rune/src/clipboard/html.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite
struct ClipboardHtmlTests {
    @Test
    func formattingSurvives() {
        let html = #"<p class="p1"><b>Bold</b> <i>it</i> <a href="https://example.com/a?b=1">link</a><br/><span style="font-weight: 700; color: #333">x</span></p>"#
        #expect(
            sanitizeHtml(html)
                == #"<p class="p1"><b>Bold</b> <i>it</i> <a href="https://example.com/a?b=1">link</a><br /><span style="font-weight: 700; color: #333">x</span></p>"#
        )
        #expect(sanitizeHtml("<ul><li>1 &lt; 2 &amp; 3 > 0</li></ul>") == "<ul><li>1 &lt; 2 &amp; 3 > 0</li></ul>")
        #expect(
            sanitizeHtml("<style>p.p1 {margin: 0; font: 12px Helvetica}</style><p>a</p>")
                == "<style>p.p1 {margin: 0; font: 12px Helvetica}</style><p>a</p>"
        )
        #expect(sanitizeHtml("a < b") == "a &lt; b")
        #expect(
            sanitizeHtml(#"<img src="data:image/png;base64,AAAA" alt='a "q"'>"#)
                == #"<img src="data:image/png;base64,AAAA" alt="a &quot;q&quot;">"#
        )
        #expect(
            sanitizeHtml(#"<img srcset="data:image/png;base64,AAAA 1x, https://example.com/a.png 2x">"#)
                == #"<img srcset="data:image/png;base64,AAAA 1x, https://example.com/a.png 2x">"#
        )
    }

    @Test
    func activeContentGoes() {
        let cases: [(String, String)] = [
            ("<p>a<script>alert(1)</script>b</p>", "<p>ab</p>"),
            ("<p>a<SCRIPT type=x>alert(1)</ScRiPt >b</p>", "<p>ab</p>"),
            ("<script/src=x></script>ok", "ok"),
            ("<scr\0ipt>alert(1)</scr\0ipt>ok", "ok"),
            ("<img src=x onerror=alert(1)>", "<img src=\"x\">"),
            ("<img src=x on\0error=alert(1)>", "<img src=\"x\">"),
            ("<img src=x OnError = 'alert(1)' >", "<img src=\"x\">"),
            ("<a href=\"javascript:alert(1)\">x</a>", "<a>x</a>"),
            ("<a href=\" JaVa&#x09;Script&colon;alert(1)\">x</a>", "<a>x</a>"),
            ("<a href=\"jav&#97;script:alert(1)\">x</a>", "<a>x</a>"),
            ("<a href=\"javascript&#0000000000000000000000000000000000058;alert(1)\">x</a>", "<a>x</a>"),
            ("<a href=\"javascript&#x00000000000000000000000000000000003a;alert(1)\">x</a>", "<a>x</a>"),
            ("<a href=\"javascript&unknownentity;alert(1)\">x</a>", "<a>x</a>"),
            ("<a href=\"//evil.example/x\">x</a>", "<a>x</a>"),
            ("<a href='vbscript:x'>x</a>", "<a>x</a>"),
            ("<img src=\"data:image/svg+xml;base64,AAAA\">", "<img>"),
            ("<img src=\"data:image/png.svg;base64,AAAA\">", "<img>"),
            ("<a href=\"data:text/html,<script>\">x</a>", "<a>x</a>"),
            ("<iframe srcdoc=\"<script>\"></iframe>t", "t"),
            ("<svg><a xlink:href=\"javascript:x\"/><script>x</script></svg>t", "t"),
            ("<math><mi href=javascript:x>x</mi></math>t", "t"),
            ("<meta http-equiv=refresh content=\"0;url=javascript:x\"><base href=//evil><link rel=import href=x>t", "t"),
            ("<embed src=x.swf><object data=x>fallback</object>t", "t"),
            ("<div style=\"background:url(javascript:x)\">t</div>", "<div>t</div>"),
            ("<div style=\"width: expression(alert(1))\">t</div>", "<div>t</div>"),
            ("<div style=\"x: ex/**/pression(1)\">t</div>", "<div>t</div>"),
            ("<div style=\"font-family:'/*';background:url(https://evil.example/x);/*'\">t</div>", "<div>t</div>"),
            ("<div style=\"&commat;import 'https://evil.example/x.css'\">t</div>", "<div>t</div>"),
            ("<div style=\"background:u\\72l(x)\">t</div>", "<div>t</div>"),
            ("<div style=\"background:u\0rl(x)\">t</div>", "<div>t</div>"),
            ("<style>@import 'x.css';</style>t", "t"),
            ("<style>a{font-family:'/*'}@import 'x.css';/*'}*/</style>t", "t"),
            ("<style>a{background:&#x75;rl(x)}</style>t", "t"),
            ("<style>p{}</style><script>x</script>t", "<style>p{}</style>t"),
            ("<style>p{}</style ><b>t</b>", "<style>p{}</style><b>t</b>"),
            ("<!--<script>x</script>-->t", "t"),
            ("<!--><script>x</script>t", "t"),
            ("<!---><script>x</script>t", "t"),
            ("<!-- --!><script>x</script>t", "t"),
            ("<![CDATA[<script>x</script>]]>t", "t"),
            ("<!--[if gte mso 9]><xml>x</xml><![endif]-->t", "t"),
            ("<![if !supportLists]>t<![endif]>", "t"),
            ("<!DOCTYPE html><html><body>t</body></html>", "<html><body>t</body></html>"),
            ("<title><!--</title><script>x</script>-->t", "t"),
            ("<textarea><div title=\"</textarea><script>x</script>\"></div></textarea>t", "<div title=\"&lt;/textarea&gt;&lt;script&gt;x&lt;/script&gt;\"></div>t"),
            ("<xmp><script>x</script></xmp>t", "t"),
            ("<plaintext><script>x</script>", ""),
            ("<form action=https://evil.example><button formaction=javascript:y>b</button></form>", "<button>b</button>"),
            ("<details open ontoggle=x>t</details>", "<details open>t</details>"),
            ("<scr<script>ipt>alert(1)</script>", "<scr>ipt>alert(1)"),
            ("<img srcset=\"a.png 1x, javascript:x 2x\">", "<img>"),
            ("t<script>never closed", "t"),
            ("t<img src=x", "t"),
            ("t<a href=\"unterminated>", "t"),
            ("a\0b", "ab"),
        ]
        for (dirty, want) in cases {
            #expect(sanitizeHtml(dirty) == want, Comment(rawValue: dirty))
        }
    }

    @Test
    func cleanIsStable() {
        for html in [
            "<p><b>x</b><img src=y onload=z></p>",
            "<a href='mailto:a@b.c'>m</a>",
            "<style>a{}</style>",
            "<div title=\"<script>alert(1)</script>\">x</div>",
            "<scr<script>ipt>alert(1)</script>",
        ] {
            let once = sanitizeHtml(html)
            #expect(sanitizeHtml(once) == once)
        }
    }

    @Test
    func staysLinearAndPanicFreeOnHugeAndNestedInputs() {
        let start = RuneInstant.now()
        let manyScripts = String(repeating: "<script>alert(1)</script><b>ok</b>", count: 5_000)
        #expect(sanitizeHtml(manyScripts) == String(repeating: "<b>ok</b>", count: 5_000))

        let deep = String(repeating: "<div>", count: 5_000) + "text" + String(repeating: "</div>", count: 5_000)
        #expect(sanitizeHtml(deep) == deep)

        let unclosed = String(repeating: "<a href=\"https://example.com\" ", count: 5_000)
        #expect(sanitizeHtml(unclosed) == "")

        let multibyte = String(repeating: "café 🦀 <b title=\"🎉\">bold</b>", count: 2_000)
        #expect(sanitizeHtml(multibyte).contains("🦀"))
        #expect(start.elapsedSeconds() < 4.0)
    }

    @Test
    func cfHtmlUsesUtf8ByteOffsetsAndToleratesMinusOneOffsets() {
        let fragment = "<b>Héllo 🦀</b> <i>world</i>"
        let packed = packCfHtml(fragment)
        #expect(unpackCfHtml(Array(packed.utf8)) == fragment)
        var nulPadded = Array(packed.utf8)
        nulPadded.append(contentsOf: [0, 0, 0])
        #expect(unpackCfHtml(nulPadded) == fragment)

        let minusOneContext = "Version:0.9\r\nStartHTML:-1\r\nEndHTML:-1\r\nStartFragment:0000000109\r\nEndFragment:0000000124\r\n<!--StartFragment--><b>Hi café</b><!--EndFragment-->"
        #expect(unpackCfHtml(Array(minusOneContext.utf8)) == "<b>Hi café</b>")

        let minusOneFrag = "Version:0.9\r\nStartHTML:-000000001\r\nEndHTML:-000000001\r\nStartFragment:-000000001\r\nEndFragment:-000000001\r\n<html><body><!--StartFragment--><i>markers</i><!--EndFragment--></body></html>"
        #expect(unpackCfHtml(Array(minusOneFrag.utf8)) == "<i>markers</i>")

        let htmlOffsetsOnly = "Version:0.9\r\nStartHTML:0000000043\r\nEndHTML:0000000059\r\n<p>doc slice</p>"
        #expect(unpackCfHtml(Array(htmlOffsetsOnly.utf8)) == "<p>doc slice</p>")

        let outOfBounds = "Version:0.9\r\nStartHTML:0000000100\r\nEndHTML:0000099999\r\nStartFragment:0000000500\r\nEndFragment:0000099999\r\n<b>fallback</b>"
        #expect(unpackCfHtml(Array(outOfBounds.utf8)) == "<b>fallback</b>")
    }
}
