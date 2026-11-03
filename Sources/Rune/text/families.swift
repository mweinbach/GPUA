// Ported from: crates/rune/src/text/families.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! The families behind the sans and mono slots, and changing them while text is cached.

#if !os(WASI)
import Foundation
#endif

private final class ChosenFamiliesBox {
    var epoch: UInt64 = 0
    var chosen: (String, String)? = nil
}

#if !os(WASI)
private let chosenThreadKey = "dev.gpua.rune.text.chosen_families"

private func withChosenBox<R>(_ body: (ChosenFamiliesBox) -> R) -> R {
    let dict = Thread.current.threadDictionary
    let box: ChosenFamiliesBox
    if let existing = dict[chosenThreadKey] as? ChosenFamiliesBox {
        box = existing
    } else {
        let created = ChosenFamiliesBox()
        dict[chosenThreadKey] = created
        box = created
    }
    return body(box)
}
#else
// PORT NOTE: WASI is single-threaded; thread-local `CHOSEN` state lives in a process-local box.
nonisolated(unsafe) private let wasiChosenBox = ChosenFamiliesBox()

private func withChosenBox<R>(_ body: (ChosenFamiliesBox) -> R) -> R {
    body(wasiChosenBox)
}
#endif

/// Chooses `sans` and `mono` for every window on this thread. Choosing the families already
/// chosen changes nothing.
func chooseFamilies(_ sans: String, _ mono: String) {
    withChosenBox { box in
        if box.chosen == nil || box.chosen!.0 != sans || box.chosen!.1 != mono {
            box.epoch &+= 1
            box.chosen = (sans, mono)
        }
    }
}

/// Current thread's chosen `(epoch, (sans, mono)?)` state.
func currentChosenFamilies() -> (UInt64, (String, String)?) {
    withChosenBox { ($0.epoch, $0.chosen) }
}

/// The slot strings for `sans` and `mono`. Web (WASI) has no system fonts to fall back on, so its
/// slots end in the bundled faces.
func slots(_ sans: String, _ mono: String) -> (String, String) {
    #if os(WASI)
    return ("\(sans), Inter", "\(mono), IBM Plex Mono")
    #else
    return (sans, mono)
    #endif
}

extension TextSystem {
    /// A window's or overlay's text system: in the families chosen for every window when the
    /// app has chosen, else in `families`.
    public static func forWindow(
        _ fonts: [[UInt8]] = [],
        _ families: (String, String) = ("Inter", "Inter")
    ) -> TextSystem {
        let (epoch, chosen) = currentChosenFamilies()
        let eff = chosen ?? families
        let ts = TextSystem(fonts, eff)
        ts.chosenEpoch = epoch
        return ts
    }

    /// The sans and mono slots' families (CSS lists), as `TextSystem.init` or `setFamilies` named them.
    public func families() -> (String, String) {
        chosenFamiliesPair
    }

    /// Puts `sans` and `mono` (CSS lists, as `AppSpec.families` takes them) behind the slots.
    /// Returns `false`, dropping nothing, when the slots already hold these families.
    @discardableResult
    public func setFamilies(_ sans: String, _ mono: String) -> Bool {
        if chosenFamiliesPair.0 == sans && chosenFamiliesPair.1 == mono {
            return false
        }
        noteMeasureFamilies(sans, mono)
        chosenFamiliesPair = (sans, mono)
        let resolvedSlots = slots(sans, mono)
        self.sans = resolvedSlots.0
        self.mono = resolvedSlots.1
        self.slotSystemMono = namesSystemMono(sans) || namesSystemMono(mono)
        let picked = chooseFamiliesList(
            requested: resolvedSlots,
            systemMono: resolvedSystemMono(),
            hasFamily: { [weak self] name in self?.hasFamily(name) ?? false }
        )
        self.sansCandidates = picked.0
        self.monoCandidates = picked.1
        self.layouts.removeAll()
        self.shapes.removeAll()
        self.superseded.removeAll()
        self.runs.removeAll()
        self.primaryTraks.removeAll()
        self.primaryAxes.removeAll()
        self.glyphCache.clear()
        return true
    }

    /// Whether families were chosen since this text system last followed them.
    func familiesBehind() -> Bool {
        let (epoch, _) = currentChosenFamilies()
        return epoch != chosenEpoch
    }

    /// Takes up the families chosen since it last looked; `true` when that changed its slots.
    @discardableResult
    func followChosen() -> Bool {
        let (epoch, chosen) = currentChosenFamilies()
        if epoch == chosenEpoch {
            return false
        }
        chosenEpoch = epoch
        guard let (s, m) = chosen else { return false }
        return setFamilies(s, m)
    }
}
