// Ported from: crates/rune/src/el/focus.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! What `El` holds for focus and keys: `FocusSpec`, kept behind `Cold` because most elements set none of it.

struct PreserveOnPress: Sendable, Equatable {
    var focus: Bool = false
    var selection: Bool = false
}

struct FocusSpec: ColdEmpty {
    var physical: PhysicalInputHandler? = nil
    var enabled: Bool = false
    var order: Int32 = 0
    var group: Bool = false
    var selected: Bool = false
    var revealSelected: Bool = false
    var preserveOnPress: PreserveOnPress = PreserveOnPress()
    var ring: Outline? = nil
    /// `noFocusRing`: no default ring on this control, and none from this element.
    var ringOff: Bool = false
    /// `defaultButton`: Return presses it.
    var defaultButton: Bool = false
    var highlight: Color? = nil
    var follows: Bool = false
    var returnTo: String? = nil
    /// `onStep`: a slider's arrow and page keys.
    var step: StepFn? = nil
    /// `onStepLimit`: a slider's Home and End.
    var stepLimit: StepLimitFn? = nil
    /// `onKeyUp`.
    var keyUp: InputKeyFn? = nil
    /// `El.onKey`: keys while this element or one inside it has focus.
    var key: InputKeyFn? = nil

    static var emptyValue: FocusSpec { FocusSpec() }

    var isColdEmpty: Bool {
        physical == nil
            && !enabled
            && order == 0
            && !group
            && !selected
            && !revealSelected
            && preserveOnPress == PreserveOnPress()
            && ring == nil
            && !ringOff
            && !defaultButton
            && highlight == nil
            && !follows
            && returnTo == nil
            && step == nil
            && stepLimit == nil
            && keyUp == nil
            && key == nil
    }
}
