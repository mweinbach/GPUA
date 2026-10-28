// Ported from: src/util/resolve.rs
// Upstream commit: 599b1b7d7410d97e13bafc4c01fbe6d7a9cf060a
// Port status: ported

/// Trait to encapsulate behaviour where we need to resolve from a
/// potentially context-dependent size or dimension into
/// a context-independent size or dimension.
///
/// Will return `nil` if unable to resolve.
public protocol MaybeResolve {
    associatedtype Context
    associatedtype Resolved

    /// Resolve a dimension that might be dependent on a context, with `nil` as fallback value
    func maybeResolve(_ context: Context, _ calc: (UnsafeRawPointer?, Float) -> Float) -> Resolved
}

/// Trait to encapsulate behaviour where we need to resolve from a
/// potentially context-dependent size or dimension into
/// a context-independent size or dimension.
///
/// Will return a default value if unable to resolve.
public protocol ResolveOrZero {
    associatedtype Context
    associatedtype ZeroValue: TaffyZero

    /// Resolve a dimension that might be dependent on a context, with a default fallback value
    func resolveOrZero(_ context: Context, _ calc: (UnsafeRawPointer?, Float) -> Float) -> ZeroValue
}

// MARK: - LengthPercentage

extension LengthPercentage: MaybeResolve {
    public typealias Context = Float?
    public typealias Resolved = Float?

    @inlinable
    public func maybeResolve(_ context: Float?, _ calc: (UnsafeRawPointer?, Float) -> Float = { _, _ in 0.0 }) -> Float? {
        switch self.value {
        case .length(let v):
            return v
        case .percent(let p):
            return context.map { $0 * p }
        default:
            return nil
        }
    }

    @inlinable
    public func maybeResolve(_ context: Float, _ calc: (UnsafeRawPointer?, Float) -> Float = { _, _ in 0.0 }) -> Float? {
        maybeResolve(.some(context), calc)
    }
}

extension LengthPercentage: ResolveOrZero {
    public typealias ZeroValue = Float

    @inlinable
    public func resolveOrZero(_ context: Float?, _ calc: (UnsafeRawPointer?, Float) -> Float = { _, _ in 0.0 }) -> Float {
        maybeResolve(context, calc) ?? 0.0
    }

    @inlinable
    public func resolveOrZero(_ context: Float, _ calc: (UnsafeRawPointer?, Float) -> Float = { _, _ in 0.0 }) -> Float {
        resolveOrZero(.some(context), calc)
    }
}

// MARK: - LengthPercentageAuto

extension LengthPercentageAuto: MaybeResolve {
    public typealias Context = Float?
    public typealias Resolved = Float?

    @inlinable
    public func maybeResolve(_ context: Float?, _ calc: (UnsafeRawPointer?, Float) -> Float = { _, _ in 0.0 }) -> Float? {
        switch self.value {
        case .auto:
            return nil
        case .length(let v):
            return v
        case .percent(let p):
            return context.map { $0 * p }
        default:
            return nil
        }
    }

    @inlinable
    public func maybeResolve(_ context: Float, _ calc: (UnsafeRawPointer?, Float) -> Float = { _, _ in 0.0 }) -> Float? {
        maybeResolve(.some(context), calc)
    }
}

extension LengthPercentageAuto: ResolveOrZero {
    public typealias ZeroValue = Float

    @inlinable
    public func resolveOrZero(_ context: Float?, _ calc: (UnsafeRawPointer?, Float) -> Float = { _, _ in 0.0 }) -> Float {
        maybeResolve(context, calc) ?? 0.0
    }

    @inlinable
    public func resolveOrZero(_ context: Float, _ calc: (UnsafeRawPointer?, Float) -> Float = { _, _ in 0.0 }) -> Float {
        resolveOrZero(.some(context), calc)
    }
}

// MARK: - Dimension

extension Dimension: MaybeResolve {
    public typealias Context = Float?
    public typealias Resolved = Float?

    @inlinable
    public func maybeResolve(_ context: Float?, _ calc: (UnsafeRawPointer?, Float) -> Float = { _, _ in 0.0 }) -> Float? {
        switch self.value {
        case .auto, .minContent, .maxContent, .fitContentPx, .fitContentPercent, .fr:
            return nil
        case .length(let v):
            return v
        case .percent(let p):
            return context.map { $0 * p }
        }
    }

    @inlinable
    public func maybeResolve(_ context: Float, _ calc: (UnsafeRawPointer?, Float) -> Float = { _, _ in 0.0 }) -> Float? {
        maybeResolve(.some(context), calc)
    }
}

extension Dimension: ResolveOrZero {
    public typealias ZeroValue = Float

    @inlinable
    public func resolveOrZero(_ context: Float?, _ calc: (UnsafeRawPointer?, Float) -> Float = { _, _ in 0.0 }) -> Float {
        maybeResolve(context, calc) ?? 0.0
    }

    @inlinable
    public func resolveOrZero(_ context: Float, _ calc: (UnsafeRawPointer?, Float) -> Float = { _, _ in 0.0 }) -> Float {
        resolveOrZero(.some(context), calc)
    }
}

// MARK: - Size Extensions

extension Size where T: MaybeResolve, T.Context == Float?, T.Resolved == Float? {
    @inlinable
    public func maybeResolve(_ context: Size<Float?>, _ calc: (UnsafeRawPointer?, Float) -> Float = { _, _ in 0.0 }) -> Size<Float?> {
        Size<Float?>(
            width: self.width.maybeResolve(context.width, calc),
            height: self.height.maybeResolve(context.height, calc)
        )
    }

    @inlinable
    public func maybeResolve(_ context: Size<Float>, _ calc: (UnsafeRawPointer?, Float) -> Float = { _, _ in 0.0 }) -> Size<Float?> {
        maybeResolve(Size<Float?>(width: context.width, height: context.height), calc)
    }
}

extension Size where T: ResolveOrZero, T.Context == Float?, T.ZeroValue == Float {
    @inlinable
    public func resolveOrZero(_ context: Size<Float?>, _ calc: (UnsafeRawPointer?, Float) -> Float = { _, _ in 0.0 }) -> Size<Float> {
        Size<Float>(
            width: self.width.resolveOrZero(context.width, calc),
            height: self.height.resolveOrZero(context.height, calc)
        )
    }

    @inlinable
    public func resolveOrZero(_ context: Size<Float>, _ calc: (UnsafeRawPointer?, Float) -> Float = { _, _ in 0.0 }) -> Size<Float> {
        resolveOrZero(Size<Float?>(width: context.width, height: context.height), calc)
    }

    @inlinable
    public func resolveOrZero(_ context: Float?, _ calc: (UnsafeRawPointer?, Float) -> Float = { _, _ in 0.0 }) -> Size<Float> {
        resolveOrZero(Size<Float?>(width: context, height: context), calc)
    }

    @inlinable
    public func resolveOrZero(_ context: Float, _ calc: (UnsafeRawPointer?, Float) -> Float = { _, _ in 0.0 }) -> Size<Float> {
        resolveOrZero(Size<Float?>(width: context, height: context), calc)
    }
}

// MARK: - Rect Extensions

extension Rect where T: MaybeResolve, T.Context == Float?, T.Resolved == Float? {
    @inlinable
    public func maybeResolve(_ context: Float?, _ calc: (UnsafeRawPointer?, Float) -> Float = { _, _ in 0.0 }) -> Rect<Float?> {
        Rect<Float?>(
            left: self.left.maybeResolve(context, calc),
            right: self.right.maybeResolve(context, calc),
            top: self.top.maybeResolve(context, calc),
            bottom: self.bottom.maybeResolve(context, calc)
        )
    }

    @inlinable
    public func maybeResolve(_ context: Float, _ calc: (UnsafeRawPointer?, Float) -> Float = { _, _ in 0.0 }) -> Rect<Float?> {
        maybeResolve(.some(context), calc)
    }

    @inlinable
    public func maybeResolve(_ context: Size<Float?>, _ calc: (UnsafeRawPointer?, Float) -> Float = { _, _ in 0.0 }) -> Rect<Float?> {
        Rect<Float?>(
            left: self.left.maybeResolve(context.width, calc),
            right: self.right.maybeResolve(context.width, calc),
            top: self.top.maybeResolve(context.height, calc),
            bottom: self.bottom.maybeResolve(context.height, calc)
        )
    }

    @inlinable
    public func maybeResolve(_ context: Size<Float>, _ calc: (UnsafeRawPointer?, Float) -> Float = { _, _ in 0.0 }) -> Rect<Float?> {
        maybeResolve(Size<Float?>(width: context.width, height: context.height), calc)
    }
}

extension Rect where T: ResolveOrZero, T.Context == Float?, T.ZeroValue == Float {
    @inlinable
    public func resolveOrZero(_ context: Float?, _ calc: (UnsafeRawPointer?, Float) -> Float = { _, _ in 0.0 }) -> Rect<Float> {
        Rect<Float>(
            left: self.left.resolveOrZero(context, calc),
            right: self.right.resolveOrZero(context, calc),
            top: self.top.resolveOrZero(context, calc),
            bottom: self.bottom.resolveOrZero(context, calc)
        )
    }

    @inlinable
    public func resolveOrZero(_ context: Float, _ calc: (UnsafeRawPointer?, Float) -> Float = { _, _ in 0.0 }) -> Rect<Float> {
        resolveOrZero(.some(context), calc)
    }

    @inlinable
    public func resolveOrZero(_ context: Size<Float?>, _ calc: (UnsafeRawPointer?, Float) -> Float = { _, _ in 0.0 }) -> Rect<Float> {
        Rect<Float>(
            left: self.left.resolveOrZero(context.width, calc),
            right: self.right.resolveOrZero(context.width, calc),
            top: self.top.resolveOrZero(context.height, calc),
            bottom: self.bottom.resolveOrZero(context.height, calc)
        )
    }

    @inlinable
    public func resolveOrZero(_ context: Size<Float>, _ calc: (UnsafeRawPointer?, Float) -> Float = { _, _ in 0.0 }) -> Rect<Float> {
        resolveOrZero(Size<Float?>(width: context.width, height: context.height), calc)
    }
}

// MARK: - Line Extensions

extension Line where T: ResolveOrZero, T.Context == Float?, T.ZeroValue == Float {
    @inlinable
    public func resolveOrZero(_ context: Float?, _ calc: (UnsafeRawPointer?, Float) -> Float = { _, _ in 0.0 }) -> Line<Float> {
        Line<Float>(
            start: self.start.resolveOrZero(context, calc),
            end: self.end.resolveOrZero(context, calc)
        )
    }

    @inlinable
    public func resolveOrZero(_ context: Float, _ calc: (UnsafeRawPointer?, Float) -> Float = { _, _ in 0.0 }) -> Line<Float> {
        resolveOrZero(.some(context), calc)
    }
}
