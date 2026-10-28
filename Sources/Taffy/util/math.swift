// Ported from: src/util/math.rs
// Upstream commit: 599b1b7d7410d97e13bafc4c01fbe6d7a9cf060a
// Port status: ported

// PORT NOTE: MaybeMath methods implemented as concrete type extensions in Swift
// to support multiple In/Out types cleanly without Rust's multi-dispatch trait collision.

extension Optional where Wrapped == Float {
    @inlinable
    public func maybeMin(_ rhs: Float?) -> Float? {
        switch (self, rhs) {
        case let (l?, r?): return Swift.min(l, r)
        case (let l?, nil): return l
        case (nil, _): return nil
        }
    }

    @inlinable
    public func maybeMin(_ rhs: Float) -> Float? {
        self.map { Swift.min($0, rhs) }
    }

    @inlinable
    public func maybeMax(_ rhs: Float?) -> Float? {
        switch (self, rhs) {
        case let (l?, r?): return Swift.max(l, r)
        case (let l?, nil): return l
        case (nil, _): return nil
        }
    }

    @inlinable
    public func maybeMax(_ rhs: Float) -> Float? {
        self.map { Swift.max($0, rhs) }
    }

    @inlinable
    public func maybeClamp(min: Float?, max: Float?) -> Float? {
        switch (self, min, max) {
        case let (base?, minVal?, maxVal?):
            return Swift.max(minVal, Swift.min(maxVal, base))
        case let (base?, nil, maxVal?):
            return Swift.min(maxVal, base)
        case let (base?, minVal?, nil):
            return Swift.max(minVal, base)
        case (let base?, nil, nil):
            return base
        case (nil, _, _):
            return nil
        }
    }

    @inlinable
    public func maybeClamp(min: Float, max: Float) -> Float? {
        self.map { Swift.max(min, Swift.min(max, $0)) }
    }

    @inlinable
    public func maybeClamp(_ min: Float?, _ max: Float?) -> Float? {
        maybeClamp(min: min, max: max)
    }

    @inlinable
    public func maybeClamp(_ min: Float, _ max: Float) -> Float? {
        maybeClamp(min: min, max: max)
    }

    @inlinable
    public func maybeAdd(_ rhs: Float?) -> Float? {
        switch (self, rhs) {
        case let (l?, r?): return l + r
        case (let l?, nil): return l
        case (nil, _): return nil
        }
    }

    @inlinable
    public func maybeAdd(_ rhs: Float) -> Float? {
        self.map { $0 + rhs }
    }

    @inlinable
    public func maybeSub(_ rhs: Float?) -> Float? {
        switch (self, rhs) {
        case let (l?, r?): return l - r
        case (let l?, nil): return l
        case (nil, _): return nil
        }
    }

    @inlinable
    public func maybeSub(_ rhs: Float) -> Float? {
        self.map { $0 - rhs }
    }
}

extension Float {
    @inlinable
    public func maybeMin(_ rhs: Float?) -> Float {
        guard let r = rhs else { return self }
        return Swift.min(self, r)
    }

    @inlinable
    public func maybeMax(_ rhs: Float?) -> Float {
        guard let r = rhs else { return self }
        return Swift.max(self, r)
    }

    @inlinable
    public func maybeClamp(min: Float?, max: Float?) -> Float {
        switch (min, max) {
        case let (minVal?, maxVal?):
            return Swift.max(minVal, Swift.min(maxVal, self))
        case let (nil, maxVal?):
            return Swift.min(maxVal, self)
        case let (minVal?, nil):
            return Swift.max(minVal, self)
        case (nil, nil):
            return self
        }
    }

    @inlinable
    public func maybeClamp(_ min: Float?, _ max: Float?) -> Float {
        maybeClamp(min: min, max: max)
    }

    @inlinable
    public func maybeAdd(_ rhs: Float?) -> Float {
        guard let r = rhs else { return self }
        return self + r
    }

    @inlinable
    public func maybeSub(_ rhs: Float?) -> Float {
        guard let r = rhs else { return self }
        return self - r
    }
}

extension AvailableSpace {
    @inlinable
    public func maybeMin(_ rhs: Float) -> AvailableSpace {
        switch self {
        case .definite(let val): return .definite(Swift.min(val, rhs))
        case .minContent, .maxContent: return .definite(rhs)
        }
    }

    @inlinable
    public func maybeMin(_ rhs: Float?) -> AvailableSpace {
        guard let r = rhs else { return self }
        return maybeMin(r)
    }

    @inlinable
    public func maybeMax(_ rhs: Float) -> AvailableSpace {
        switch self {
        case .definite(let val): return .definite(Swift.max(val, rhs))
        case .minContent: return .minContent
        case .maxContent: return .maxContent
        }
    }

    @inlinable
    public func maybeMax(_ rhs: Float?) -> AvailableSpace {
        switch (self, rhs) {
        case let (.definite(val), r?): return .definite(Swift.max(val, r))
        case (.definite(let val), nil): return .definite(val)
        case (.minContent, _): return .minContent
        case (.maxContent, _): return .maxContent
        }
    }

    @inlinable
    public func maybeClamp(min: Float, max: Float) -> AvailableSpace {
        switch self {
        case .definite(let val): return .definite(Swift.max(min, Swift.min(max, val)))
        case .minContent: return .minContent
        case .maxContent: return .maxContent
        }
    }

    @inlinable
    public func maybeClamp(min: Float?, max: Float?) -> AvailableSpace {
        switch (self, min, max) {
        case let (.definite(val), minVal?, maxVal?):
            return .definite(Swift.max(minVal, Swift.min(maxVal, val)))
        case let (.definite(val), nil, maxVal?):
            return .definite(Swift.min(maxVal, val))
        case let (.definite(val), minVal?, nil):
            return .definite(Swift.max(minVal, val))
        case (.definite(let val), nil, nil):
            return .definite(val)
        case (.minContent, _, _):
            return .minContent
        case (.maxContent, _, _):
            return .maxContent
        }
    }

    @inlinable
    public func maybeClamp(_ min: Float, _ max: Float) -> AvailableSpace {
        maybeClamp(min: min, max: max)
    }

    @inlinable
    public func maybeClamp(_ min: Float?, _ max: Float?) -> AvailableSpace {
        maybeClamp(min: min, max: max)
    }

    @inlinable
    public func maybeAdd(_ rhs: Float) -> AvailableSpace {
        switch self {
        case .definite(let val): return .definite(val + rhs)
        case .minContent: return .minContent
        case .maxContent: return .maxContent
        }
    }

    @inlinable
    public func maybeAdd(_ rhs: Float?) -> AvailableSpace {
        switch (self, rhs) {
        case let (.definite(val), r?): return .definite(val + r)
        case (.definite(let val), nil): return .definite(val)
        case (.minContent, _): return .minContent
        case (.maxContent, _): return .maxContent
        }
    }

    @inlinable
    public func maybeSub(_ rhs: Float) -> AvailableSpace {
        switch self {
        case .definite(let val): return .definite(val - rhs)
        case .minContent: return .minContent
        case .maxContent: return .maxContent
        }
    }

    @inlinable
    public func maybeSub(_ rhs: Float?) -> AvailableSpace {
        switch (self, rhs) {
        case let (.definite(val), r?): return .definite(val - r)
        case (.definite(let val), nil): return .definite(val)
        case (.minContent, _): return .minContent
        case (.maxContent, _): return .maxContent
        }
    }
}

extension Size where T == Float? {
    @inlinable
    public func maybeMin(_ rhs: Size<Float?>) -> Size<Float?> {
        Size<Float?>(width: width.maybeMin(rhs.width), height: height.maybeMin(rhs.height))
    }

    @inlinable
    public func maybeMin(_ rhs: Size<Float>) -> Size<Float?> {
        Size<Float?>(width: width.maybeMin(rhs.width), height: height.maybeMin(rhs.height))
    }

    @inlinable
    public func maybeMax(_ rhs: Size<Float?>) -> Size<Float?> {
        Size<Float?>(width: width.maybeMax(rhs.width), height: height.maybeMax(rhs.height))
    }

    @inlinable
    public func maybeMax(_ rhs: Size<Float>) -> Size<Float?> {
        Size<Float?>(width: width.maybeMax(rhs.width), height: height.maybeMax(rhs.height))
    }

    @inlinable
    public func maybeClamp(min: Size<Float?>, max: Size<Float?>) -> Size<Float?> {
        Size<Float?>(
            width: width.maybeClamp(min: min.width, max: max.width),
            height: height.maybeClamp(min: min.height, max: max.height)
        )
    }

    @inlinable
    public func maybeClamp(min: Size<Float>, max: Size<Float>) -> Size<Float?> {
        Size<Float?>(
            width: width.maybeClamp(min: min.width, max: max.width),
            height: height.maybeClamp(min: min.height, max: max.height)
        )
    }

    @inlinable
    public func maybeClamp(_ min: Size<Float?>, _ max: Size<Float?>) -> Size<Float?> {
        maybeClamp(min: min, max: max)
    }

    @inlinable
    public func maybeClamp(_ min: Size<Float>, _ max: Size<Float>) -> Size<Float?> {
        maybeClamp(min: min, max: max)
    }

    @inlinable
    public func maybeAdd(_ rhs: Size<Float?>) -> Size<Float?> {
        Size<Float?>(width: width.maybeAdd(rhs.width), height: height.maybeAdd(rhs.height))
    }

    @inlinable
    public func maybeAdd(_ rhs: Size<Float>) -> Size<Float?> {
        Size<Float?>(width: width.maybeAdd(rhs.width), height: height.maybeAdd(rhs.height))
    }

    @inlinable
    public func maybeSub(_ rhs: Size<Float?>) -> Size<Float?> {
        Size<Float?>(width: width.maybeSub(rhs.width), height: height.maybeSub(rhs.height))
    }

    @inlinable
    public func maybeSub(_ rhs: Size<Float>) -> Size<Float?> {
        Size<Float?>(width: width.maybeSub(rhs.width), height: height.maybeSub(rhs.height))
    }
}

extension Size where T == Float {
    @inlinable
    public func maybeMin(_ rhs: Size<Float?>) -> Size<Float> {
        Size<Float>(width: width.maybeMin(rhs.width), height: height.maybeMin(rhs.height))
    }

    @inlinable
    public func maybeMax(_ rhs: Size<Float?>) -> Size<Float> {
        Size<Float>(width: width.maybeMax(rhs.width), height: height.maybeMax(rhs.height))
    }

    @inlinable
    public func maybeClamp(min: Size<Float?>, max: Size<Float?>) -> Size<Float> {
        Size<Float>(
            width: width.maybeClamp(min: min.width, max: max.width),
            height: height.maybeClamp(min: min.height, max: max.height)
        )
    }

    @inlinable
    public func maybeClamp(_ min: Size<Float?>, _ max: Size<Float?>) -> Size<Float> {
        maybeClamp(min: min, max: max)
    }

    @inlinable
    public func maybeAdd(_ rhs: Size<Float?>) -> Size<Float> {
        Size<Float>(width: width.maybeAdd(rhs.width), height: height.maybeAdd(rhs.height))
    }

    @inlinable
    public func maybeSub(_ rhs: Size<Float?>) -> Size<Float> {
        Size<Float>(width: width.maybeSub(rhs.width), height: height.maybeSub(rhs.height))
    }
}

extension Size where T == AvailableSpace {
    @inlinable
    public func maybeMin(_ rhs: Size<Float>) -> Size<AvailableSpace> {
        Size<AvailableSpace>(width: width.maybeMin(rhs.width), height: height.maybeMin(rhs.height))
    }

    @inlinable
    public func maybeMin(_ rhs: Size<Float?>) -> Size<AvailableSpace> {
        Size<AvailableSpace>(width: width.maybeMin(rhs.width), height: height.maybeMin(rhs.height))
    }

    @inlinable
    public func maybeMax(_ rhs: Size<Float>) -> Size<AvailableSpace> {
        Size<AvailableSpace>(width: width.maybeMax(rhs.width), height: height.maybeMax(rhs.height))
    }

    @inlinable
    public func maybeMax(_ rhs: Size<Float?>) -> Size<AvailableSpace> {
        Size<AvailableSpace>(width: width.maybeMax(rhs.width), height: height.maybeMax(rhs.height))
    }

    @inlinable
    public func maybeClamp(min: Size<Float>, max: Size<Float>) -> Size<AvailableSpace> {
        Size<AvailableSpace>(
            width: width.maybeClamp(min: min.width, max: max.width),
            height: height.maybeClamp(min: min.height, max: max.height)
        )
    }

    @inlinable
    public func maybeClamp(min: Size<Float?>, max: Size<Float?>) -> Size<AvailableSpace> {
        Size<AvailableSpace>(
            width: width.maybeClamp(min: min.width, max: max.width),
            height: height.maybeClamp(min: min.height, max: max.height)
        )
    }

    @inlinable
    public func maybeClamp(_ min: Size<Float>, _ max: Size<Float>) -> Size<AvailableSpace> {
        maybeClamp(min: min, max: max)
    }

    @inlinable
    public func maybeClamp(_ min: Size<Float?>, _ max: Size<Float?>) -> Size<AvailableSpace> {
        maybeClamp(min: min, max: max)
    }

    @inlinable
    public func maybeAdd(_ rhs: Size<Float>) -> Size<AvailableSpace> {
        Size<AvailableSpace>(width: width.maybeAdd(rhs.width), height: height.maybeAdd(rhs.height))
    }

    @inlinable
    public func maybeAdd(_ rhs: Size<Float?>) -> Size<AvailableSpace> {
        Size<AvailableSpace>(width: width.maybeAdd(rhs.width), height: height.maybeAdd(rhs.height))
    }

    @inlinable
    public func maybeSub(_ rhs: Size<Float>) -> Size<AvailableSpace> {
        Size<AvailableSpace>(width: width.maybeSub(rhs.width), height: height.maybeSub(rhs.height))
    }

    @inlinable
    public func maybeSub(_ rhs: Size<Float?>) -> Size<AvailableSpace> {
        Size<AvailableSpace>(width: width.maybeSub(rhs.width), height: height.maybeSub(rhs.height))
    }
}
