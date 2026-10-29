// Ported from: crates/gpui_windows/src/directx_atlas.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(Windows)
import Foundation
import GPUI
import GPUICollections
#if canImport(CWinSys)
import CWinSys
#endif

// MARK: - Shelf Atlas Allocator (2D Shelf Bin-Packing)

/// 2D shelf bin-packing allocator for texture atlas sub-allocations.
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

        return nil
    }

    public mutating func clear() {
        shelves.removeAll(keepingCapacity: true)
        nextTileId = 1
    }
}

// PORT NOTE: DirectXAtlasTexture holds D3D11Texture2D and ShaderResourceView COM pointers for an atlas sheet.
final class DirectXAtlasTexture: @unchecked Sendable {
    let id: AtlasTextureId
    let bytesPerPixel: UInt32
    var allocator: ShelfAtlasAllocator
    let texture: WinHandle
    let view: WinHandle
    var liveAtlasKeys: UInt32 = 0

    init(id: AtlasTextureId, bytesPerPixel: UInt32, size: Size<DevicePixels>, texture: WinHandle, view: WinHandle) {
        self.id = id
        self.bytesPerPixel = bytesPerPixel
        self.allocator = ShelfAtlasAllocator(size: size)
        self.texture = texture
        self.view = view
    }

    deinit {
        cwin_release_com_object(view)
        cwin_release_com_object(texture)
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

    func upload(deviceContext: WinHandle, bounds: Bounds<DevicePixels>, data: Data) {
        let left = UInt32(max(0, bounds.origin.x.value))
        let top = UInt32(max(0, bounds.origin.y.value))
        let width = UInt32(bounds.size.width.value)
        let height = UInt32(bounds.size.height.value)
        let rowPitch = width * bytesPerPixel

        data.withUnsafeBytes { rawBuf in
            if let ptr = rawBuf.baseAddress {
                _ = cwin_d3d11_update_subresource(
                    deviceContext,
                    texture,
                    left,
                    top,
                    width,
                    height,
                    ptr,
                    rowPitch
                )
            }
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

// PORT NOTE: DirectXAtlas coordinates texture sheets, allocation, and subresource updates with NSLock synchronization.
public final class DirectXAtlas: PlatformAtlas, @unchecked Sendable {
    private let lock = NSLock()
    private var device: WinHandle
    private var deviceContext: WinHandle
    private var monochromeTextures: [DirectXAtlasTexture?] = []
    private var polychromeTextures: [DirectXAtlasTexture?] = []
    private var subpixelTextures: [DirectXAtlasTexture?] = []
    private var monochromeFreeList: [Int] = []
    private var polychromeFreeList: [Int] = []
    private var subpixelFreeList: [Int] = []
    private var tilesByKey: [AtlasKey: AtlasTile] = [:]

    public init(device: WinHandle, deviceContext: WinHandle) {
        self.device = device
        self.deviceContext = deviceContext
    }

    public func getTextureView(id: AtlasTextureId) -> WinHandle? {
        lock.lock()
        defer { lock.unlock() }
        let list: [DirectXAtlasTexture?] = switch id.kind {
        case .monochrome: monochromeTextures
        case .polychrome: polychromeTextures
        case .subpixel: subpixelTextures
        }
        let idx = Int(id.index)
        guard idx >= 0 && idx < list.count else { return nil }
        return list[idx]?.view
    }

    public func handleDeviceLost(device: WinHandle, deviceContext: WinHandle) {
        lock.lock()
        defer { lock.unlock() }
        self.device = device
        self.deviceContext = deviceContext
        monochromeTextures.removeAll()
        polychromeTextures.removeAll()
        subpixelTextures.removeAll()
        monochromeFreeList.removeAll()
        polychromeFreeList.removeAll()
        subpixelFreeList.removeAll()
        tilesByKey.removeAll()
    }

    // MARK: - PlatformAtlas Protocol Conformance

    public func getOrInsertWith(
        key: AtlasKey,
        build: () throws -> (Size<DevicePixels>, Data)?
    ) throws -> AtlasTile? {
        lock.lock()
        if let tile = tilesByKey[key] {
            lock.unlock()
            return tile
        }
        lock.unlock()

        guard let (size, data) = try build() else {
            return nil
        }

        lock.lock()
        defer { lock.unlock() }

        if let tile = tilesByKey[key] {
            return tile
        }

        guard let tile = allocate(size: size, kind: key.textureKind()) else {
            return nil
        }

        if let texture = texture(id: tile.textureId) {
            texture.upload(deviceContext: deviceContext, bounds: tile.bounds, data: data)
        }
        tilesByKey[key] = tile
        return tile
    }

    public func remove(key: AtlasKey) {
        lock.lock()
        defer { lock.unlock() }
        guard let tile = tilesByKey.removeValue(forKey: key) else {
            return
        }
        let id = tile.textureId
        let idx = Int(id.index)
        switch id.kind {
        case .monochrome:
            if idx < monochromeTextures.count, let tex = monochromeTextures[idx] {
                tex.decrementRefCount()
                if tex.isUnreferenced {
                    monochromeTextures[idx] = nil
                    monochromeFreeList.append(idx)
                }
            }
        case .polychrome:
            if idx < polychromeTextures.count, let tex = polychromeTextures[idx] {
                tex.decrementRefCount()
                if tex.isUnreferenced {
                    polychromeTextures[idx] = nil
                    polychromeFreeList.append(idx)
                }
            }
        case .subpixel:
            if idx < subpixelTextures.count, let tex = subpixelTextures[idx] {
                tex.decrementRefCount()
                if tex.isUnreferenced {
                    subpixelTextures[idx] = nil
                    subpixelFreeList.append(idx)
                }
            }
        }
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        monochromeTextures.removeAll()
        polychromeTextures.removeAll()
        subpixelTextures.removeAll()
        monochromeFreeList.removeAll()
        polychromeFreeList.removeAll()
        subpixelFreeList.removeAll()
        tilesByKey.removeAll()
    }

    private func allocate(size: Size<DevicePixels>, kind: AtlasTextureKind) -> AtlasTile? {
        let list: [DirectXAtlasTexture?] = switch kind {
        case .monochrome: monochromeTextures
        case .polychrome: polychromeTextures
        case .subpixel: subpixelTextures
        }

        for tex in list.reversed() {
            if let tex = tex, let tile = tex.allocate(size: size) {
                return tile
            }
        }

        guard let newTex = pushTexture(minSize: size, kind: kind) else {
            return nil
        }
        return newTex.allocate(size: size)
    }

    private func pushTexture(minSize: Size<DevicePixels>, kind: AtlasTextureKind) -> DirectXAtlasTexture? {
        let defaultSize = Size(width: DevicePixels(1024), height: DevicePixels(1024))
        let maxSize = Size(width: DevicePixels(16384), height: DevicePixels(16384))
        let width = max(defaultSize.width.value, min(maxSize.width.value, minSize.width.value))
        let height = max(defaultSize.height.value, min(maxSize.height.value, minSize.height.value))
        let size = Size(width: DevicePixels(width), height: DevicePixels(height))

        let format: UInt32
        let bytesPerPixel: UInt32
        switch kind {
        case .monochrome:
            format = 61 // DXGI_FORMAT_R8_UNORM
            bytesPerPixel = 1
        case .polychrome:
            format = 87 // DXGI_FORMAT_B8G8R8A8_UNORM
            bytesPerPixel = 4
        case .subpixel:
            format = 28 // DXGI_FORMAT_R8G8B8A8_UNORM
            bytesPerPixel = 4
        }

        var texPtr: UnsafeMutableRawPointer?
        var srvPtr: UnsafeMutableRawPointer?
        let hr = cwin_d3d11_create_texture_2d(
            device,
            UInt32(width),
            UInt32(height),
            format,
            0x8, // D3D11_BIND_SHADER_RESOURCE
            0,
            &texPtr,
            &srvPtr
        )
        guard hr == 0, let texPtr = texPtr, let srvPtr = srvPtr else {
            return nil
        }

        let index: Int
        switch kind {
        case .monochrome:
            if let free = monochromeFreeList.popLast() {
                index = free
            } else {
                index = monochromeTextures.count
                monochromeTextures.append(nil)
            }
        case .polychrome:
            if let free = polychromeFreeList.popLast() {
                index = free
            } else {
                index = polychromeTextures.count
                polychromeTextures.append(nil)
            }
        case .subpixel:
            if let free = subpixelFreeList.popLast() {
                index = free
            } else {
                index = subpixelTextures.count
                subpixelTextures.append(nil)
            }
        }

        let atlasTex = DirectXAtlasTexture(
            id: AtlasTextureId(index: UInt32(index), kind: kind),
            bytesPerPixel: bytesPerPixel,
            size: size,
            texture: texPtr,
            view: srvPtr
        )

        switch kind {
        case .monochrome: monochromeTextures[index] = atlasTex
        case .polychrome: polychromeTextures[index] = atlasTex
        case .subpixel: subpixelTextures[index] = atlasTex
        }

        return atlasTex
    }

    private func texture(id: AtlasTextureId) -> DirectXAtlasTexture? {
        let list: [DirectXAtlasTexture?] = switch id.kind {
        case .monochrome: monochromeTextures
        case .polychrome: polychromeTextures
        case .subpixel: subpixelTextures
        }
        let idx = Int(id.index)
        guard idx >= 0 && idx < list.count else { return nil }
        return list[idx]
    }
}

#endif
