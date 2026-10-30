// Ported from: crates/gpui_metal/src/atlas.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if canImport(Metal)
import Foundation
import GPUI
import GPUICollections
import Metal

// MARK: - Error Types

/// Errors thrown by `MetalAtlas` during tile allocation or upload.
public enum MetalAtlasError: Error, LocalizedError, Sendable {
    case allocationFailed(Size<DevicePixels>, AtlasTextureKind)
    case textureCreationFailed(Size<DevicePixels>, AtlasTextureKind)
    case missingTexture(AtlasTextureId)

    public var errorDescription: String? {
        switch self {
        case .allocationFailed(let size, let kind):
            return "Failed to allocate atlas tile of size \(size) for kind \(kind)"
        case .textureCreationFailed(let size, let kind):
            return "Failed to create Metal atlas texture of size \(size) for kind \(kind)"
        case .missingTexture(let id):
            return "Missing Metal atlas texture for id \(id)"
        }
    }
}

// MARK: - Bucketed Shelf Atlas Allocator

// PORT NOTE: Replaces Rust `etagere::BucketedAtlasAllocator` with an idiomatic Swift 2D bucketed
// shelf bin-packer matching upstream shelf packing, quantized shelf heights, and tile ID assignment.
struct BucketedAtlasAllocator: Sendable {
    struct Shelf: Sendable {
        var y: Int32
        var height: Int32
        var currentX: Int32
    }

    let size: Size<DevicePixels>
    private var shelves: [Shelf] = []
    private var nextTileId: UInt32 = 1

    init(size: Size<DevicePixels>) {
        self.size = size
    }

    mutating func allocate(_ requestedSize: Size<DevicePixels>) -> (tileId: TileId, origin: Point<DevicePixels>)? {
        let reqW = requestedSize.width.value
        let reqH = requestedSize.height.value
        let sheetW = size.width.value
        let sheetH = size.height.value

        guard reqW > 0, reqH > 0, reqW <= sheetW, reqH <= sheetH else {
            return nil
        }

        // Align horizontal cursor advances to 4 pixels when space permits to reduce cache-line splits,
        // falling back to exact fit at the right edge of a shelf.
        let alignedW: Int32 = ((reqW + 3) & ~3)

        // 1. Find an existing shelf that minimizes vertical waste.
        var bestShelfIndex: Int?
        var minWaste = Int32.max

        for (index, shelf) in shelves.enumerated() {
            let remainingW = sheetW - shelf.currentX
            if shelf.height >= reqH && remainingW >= reqW {
                let waste = shelf.height - reqH
                if waste < minWaste {
                    minWaste = waste
                    bestShelfIndex = index
                    if waste == 0 {
                        break
                    }
                }
            }
        }

        if let index = bestShelfIndex {
            let originX = shelves[index].currentX
            let originY = shelves[index].y
            let advanceX = (sheetW - originX >= alignedW) ? alignedW : reqW
            shelves[index].currentX += advanceX

            let id = TileId(nextTileId)
            nextTileId &+= 1
            return (id, Point(x: DevicePixels(originX), y: DevicePixels(originY)))
        }

        // 2. Open a new shelf at the bottom of the texture sheet if vertical space permits.
        let nextShelfY = shelves.last.map { $0.y + $0.height } ?? 0
        let remainingH = sheetH - nextShelfY
        guard remainingH >= reqH else {
            return nil
        }

        let quantizedH: Int32
        if reqH <= 64 {
            quantizedH = (reqH + 7) & ~7
        } else if reqH <= 256 {
            quantizedH = (reqH + 15) & ~15
        } else {
            quantizedH = reqH
        }
        let shelfH = Swift.min(Swift.max(reqH, quantizedH), remainingH)
        let advanceX = (sheetW >= alignedW) ? alignedW : reqW

        shelves.append(Shelf(y: nextShelfY, height: shelfH, currentX: advanceX))

        let id = TileId(nextTileId)
        nextTileId &+= 1
        return (id, Point(x: DevicePixels(0), y: DevicePixels(nextShelfY)))
    }
}

// MARK: - MetalAtlasTexture

// PORT NOTE: MetalAtlasTexture wraps an MTLTexture and mutable shelf allocator, accessed exclusively
// while holding MetalAtlas's NSLock (matching upstream `Mutex<MetalAtlasState>` + `AssertSend`).
final class MetalAtlasTexture: @unchecked Sendable {
    let id: AtlasTextureId
    var allocator: BucketedAtlasAllocator
    let metalTexture: any MTLTexture
    var liveAtlasKeys: UInt32

    init(
        id: AtlasTextureId,
        allocator: BucketedAtlasAllocator,
        metalTexture: any MTLTexture,
        liveAtlasKeys: UInt32 = 0
    ) {
        self.id = id
        self.allocator = allocator
        self.metalTexture = metalTexture
        self.liveAtlasKeys = liveAtlasKeys
    }

    func allocate(_ size: Size<DevicePixels>) -> AtlasTile? {
        guard let allocation = allocator.allocate(size) else {
            return nil
        }
        liveAtlasKeys += 1
        return AtlasTile(
            textureId: id,
            tileId: allocation.tileId,
            padding: 0,
            bounds: Bounds(origin: allocation.origin, size: size)
        )
    }

    func upload(bounds: Bounds<DevicePixels>, bytes: Data) {
        let width = Int(bounds.size.width.value)
        let height = Int(bounds.size.height.value)
        guard width > 0, height > 0 else { return }

        let bpp = bytesPerPixel()
        let bytesPerRow = Int(bounds.size.width.toBytes(bytesPerPixel: bpp))
        let requiredBytes = bytesPerRow * height
        guard bytes.count >= requiredBytes else { return }

        let region = MTLRegionMake2D(
            Int(bounds.origin.x.value),
            Int(bounds.origin.y.value),
            width,
            height
        )
        bytes.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            metalTexture.replace(
                region: region,
                mipmapLevel: 0,
                withBytes: baseAddress,
                bytesPerRow: bytesPerRow
            )
        }
    }

    func bytesPerPixel() -> UInt8 {
        switch metalTexture.pixelFormat {
        case .a8Unorm, .r8Unorm:
            return 1
        case .rgba8Unorm, .bgra8Unorm:
            return 4
        default:
            return 4
        }
    }

    func decrementRefCount() {
        if liveAtlasKeys > 0 {
            liveAtlasKeys -= 1
        }
    }

    var isUnreferenced: Bool {
        liveAtlasKeys == 0
    }
}

// MARK: - MetalAtlasState

private struct MetalAtlasState {
    static let defaultAtlasSize = Size(width: DevicePixels(1024), height: DevicePixels(1024))
    // Max texture size on all modern Apple GPUs. Anything bigger crashes in validateWithDevice.
    static let maxAtlasSize = Size(width: DevicePixels(16384), height: DevicePixels(16384))

    let device: any MTLDevice
    let isAppleGpu: Bool
    var monochromeTextures = AtlasTextureList<MetalAtlasTexture>()
    var polychromeTextures = AtlasTextureList<MetalAtlasTexture>()
    var subpixelTextures = AtlasTextureList<MetalAtlasTexture>()
    var tilesByKey: [AtlasKey: AtlasTile] = [:]

    mutating func textureList<R>(
        for kind: AtlasTextureKind,
        _ body: (inout AtlasTextureList<MetalAtlasTexture>) throws -> R
    ) rethrows -> R {
        switch kind {
        case .monochrome:
            return try body(&monochromeTextures)
        case .polychrome:
            return try body(&polychromeTextures)
        case .subpixel:
            // PORT NOTE: Metal does not use LCD subpixel atlas sheets on Apple displays,
            // but we maintain a BGRA8Unorm list so `.subpixel` keys degrade gracefully without crashing.
            return try body(&subpixelTextures)
        }
    }

    func texture(_ id: AtlasTextureId) -> MetalAtlasTexture? {
        let list: AtlasTextureList<MetalAtlasTexture>
        switch id.kind {
        case .monochrome:
            list = monochromeTextures
        case .polychrome:
            list = polychromeTextures
        case .subpixel:
            list = subpixelTextures
        }
        let index = Int(id.index)
        guard index >= 0 && index < list.textures.count else {
            return nil
        }
        return list.textures[index]
    }

    mutating func allocate(
        size: Size<DevicePixels>,
        textureKind: AtlasTextureKind
    ) throws -> AtlasTile? {
        guard size.width.value > 0 && size.height.value > 0 else {
            return nil
        }

        let existingTile: AtlasTile? = textureList(for: textureKind) { textures in
            for idx in stride(from: textures.textures.count - 1, through: 0, by: -1) {
                if let texture = textures.textures[idx], let tile = texture.allocate(size) {
                    return tile
                }
            }
            return nil
        }

        if let existingTile {
            return existingTile
        }

        let newTexture = try pushTexture(minSize: size, kind: textureKind)
        return newTexture.allocate(size)
    }

    mutating func pushTexture(
        minSize: Size<DevicePixels>,
        kind: AtlasTextureKind
    ) throws -> MetalAtlasTexture {
        let clampedSize = minSize.min(Self.maxAtlasSize).max(Self.defaultAtlasSize)

        let descriptor = MTLTextureDescriptor()
        descriptor.width = Int(clampedSize.width.value)
        descriptor.height = Int(clampedSize.height.value)

        switch kind {
        case .monochrome:
            descriptor.pixelFormat = .a8Unorm
            descriptor.usage = .shaderRead
        case .polychrome, .subpixel:
            descriptor.pixelFormat = .bgra8Unorm
            descriptor.usage = .shaderRead
        }

        // Shared memory mode can be used on Apple GPU families (and is the only CPU-accessible
        // texture storage mode on iOS/visionOS). On Intel/AMD macOS GPUs, use `.managed`.
        #if os(macOS)
        descriptor.storageMode = isAppleGpu ? .shared : .managed
        #else
        descriptor.storageMode = .shared
        #endif

        guard let metalTexture = device.makeTexture(descriptor: descriptor) else {
            throw MetalAtlasError.textureCreationFailed(clampedSize, kind)
        }

        return textureList(for: kind) { list in
            let reusedIndex = list.freeList.popLast()
            let textureIndex = reusedIndex ?? list.textures.count

            let atlasTexture = MetalAtlasTexture(
                id: AtlasTextureId(index: UInt32(textureIndex), kind: kind),
                allocator: BucketedAtlasAllocator(size: clampedSize),
                metalTexture: metalTexture,
                liveAtlasKeys: 0
            )

            if let reusedIndex {
                list.textures[reusedIndex] = atlasTexture
            } else {
                list.textures.append(atlasTexture)
            }
            return atlasTexture
        }
    }
}

// MARK: - MetalAtlas

/// Metal texture atlas managing monochrome (`A8Unorm`) and polychrome (`BGRA8Unorm`) sprite sheets.
// PORT NOTE: Synchronized via NSLock matching upstream `Mutex<MetalAtlasState>`.
public final class MetalAtlas: PlatformAtlas, @unchecked Sendable {
    private let lock = NSLock()
    private var state: MetalAtlasState

    public init(_ device: any MTLDevice, _ isAppleGpu: Bool) {
        self.state = MetalAtlasState(device: device, isAppleGpu: isAppleGpu)
    }

    public convenience init(device: any MTLDevice, isAppleGpu: Bool) {
        self.init(device, isAppleGpu)
    }

    /// Creates a new `MetalAtlas` for the given Metal device.
    public static func new(_ device: any MTLDevice, _ isAppleGpu: Bool) -> MetalAtlas {
        MetalAtlas(device, isAppleGpu)
    }

    /// Returns the `MTLTexture` backing the given `AtlasTextureId`.
    public func metalTexture(_ id: AtlasTextureId) -> any MTLTexture {
        lock.lock()
        defer { lock.unlock() }
        guard let texture = state.texture(id) else {
            preconditionFailure("Requested nonexistent MetalAtlas texture for id: \(id)")
        }
        return texture.metalTexture
    }

    public func getOrInsertWith(
        key: AtlasKey,
        build: () throws -> (Size<DevicePixels>, Data)?
    ) throws -> AtlasTile? {
        lock.lock()
        defer { lock.unlock() }

        if let existing = state.tilesByKey[key] {
            return existing
        }

        guard let (size, bytes) = try build() else {
            return nil
        }

        let kind = key.textureKind()
        guard let tile = try state.allocate(size: size, textureKind: kind) else {
            throw MetalAtlasError.allocationFailed(size, kind)
        }

        guard let texture = state.texture(tile.textureId) else {
            throw MetalAtlasError.missingTexture(tile.textureId)
        }

        texture.upload(bounds: tile.bounds, bytes: bytes)
        state.tilesByKey[key] = tile
        return tile
    }

    public func getOrInsertWith(
        _ key: AtlasKey,
        _ build: () throws -> (Size<DevicePixels>, Data)?
    ) throws -> AtlasTile? {
        try getOrInsertWith(key: key, build: build)
    }

    public func remove(key: AtlasKey) {
        lock.lock()
        defer { lock.unlock() }

        guard let removedTile = state.tilesByKey.removeValue(forKey: key) else {
            return
        }
        let id = removedTile.textureId

        state.textureList(for: id.kind) { textures in
            guard let slotIndex = textures.textures.firstIndex(where: { $0?.id == id }),
                  let texture = textures.textures[slotIndex] else {
                return
            }

            textures.textures[slotIndex] = nil
            texture.decrementRefCount()

            if texture.isUnreferenced {
                textures.freeList.append(Int(id.index))
            } else {
                textures.textures[slotIndex] = texture
            }
        }
    }

    public func remove(_ key: AtlasKey) {
        remove(key: key)
    }
}
#endif
