// Ported from: crates/rune/src/runtime/font_families.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Runtime font family switching (`sans` / `mono`), invalidating cached text layouts and memo scope.

extension Runtime {
    public func fontFamilies() -> (String, String) {
        (text.sans, text.mono)
    }

    public func setFontFamilies(_ sans: String, _ mono: String) {
        guard text.sans != sans || text.mono != mono else { return }
        text.sans = sans
        text.mono = mono
        bumpFontEpoch()
        text.atlas.invalidate()
        memo.clear()
        textLayoutCache.removeAll()
        markDirty(CommitWhy.FONTS)
    }
}
