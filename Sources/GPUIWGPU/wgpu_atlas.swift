// Ported from: crates/gpui_wgpu/src/wgpu_atlas.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(Linux) || os(Windows) || os(Android) || os(WASI)
import Foundation
import CWebGPU
import GPUI
import GPUICollections

// MARK: - Shelf Atlas Allocator (2D Shelf / Etagere Bin-Packing)

/// 2D shelf bin-packing allocator that organizes texture space into horizontal shelves.
public struct ShelfAtlasAllocator: Sendable {
    public struct Shelf: Sendable {
        public var y: Int32
        public var height: Int32
        public var currentX: Int32
    }

    public var size: Size<DevicePixels>
    public private(set) var shelves: [Shelf] = []
    public private(set) var nextTileId: UInt32 = 1

    public init(size: Size<DevicePixels>) {
        self.size = size
    }

    public mutating func allocate(size requestedSize: Size<DevicePixels>) -> (TileId, Bounds<DevicePixels>)? {
        let reqW = requestedSize.width.value
        let reqH = requestedSize.height.value
        let sheetW = size.width.value
        let sheetH = size.height.value

        guard reqW > 0, reqH > 0, reqW <= sheetW, reqH <= sheetH else {
            return nil
        }

        // 1. Try to find an existing shelf that minimizes wasted vertical height
        var bestShelfIdx: Int?
        var minWaste = Int32.max

        for (idx, shelf) in shelves.enumerated() {
            if shelf.height >= reqH && (sheetW - shelf.currentX) >= reqW {
                let waste = shelf.height - reqH
                if waste < minWaste {
                    minWaste = waste
                    bestShelfIdx = idx
                }
            }
        }

        if let idx = bestShelfIdx {
            let originX = shelves[idx].currentX
            let originY = shelves[idx].y
            shelves[idx].currentX += reqW
            let tileId = TileId(nextTileId)
            nextTileId += 1
            let bounds = Bounds(
                origin: Point(x: DevicePixels(originX), y: DevicePixels(originY)),
                size: requestedSize
            )
            return (tileId, bounds)
        }

        // 2. Allocate a new shelf at the bottom if vertical space allows
        let lastShelfY = shelves.last.map { $0.y + $0.height } ?? 0
        if sheetH - lastShelfY >= reqH {
            let newShelf = Shelf(y: lastShelfY, height: reqH, currentX: reqW)
            shelves.append(newShelf)
            let tileId = TileId(nextTileId)
            nextTileId += 1
            let bounds = Bounds(
                origin: Point(x: DevicePixels(0), y: DevicePixels(lastShelfY)),
                size: requestedSize
            )
            return (tileId, bounds)
        }

        // Sheet is full
        return nil
    }

    public mutating func clear() {
        shelves.removeAll(keepingCapacity: true)
        nextTileId = 1
    }
}

// MARK: - WgpuTextureInfo

// PORT NOTE: WGPUTextureView is an opaque C pointer managed by the engine and safe across concurrency domains.
public struct WgpuTextureInfo: @unchecked Sendable {
    public var view: WGPUTextureView

    public init(view: WGPUTextureView) {
        self.view = view
    }
}

// MARK: - Internal Types

struct PendingUpload: Sendable {
    var id: AtlasTextureId
    var bounds: Bounds<DevicePixels>
    var data: Data
}

// PORT NOTE: WgpuAtlasTexture wraps C WebGPU pointers and is protected by WgpuAtlas's synchronization lock.
final class WgpuAtlasTexture: @unchecked Sendable {
    var id: AtlasTextureId
    var allocator: ShelfAtlasAllocator
    var format: WGPUTextureFormat
    var texture: WGPUTexture
    var view: WGPUTextureView
    var liveAtlasKeys: UInt32

    init(
        id: AtlasTextureId,
        allocator: ShelfAtlasAllocator,
        format: WGPUTextureFormat,
        texture: WGPUTexture,
        view: WGPUTextureView,
        liveAtlasKeys: UInt32 = 0
    ) {
        self.id = id
        self.allocator = allocator
        self.format = format
        self.texture = texture
        self.view = view
        self.liveAtlasKeys = liveAtlasKeys
    }

    func allocate(size: Size<DevicePixels>) -> AtlasTile? {
        guard let (tileId, bounds) = allocator.allocate(size: size) else {
            return nil
        }
        liveAtlasKeys += 1
        return AtlasTile(
            textureId: id,
            tileId: tileId,
            padding: 0,
            bounds: bounds
        )
    }

    var bytesPerPixel: UInt32 {
        switch format {
        case WGPUTextureFormat_R8Unorm: return 1
        default: return 4
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

    func destroy() {
        #if os(Linux)
        wgpuTextureViewRelease(view)
        wgpuTextureRelease(texture)
        #endif
    }
}

struct WgpuAtlasStorage {
    var monochromeTextures = AtlasTextureList<WgpuAtlasTexture>()
    var subpixelTextures = AtlasTextureList<WgpuAtlasTexture>()
    var polychromeTextures = AtlasTextureList<WgpuAtlasTexture>()

    subscript(kind: AtlasTextureKind) -> AtlasTextureList<WgpuAtlasTexture> {
        get {
            switch kind {
            case .monochrome: return monochromeTextures
            case .subpixel: return subpixelTextures
            case .polychrome: return polychromeTextures
            }
        }
        set {
            switch kind {
            case .monochrome: monochromeTextures = newValue
            case .subpixel: subpixelTextures = newValue
            case .polychrome: polychromeTextures = newValue
            }
        }
    }

    func get(_ id: AtlasTextureId) -> WgpuAtlasTexture? {
        let list = self[id.kind]
        let idx = Int(id.index)
        guard idx >= 0 && idx < list.textures.count else { return nil }
        return list.textures[idx]
    }

    mutating func clear() {
        for slot in monochromeTextures.textures { slot?.destroy() }
        for slot in subpixelTextures.textures { slot?.destroy() }
        for slot in polychromeTextures.textures { slot?.destroy() }
        monochromeTextures = AtlasTextureList()
        subpixelTextures = AtlasTextureList()
        polychromeTextures = AtlasTextureList()
    }
}

struct WgpuAtlasState {
    var device: WGPUDevice
    var queue: WGPUQueue
    var maxTextureSize: UInt32
    var storage = WgpuAtlasStorage()
    var tilesByKey: [AtlasKey: AtlasTile] = [:]
    var pendingUploads: [PendingUpload] = []

    init(device: WGPUDevice, queue: WGPUQueue) {
        self.device = device
        self.queue = queue

        var limits = WGPULimits()
        self.maxTextureSize = 8192
        #if os(Linux)
        if wgpuDeviceGetLimits(device, &limits) == WGPUStatus_Success {
            self.maxTextureSize = max(limits.maxTextureDimension2D, 2048)
        }
        #endif
    }

    mutating func allocate(size: Size<DevicePixels>, kind: AtlasTextureKind) -> AtlasTile? {
        let list = storage[kind]
        // Try allocating in existing textures in reverse order
        for i in stride(from: list.textures.count - 1, through: 0, by: -1) {
            if let texture = list.textures[i], let tile = texture.allocate(size: size) {
                return tile
            }
        }

        // Allocate a new texture sheet
        let newTexture = pushTexture(minSize: size, kind: kind)
        return newTexture.allocate(size: size)
    }

    mutating func pushTexture(minSize: Size<DevicePixels>, kind: AtlasTextureKind) -> WgpuAtlasTexture {
        let defaultAtlasSize = Size(width: DevicePixels(1024), height: DevicePixels(1024))
        let maxAtlasSize = Size(
            width: DevicePixels(Int32(maxTextureSize)),
            height: DevicePixels(Int32(maxTextureSize))
        )

        let sheetW = min(max(minSize.width.value, defaultAtlasSize.width.value), maxAtlasSize.width.value)
        let sheetH = min(max(minSize.height.value, defaultAtlasSize.height.value), maxAtlasSize.height.value)
        let sheetSize = Size(width: DevicePixels(sheetW), height: DevicePixels(sheetH))

        let format: WGPUTextureFormat
        switch kind {
        case .monochrome:
            format = WGPUTextureFormat_R8Unorm
        case .subpixel, .polychrome:
            format = WGPUTextureFormat_BGRA8Unorm
        }

        var desc = WGPUTextureDescriptor()
        desc.label = WGPUStringView(data: nil, length: 0)
        desc.size = WGPUExtent3D(width: UInt32(sheetW), height: UInt32(sheetH), depthOrArrayLayers: 1)
        desc.mipLevelCount = 1
        desc.sampleCount = 1
        desc.dimension = WGPUTextureDimension_2D
        desc.format = format
        desc.usage = WGPUTextureUsage_TextureBinding | WGPUTextureUsage_CopyDst
        #if os(Linux)
        let texture = wgpuDeviceCreateTexture(device, &desc)!
        let view = wgpuTextureCreateView(texture, nil)!
        #else
        // PORT NOTE: WebGPU C runtime calls are gated on os(Linux) because libwgpu_native is linked on Linux, while Windows uses D3D11 in GPUIWindows and Android/WASI backends are deferred per R3.
        let texture = UnsafeMutableRawPointer(bitPattern: 1)!
        let view = UnsafeMutableRawPointer(bitPattern: 1)!
        #endif

        var list = storage[kind]
        let slotIndex: Int
        if let freeIdx = list.freeList.popLast() {
            slotIndex = freeIdx
        } else {
            slotIndex = list.textures.count
            list.textures.append(nil)
        }

        let atlasTexture = WgpuAtlasTexture(
            id: AtlasTextureId(index: UInt32(slotIndex), kind: kind),
            allocator: ShelfAtlasAllocator(size: sheetSize),
            format: format,
            texture: texture,
            view: view,
            liveAtlasKeys: 0
        )
        list.textures[slotIndex] = atlasTexture
        storage[kind] = list
        return atlasTexture
    }

    mutating func uploadTexture(id: AtlasTextureId, bounds: Bounds<DevicePixels>, data: Data) {
        pendingUploads.append(PendingUpload(id: id, bounds: bounds, data: data))
    }

    mutating func flushUploads() {
        let uploads = pendingUploads
        pendingUploads.removeAll(keepingCapacity: true)

        for upload in uploads {
            guard let texture = storage.get(upload.id) else {
                continue
            }

            let width = UInt32(upload.bounds.size.width.value)
            let height = UInt32(upload.bounds.size.height.value)
            guard width > 0, height > 0 else { continue }

            let bytesPerPixel = texture.bytesPerPixel
            let bytesPerRow = width * bytesPerPixel

            var destCopy = WGPUTexelCopyTextureInfo()
            destCopy.texture = texture.texture
            destCopy.mipLevel = 0
            destCopy.origin = WGPUOrigin3D(
                x: UInt32(upload.bounds.origin.x.value),
                y: UInt32(upload.bounds.origin.y.value),
                z: 0
            )
            destCopy.aspect = WGPUTextureAspect_All

            var layout = WGPUTexelCopyBufferLayout()
            layout.offset = 0
            layout.bytesPerRow = bytesPerRow
            layout.rowsPerImage = height

            var extent = WGPUExtent3D(width: width, height: height, depthOrArrayLayers: 1)

            #if os(Linux)
            upload.data.withUnsafeBytes { rawBytes in
                guard let basePtr = rawBytes.baseAddress else { return }
                wgpuQueueWriteTexture(queue, &destCopy, basePtr, rawBytes.count, &layout, &extent)
            }
            #else
            // PORT NOTE: WebGPU C runtime calls are gated on os(Linux) because libwgpu_native is linked on Linux, while Windows uses D3D11 in GPUIWindows and Android/WASI backends are deferred per R3.
            #endif
        }
    }
}

// MARK: - WgpuAtlas

// PORT NOTE: WgpuAtlas is internally synchronized using NSLock to conform to PlatformAtlas and Sendable.
public final class WgpuAtlas: PlatformAtlas, @unchecked Sendable {
    private let lock = NSLock()
    private var state: WgpuAtlasState

    public init(device: WGPUDevice, queue: WGPUQueue) {
        self.state = WgpuAtlasState(device: device, queue: queue)
    }

    public static func new(device: WGPUDevice, queue: WGPUQueue) -> WgpuAtlas {
        WgpuAtlas(device: device, queue: queue)
    }

    public func beforeFrame() {
        lock.lock()
        state.flushUploads()
        lock.unlock()
    }

    public func getTextureInfo(id: AtlasTextureId) -> WgpuTextureInfo {
        lock.lock()
        defer { lock.unlock() }
        guard let texture = state.storage.get(id) else {
            fatalError("Atlas texture \(id) not found")
        }
        return WgpuTextureInfo(view: texture.view)
    }

    public func handleDeviceLost(device: WGPUDevice, queue: WGPUQueue) {
        lock.lock()
        defer { lock.unlock() }
        state.storage.clear()
        state.tilesByKey.removeAll()
        state.pendingUploads.removeAll()
        state.device = device
        state.queue = queue
    }

    // MARK: - PlatformAtlas Conformance

    public func getOrInsertWith(
        key: AtlasKey,
        build: () throws -> (Size<DevicePixels>, Data)?
    ) throws -> AtlasTile? {
        lock.lock()
        defer { lock.unlock() }

        if let existing = state.tilesByKey[key] {
            return existing
        }

        guard let (size, data) = try build() else {
            return nil
        }

        guard let tile = state.allocate(size: size, kind: key.textureKind()) else {
            return nil
        }

        state.uploadTexture(id: tile.textureId, bounds: tile.bounds, data: data)
        state.tilesByKey[key] = tile
        return tile
    }

    public func remove(key: AtlasKey) {
        lock.lock()
        defer { lock.unlock() }

        guard let tile = state.tilesByKey.removeValue(forKey: key) else {
            return
        }

        let id = tile.textureId
        var list = state.storage[id.kind]
        let idx = Int(id.index)
        guard idx >= 0 && idx < list.textures.count, let texture = list.textures[idx] else {
            return
        }

        texture.decrementRefCount()
        if texture.isUnreferenced {
            // Drop pending uploads referencing this freed texture
            state.pendingUploads.removeAll { $0.id == id }
            // Recycle slot in freeList
            list.freeList.append(idx)
            texture.destroy()
            list.textures[idx] = nil
            state.storage[id.kind] = list
        }
    }
}
#endif
