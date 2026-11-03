// Tests ported from: crates/rune/src/open_url.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite
struct OpenUrlTests {
    @Test
    func allowsWebAndMailLinksOnly() throws {
        #expect(try checkOpenUrl("  https://example.com/a?b=1#c ") == "https://example.com/a?b=1#c")
        #expect(try checkOpenUrl("HTTP://example.com") == "http://example.com")
        #expect(try checkOpenUrl("https://[::1]:8080/path") == "https://[::1]:8080/path")
        #expect(try checkOpenUrl("mailto:someone@example.com?subject=Hi") == "mailto:someone@example.com?subject=Hi")
        #expect(throws: OpenUrlError.unsupportedScheme("file")) {
            _ = try checkOpenUrl("file:///etc/passwd")
        }
        #expect(throws: OpenUrlError.unsupportedScheme("javascript")) {
            _ = try checkOpenUrl("JavaScript:alert(1)")
        }
        #expect(throws: OpenUrlError.unsupportedScheme("myapp")) {
            _ = try checkOpenUrl("myapp://do/thing")
        }
        #expect(throws: OpenUrlError.empty) {
            _ = try checkOpenUrl("")
        }
        #expect(throws: OpenUrlError.empty) {
            _ = try checkOpenUrl("  ")
        }
        let badLinks = [
            "example.com", "https:", "https://", "https:///x", "https://a b", "https://a\n.com",
            "mailto:", "mailto://example.com", "1http://x", "://x",
            "https://\\evil.com", "https://example.com/\"--flag", "https://example.com/a\\b",
            "https://example.com/%ZZ", "https://example.com/%00", "https://example.com/%2",
            "https://@/", "https://user@/", "https://:80/", "https://example.com:abc/",
            "https://evil%2f.com/", "https://.example.com", "https://a..b.com",
            "https://example.com/a[0]", "https://[not-ipv6]/", "https://[::1]abc/",
        ]
        for bad in badLinks {
            #expect(throws: OpenUrlError.invalid, Comment(rawValue: bad)) {
                _ = try checkOpenUrl(bad)
            }
        }
    }

    @Test
    func sameTabLinksMayBeRelativeOnlyOnWeb() throws {
        for relative in ["/notes/42", "notes/42?x=1", "?q=a", "#top", "../c", "a/b:c"] {
            #expect(try checkOpenUrlLink(relative, relative: true) == relative)
            #expect(throws: OpenUrlError.invalid) {
                _ = try checkOpenUrlLink(relative, relative: false)
            }
        }
        #expect(throws: OpenUrlError.unsupportedScheme("javascript")) {
            _ = try checkOpenUrlLink("javascript:alert(1)", relative: true)
        }
        #expect(throws: OpenUrlError.invalid) {
            _ = try checkOpenUrlLink("/a b", relative: true)
        }
        #expect(try checkOpenUrlLink("HTTPS://example.com/x", relative: true) == "https://example.com/x")
        #if !os(WASI)
        #expect(throws: OpenUrlError.invalid) {
            _ = try checkOpenUrlSameTab("/notes/42")
        }
        #endif
    }

    @Test
    func headlessRunsRecordTheRequestAndOpenNothing() {
        let rt = Runtime<[String]>([], { _, _ in el() }, (50.0, 50.0), Env.new(true, 1.0))
        _ = rt.frame(0.0)
        var errors: [OpenUrlError?] = []
        rt.hostUpdate { _, tx in
            func attempt(_ f: () throws -> Void) -> OpenUrlError? {
                do { try f(); return nil }
                catch let e as OpenUrlError { return e }
                catch { return .invalid }
            }
            errors.append(attempt { try tx.openUrl("https://example.com/docs") })
            errors.append(attempt { try tx.openUrl("file:///etc/hosts") })
            errors.append(attempt { try tx.openUrl("mailto:a@example.com") })
            errors.append(attempt { try tx.openUrlSameTab("https://example.com/here") })
        }
        rt.hostUpdate { seen, tx in
            seen.append("handler")
            try? tx.openUrl("https://example.com/clicked")
        }
        #expect(errors == [nil, .unsupportedScheme("file"), nil, nil])
        #expect(rt.takeUrlRequests() == [
            "https://example.com/docs",
            "mailto:a@example.com",
            "https://example.com/here",
            "https://example.com/clicked",
        ])
        #expect(rt.takeUrlRequests().isEmpty)
    }
}
