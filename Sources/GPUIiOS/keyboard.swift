// Ported from: crates/gpui_ios/src/keyboard.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(iOS) || os(visionOS)
import Foundation
import GPUI
import UIKit

// MARK: - iOS Keyboard Layout

/// Represents the active iOS keyboard input mode (`UITextInputMode`).
public struct IosKeyboardLayout: PlatformKeyboardLayout, Sendable, Equatable {
    public let id: String
    public let name: String

    public init(id: String = "com.apple.keylayout.US", name: String = "US") {
        self.id = id
        self.name = name
    }

    /// Queries `UITextInputMode.activeInputModes` on the main thread to determine the active
    /// hardware/software keyboard language identifier and display name, falling back to `"en-US"`.
    public static func current() -> IosKeyboardLayout {
        let queryCurrent: @MainActor () -> IosKeyboardLayout = {
            for mode in UITextInputMode.activeInputModes {
                if let primaryLanguage = mode.primaryLanguage, !primaryLanguage.isEmpty {
                    let displayName = Locale.current.localizedString(forIdentifier: primaryLanguage)
                        ?? primaryLanguage
                    return IosKeyboardLayout(id: primaryLanguage, name: displayName)
                }
            }
            return IosKeyboardLayout(id: "en-US", name: "English (US)")
        }

        if Thread.isMainThread {
            return MainActor.assumeIsolated(queryCurrent)
        } else {
            return DispatchQueue.main.sync {
                MainActor.assumeIsolated(queryCurrent)
            }
        }
    }
}

// MARK: - iOS Keyboard Mapper

/// Maps hardware key equivalents across international iOS keyboard layouts
/// (AZERTY French/Belgian, QWERTZ German/Central-European, Turkish-F), matching
/// upstream `IosKeyboardMapper`.
public struct IosKeyboardMapper: PlatformKeyboardMapper, Sendable {
    private let keyEquivalents: [Character: Character]?

    public init(_ layoutId: String) {
        self.keyEquivalents = Self.buildKeyEquivalents(for: layoutId)
    }

    /// Creates an `IosKeyboardMapper` for the given layout identifier, matching upstream
    /// `IosKeyboardMapper::new(layout_id)`.
    public static func new(_ layoutId: String) -> IosKeyboardMapper {
        IosKeyboardMapper(layoutId)
    }

    public func mapKeyEquivalent(
        keystroke: Keystroke,
        useKeyEquivalents: Bool
    ) -> KeybindingKeystroke {
        if useKeyEquivalents,
           let map = keyEquivalents,
           keystroke.key.count == 1,
           let ch = keystroke.key.first,
           let mapped = map[ch]
        {
            var adjusted = keystroke
            adjusted.key = String(mapped)
            return KeybindingKeystroke.fromKeystroke(adjusted)
        }
        return KeybindingKeystroke.fromKeystroke(keystroke)
    }

    public func getKeyEquivalents() -> [Character: Character]? {
        keyEquivalents
    }

    // MARK: - Layout Mapping Tables

    private static func buildKeyEquivalents(for layoutId: String) -> [Character: Character]? {
        let normalized = layoutId.replacingOccurrences(of: "_", with: "-")
        let lower = normalized.lowercased()
        let baseLang = lower.split(separator: "-").first.map(String.init) ?? lower

        // French / Belgian AZERTY (`fr*`, `nl-be`)
        if baseLang == "fr" || lower.hasPrefix("nl-be") {
            return [
                "a": "q",
                "q": "a",
                "z": "w",
                "w": "z",
                "m": ";",
                ";": "m",
                ",": "?",
            ]
        }

        // German / Austrian / Swiss / Central European QWERTZ (`de*`, `cs`, `sk`, `hu`)
        if baseLang == "de" || baseLang == "cs" || baseLang == "sk" || baseLang == "hu" {
            return [
                "z": "y",
                "y": "z",
            ]
        }

        // Turkish-F (`tr*` with `-F` / `Turkish-F`)
        if baseLang == "tr" && layoutId.contains("F") {
            return [
                "f": "a",
                "g": "s",
                "i": "d",
                "o": "f",
                "d": "g",
                "r": "h",
                "n": "j",
                "h": "k",
                "p": "l",
                "q": "w",
                "w": "e",
                "u": "r",
                "y": "t",
            ]
        }

        return nil
    }
}
#endif
