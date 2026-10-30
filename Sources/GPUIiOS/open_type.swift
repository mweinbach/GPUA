// Ported from: crates/gpui_ios/src/open_type.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(iOS) || os(visionOS)
import CoreFoundation
import CoreGraphics
import CoreText
import Foundation
import GPUI

// MARK: - OpenType Feature & Fallback Application

/// Applies OpenType `FontFeatures` tags and custom `FontFallbacks` (plus the user's preferred
/// language cascade list, excluding `.LastResort`) to a `CTFont`, matching upstream
/// `open_type::apply_features_and_fallbacks`.
func applyFeaturesAndFallbacks(
    _ font: inout CTFont,
    _ features: FontFeatures,
    _ fallbacks: FontFallbacks?
) {
    let featureEntries = features.tagValueList()
    let customFallbacks = fallbacks?.fallbackList() ?? []

    if featureEntries.isEmpty && customFallbacks.isEmpty {
        // Still attach system preferred-language cascade descriptors (filtering `.LastResort`)
        // when available so emoji and CJK fallback matches upstream CoreText behavior.
        let cascade = buildCascadeDescriptors(for: font, customFallbacks: [])
        guard !cascade.isEmpty else { return }
        let attrs: [CFString: Any] = [
            kCTFontCascadeListAttribute: cascade as CFArray,
        ]
        let descriptor = CTFontDescriptorCreateWithAttributes(attrs as CFDictionary)
        font = CTFontCreateCopyWithAttributes(font, 0.0, nil, descriptor)
        return
    }

    var attributes: [CFString: Any] = [:]

    // 1. OpenType feature settings (`kCTFontOpenTypeFeatureTag` / `kCTFontOpenTypeFeatureValue`)
    var ctFeatureArray: [[CFString: Any]] = []
    for (tag, value) in featureEntries where tag.utf8.count == 4 {
        ctFeatureArray.append([
            kCTFontOpenTypeFeatureTag: tag as CFString,
            kCTFontOpenTypeFeatureValue: NSNumber(value: value),
        ])
    }
    if !ctFeatureArray.isEmpty {
        attributes[kCTFontFeatureSettingsAttribute] = ctFeatureArray as CFArray
    }

    // 2. Fallback cascade list (user fallbacks followed by system preferred-language cascade)
    let cascadeDescriptors = buildCascadeDescriptors(for: font, customFallbacks: customFallbacks)
    if !cascadeDescriptors.isEmpty {
        attributes[kCTFontCascadeListAttribute] = cascadeDescriptors as CFArray
    }

    guard !attributes.isEmpty else { return }
    let descriptor = CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
    font = CTFontCreateCopyWithAttributes(font, 0.0, nil, descriptor)
}

private func buildCascadeDescriptors(
    for font: CTFont,
    customFallbacks: [String]
) -> [CTFontDescriptor] {
    var result: [CTFontDescriptor] = []
    result.reserveCapacity(customFallbacks.count + 8)

    for familyName in customFallbacks where !familyName.isEmpty {
        let desc = CTFontDescriptorCreateWithNameAndSize(familyName as CFString, 0.0)
        result.append(desc)
    }

    let preferredLanguages = Locale.preferredLanguages as CFArray
    if let defaultCascade = CTFontCopyDefaultCascadeListForLanguages(font, preferredLanguages) as? [CTFontDescriptor] {
        for desc in defaultCascade {
            if let name = CTFontDescriptorCopyAttribute(desc, kCTFontNameAttribute) as? String,
               name == ".LastResort"
            {
                continue
            }
            result.append(desc)
        }
    }

    return result
}
#endif
