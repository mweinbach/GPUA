// Ported from: crates/media/src/bindings.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if canImport(CoreMedia) && canImport(CoreVideo)
@_exported import CoreMedia
@_exported import CoreVideo
#if canImport(VideoToolbox)
@_exported import VideoToolbox
#endif

// Re-export C constant accessors matching upstream bindings.rs
public var kCMSampleAttachmentKey_NotSyncVal: CFString { kCMSampleAttachmentKey_NotSync }
public var kCMTimeInvalidVal: CMTime { .invalid }
public var kCVReturnSuccessVal: CVReturn { kCVReturnSuccess }
public var kCVPixelFormatType_32BGRAVal: OSType { kCVPixelFormatType_32BGRA }
public var kCVPixelFormatType_420YpCbCr8BiPlanarFullRangeVal: OSType { kCVPixelFormatType_420YpCbCr8BiPlanarFullRange }
public var kCVPixelFormatType_420YpCbCr8BiPlanarVideoRangeVal: OSType { kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange }
public var kCVPixelFormatType_420YpCbCr8PlanarVal: OSType { kCVPixelFormatType_420YpCbCr8Planar }
#else
// Cross-platform fallback declarations for non-Apple platforms
public typealias CVReturn = Int32
public var kCVReturnSuccessVal: CVReturn { 0 }
public var kCVPixelFormatType_32BGRAVal: UInt32 { 0x42475241 }
public var kCVPixelFormatType_420YpCbCr8BiPlanarFullRangeVal: UInt32 { 0x34323066 }
public var kCVPixelFormatType_420YpCbCr8BiPlanarVideoRangeVal: UInt32 { 0x34323076 }
public var kCVPixelFormatType_420YpCbCr8PlanarVal: UInt32 { 0x79343230 }
public typealias CMItemIndex = Int
public struct CMSampleTimingInfo: Sendable, Equatable {
    public init() {}
}
public typealias CMVideoCodecType = UInt32
public let kCMVideoCodecType_H264: CMVideoCodecType = 0x61766331
#endif
