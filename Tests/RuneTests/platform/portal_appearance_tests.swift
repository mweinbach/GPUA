// Tests ported from: crates/rune/src/platform/portal_appearance_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("PortalAppearanceTests")
struct PortalAppearanceTests {
    @Test("only an explicit preference picks an appearance")
    func onlyAnExplicitPreferencePicksAnAppearance() {
        #expect(portalSchemeDark(1) == true)
        #expect(portalSchemeDark(2) == false)
        #expect(portalSchemeDark(0) == nil)
        #expect(portalSchemeDark(7) == nil)
    }

    @Test("reads the scheme however deeply the portal wraps it")
    func readsTheSchemeHoweverDeeplyThePortalWrapsIt() {
        #expect(portalScheme(.u32(2)) == 2)
        #expect(portalScheme(.variant(.u32(1))) == 1)
        #expect(portalScheme(.variant(.variant(.u32(2)))) == 2)
        #expect(portalScheme(.str("prefer-dark")) == nil)
    }
}
