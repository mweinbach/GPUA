// Ported from: crates/media/src/media.rs
// Upstream commit: 650aab59d54f
// Port status: ported

import Foundation

#if canImport(CoreMedia) && canImport(CoreVideo)
@_exported import CoreMedia
@_exported import CoreVideo
#if canImport(Metal)
import Metal
#endif

public enum core_media {
    public typealias CMSampleBuffer = CoreMedia.CMSampleBuffer
    public typealias CMFormatDescription = CoreMedia.CMFormatDescription
    public typealias CMBlockBuffer = CoreMedia.CMBlockBuffer
    public typealias CMSampleTimingInfo = CoreMedia.CMSampleTimingInfo
}

public enum core_video {
    public typealias CVImageBuffer = CoreVideo.CVImageBuffer
    public typealias CVPixelBuffer = CoreVideo.CVPixelBuffer
    #if canImport(Metal)
    public typealias CVMetalTextureCache = CoreVideo.CVMetalTextureCache
    public typealias CVMetalTexture = CoreVideo.CVMetalTexture
    #endif
}

extension CMSampleBuffer {
    public func attachments() -> [[String: Any]] {
        guard let array = CMSampleBufferGetSampleAttachmentsArray(self, createIfNecessary: true) as? [[String: Any]] else {
            return []
        }
        return array
    }

    public func imageBuffer() -> CVImageBuffer? {
        CMSampleBufferGetImageBuffer(self)
    }

    public func sampleTimingInfo(index: Int = 0) throws -> CMSampleTimingInfo {
        var timingInfo = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: .invalid,
            decodeTimeStamp: .invalid
        )
        let status = CMSampleBufferGetSampleTimingInfo(self, at: index, timingInfoOut: &timingInfo)
        guard status == 0 else {
            throw NSError(
                domain: "Media.CoreMedia",
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "error getting sample timing info, code: \(status)"]
            )
        }
        return timingInfo
    }

    public func formatDescription() -> CMFormatDescription? {
        CMSampleBufferGetFormatDescription(self)
    }

    public func data() -> CMBlockBuffer? {
        CMSampleBufferGetDataBuffer(self)
    }
}

extension CMFormatDescription {
    public func h264ParameterSetCount() -> Int {
        var count: Int = 0
        let status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
            self,
            parameterSetIndex: 0,
            parameterSetPointerOut: nil,
            parameterSetSizeOut: nil,
            parameterSetCountOut: &count,
            nalUnitHeaderLengthOut: nil
        )
        guard status == 0 else { return 0 }
        return count
    }

    public func h264ParameterSet(atIndex index: Int) throws -> Data {
        var ptr: UnsafePointer<UInt8>? = nil
        var size: Int = 0
        let status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
            self,
            parameterSetIndex: index,
            parameterSetPointerOut: &ptr,
            parameterSetSizeOut: &size,
            parameterSetCountOut: nil,
            nalUnitHeaderLengthOut: nil
        )
        guard status == 0, let p = ptr else {
            throw NSError(
                domain: "Media.CoreMedia",
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "error getting parameter set at \(index), code: \(status)"]
            )
        }
        return Data(bytes: p, count: size)
    }
}

extension CMBlockBuffer {
    public func bytes() throws -> Data {
        var lengthAtOffset: Int = 0
        var totalLength: Int = 0
        var dataPointer: UnsafeMutablePointer<CChar>? = nil

        let status = CMBlockBufferGetDataPointer(
            self,
            atOffset: 0,
            lengthAtOffsetOut: &lengthAtOffset,
            totalLengthOut: &totalLength,
            dataPointerOut: &dataPointer
        )
        guard status == 0, let p = dataPointer else {
            throw NSError(
                domain: "Media.CoreMedia",
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "could not get block buffer data, code: \(status)"]
            )
        }
        return Data(bytes: p, count: totalLength)
    }
}

#if canImport(Metal)
extension CVMetalTextureCache {
    public static func create(metalDevice: any MTLDevice) throws -> CVMetalTextureCache {
        var cache: CVMetalTextureCache?
        let result = CVMetalTextureCacheCreate(
            kCFAllocatorDefault,
            nil,
            metalDevice,
            nil,
            &cache
        )
        guard result == kCVReturnSuccess, let c = cache else {
            throw NSError(
                domain: "Media.CoreVideo",
                code: Int(result),
                userInfo: [NSLocalizedDescriptionKey: "could not create texture cache, code: \(result)"]
            )
        }
        return c
    }

    public func createTextureFromImage(
        source: CVImageBuffer,
        textureAttributes: CFDictionary? = nil,
        pixelFormat: MTLPixelFormat,
        width: Int,
        height: Int,
        planeIndex: Int = 0
    ) throws -> CVMetalTexture {
        var texture: CVMetalTexture?
        let result = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            self,
            source,
            textureAttributes,
            pixelFormat,
            width,
            height,
            planeIndex,
            &texture
        )
        guard result == kCVReturnSuccess, let t = texture else {
            throw NSError(
                domain: "Media.CoreVideo",
                code: Int(result),
                userInfo: [NSLocalizedDescriptionKey: "could not create texture from image, code: \(result)"]
            )
        }
        return t
    }
}

extension CVMetalTexture {
    public func asTexture() -> (any MTLTexture)? {
        CVMetalTextureGetTexture(self)
    }
}
#endif

#else
// Non-Apple fallback stubs
public enum core_media {
    public struct CMSampleBuffer: Sendable {}
    public struct CMFormatDescription: Sendable {}
    public struct CMBlockBuffer: Sendable {}
}

public enum core_video {
    public struct CVImageBuffer: Sendable {}
    public struct CVPixelBuffer: Sendable {}
    public struct CVMetalTextureCache: Sendable {}
    public struct CVMetalTexture: Sendable {}
}
#endif
