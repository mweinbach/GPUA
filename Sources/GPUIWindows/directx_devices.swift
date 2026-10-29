// Ported from: crates/gpui_windows/src/directx_devices.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(Windows)
import Foundation
#if canImport(CWinSys)
import CWinSys
#endif

public enum DirectXError: Error, CustomStringConvertible {
    case deviceCreationFailure(Int32)
    case deviceLost
    case featureUnsupported(String)
    case swapchainCreationFailure(Int32)
    case shaderCompilationFailure(String)
    case bufferCreationFailure(Int32)
    case textureCreationFailure(Int32)

    public var description: String {
        switch self {
        case .deviceCreationFailure(let hr):
            return "Failed to create Direct3D 11 device (HRESULT: \(hr))"
        case .deviceLost:
            return "Direct3D 11 device was lost or removed"
        case .featureUnsupported(let msg):
            return "Direct3D 11 feature unsupported: \(msg)"
        case .swapchainCreationFailure(let hr):
            return "Failed to create DXGI swapchain (HRESULT: \(hr))"
        case .shaderCompilationFailure(let msg):
            return "Direct3D 11 shader compilation failed: \(msg)"
        case .bufferCreationFailure(let hr):
            return "Failed to create Direct3D 11 buffer (HRESULT: \(hr))"
        case .textureCreationFailure(let hr):
            return "Failed to create Direct3D 11 texture (HRESULT: \(hr))"
        }
    }
}

// PORT NOTE: Retry loop recovering from DXGI_ERROR_DEVICE_RESET / DXGI_ERROR_DEVICE_REMOVED
public func tryToRecoverFromDeviceLost<T>(_ f: () throws -> T) throws -> T {
    var lastError: (any Error)?
    for i in 0..<5 {
        if i > 0 {
            Thread.sleep(forTimeInterval: Double(100 + i * 10) / 1000.0)
        }
        do {
            return try f()
        } catch {
            lastError = error
        }
    }
    throw lastError ?? DirectXError.deviceLost
}

// PORT NOTE: DirectXDevices wraps native ID3D11Device and ID3D11DeviceContext COM pointers.
public final class DirectXDevices: @unchecked Sendable {
    public let device: WinHandle
    public let deviceContext: WinHandle
    public let featureLevel: UInt32
    public let isWarp: Bool

    public init(preferWarp: Bool = false, enableDebug: Bool = false) throws {
        var dev: UnsafeMutableRawPointer?
        var ctx: UnsafeMutableRawPointer?
        var fl: UInt32 = 0
        let status: Int32
        if preferWarp {
            status = cwin_d3d11_create_device_warp(enableDebug ? 1 : 0, &dev, &ctx, &fl)
        } else {
            status = cwin_d3d11_create_device(enableDebug ? 1 : 0, &dev, &ctx, &fl)
        }
        guard status == 0, let dev = dev, let ctx = ctx else {
            throw DirectXError.deviceCreationFailure(status)
        }
        self.device = dev
        self.deviceContext = ctx
        self.featureLevel = fl
        self.isWarp = preferWarp
    }

    public init(device: WinHandle, deviceContext: WinHandle, featureLevel: UInt32 = 0xb000, isWarp: Bool = false) {
        cwin_addref_com_object(device)
        cwin_addref_com_object(deviceContext)
        self.device = device
        self.deviceContext = deviceContext
        self.featureLevel = featureLevel
        self.isWarp = isWarp
    }

    deinit {
        cwin_release_com_object(deviceContext)
        cwin_release_com_object(device)
    }

    public func createSwapchain(hwnd: WinHandle, width: UInt32, height: UInt32) throws -> WinHandle {
        var swapchain: UnsafeMutableRawPointer?
        let hr = cwin_d3d11_create_swapchain_for_hwnd(device, hwnd, width, height, &swapchain)
        guard hr == 0, let swapchain = swapchain else {
            throw DirectXError.swapchainCreationFailure(hr)
        }
        return swapchain
    }
}

#endif
