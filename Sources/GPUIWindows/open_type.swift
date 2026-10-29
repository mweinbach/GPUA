// Swift-only: OpenType feature tag mappings and typography features for DirectWrite
#if os(Windows)
import Foundation
import CWinSys
import GPUI

public func makeOpenTypeTag(_ tagName: String) -> UInt32 {
    var tag: UInt32 = 0
    for (i, byte) in tagName.utf8.prefix(4).enumerated() {
        tag |= UInt32(byte) << (i * 8)
    }
    return tag
}

public struct DirectWriteFontFeature: Sendable, Equatable, Hashable {
    public var tag: UInt32
    public var parameter: UInt32

    public init(tag: UInt32, parameter: UInt32 = 1) {
        self.tag = tag
        self.parameter = parameter
    }

    public init(name: String, parameter: UInt32 = 1) {
        self.tag = makeOpenTypeTag(name)
        self.parameter = parameter
    }
}

public enum OpenTypeTags {
    public static let liga = makeOpenTypeTag("liga")
    public static let clig = makeOpenTypeTag("clig")
    public static let calt = makeOpenTypeTag("calt")
    public static let dlig = makeOpenTypeTag("dlig")
    public static let hlig = makeOpenTypeTag("hlig")
    public static let zero = makeOpenTypeTag("zero")
    public static let frac = makeOpenTypeTag("frac")
    public static let ordn = makeOpenTypeTag("ordn")
    public static let tnum = makeOpenTypeTag("tnum")
    public static let pnum = makeOpenTypeTag("pnum")
    public static let onum = makeOpenTypeTag("onum")
    public static let lnum = makeOpenTypeTag("lnum")
    public static let smcp = makeOpenTypeTag("smcp")
    public static let c2sc = makeOpenTypeTag("c2sc")
    public static let caseTag = makeOpenTypeTag("case")
}

public func applyFontFeatures(
    typography: WinHandle,
    features: FontFeatures
) {
    let tagValues = features.tagValueList()

    var featureLigaParam: UInt32 = 1
    var featureCligParam: UInt32 = 1
    var featureCaltParam: UInt32 = 1

    for (tag, value) in tagValues {
        if tag == "liga" {
            featureLigaParam = value
        } else if tag == "clig" {
            featureCligParam = value
        } else if tag == "calt" {
            featureCaltParam = value
        } else {
            let directWriteTag = makeOpenTypeTag(tag)
            _ = cwin_dwrite_typography_add_feature(typography, directWriteTag, value)
        }
    }

    _ = cwin_dwrite_typography_add_feature(typography, OpenTypeTags.liga, featureLigaParam)
    _ = cwin_dwrite_typography_add_feature(typography, OpenTypeTags.clig, featureCligParam)
    _ = cwin_dwrite_typography_add_feature(typography, OpenTypeTags.calt, featureCaltParam)
}

#endif
