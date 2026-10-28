// Ported from: src/tree/cache.rs
// Upstream commit: 599b1b7d7410d97e13bafc4c01fbe6d7a9cf060a
// Port status: ported

/// The number of cache entries for each node in the tree
@usableFromInline
internal let CACHE_SIZE: Int = 9

/// Cached intermediate layout results
public struct CacheEntry<T: Sendable>: Sendable, Equatable where T: Equatable {
    /// The initial cached size of the node itself
    public var knownDimensions: Size<Float?>
    /// The initial cached size of the parent's node
    public var availableSpace: Size<AvailableSpace>
    /// The cached size and baselines of the item
    public var content: T

    @inlinable
    public init(knownDimensions: Size<Float?>, availableSpace: Size<AvailableSpace>, content: T) {
        self.knownDimensions = knownDimensions
        self.availableSpace = availableSpace
        self.content = content
    }
}

/// Clear operation outcome. See [`Cache.clear`]
public enum ClearState: Sendable, Copyable, Hashable, Equatable {
    /// Cleared some values
    case cleared
    /// Everything was already cleared
    case alreadyEmpty
}

/// A cache for caching the results of a sizing a Grid Item or Flexbox Item
public struct Cache: Sendable, Equatable {
    /// The cache entry for the node's final layout
    public var finalLayoutEntry: CacheEntry<LayoutOutput>?
    /// The cache entries for the node's preliminary size measurements
    public var measureEntries: [CacheEntry<Size<Float>>?]
    /// Tracks if all cache entries are empty
    @usableFromInline
    internal var _isEmpty: Bool

    @inlinable
    public init() {
        self.finalLayoutEntry = nil
        self.measureEntries = [CacheEntry<Size<Float>>?](repeating: nil, count: CACHE_SIZE)
        self._isEmpty = true
    }

    /// Create a new empty cache
    @inlinable
    public static func new() -> Cache {
        Cache()
    }

    /// Return the cache slot to cache the current computed result in
    @inlinable
    public static func computeCacheSlot(knownDimensions: Size<Float?>, availableSpace: Size<AvailableSpace>) -> Int {
        let hasKnownWidth = knownDimensions.width != nil
        let hasKnownHeight = knownDimensions.height != nil

        // Slot 0: Both known_dimensions were set
        if hasKnownWidth && hasKnownHeight {
            return 0
        }

        // Slot 1: width but not height known_dimension was set and the other dimension was either a MaxContent or Definite available space constraint
        // Slot 2: width but not height known_dimension was set and the other dimension was a MinContent constraint
        if hasKnownWidth && !hasKnownHeight {
            return 1 + (availableSpace.height == .minContent ? 1 : 0)
        }

        // Slot 3: height but not width known_dimension was set and the other dimension was either a MaxContent or Definite available space constraint
        // Slot 4: height but not width known_dimension was set and the other dimension was a MinContent constraint
        if hasKnownHeight && !hasKnownWidth {
            return 3 + (availableSpace.width == .minContent ? 1 : 0)
        }

        // Slots 5-8: Neither known_dimensions were set and:
        switch (availableSpace.width, availableSpace.height) {
        // Slot 5: x-axis available space is MaxContent or Definite and y-axis available space is MaxContent or Definite
        case (.maxContent, .maxContent), (.maxContent, .definite), (.definite, .maxContent), (.definite, .definite):
            return 5
        // Slot 6: x-axis available space is MaxContent or Definite and y-axis available space is MinContent
        case (.maxContent, .minContent), (.definite, .minContent):
            return 6
        // Slot 7: x-axis available space is MinContent and y-axis available space is MaxContent or Definite
        case (.minContent, .maxContent), (.minContent, .definite):
            return 7
        // Slot 8: x-axis available space is MinContent and y-axis available space is MinContent
        case (.minContent, .minContent):
            return 8
        }
    }

    /// Try to retrieve a cached result from the cache
    @inlinable
    public func get(
        knownDimensions: Size<Float?>,
        availableSpace: Size<AvailableSpace>,
        runMode: RunMode
    ) -> LayoutOutput? {
        switch runMode {
        case .performLayout:
            guard let entry = finalLayoutEntry else { return nil }
            let cachedSize = entry.content.size
            let widthMatches = (knownDimensions.width == entry.knownDimensions.width || knownDimensions.width == cachedSize.width)
            let heightMatches = (knownDimensions.height == entry.knownDimensions.height || knownDimensions.height == cachedSize.height)
            let widthSpaceMatches = (knownDimensions.width != nil || entry.availableSpace.width.isRoughlyEqual(to: availableSpace.width))
            let heightSpaceMatches = (knownDimensions.height != nil || entry.availableSpace.height.isRoughlyEqual(to: availableSpace.height))

            if widthMatches && heightMatches && widthSpaceMatches && heightSpaceMatches {
                return entry.content
            }
            return nil

        case .computeSize:
            for entryOpt in measureEntries {
                guard let entry = entryOpt else { continue }
                let cachedSize = entry.content
                let widthMatches = (knownDimensions.width == entry.knownDimensions.width || knownDimensions.width == cachedSize.width)
                let heightMatches = (knownDimensions.height == entry.knownDimensions.height || knownDimensions.height == cachedSize.height)
                let widthSpaceMatches = (knownDimensions.width != nil || entry.availableSpace.width.isRoughlyEqual(to: availableSpace.width))
                let heightSpaceMatches = (knownDimensions.height != nil || entry.availableSpace.height.isRoughlyEqual(to: availableSpace.height))

                if widthMatches && heightMatches && widthSpaceMatches && heightSpaceMatches {
                    return LayoutOutput.fromOuterSize(cachedSize)
                }
            }
            return nil

        case .performHiddenLayout:
            return nil
        }
    }

    /// Store a computed size in the cache
    @inlinable
    public mutating func store(
        knownDimensions: Size<Float?>,
        availableSpace: Size<AvailableSpace>,
        runMode: RunMode,
        layoutOutput: LayoutOutput
    ) {
        switch runMode {
        case .performLayout:
            self._isEmpty = false
            self.finalLayoutEntry = CacheEntry(
                knownDimensions: knownDimensions,
                availableSpace: availableSpace,
                content: layoutOutput
            )
        case .computeSize:
            self._isEmpty = false
            let slot = Self.computeCacheSlot(knownDimensions: knownDimensions, availableSpace: availableSpace)
            self.measureEntries[slot] = CacheEntry(
                knownDimensions: knownDimensions,
                availableSpace: availableSpace,
                content: layoutOutput.size
            )
        case .performHiddenLayout:
            break
        }
    }

    /// Clear all cache entries and reports clear operation outcome ([`ClearState`])
    @inlinable
    public mutating func clear() -> ClearState {
        if _isEmpty {
            return .alreadyEmpty
        }
        self._isEmpty = true
        self.finalLayoutEntry = nil
        self.measureEntries = [CacheEntry<Size<Float>>?](repeating: nil, count: CACHE_SIZE)
        return .cleared
    }

    /// Returns true if all cache entries are None, else false
    @inlinable
    public var isEmpty: Bool {
        finalLayoutEntry == nil && !measureEntries.contains(where: { $0 != nil })
    }
}
