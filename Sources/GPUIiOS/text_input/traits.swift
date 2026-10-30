// Ported from: crates/gpui_ios/src/text_input/traits.rs
// Upstream commit: 650aab59d54f
// Port status: ported

import Foundation
import GPUI
#if os(iOS) || os(visionOS)
import UIKit
#endif

// MARK: - iOS Text Input Trait Options

/// Keyboard layout style for iOS software keyboard presentation.
public enum IosTextInputKeyboardType: Sendable, Equatable {
    case `default`
    case asciiCapable
    case numbersAndPunctuation
    case url
    case numberPad
    case phonePad
    case namePhonePad
    case emailAddress
    case decimalPad
    case twitter
    case webSearch
}

/// Return key label for iOS software keyboard presentation.
public enum IosTextInputReturnKeyType: Sendable, Equatable {
    case `default`
    case go
    case google
    case join
    case next
    case route
    case search
    case send
    case done
    case emergencyCall
    case `continue`
}

/// Autocorrection behavior for iOS text controls.
public enum IosTextInputAutocorrection: Sendable, Equatable {
    case `default`
    case disabled
    case enabled
}

/// Spell-checking behavior for iOS text controls.
public enum IosTextInputSpellChecking: Sendable, Equatable {
    case `default`
    case disabled
    case enabled
}

/// Autocapitalization behavior for iOS text controls.
public enum IosTextInputAutocapitalization: Sendable, Equatable {
    case none
    case words
    case sentences
    case allCharacters
}

/// Software keyboard visual appearance.
public enum IosTextInputKeyboardAppearance: Sendable, Equatable {
    case `default`
    case dark
    case light
}

/// Autofill / semantic content type for iOS text controls.
public enum IosTextInputContentType: Sendable, Equatable {
    case username
    case password
    case newPassword
    case oneTimeCode
    case emailAddress
    case telephoneNumber
    case url
    case name
    case streetAddressLine1
    case streetAddressLine2
    case city
    case state
    case postalCode
    case countryName
}

/// Policy controlling whether focusing the backing control presents the on-screen keyboard.
public enum IosTextInputSoftKeyboardPolicy: Sendable, Equatable {
    case automatic
    case hidden
}

/// Extended iOS trait configuration supplementing `GPUI.TextInputConfig`.
public struct IosTextInputTraitsConfig: Sendable, Equatable {
    public var base: TextInputConfig
    public var keyboardType: IosTextInputKeyboardType
    public var returnKeyType: IosTextInputReturnKeyType
    public var autocorrection: IosTextInputAutocorrection
    public var spellChecking: IosTextInputSpellChecking
    public var autocapitalization: IosTextInputAutocapitalization
    public var keyboardAppearance: IosTextInputKeyboardAppearance
    public var smartInsertDeleteEnabled: Bool
    public var contentType: IosTextInputContentType?
    public var softKeyboardPolicy: IosTextInputSoftKeyboardPolicy

    public init(
        base: TextInputConfig = TextInputConfig(),
        keyboardType: IosTextInputKeyboardType = .default,
        returnKeyType: IosTextInputReturnKeyType = .default,
        autocorrection: IosTextInputAutocorrection = .default,
        spellChecking: IosTextInputSpellChecking = .default,
        autocapitalization: IosTextInputAutocapitalization = .sentences,
        keyboardAppearance: IosTextInputKeyboardAppearance = .default,
        smartInsertDeleteEnabled: Bool = true,
        contentType: IosTextInputContentType? = nil,
        softKeyboardPolicy: IosTextInputSoftKeyboardPolicy = .automatic
    ) {
        self.base = base
        self.keyboardType = keyboardType
        self.returnKeyType = returnKeyType
        self.autocorrection = autocorrection
        self.spellChecking = spellChecking
        self.autocapitalization = autocapitalization
        self.keyboardAppearance = keyboardAppearance
        self.smartInsertDeleteEnabled = smartInsertDeleteEnabled
        self.contentType = contentType
        self.softKeyboardPolicy = softKeyboardPolicy
    }
}

/// Returns `true` when the backing UIKit control should be a multi-line `UITextView` rather than
/// a single-line `GPUIBackedTextField` (`UITextView` does not support `isSecureTextEntry`).
func shouldUseTextView(_ config: TextInputConfig) -> Bool {
    config.multiline && !config.secureEntry
}

/// Overload accepting `IosTextInputTraitsConfig`.
func shouldUseTextView(_ traits: IosTextInputTraitsConfig) -> Bool {
    shouldUseTextView(traits.base)
}

#if os(iOS) || os(visionOS)
/// Applies `TextInputConfig` traits onto a `UITextField` or `UITextView` and reloads input views.
@MainActor
func applyTextInputTraits(_ view: UIView, _ config: TextInputConfig) {
    let traits = IosTextInputTraitsConfig(
        base: config,
        autocorrection: config.secureEntry ? .disabled : .default,
        spellChecking: config.secureEntry ? .disabled : .default,
        autocapitalization: config.secureEntry ? .none : .sentences,
        smartInsertDeleteEnabled: !config.secureEntry,
        contentType: config.secureEntry ? .password : nil
    )
    applyTextInputTraits(view, traits)
}

/// Applies full `IosTextInputTraitsConfig` traits onto a `UITextField` or `UITextView`.
@MainActor
func applyTextInputTraits(_ view: UIView, _ traits: IosTextInputTraitsConfig) {
    let kbType = mapKeyboardType(traits.keyboardType)
    let retType = mapReturnKeyType(traits.returnKeyType)
    let autocorrect = mapAutocorrection(traits.autocorrection)
    let spellCheck = mapSpellChecking(traits.spellChecking)
    let autocap = mapAutocapitalization(traits.autocapitalization)
    let appearance = mapKeyboardAppearance(traits.keyboardAppearance)
    let smartInsert: UITextSmartInsertDeleteType = traits.smartInsertDeleteEnabled ? .yes : .no
    let contentType = traits.contentType.map(mapContentType)

    if let textField = view as? UITextField {
        textField.keyboardType = kbType
        textField.returnKeyType = retType
        textField.isSecureTextEntry = traits.base.secureEntry
        textField.autocorrectionType = autocorrect
        textField.spellCheckingType = spellCheck
        textField.autocapitalizationType = autocap
        textField.keyboardAppearance = appearance
        textField.smartInsertDeleteType = smartInsert
        textField.textContentType = contentType
        textField.reloadInputViews()
    } else if let textView = view as? UITextView {
        textView.keyboardType = kbType
        textView.returnKeyType = retType
        textView.isSecureTextEntry = traits.base.secureEntry
        textView.autocorrectionType = autocorrect
        textView.spellCheckingType = spellCheck
        textView.autocapitalizationType = autocap
        textView.keyboardAppearance = appearance
        textView.smartInsertDeleteType = smartInsert
        textView.textContentType = contentType
        textView.reloadInputViews()
    }
}

private func mapKeyboardType(_ type: IosTextInputKeyboardType) -> UIKeyboardType {
    switch type {
    case .default: return .default
    case .asciiCapable: return .asciiCapable
    case .numbersAndPunctuation: return .numbersAndPunctuation
    case .url: return .URL
    case .numberPad: return .numberPad
    case .phonePad: return .phonePad
    case .namePhonePad: return .namePhonePad
    case .emailAddress: return .emailAddress
    case .decimalPad: return .decimalPad
    case .twitter: return .twitter
    case .webSearch: return .webSearch
    }
}

private func mapReturnKeyType(_ type: IosTextInputReturnKeyType) -> UIReturnKeyType {
    switch type {
    case .default: return .default
    case .go: return .go
    case .google: return .google
    case .join: return .join
    case .next: return .next
    case .route: return .route
    case .search: return .search
    case .send: return .send
    case .done: return .done
    case .emergencyCall: return .emergencyCall
    case .continue: return .continue
    }
}

private func mapAutocorrection(_ type: IosTextInputAutocorrection) -> UITextAutocorrectionType {
    switch type {
    case .default: return .default
    case .disabled: return .no
    case .enabled: return .yes
    }
}

private func mapSpellChecking(_ type: IosTextInputSpellChecking) -> UITextSpellCheckingType {
    switch type {
    case .default: return .default
    case .disabled: return .no
    case .enabled: return .yes
    }
}

private func mapAutocapitalization(_ type: IosTextInputAutocapitalization) -> UITextAutocapitalizationType {
    switch type {
    case .none: return .none
    case .words: return .words
    case .sentences: return .sentences
    case .allCharacters: return .allCharacters
    }
}

private func mapKeyboardAppearance(_ type: IosTextInputKeyboardAppearance) -> UIKeyboardAppearance {
    switch type {
    case .default: return .default
    case .dark: return .dark
    case .light: return .light
    }
}

private func mapContentType(_ type: IosTextInputContentType) -> UITextContentType {
    switch type {
    case .username: return .username
    case .password: return .password
    case .newPassword: return .newPassword
    case .oneTimeCode: return .oneTimeCode
    case .emailAddress: return .emailAddress
    case .telephoneNumber: return .telephoneNumber
    case .url: return .URL
    case .name: return .name
    case .streetAddressLine1: return .streetAddressLine1
    case .streetAddressLine2: return .streetAddressLine2
    case .city: return .addressCity
    case .state: return .addressState
    case .postalCode: return .postalCode
    case .countryName: return .countryName
    }
}
#endif
