// Ported from: crates/rune/src/playground/variants.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Variants: a story's state made with one of its named tweaks, picked by 1 to 9.

extension PlaygroundLive {
    /// The open story's variants' names, in key order.
    func variants() -> [String] {
        variantsOf(selected)
    }

    func variantsOf(_ i: Int) -> [String] {
        if i < scenes.count {
            return variantsList.filter { $0.0 == i }.map(\.1)
        }
        let pageIdx = i - scenes.count
        guard pageIdx >= 0 && pageIdx < pages.count else { return [] }
        if case .own(let ownStory) = pages[pageIdx].kind {
            return ownStory.variants()
        }
        return []
    }

    /// `--variant`: story `name` (else the first) opens on the variant `variantName` names, by
    /// number from 1 or by name.
    func pick(_ storyName: String?, _ variantName: String) -> Result<Void, ToolingCliError> {
        let i = storyName.flatMap { find($0) } ?? selected
        let names = variantsOf(i)
        let byNumber: Int?
        if let parsed = Int(variantName), parsed >= 1 && parsed <= names.count {
            byNumber = parsed - 1
        } else {
            byNumber = nil
        }
        let chosen: Int?
        if let byNumber {
            chosen = byNumber
        } else if let exact = names.firstIndex(of: variantName) {
            chosen = exact
        } else {
            chosen = names.firstIndex(where: { $0.lowercased() == variantName.lowercased() && $0.utf8.count == variantName.utf8.count })
                ?? names.firstIndex(where: { $0.caseInsensitiveCompare(variantName) == .orderedSame })
        }
        guard let n = chosen else {
            if names.isEmpty {
                return .failure(ToolingCliError("\(path(i).debugDescription) has no variants"))
            }
            return .failure(ToolingCliError("no variant \(variantName.debugDescription) of \(path(i).debugDescription); it has: \(names.joined(separator: ", "))"))
        }
        if i >= 0 && i < variant.count {
            variant[i] = n
        }
        // A story's stage outlives a switch away; made again, it takes the variant.
        let pageIdx = i - scenes.count
        if pageIdx >= 0 && pageIdx < owned.count {
            owned[pageIdx] = nil
        }
        return .success(())
    }

    /// The open story's variant, by index, of those it has.
    func variantAt() -> Int {
        guard selected >= 0 && selected < variant.count else { return 0 }
        return variant[selected]
    }

    /// The open scene's variant's fn, if it has variants.
    func sceneVariant() -> PlaygroundVariant<S>? {
        let matching = variantsList.filter { $0.0 == selected }
        let at = variantAt()
        guard at >= 0 && at < matching.count else { return nil }
        return matching[at].2
    }

    /// What a digit key does: the open story's variant it names, if it has that many.
    func variantKey(_ c: Character) -> PlaygroundRequest? {
        guard let d = c.wholeNumberValue, d >= 1 && d <= 9 else { return nil }
        return d <= variants().count ? .variant(d - 1) : nil
    }
}
