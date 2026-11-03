// Ported from: crates/rune/src/gpu/metal/query.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Timestamp `MetalQuerySet` for stage-boundary GPU timing (`MTLCounterSampleBuffer` when
//! supported by the Metal device, with monotonic nanosecond fallback on virtual/simulator devices).

#if canImport(Metal)
import Metal
import QuartzCore
#endif
#if !os(WASI)
import Foundation
#endif

#if canImport(Metal)
public func metalSupportsTimestampQuery(_ device: any MTLDevice) -> Bool {
    guard device.supportsCounterSampling(.atStageBoundary) else { return false }
    guard let sets = device.counterSets else { return false }
    return sets.contains { $0.name == MTLCommonCounterSet.timestamp.rawValue }
}
#endif

/// Timestamp query set storing `count` 64-bit nanosecond ticks.
// PORT NOTE: Synchronized via `lock` (`LiveLock`) and backed by `MTLCounterSampleBuffer` on Apple Silicon GPUs.
public final class MetalQuerySet: @unchecked Sendable {
    public let count: Int
    #if canImport(Metal)
    public let counterBuffer: (any MTLCounterSampleBuffer)?
    #endif
    private let lock = LiveLock()
    private var fallbackTicks: [UInt64]

    public init(shared: MetalShared, count: Int) {
        self.count = max(1, count)
        self.fallbackTicks = [UInt64](repeating: 0, count: max(1, count))
        #if canImport(Metal)
        if let dev = shared.mtlDevice,
           dev.supportsCounterSampling(.atStageBoundary),
           let tsSet = dev.counterSets?.first(where: { $0.name == MTLCommonCounterSet.timestamp.rawValue }) {
            let desc = MTLCounterSampleBufferDescriptor()
            desc.counterSet = tsSet
            desc.storageMode = .shared
            desc.sampleCount = max(1, count)
            self.counterBuffer = try? dev.makeCounterSampleBuffer(descriptor: desc)
        } else {
            self.counterBuffer = nil
        }
        #else
        _ = shared
        #endif
    }

    func recordFallbackTimestamp(at index: Int, nanoseconds: UInt64) {
        lock.withLock {
            if index >= 0 && index < fallbackTicks.count {
                fallbackTicks[index] = nanoseconds
            }
        }
    }

    func readFallbackRange(_ range: Range<Int>) -> [UInt64] {
        lock.withLock {
            let lo = max(0, min(range.lowerBound, fallbackTicks.count))
            let hi = max(lo, min(range.upperBound, fallbackTicks.count))
            return Array(fallbackTicks[lo..<hi])
        }
    }
}

/// Pass boundary timestamp write configuration (`beginningOfPassWriteIndex`, `endOfPassWriteIndex`).
public struct MetalPassTimestampWrites: Sendable {
    public let querySet: MetalQuerySet
    public let beginningIndex: Int?
    public let endIndex: Int?

    public init(querySet: MetalQuerySet, beginningIndex: Int? = nil, endIndex: Int? = nil) {
        self.querySet = querySet
        self.beginningIndex = beginningIndex
        self.endIndex = endIndex
    }
}
