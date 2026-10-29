// Tests ported from: crates/gpui/src/svg_renderer.rs (#[cfg(test)] items)
// Upstream commit: 650aab59d54f
// Port status: ported

import Foundation
import Testing
@testable import GPUI

private func loadBundledFontBytes() -> ([UInt8], [UInt8]) {
    let fixtureDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/fonts")
    let ibmPath = fixtureDir.appendingPathComponent("ibm-plex-sans/IBMPlexSans-Regular.ttf").path
    let lilexPath = fixtureDir.appendingPathComponent("lilex/Lilex-Regular.ttf").path

    var ibmData: [UInt8] = []
    if let data = FileManager.default.contents(atPath: ibmPath) {
        ibmData = Array(data)
    }

    var lilexData: [UInt8] = []
    if let data = FileManager.default.contents(atPath: lilexPath) {
        lilexData = Array(data)
    }

    return (ibmData, lilexData)
}

private func dbWithBundledFonts() -> FontDatabase {
    let db = FontDatabase()
    let (ibm, lilex) = loadBundledFontBytes()
    if !ibm.isEmpty {
        _ = db.loadFontData(ibm)
    }
    if !lilex.isEmpty {
        _ = db.loadFontData(lilex)
    }
    return db
}

@Suite("SvgRendererTests")
struct SvgRendererTests {
    @Test
    func test_is_emoji_presentation() {
        let cases: [(Character, Bool)] = [
            ("a", false),
            ("Z", false),
            ("1", false),
            ("#", false),
            ("*", false),
            ("漢", false),
            ("中", false),
            ("カ", false),
            ("©", false),
            ("♥", false),
            ("😀", true),
            ("✅", true),
            ("🇺🇸", true),
            ("©️", false),
            ("♥️", false),
            ("1️⃣", false),
        ]

        for (value, expected) in cases {
            #expect(isEmojiPresentation(value) == expected, "for char \(value)")
        }
    }

    @Test
    func fix_generic_font_families_sets_all_families() {
        var db = dbWithBundledFonts()
        fixGenericFontFamilies(&db)

        let families: [FontFamily] = [
            .sansSerif,
            .serif,
            .monospace,
            .cursive,
            .fantasy,
        ]

        for family in families {
            let query = FontQuery(families: [family])
            #expect(db.query(query) != nil, "Expected generic family \(family) to resolve after fixGenericFontFamilies")
        }
    }

    @Test
    func test_select_emoji_font_skips_family_without_glyph() {
        var db = dbWithBundledFonts()
        fixGenericFontFamilies(&db)

        guard let ibmPlexSans = db.query(FontQuery(families: [.named("IBM Plex Sans")])),
              let lilex = db.query(FontQuery(families: [.named("Lilex")])) else {
            Issue.record("Both IBM Plex Sans and Lilex should resolve")
            return
        }

        let selected = selectEmojiFont(
            character: "│",
            fonts: [],
            db: db,
            families: ["IBM Plex Sans", "Lilex"]
        )

        #expect(selected == lilex)
        #expect(!fontHasChar(db: db, id: ibmPlexSans, character: "│"))
        #expect(fontHasChar(db: db, id: lilex, character: "│"))
    }

    @Test
    func fix_generic_font_families_monospace_resolves_to_lilex() {
        var db = dbWithBundledFonts()
        fixGenericFontFamilies(&db)

        let query = FontQuery(families: [.monospace])
        let id = db.query(query)
        #expect(id != nil, "Monospace should resolve")

        if let id = id, let face = db.face(id) {
            let hasLilex = face.families.contains(where: { $0.0.localizedCaseInsensitiveContains("Lilex") })
            #expect(hasLilex, "Monospace should map to Lilex, got \(face.families)")
        } else {
            Issue.record("Face should exist")
        }
    }
}
