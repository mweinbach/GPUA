// Ported from: crates/gpui_macos/src/open_type.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(macOS)
import CoreFoundation
import CoreText
import Foundation
import GPUI

private let ctFeatureOpenTypeTagKey = "CTFeatureOpenTypeTag"
private let ctFeatureOpenTypeValueKey = "CTFeatureOpenTypeValue"

/// Applies OpenType feature tags and custom font fallback cascade descriptors to `font`.
public func applyFeaturesAndFallbacks(
    _ font: inout CTFont,
    _ features: FontFeatures,
    _ fallbacks: FontFallbacks?
) {
    let openTypeTagKey = ctFeatureOpenTypeTagKey as CFString
    let openTypeValueKey = ctFeatureOpenTypeValueKey as CFString
    var featureArray: [[CFString: Any]] = []
    for (tag, value) in features.tagValueList() {
        guard tag.utf8.count == 4 else { continue }
        let entry: [CFString: Any] = [
            openTypeTagKey: tag as CFString,
            openTypeValueKey: NSNumber(value: value),
        ]
        featureArray.append(entry)
    }

    var cascadeDescriptors: [CTFontDescriptor] = []
    if let fallbacks, !fallbacks.fallbackList().isEmpty {
        let preferredLanguages = CFLocaleCopyPreferredLanguages()
        let defaultCascade: [CTFontDescriptor]
        if let cfCascade = CTFontCopyDefaultCascadeListForLanguages(font, preferredLanguages)
            as? [CTFontDescriptor]
        {
            defaultCascade = cfCascade.filter { desc in
                CTFontDescriptorCopyAttribute(desc, kCTFontNameAttribute) != nil
            }
        } else {
            defaultCascade = []
        }

        for name in fallbacks.fallbackList() {
            let desc = CTFontDescriptorCreateWithNameAndSize(name as CFString, 0.0)
            cascadeDescriptors.append(desc)
        }
        cascadeDescriptors.append(contentsOf: defaultCascade)
    }

    guard !featureArray.isEmpty || !cascadeDescriptors.isEmpty else {
        return
    }

    var attributes: [CFString: Any] = [:]
    if !featureArray.isEmpty {
        attributes[kCTFontFeatureSettingsAttribute] = featureArray
    }
    if !cascadeDescriptors.isEmpty {
        attributes[kCTFontCascadeListAttribute] = cascadeDescriptors
    }

    let newDescriptor = CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
    font = CTFontCreateCopyWithAttributes(font, 0.0, nil, newDescriptor)
}
#endif
