// Ported from: crates/rune/src/text/measure.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Measuring text from a view, for views that place things themselves (table columns, diagram
//! nodes). Each thread keeps a `TextSystem` built from the fonts the most recent `TextSystem`
//! was given, with `withFamilies` providing thread-scoped isolation for parallel tests.

#if !os(WASI)
import Foundation
#endif

private struct MeasureFontsState: Sendable {
    /// Bumped by any change, of fonts or families.
    var generation: UInt64
    /// The `generation` that last changed the fonts.
    var fontsGeneration: UInt64
    var fonts: [[UInt8]]
    var families: (String, String)
    /// Zero for the process-wide state; a `withFamilies` scope's own number otherwise.
    var scope: UInt64
}

private final class ThreadMeasurerBox {
    var generation: UInt64 = 0
    var fontsGeneration: UInt64 = 0
    var text: TextSystem? = nil
    var calls: UInt32 = 0
    var overrideState: MeasureFontsState? = nil
}

/// Layouts kept between evictions on a thread's measurer.
private let EVICT_EVERY: UInt32 = 512

private let globalMeasureLock = LiveLock()
// PORT NOTE: Guarded by `globalMeasureLock` (`Mutex<Option<Fonts>>` + `SCOPES` in upstream `measure.rs`).
nonisolated(unsafe) private var globalMeasureFonts: MeasureFontsState? = nil
// PORT NOTE: Guarded by `globalMeasureLock` for monotonic `withFamilies` scope IDs.
nonisolated(unsafe) private var nextMeasureScopeId: UInt64 = 1

#if !os(WASI)
private let measurerThreadKey = "dev.gpua.rune.text.measurer"

private func currentMeasurerBox() -> ThreadMeasurerBox {
    let dict = Thread.current.threadDictionary
    if let existing = dict[measurerThreadKey] as? ThreadMeasurerBox {
        return existing
    }
    let created = ThreadMeasurerBox()
    dict[measurerThreadKey] = created
    return created
}
#else
// PORT NOTE: WASI is single-threaded; thread-local measurer state lives in a process-local box.
nonisolated(unsafe) private let wasiMeasurerBox = ThreadMeasurerBox()

private func currentMeasurerBox() -> ThreadMeasurerBox {
    wasiMeasurerBox
}
#endif

private func withMeasureState<R>(_ body: (inout MeasureFontsState?) -> R) -> R {
    let box = currentMeasurerBox()
    if let scoped = box.overrideState {
        var slot: MeasureFontsState? = scoped
        let r = body(&slot)
        box.overrideState = slot
        return r
    } else {
        return globalMeasureLock.withLock {
            body(&globalMeasureFonts)
        }
    }
}

private func applyMeasureFonts(
    _ slot: inout MeasureFontsState?,
    _ fonts: [[UInt8]],
    _ families: (String, String)
) {
    let sameFonts = slot.map { $0.fonts == fonts } ?? false
    if sameFonts, let f = slot, f.families.0 == families.0 && f.families.1 == families.1 {
        return
    }
    let gen = (slot?.generation ?? 0) &+ 1
    let fontsGen: UInt64
    if sameFonts, let f = slot {
        fontsGen = f.fontsGeneration
    } else {
        fontsGen = gen
    }
    let scope = slot?.scope ?? 0
    slot = MeasureFontsState(
        generation: gen,
        fontsGeneration: fontsGen,
        fonts: fonts,
        families: families,
        scope: scope
    )
}

/// Called by every `TextSystem.init`; the next measurement uses these fonts.
func noteMeasureFonts(_ fonts: [[UInt8]], _ families: (String, String)) {
    withMeasureState { slot in
        applyMeasureFonts(&slot, fonts, families)
    }
}

/// Called by `TextSystem.setFamilies`; the next measurement uses these families.
func noteMeasureFamilies(_ sans: String, _ mono: String) {
    withMeasureState { slot in
        guard var f = slot else { return }
        if f.families.0 != sans || f.families.1 != mono {
            f.generation &+= 1
            f.families = (sans, mono)
            slot = f
        }
    }
}

private func epochOf(_ f: MeasureFontsState) -> UInt64 {
    if f.scope == 0 {
        return f.generation
    } else {
        return (1 << 63) | (f.scope << 32) | (f.generation & 0xFFFF_FFFF)
    }
}

/// Changes whenever the fonts or families `measure` uses change. Under a `withFamilies` guard
/// it differs from the unscoped epoch and from every other guard.
public func fontEpoch() -> UInt64 {
    withMeasureState { slot in
        slot.map(epochOf) ?? 0
    }
}

/// Explicitly bump the current thread's or process's font epoch.
public func bumpFontEpoch() {
    withMeasureState { slot in
        if var f = slot {
            f.generation &+= 1
            slot = f
        } else {
            slot = MeasureFontsState(
                generation: 1,
                fontsGeneration: 1,
                fonts: [],
                families: ("Inter", "Inter"),
                scope: 0
            )
        }
    }
}

/// Holds a thread-scoped family override; ends when deinitialized.
public final class FamiliesGuard {
    private let previous: MeasureFontsState?
    private var released: Bool = false

    fileprivate init(previous: MeasureFontsState?) {
        self.previous = previous
    }

    public func drop() {
        guard !released else { return }
        released = true
        currentMeasurerBox().overrideState = previous
    }

    deinit {
        drop()
    }
}

/// Makes `measure`, `advance`, `ink`, and `fontEpoch` on this thread use `sans` and `mono`
/// for as long as the returned `FamiliesGuard` lives, isolating parallel tests.
public func withFamilies(_ sans: String, _ mono: String) -> FamiliesGuard {
    if withMeasureState({ $0 == nil }) {
        withMeasureText { _ in }
    }
    let scope = globalMeasureLock.withLock { () -> UInt64 in
        let id = nextMeasureScopeId
        nextMeasureScopeId &+= 1
        return id
    }
    let seeded: MeasureFontsState? = withMeasureState { slot in
        guard let f = slot else { return nil }
        return MeasureFontsState(
            generation: f.generation &+ 1,
            fontsGeneration: f.fontsGeneration,
            fonts: f.fonts,
            families: (sans, mono),
            scope: scope
        )
    }
    let box = currentMeasurerBox()
    let prev = box.overrideState
    box.overrideState = seeded
    return FamiliesGuard(previous: prev)
}

/// Size in points of `text` (with `spans`) set in `style`, wrapped at `maxWidth` points when given.
/// Widths round up to whole points. `maxWidth: 0.0` gives CSS `min-content`.
public func measure(
    _ text: String,
    _ spans: [Span] = [],
    _ style: TextStyle,
    _ maxWidth: Float? = nil
) -> (Float, Float) {
    measureWith(text, spans, style, maxWidth, RichLayoutOptions())
}

/// `measure` laid out with `RichLayoutOptions` (`wrapAnywhere`, `align`).
public func measureWith(
    _ text: String,
    _ spans: [Span],
    _ style: TextStyle,
    _ maxWidth: Float?,
    _ options: RichLayoutOptions
) -> (Float, Float) {
    withMeasureText { t in
        let l = t.layoutRichWith(text, spans, style, 1.0, maxWidth, options)
        return (l.fullWidth().rounded(.up), layoutHeight(l, style, 1.0))
    }
}

/// Unrounded advance in points of `text` set on one line in `style`.
public func advance(_ text: String, _ style: TextStyle) -> Float {
    withMeasureText { t in
        t.layoutRich(text, [], style, 1.0, nil).fullWidth()
    }
}

/// Runs `body` on this thread's `TextSystem`, built from the fonts the app was given.
func withMeasureText<R>(_ body: (TextSystem) -> R) -> R {
    let box = currentMeasurerBox()
    let current = fontEpoch()
    if box.text == nil || box.generation != current {
        let wanted = withMeasureState { slot -> (UInt64, [[UInt8]], (String, String))? in
            guard let f = slot else { return nil }
            return (f.fontsGeneration, f.fonts, f.families)
        }
        if let existingText = box.text, let (fg, _, (sans, mono)) = wanted, box.fontsGeneration == fg {
            existingText.setFamilies(sans, mono)
            box.generation = fontEpoch()
        } else {
            let created: TextSystem
            if let (_, fonts, fam) = wanted {
                created = TextSystem(fonts, fam)
            } else {
                created = TextSystem()
            }
            let settledFg = withMeasureState { $0?.fontsGeneration ?? 0 }
            box.text = created
            box.fontsGeneration = settledFg
            box.generation = fontEpoch()
            box.calls = 0
        }
    }
    let t = box.text!
    box.calls &+= 1
    if box.calls % EVICT_EVERY == 0 {
        t.endCommit()
    }
    return body(t)
}
