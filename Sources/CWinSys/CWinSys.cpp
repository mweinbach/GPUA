// Swift-only: C++ implementation of CWinSys COM and Win32 bridge functions
#if defined(_WIN32)

#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif
#ifndef _CRT_SECURE_NO_WARNINGS
#define _CRT_SECURE_NO_WARNINGS
#endif

#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <d3d11_1.h>
#include <dxgi1_6.h>
#include <d3dcompiler.h>
#include <dwrite_3.h>
#include <dwmapi.h>
#include <shellapi.h>
#include <shlobj.h>
#include <wincred.h>
#include <mmsystem.h>
#include <uxtheme.h>
#include <directmanipulation.h>

#include <cmath>
#include <algorithm>
#include <cstdlib>
#include <cstring>
#include <vector>
#include <string>

#include "CWinSys.h"

static_assert(sizeof(wchar_t) == sizeof(uint16_t), "wchar_t must be 16-bit on Windows");

// MARK: - Direct3D 11 & DXGI

void cwin_release_com_object(void* obj) {
    if (obj) {
        IUnknown* unk = static_cast<IUnknown*>(obj);
        unk->Release();
    }
}

void cwin_addref_com_object(void* obj) {
    if (obj) {
        IUnknown* unk = static_cast<IUnknown*>(obj);
        unk->AddRef();
    }
}

int cwin_d3d11_create_device(int enable_debug, void** out_device, void** out_context, uint32_t* out_feature_level) {
    if (!out_device || !out_context) return (int)E_INVALIDARG;

    static const D3D_FEATURE_LEVEL feature_levels[] = {
        D3D_FEATURE_LEVEL_11_1,
        D3D_FEATURE_LEVEL_11_0,
        D3D_FEATURE_LEVEL_10_1,
        D3D_FEATURE_LEVEL_10_0,
    };

    UINT flags = D3D11_CREATE_DEVICE_BGRA_SUPPORT;
    if (enable_debug) {
        flags |= D3D11_CREATE_DEVICE_DEBUG;
    }

    ID3D11Device* device = nullptr;
    ID3D11DeviceContext* context = nullptr;
    D3D_FEATURE_LEVEL feature_level = D3D_FEATURE_LEVEL_11_0;

    // First attempt: Hardware adapter
    HRESULT hr = D3D11CreateDevice(
        nullptr,
        D3D_DRIVER_TYPE_HARDWARE,
        nullptr,
        flags,
        feature_levels,
        sizeof(feature_levels) / sizeof(feature_levels[0]),
        D3D11_SDK_VERSION,
        &device,
        &feature_level,
        &context
    );

    // If hardware failed with debug flag (e.g. SDK Layers not installed), retry without debug flag
    if (FAILED(hr) && (flags & D3D11_CREATE_DEVICE_DEBUG)) {
        flags &= ~D3D11_CREATE_DEVICE_DEBUG;
        hr = D3D11CreateDevice(
            nullptr,
            D3D_DRIVER_TYPE_HARDWARE,
            nullptr,
            flags,
            feature_levels,
            sizeof(feature_levels) / sizeof(feature_levels[0]),
            D3D11_SDK_VERSION,
            &device,
            &feature_level,
            &context
        );
    }

    // Second attempt: WARP software rasterizer fallback for headless CI or environments without GPU
    if (FAILED(hr)) {
        hr = D3D11CreateDevice(
            nullptr,
            D3D_DRIVER_TYPE_WARP,
            nullptr,
            flags,
            feature_levels,
            sizeof(feature_levels) / sizeof(feature_levels[0]),
            D3D11_SDK_VERSION,
            &device,
            &feature_level,
            &context
        );
    }

    if (FAILED(hr)) return (int)hr;

    *out_device = device;
    *out_context = context;
    if (out_feature_level) *out_feature_level = (uint32_t)feature_level;
    return 0;
}

int cwin_d3d11_create_device_warp(int enable_debug, void** out_device, void** out_context, uint32_t* out_feature_level) {
    if (!out_device || !out_context) return (int)E_INVALIDARG;

    static const D3D_FEATURE_LEVEL feature_levels[] = {
        D3D_FEATURE_LEVEL_11_1,
        D3D_FEATURE_LEVEL_11_0,
        D3D_FEATURE_LEVEL_10_1,
        D3D_FEATURE_LEVEL_10_0,
    };

    UINT flags = D3D11_CREATE_DEVICE_BGRA_SUPPORT;
    if (enable_debug) {
        flags |= D3D11_CREATE_DEVICE_DEBUG;
    }

    ID3D11Device* device = nullptr;
    ID3D11DeviceContext* context = nullptr;
    D3D_FEATURE_LEVEL feature_level = D3D_FEATURE_LEVEL_11_0;

    HRESULT hr = D3D11CreateDevice(
        nullptr,
        D3D_DRIVER_TYPE_WARP,
        nullptr,
        flags,
        feature_levels,
        sizeof(feature_levels) / sizeof(feature_levels[0]),
        D3D11_SDK_VERSION,
        &device,
        &feature_level,
        &context
    );

    if (FAILED(hr) && (flags & D3D11_CREATE_DEVICE_DEBUG)) {
        flags &= ~D3D11_CREATE_DEVICE_DEBUG;
        hr = D3D11CreateDevice(
            nullptr,
            D3D_DRIVER_TYPE_WARP,
            nullptr,
            flags,
            feature_levels,
            sizeof(feature_levels) / sizeof(feature_levels[0]),
            D3D11_SDK_VERSION,
            &device,
            &feature_level,
            &context
        );
    }

    if (FAILED(hr)) return (int)hr;

    *out_device = device;
    *out_context = context;
    if (out_feature_level) *out_feature_level = (uint32_t)feature_level;
    return 0;
}

int cwin_d3d11_create_swapchain_for_hwnd(void* device, void* hwnd, uint32_t width, uint32_t height, void** out_swapchain) {
    if (!device || !hwnd || !out_swapchain) return (int)E_INVALIDARG;

    ID3D11Device* d3d_device = static_cast<ID3D11Device*>(device);
    IDXGIDevice* dxgi_device = nullptr;
    HRESULT hr = d3d_device->QueryInterface(__uuidof(IDXGIDevice), reinterpret_cast<void**>(&dxgi_device));
    if (FAILED(hr)) return (int)hr;

    IDXGIAdapter* adapter = nullptr;
    hr = dxgi_device->GetAdapter(&adapter);
    dxgi_device->Release();
    if (FAILED(hr)) return (int)hr;

    IDXGIFactory2* factory2 = nullptr;
    hr = adapter->GetParent(__uuidof(IDXGIFactory2), reinterpret_cast<void**>(&factory2));
    adapter->Release();
    if (FAILED(hr)) return (int)hr;

    DXGI_SWAP_CHAIN_DESC1 desc = {};
    desc.Width = width;
    desc.Height = height;
    desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
    desc.Stereo = FALSE;
    desc.SampleDesc.Count = 1;
    desc.SampleDesc.Quality = 0;
    desc.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
    desc.BufferCount = 2; // Flip model requires at least 2 buffers
    desc.Scaling = DXGI_SCALING_NONE;
    desc.SwapEffect = DXGI_SWAP_EFFECT_FLIP_DISCARD;
    desc.AlphaMode = DXGI_ALPHA_MODE_UNSPECIFIED;
    desc.Flags = 0;

    IDXGISwapChain1* swapchain = nullptr;
    hr = factory2->CreateSwapChainForHwnd(
        d3d_device,
        static_cast<HWND>(hwnd),
        &desc,
        nullptr,
        nullptr,
        &swapchain
    );

    // If DXGI_SCALING_NONE fails on certain display configurations, fallback to STRETCH
    if (FAILED(hr)) {
        desc.Scaling = DXGI_SCALING_STRETCH;
        hr = factory2->CreateSwapChainForHwnd(
            d3d_device,
            static_cast<HWND>(hwnd),
            &desc,
            nullptr,
            nullptr,
            &swapchain
        );
    }
    factory2->Release();

    if (FAILED(hr)) return (int)hr;
    *out_swapchain = swapchain;
    return 0;
}

int cwin_d3d11_resize_swapchain(void* swapchain, uint32_t width, uint32_t height) {
    if (!swapchain) return (int)E_INVALIDARG;
    IDXGISwapChain* sc = static_cast<IDXGISwapChain*>(swapchain);
    HRESULT hr = sc->ResizeBuffers(0, width, height, DXGI_FORMAT_UNKNOWN, 0);
    return (int)hr;
}

int cwin_d3d11_present_swapchain(void* swapchain, uint32_t sync_interval, uint32_t flags) {
    if (!swapchain) return (int)E_INVALIDARG;
    IDXGISwapChain* sc = static_cast<IDXGISwapChain*>(swapchain);
    HRESULT hr = sc->Present(static_cast<UINT>(sync_interval), static_cast<UINT>(flags));
    return (int)hr;
}

int cwin_d3d11_get_swapchain_backbuffer(void* swapchain, void** out_texture) {
    if (!swapchain || !out_texture) return (int)E_INVALIDARG;
    IDXGISwapChain* sc = static_cast<IDXGISwapChain*>(swapchain);
    ID3D11Texture2D* backbuffer = nullptr;
    HRESULT hr = sc->GetBuffer(0, __uuidof(ID3D11Texture2D), reinterpret_cast<void**>(&backbuffer));
    if (FAILED(hr)) return (int)hr;
    *out_texture = backbuffer;
    return 0;
}

int cwin_d3d11_create_render_target_view(void* device, void* texture, void** out_rtv) {
    if (!device || !texture || !out_rtv) return (int)E_INVALIDARG;
    ID3D11Device* dev = static_cast<ID3D11Device*>(device);
    ID3D11Resource* res = static_cast<ID3D11Resource*>(texture);
    ID3D11RenderTargetView* rtv = nullptr;
    HRESULT hr = dev->CreateRenderTargetView(res, nullptr, &rtv);
    if (FAILED(hr)) return (int)hr;
    *out_rtv = rtv;
    return 0;
}

int cwin_d3d11_compile_hlsl(const char* source, size_t source_len, const char* entry_point, const char* target, void** out_blob, char** out_error) {
    if (!source || !entry_point || !target || !out_blob) return (int)E_INVALIDARG;
    ID3DBlob* code_blob = nullptr;
    ID3DBlob* error_blob = nullptr;
    UINT compile_flags = D3DCOMPILE_ENABLE_STRICTNESS;
#if defined(_DEBUG)
    compile_flags |= D3DCOMPILE_DEBUG | D3DCOMPILE_SKIP_OPTIMIZATION;
#else
    compile_flags |= D3DCOMPILE_OPTIMIZATION_LEVEL3;
#endif

    HRESULT hr = D3DCompile(
        source,
        source_len,
        nullptr,
        nullptr,
        D3D_COMPILE_STANDARD_FILE_INCLUDE,
        entry_point,
        target,
        compile_flags,
        0,
        &code_blob,
        &error_blob
    );

    if (FAILED(hr)) {
        if (error_blob && out_error) {
            const char* msg = static_cast<const char*>(error_blob->GetBufferPointer());
            size_t len = error_blob->GetBufferSize();
            char* err_copy = static_cast<char*>(malloc(len + 1));
            if (err_copy) {
                memcpy(err_copy, msg, len);
                err_copy[len] = '\0';
                *out_error = err_copy;
            }
        }
        if (error_blob) error_blob->Release();
        return (int)hr;
    }

    if (error_blob) error_blob->Release();
    *out_blob = code_blob;
    if (out_error) *out_error = nullptr;
    return 0;
}

void cwin_d3d11_free_error_string(char* error_string) {
    if (error_string) {
        free(error_string);
    }
}

const void* cwin_d3d_blob_get_pointer(void* blob) {
    if (!blob) return nullptr;
    return static_cast<ID3DBlob*>(blob)->GetBufferPointer();
}

size_t cwin_d3d_blob_get_size(void* blob) {
    if (!blob) return 0;
    return static_cast<ID3DBlob*>(blob)->GetBufferSize();
}

int cwin_d3d11_create_vertex_shader(void* device, const void* bytecode, size_t len, void** out_shader) {
    if (!device || !bytecode || !out_shader) return (int)E_INVALIDARG;
    ID3D11Device* dev = static_cast<ID3D11Device*>(device);
    ID3D11VertexShader* vs = nullptr;
    HRESULT hr = dev->CreateVertexShader(bytecode, len, nullptr, &vs);
    if (FAILED(hr)) return (int)hr;
    *out_shader = vs;
    return 0;
}

int cwin_d3d11_create_pixel_shader(void* device, const void* bytecode, size_t len, void** out_shader) {
    if (!device || !bytecode || !out_shader) return (int)E_INVALIDARG;
    ID3D11Device* dev = static_cast<ID3D11Device*>(device);
    ID3D11PixelShader* ps = nullptr;
    HRESULT hr = dev->CreatePixelShader(bytecode, len, nullptr, &ps);
    if (FAILED(hr)) return (int)hr;
    *out_shader = ps;
    return 0;
}

int cwin_d3d11_create_structured_buffer(void* device, uint32_t stride, uint32_t element_count, int dynamic, void** out_buffer, void** out_srv) {
    if (!device || !out_buffer) return (int)E_INVALIDARG;
    ID3D11Device* dev = static_cast<ID3D11Device*>(device);

    D3D11_BUFFER_DESC desc = {};
    desc.ByteWidth = stride * (element_count > 0 ? element_count : 1);
    desc.MiscFlags = D3D11_RESOURCE_MISC_BUFFER_STRUCTURED;
    desc.StructureByteStride = stride;
    if (dynamic) {
        desc.Usage = D3D11_USAGE_DYNAMIC;
        desc.CPUAccessFlags = D3D11_CPU_ACCESS_WRITE;
    } else {
        desc.Usage = D3D11_USAGE_DEFAULT;
        desc.CPUAccessFlags = 0;
    }
    desc.BindFlags = D3D11_BIND_SHADER_RESOURCE;

    ID3D11Buffer* buf = nullptr;
    HRESULT hr = dev->CreateBuffer(&desc, nullptr, &buf);
    if (FAILED(hr)) return (int)hr;

    if (out_srv) {
        D3D11_SHADER_RESOURCE_VIEW_DESC srv_desc = {};
        srv_desc.Format = DXGI_FORMAT_UNKNOWN;
        srv_desc.ViewDimension = D3D11_SRV_DIMENSION_BUFFER;
        srv_desc.Buffer.FirstElement = 0;
        srv_desc.Buffer.NumElements = element_count;

        ID3D11ShaderResourceView* srv = nullptr;
        hr = dev->CreateShaderResourceView(buf, &srv_desc, &srv);
        if (FAILED(hr)) {
            buf->Release();
            return (int)hr;
        }
        *out_srv = srv;
    }

    *out_buffer = buf;
    return 0;
}

int cwin_d3d11_create_buffer_view_range(void* device, void* buffer, uint32_t first_element, uint32_t num_elements, void** out_srv) {
    if (!device || !buffer || !out_srv) return (int)E_INVALIDARG;
    ID3D11Device* dev = static_cast<ID3D11Device*>(device);
    ID3D11Buffer* buf = static_cast<ID3D11Buffer*>(buffer);

    D3D11_SHADER_RESOURCE_VIEW_DESC srv_desc = {};
    srv_desc.Format = DXGI_FORMAT_UNKNOWN;
    srv_desc.ViewDimension = D3D11_SRV_DIMENSION_BUFFER;
    srv_desc.Buffer.FirstElement = first_element;
    srv_desc.Buffer.NumElements = num_elements;

    ID3D11ShaderResourceView* srv = nullptr;
    HRESULT hr = dev->CreateShaderResourceView(buf, &srv_desc, &srv);
    if (FAILED(hr)) return (int)hr;
    *out_srv = srv;
    return 0;
}

int cwin_d3d11_create_constant_buffer(void* device, uint32_t byte_width, void** out_buffer) {
    if (!device || !out_buffer) return (int)E_INVALIDARG;
    ID3D11Device* dev = static_cast<ID3D11Device*>(device);

    // Constant buffers must be a multiple of 16 bytes
    uint32_t aligned_width = (byte_width + 15) & ~15;

    D3D11_BUFFER_DESC desc = {};
    desc.ByteWidth = aligned_width;
    desc.Usage = D3D11_USAGE_DYNAMIC;
    desc.BindFlags = D3D11_BIND_CONSTANT_BUFFER;
    desc.CPUAccessFlags = D3D11_CPU_ACCESS_WRITE;
    desc.MiscFlags = 0;

    ID3D11Buffer* buf = nullptr;
    HRESULT hr = dev->CreateBuffer(&desc, nullptr, &buf);
    if (FAILED(hr)) return (int)hr;
    *out_buffer = buf;
    return 0;
}

int cwin_d3d11_map_discard(void* context, void* buffer, const void* data, size_t byte_count) {
    if (!context || !buffer || !data) return (int)E_INVALIDARG;
    ID3D11DeviceContext* ctx = static_cast<ID3D11DeviceContext*>(context);
    ID3D11Resource* res = static_cast<ID3D11Resource*>(buffer);

    D3D11_MAPPED_SUBRESOURCE mapped = {};
    HRESULT hr = ctx->Map(res, 0, D3D11_MAP_WRITE_DISCARD, 0, &mapped);
    if (FAILED(hr)) return (int)hr;

    memcpy(mapped.pData, data, byte_count);
    ctx->Unmap(res, 0);
    return 0;
}

int cwin_d3d11_create_texture_2d(void* device, uint32_t width, uint32_t height, uint32_t format, uint32_t bind_flags, int dynamic, void** out_texture, void** out_srv) {
    if (!device || !out_texture) return (int)E_INVALIDARG;
    ID3D11Device* dev = static_cast<ID3D11Device*>(device);

    D3D11_TEXTURE2D_DESC desc = {};
    desc.Width = width;
    desc.Height = height;
    desc.MipLevels = 1;
    desc.ArraySize = 1;
    desc.Format = static_cast<DXGI_FORMAT>(format);
    desc.SampleDesc.Count = 1;
    desc.SampleDesc.Quality = 0;
    desc.Usage = dynamic ? D3D11_USAGE_DYNAMIC : D3D11_USAGE_DEFAULT;
    desc.BindFlags = bind_flags;
    desc.CPUAccessFlags = dynamic ? D3D11_CPU_ACCESS_WRITE : 0;
    desc.MiscFlags = 0;

    ID3D11Texture2D* tex = nullptr;
    HRESULT hr = dev->CreateTexture2D(&desc, nullptr, &tex);
    if (FAILED(hr)) return (int)hr;

    if (out_srv && (bind_flags & D3D11_BIND_SHADER_RESOURCE)) {
        D3D11_SHADER_RESOURCE_VIEW_DESC srv_desc = {};
        srv_desc.Format = desc.Format;
        srv_desc.ViewDimension = D3D11_SRV_DIMENSION_TEXTURE2D;
        srv_desc.Texture2D.MostDetailedMip = 0;
        srv_desc.Texture2D.MipLevels = 1;

        ID3D11ShaderResourceView* srv = nullptr;
        hr = dev->CreateShaderResourceView(tex, &srv_desc, &srv);
        if (FAILED(hr)) {
            tex->Release();
            return (int)hr;
        }
        *out_srv = srv;
    }

    *out_texture = tex;
    return 0;
}

int cwin_d3d11_update_subresource(void* context, void* texture, uint32_t dst_x, uint32_t dst_y, uint32_t width, uint32_t height, const void* data, uint32_t row_pitch) {
    if (!context || !texture || !data) return (int)E_INVALIDARG;
    ID3D11DeviceContext* ctx = static_cast<ID3D11DeviceContext*>(context);
    ID3D11Resource* res = static_cast<ID3D11Resource*>(texture);

    D3D11_BOX box;
    box.left = dst_x;
    box.top = dst_y;
    box.front = 0;
    box.right = dst_x + width;
    box.bottom = dst_y + height;
    box.back = 1;

    ctx->UpdateSubresource(res, 0, &box, data, row_pitch, 0);
    return 0;
}

int cwin_d3d11_readback_texture_pixels(void* device, void* context, void* texture, uint32_t width, uint32_t height, uint32_t* out_row_pitch, int swizzle_bgra, uint8_t** out_pixels) {
    if (!device || !context || !texture || !out_pixels) return (int)E_INVALIDARG;

    ID3D11Device* dev = static_cast<ID3D11Device*>(device);
    ID3D11DeviceContext* ctx = static_cast<ID3D11DeviceContext*>(context);

    ID3D11Texture2D* src_tex = nullptr;
    HRESULT hr = static_cast<IUnknown*>(texture)->QueryInterface(__uuidof(ID3D11Texture2D), reinterpret_cast<void**>(&src_tex));
    if (FAILED(hr)) return (int)hr;

    D3D11_TEXTURE2D_DESC src_desc = {};
    src_tex->GetDesc(&src_desc);

    uint32_t target_width = (width > 0) ? width : src_desc.Width;
    uint32_t target_height = (height > 0) ? height : src_desc.Height;

    D3D11_TEXTURE2D_DESC staging_desc = src_desc;
    staging_desc.Width = target_width;
    staging_desc.Height = target_height;
    staging_desc.MipLevels = 1;
    staging_desc.ArraySize = 1;
    staging_desc.Usage = D3D11_USAGE_STAGING;
    staging_desc.BindFlags = 0;
    staging_desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
    staging_desc.MiscFlags = 0;

    ID3D11Texture2D* staging_tex = nullptr;
    hr = dev->CreateTexture2D(&staging_desc, nullptr, &staging_tex);
    if (FAILED(hr)) {
        src_tex->Release();
        return (int)hr;
    }

    if (staging_desc.Width == src_desc.Width && staging_desc.Height == src_desc.Height) {
        ctx->CopyResource(staging_tex, src_tex);
    } else {
        D3D11_BOX box = { 0, 0, 0, staging_desc.Width, staging_desc.Height, 1 };
        ctx->CopySubresourceRegion(staging_tex, 0, 0, 0, 0, src_tex, 0, &box);
    }
    src_tex->Release();

    D3D11_MAPPED_SUBRESOURCE mapped = {};
    hr = ctx->Map(staging_tex, 0, D3D11_MAP_READ, 0, &mapped);
    if (FAILED(hr)) {
        staging_tex->Release();
        return (int)hr;
    }

    uint32_t dst_pitch = target_width * 4;
    uint8_t* pixel_buf = static_cast<uint8_t*>(malloc(static_cast<size_t>(dst_pitch) * target_height));
    if (!pixel_buf) {
        ctx->Unmap(staging_tex, 0);
        staging_tex->Release();
        return (int)E_OUTOFMEMORY;
    }

    const uint8_t* src_row = static_cast<const uint8_t*>(mapped.pData);
    for (uint32_t y = 0; y < target_height; ++y) {
        uint8_t* dst_row = pixel_buf + static_cast<size_t>(y) * dst_pitch;
        const uint8_t* src_pix = src_row + static_cast<size_t>(y) * mapped.RowPitch;
        if (swizzle_bgra) {
            for (uint32_t x = 0; x < target_width; ++x) {
                uint8_t b = src_pix[x * 4 + 0];
                uint8_t g = src_pix[x * 4 + 1];
                uint8_t r = src_pix[x * 4 + 2];
                uint8_t a = src_pix[x * 4 + 3];
                dst_row[x * 4 + 0] = r;
                dst_row[x * 4 + 1] = g;
                dst_row[x * 4 + 2] = b;
                dst_row[x * 4 + 3] = a;
            }
        } else {
            memcpy(dst_row, src_pix, dst_pitch);
        }
    }

    ctx->Unmap(staging_tex, 0);
    staging_tex->Release();

    if (out_row_pitch) *out_row_pitch = dst_pitch;
    *out_pixels = pixel_buf;
    return 0;
}

void cwin_d3d11_free_pixel_buffer(uint8_t* pixels) {
    if (pixels) {
        free(pixels);
    }
}

int cwin_d3d11_create_msaa_render_target(void* device, uint32_t width, uint32_t height, uint32_t sample_count, void** out_texture, void** out_rtv) {
    if (!device || !out_texture || !out_rtv) return (int)E_INVALIDARG;
    ID3D11Device* dev = static_cast<ID3D11Device*>(device);

    D3D11_TEXTURE2D_DESC desc = {};
    desc.Width = width;
    desc.Height = height;
    desc.MipLevels = 1;
    desc.ArraySize = 1;
    desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
    desc.SampleDesc.Count = sample_count;
    desc.SampleDesc.Quality = D3D11_STANDARD_MULTISAMPLE_PATTERN;
    desc.Usage = D3D11_USAGE_DEFAULT;
    desc.BindFlags = D3D11_BIND_RENDER_TARGET;

    ID3D11Texture2D* tex = nullptr;
    HRESULT hr = dev->CreateTexture2D(&desc, nullptr, &tex);
    if (FAILED(hr)) return (int)hr;

    ID3D11RenderTargetView* rtv = nullptr;
    hr = dev->CreateRenderTargetView(tex, nullptr, &rtv);
    if (FAILED(hr)) {
        tex->Release();
        return (int)hr;
    }

    *out_texture = tex;
    *out_rtv = rtv;
    return 0;
}

int cwin_d3d11_resolve_subresource(void* context, void* dst_res, uint32_t dst_subres, void* src_res, uint32_t src_subres, uint32_t format) {
    if (!context || !dst_res || !src_res) return (int)E_INVALIDARG;
    ID3D11DeviceContext* ctx = static_cast<ID3D11DeviceContext*>(context);
    ctx->ResolveSubresource(
        static_cast<ID3D11Resource*>(dst_res),
        dst_subres,
        static_cast<ID3D11Resource*>(src_res),
        src_subres,
        static_cast<DXGI_FORMAT>(format)
    );
    return 0;
}

void cwin_d3d11_clear_render_target_view(void* context, void* rtv, const float color[4]) {
    if (context && rtv) {
        static_cast<ID3D11DeviceContext*>(context)->ClearRenderTargetView(
            static_cast<ID3D11RenderTargetView*>(rtv),
            color
        );
    }
}

void cwin_d3d11_om_set_render_targets(void* context, uint32_t num_views, void* const* rtvs, void* dsv) {
    if (context) {
        static_cast<ID3D11DeviceContext*>(context)->OMSetRenderTargets(
            num_views,
            reinterpret_cast<ID3D11RenderTargetView* const*>(rtvs),
            static_cast<ID3D11DepthStencilView*>(dsv)
        );
    }
}

int cwin_d3d11_create_blend_state(void* device, int blend_mode, void** out_state) {
    if (!device || !out_state) return (int)E_INVALIDARG;
    ID3D11Device* dev = static_cast<ID3D11Device*>(device);

    D3D11_BLEND_DESC desc = {};
    desc.RenderTarget[0].BlendEnable = TRUE;
    desc.RenderTarget[0].BlendOp = D3D11_BLEND_OP_ADD;
    desc.RenderTarget[0].BlendOpAlpha = D3D11_BLEND_OP_ADD;

    if (blend_mode == 1) {
        // Subpixel rendering
        desc.RenderTarget[0].SrcBlend = D3D11_BLEND_SRC1_COLOR;
        desc.RenderTarget[0].DestBlend = D3D11_BLEND_INV_SRC1_COLOR;
        desc.RenderTarget[0].SrcBlendAlpha = D3D11_BLEND_ONE;
        desc.RenderTarget[0].DestBlendAlpha = D3D11_BLEND_ZERO;
        desc.RenderTarget[0].RenderTargetWriteMask = D3D11_COLOR_WRITE_ENABLE_ALL & ~D3D11_COLOR_WRITE_ENABLE_ALPHA;
    } else if (blend_mode == 2) {
        // Path rasterization / path sprite (premultiplied alpha)
        desc.RenderTarget[0].SrcBlend = D3D11_BLEND_ONE;
        desc.RenderTarget[0].DestBlend = D3D11_BLEND_INV_SRC_ALPHA;
        desc.RenderTarget[0].SrcBlendAlpha = D3D11_BLEND_ONE;
        desc.RenderTarget[0].DestBlendAlpha = D3D11_BLEND_INV_SRC_ALPHA;
        desc.RenderTarget[0].RenderTargetWriteMask = D3D11_COLOR_WRITE_ENABLE_ALL;
    } else {
        // Standard alpha blending (Quad, Shadow, Underline, Mono/Poly sprites)
        desc.RenderTarget[0].SrcBlend = D3D11_BLEND_SRC_ALPHA;
        desc.RenderTarget[0].DestBlend = D3D11_BLEND_INV_SRC_ALPHA;
        desc.RenderTarget[0].SrcBlendAlpha = D3D11_BLEND_ONE;
        desc.RenderTarget[0].DestBlendAlpha = D3D11_BLEND_ONE;
        desc.RenderTarget[0].RenderTargetWriteMask = D3D11_COLOR_WRITE_ENABLE_ALL;
    }

    ID3D11BlendState* bs = nullptr;
    HRESULT hr = dev->CreateBlendState(&desc, &bs);
    if (FAILED(hr)) return (int)hr;
    *out_state = bs;
    return 0;
}

void cwin_d3d11_om_set_blend_state(void* context, void* blend_state, const float blend_factor[4], uint32_t sample_mask) {
    if (context) {
        static_cast<ID3D11DeviceContext*>(context)->OMSetBlendState(
            static_cast<ID3D11BlendState*>(blend_state),
            blend_factor,
            sample_mask
        );
    }
}

int cwin_d3d11_create_sampler_state(void* device, int filter_linear, int address_clamp, void** out_sampler) {
    if (!device || !out_sampler) return (int)E_INVALIDARG;
    ID3D11Device* dev = static_cast<ID3D11Device*>(device);

    D3D11_SAMPLER_DESC desc = {};
    desc.Filter = filter_linear ? D3D11_FILTER_MIN_MAG_MIP_LINEAR : D3D11_FILTER_MIN_MAG_MIP_POINT;
    desc.AddressU = address_clamp ? D3D11_TEXTURE_ADDRESS_CLAMP : D3D11_TEXTURE_ADDRESS_WRAP;
    desc.AddressV = address_clamp ? D3D11_TEXTURE_ADDRESS_CLAMP : D3D11_TEXTURE_ADDRESS_WRAP;
    desc.AddressW = address_clamp ? D3D11_TEXTURE_ADDRESS_CLAMP : D3D11_TEXTURE_ADDRESS_WRAP;
    desc.MipLODBias = 0.0f;
    desc.MaxAnisotropy = 1;
    desc.ComparisonFunc = D3D11_COMPARISON_ALWAYS;
    desc.MinLOD = 0.0f;
    desc.MaxLOD = D3D11_FLOAT32_MAX;

    ID3D11SamplerState* ss = nullptr;
    HRESULT hr = dev->CreateSamplerState(&desc, &ss);
    if (FAILED(hr)) return (int)hr;
    *out_sampler = ss;
    return 0;
}

void cwin_d3d11_ps_set_samplers(void* context, uint32_t start_slot, uint32_t num_samplers, void* const* samplers) {
    if (context) {
        static_cast<ID3D11DeviceContext*>(context)->PSSetSamplers(
            start_slot,
            num_samplers,
            reinterpret_cast<ID3D11SamplerState* const*>(samplers)
        );
    }
}

int cwin_d3d11_create_rasterizer_state(void* device, int scissor_enable, void** out_state) {
    if (!device || !out_state) return (int)E_INVALIDARG;
    ID3D11Device* dev = static_cast<ID3D11Device*>(device);

    D3D11_RASTERIZER_DESC desc = {};
    desc.FillMode = D3D11_FILL_SOLID;
    desc.CullMode = D3D11_CULL_NONE;
    desc.FrontCounterClockwise = FALSE;
    desc.DepthBias = 0;
    desc.DepthBiasClamp = 0.0f;
    desc.SlopeScaledDepthBias = 0.0f;
    desc.DepthClipEnable = TRUE;
    desc.ScissorEnable = scissor_enable ? TRUE : FALSE;
    desc.MultisampleEnable = TRUE;
    desc.AntialiasedLineEnable = FALSE;

    ID3D11RasterizerState* rs = nullptr;
    HRESULT hr = dev->CreateRasterizerState(&desc, &rs);
    if (FAILED(hr)) return (int)hr;
    *out_state = rs;
    return 0;
}

void cwin_d3d11_rs_set_state(void* context, void* rasterizer_state) {
    if (context) {
        static_cast<ID3D11DeviceContext*>(context)->RSSetState(
            static_cast<ID3D11RasterizerState*>(rasterizer_state)
        );
    }
}

void cwin_d3d11_rs_set_viewports(void* context, uint32_t num_viewports, const void* viewports) {
    if (context) {
        static_cast<ID3D11DeviceContext*>(context)->RSSetViewports(
            num_viewports,
            static_cast<const D3D11_VIEWPORT*>(viewports)
        );
    }
}

void cwin_d3d11_rs_set_scissor_rects(void* context, uint32_t num_rects, const void* rects) {
    if (context) {
        static_cast<ID3D11DeviceContext*>(context)->RSSetScissorRects(
            num_rects,
            static_cast<const D3D11_RECT*>(rects)
        );
    }
}

void cwin_d3d11_ia_set_primitive_topology(void* context, uint32_t topology) {
    if (context) {
        static_cast<ID3D11DeviceContext*>(context)->IASetPrimitiveTopology(
            static_cast<D3D11_PRIMITIVE_TOPOLOGY>(topology)
        );
    }
}

void cwin_d3d11_vs_set_shader(void* context, void* shader) {
    if (context) {
        static_cast<ID3D11DeviceContext*>(context)->VSSetShader(
            static_cast<ID3D11VertexShader*>(shader),
            nullptr,
            0
        );
    }
}

void cwin_d3d11_ps_set_shader(void* context, void* shader) {
    if (context) {
        static_cast<ID3D11DeviceContext*>(context)->PSSetShader(
            static_cast<ID3D11PixelShader*>(shader),
            nullptr,
            0
        );
    }
}

void cwin_d3d11_vs_set_constant_buffers(void* context, uint32_t start_slot, uint32_t num_buffers, void* const* buffers) {
    if (context) {
        static_cast<ID3D11DeviceContext*>(context)->VSSetConstantBuffers(
            start_slot,
            num_buffers,
            reinterpret_cast<ID3D11Buffer* const*>(buffers)
        );
    }
}

void cwin_d3d11_ps_set_constant_buffers(void* context, uint32_t start_slot, uint32_t num_buffers, void* const* buffers) {
    if (context) {
        static_cast<ID3D11DeviceContext*>(context)->PSSetConstantBuffers(
            start_slot,
            num_buffers,
            reinterpret_cast<ID3D11Buffer* const*>(buffers)
        );
    }
}

void cwin_d3d11_vs_set_shader_resources(void* context, uint32_t start_slot, uint32_t num_views, void* const* views) {
    if (context) {
        static_cast<ID3D11DeviceContext*>(context)->VSSetShaderResources(
            start_slot,
            num_views,
            reinterpret_cast<ID3D11ShaderResourceView* const*>(views)
        );
    }
}

void cwin_d3d11_ps_set_shader_resources(void* context, uint32_t start_slot, uint32_t num_views, void* const* views) {
    if (context) {
        static_cast<ID3D11DeviceContext*>(context)->PSSetShaderResources(
            start_slot,
            num_views,
            reinterpret_cast<ID3D11ShaderResourceView* const*>(views)
        );
    }
}

void cwin_d3d11_draw(void* context, uint32_t vertex_count, uint32_t start_vertex_location) {
    if (context) {
        static_cast<ID3D11DeviceContext*>(context)->Draw(vertex_count, start_vertex_location);
    }
}

void cwin_d3d11_draw_instanced(void* context, uint32_t vertex_count_per_instance, uint32_t instance_count, uint32_t start_vertex_location, uint32_t start_instance_location) {
    if (context) {
        static_cast<ID3D11DeviceContext*>(context)->DrawInstanced(
            vertex_count_per_instance,
            instance_count,
            start_vertex_location,
            start_instance_location
        );
    }
}

void cwin_d3d11_clear_state(void* context) {
    if (context) {
        static_cast<ID3D11DeviceContext*>(context)->ClearState();
    }
}

void cwin_d3d11_flush(void* context) {
    if (context) {
        static_cast<ID3D11DeviceContext*>(context)->Flush();
    }
}

// MARK: - DirectWrite

namespace {

struct FontMemoryPayload {
    const void* data;
    UINT32 size;
};

class MemoryFontFileStream : public IDWriteFontFileStream {
    LONG ref_count_;
    void* data_;
    UINT32 size_;

public:
    MemoryFontFileStream(const void* data, UINT32 size)
        : ref_count_(1), data_(nullptr), size_(size) {
        if (data && size > 0) {
            data_ = malloc(size);
            if (data_) {
                memcpy(data_, data, size);
            }
        }
    }

    ~MemoryFontFileStream() {
        if (data_) {
            free(data_);
            data_ = nullptr;
        }
    }

    ULONG STDMETHODCALLTYPE AddRef() noexcept override { return InterlockedIncrement(&ref_count_); }
    ULONG STDMETHODCALLTYPE Release() noexcept override {
        ULONG count = InterlockedDecrement(&ref_count_);
        if (count == 0) delete this;
        return count;
    }
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void** ppv) noexcept override {
        if (!ppv) return E_POINTER;
        if (riid == __uuidof(IUnknown) || riid == __uuidof(IDWriteFontFileStream)) {
            *ppv = static_cast<IDWriteFontFileStream*>(this);
            AddRef();
            return S_OK;
        }
        *ppv = nullptr;
        return E_NOINTERFACE;
    }

    HRESULT STDMETHODCALLTYPE ReadFileFragment(const void** fragmentStart, UINT64 fileOffset, UINT64 fragmentSize, void** fragmentContext) noexcept override {
        if (!data_ || fileOffset + fragmentSize > size_) return E_INVALIDARG;
        *fragmentStart = static_cast<const uint8_t*>(data_) + fileOffset;
        *fragmentContext = nullptr;
        return S_OK;
    }
    void STDMETHODCALLTYPE ReleaseFileFragment(void* fragmentContext) noexcept override {}
    HRESULT STDMETHODCALLTYPE GetFileSize(UINT64* fileSize) noexcept override {
        if (!fileSize) return E_POINTER;
        *fileSize = size_;
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE GetLastWriteTime(UINT64* lastWriteTime) noexcept override {
        if (!lastWriteTime) return E_POINTER;
        *lastWriteTime = 0;
        return S_OK;
    }
};

class MemoryFontFileLoader : public IDWriteFontFileLoader {
    LONG ref_count_;
public:
    MemoryFontFileLoader() : ref_count_(1) {}

    ULONG STDMETHODCALLTYPE AddRef() noexcept override { return InterlockedIncrement(&ref_count_); }
    ULONG STDMETHODCALLTYPE Release() noexcept override {
        ULONG count = InterlockedDecrement(&ref_count_);
        if (count == 0) delete this;
        return count;
    }
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void** ppv) noexcept override {
        if (!ppv) return E_POINTER;
        if (riid == __uuidof(IUnknown) || riid == __uuidof(IDWriteFontFileLoader)) {
            *ppv = static_cast<IDWriteFontFileLoader*>(this);
            AddRef();
            return S_OK;
        }
        *ppv = nullptr;
        return E_NOINTERFACE;
    }

    HRESULT STDMETHODCALLTYPE CreateStreamFromKey(const void* fontFileReferenceKey, UINT32 fontFileReferenceKeySize, IDWriteFontFileStream** fontFileStream) noexcept override {
        if (!fontFileStream || fontFileReferenceKeySize != sizeof(FontMemoryPayload)) return E_INVALIDARG;
        const FontMemoryPayload* payload = static_cast<const FontMemoryPayload*>(fontFileReferenceKey);
        *fontFileStream = new MemoryFontFileStream(payload->data, payload->size);
        return S_OK;
    }
};

class CWinFontLoaderWrapper : public IUnknown {
    LONG ref_count_;
public:
    IDWriteFactory* factory;
    IDWriteFontFileLoader* loader;

    CWinFontLoaderWrapper(IDWriteFactory* f, IDWriteFontFileLoader* l)
        : ref_count_(1), factory(f), loader(l) {
        if (factory) factory->AddRef();
        if (loader) loader->AddRef();
    }

    virtual ~CWinFontLoaderWrapper() {
        if (factory && loader) {
            factory->UnregisterFontFileLoader(loader);
        }
        if (loader) loader->Release();
        if (factory) factory->Release();
    }

    ULONG STDMETHODCALLTYPE AddRef() noexcept override { return InterlockedIncrement(&ref_count_); }
    ULONG STDMETHODCALLTYPE Release() noexcept override {
        ULONG count = InterlockedDecrement(&ref_count_);
        if (count == 0) delete this;
        return count;
    }
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void** ppv) noexcept override {
        if (!ppv) return E_POINTER;
        if (riid == __uuidof(IUnknown)) {
            *ppv = static_cast<IUnknown*>(this);
            AddRef();
            return S_OK;
        }
        *ppv = nullptr;
        return E_NOINTERFACE;
    }
};


} // namespace

int cwin_dwrite_create_factory(void** out_factory) {
    if (!out_factory) return (int)E_INVALIDARG;

    IDWriteFactory* factory = nullptr;
    HRESULT hr = DWriteCreateFactory(
        DWRITE_FACTORY_TYPE_SHARED,
        __uuidof(IDWriteFactory5),
        reinterpret_cast<IUnknown**>(&factory)
    );
    if (FAILED(hr)) {
        hr = DWriteCreateFactory(
            DWRITE_FACTORY_TYPE_SHARED,
            __uuidof(IDWriteFactory3),
            reinterpret_cast<IUnknown**>(&factory)
        );
    }
    if (FAILED(hr)) {
        hr = DWriteCreateFactory(
            DWRITE_FACTORY_TYPE_SHARED,
            __uuidof(IDWriteFactory),
            reinterpret_cast<IUnknown**>(&factory)
        );
    }

    if (FAILED(hr)) return (int)hr;
    *out_factory = factory;
    return 0;
}

int cwin_dwrite_register_in_memory_font_loader(void* factory, void** out_loader) {
    if (!factory || !out_loader) return (int)E_INVALIDARG;

    IDWriteFactory* dwrite_factory = static_cast<IDWriteFactory*>(factory);
    IDWriteFactory5* f5 = nullptr;
    IDWriteFontFileLoader* font_loader = nullptr;

    if (SUCCEEDED(dwrite_factory->QueryInterface(__uuidof(IDWriteFactory5), reinterpret_cast<void**>(&f5)))) {
        IDWriteInMemoryFontFileLoader* mem_loader = nullptr;
        if (SUCCEEDED(f5->CreateInMemoryFontFileLoader(&mem_loader))) {
            dwrite_factory->RegisterFontFileLoader(mem_loader);
            font_loader = mem_loader;
        }
        f5->Release();
    }

    if (!font_loader) {
        MemoryFontFileLoader* custom_loader = new MemoryFontFileLoader();
        dwrite_factory->RegisterFontFileLoader(custom_loader);
        font_loader = custom_loader;
    }

    CWinFontLoaderWrapper* wrapper = new CWinFontLoaderWrapper(dwrite_factory, font_loader);
    font_loader->Release();
    *out_loader = wrapper;
    return 0;
}

int cwin_dwrite_create_font_file_reference(void* loader, const void* data, size_t size, void** out_font_file) {
    if (!loader || !data || !out_font_file) return (int)E_INVALIDARG;

    CWinFontLoaderWrapper* wrapper = static_cast<CWinFontLoaderWrapper*>(loader);
    IDWriteFactory* factory = wrapper->factory;
    IDWriteFontFileLoader* font_loader = wrapper->loader;

    IDWriteInMemoryFontFileLoader* in_mem = nullptr;
    if (SUCCEEDED(font_loader->QueryInterface(__uuidof(IDWriteInMemoryFontFileLoader), reinterpret_cast<void**>(&in_mem)))) {
        IDWriteFontFile* font_file = nullptr;
        HRESULT hr = in_mem->CreateInMemoryFontFileReference(factory, data, static_cast<UINT32>(size), nullptr, &font_file);
        in_mem->Release();
        if (FAILED(hr)) return (int)hr;
        *out_font_file = font_file;
        return 0;
    }

    FontMemoryPayload payload = { data, static_cast<UINT32>(size) };
    IDWriteFontFile* font_file = nullptr;
    HRESULT hr = factory->CreateCustomFontFileReference(&payload, sizeof(payload), font_loader, &font_file);
    if (FAILED(hr)) return (int)hr;
    *out_font_file = font_file;
    return 0;
}

int cwin_dwrite_create_font_set_builder(void* factory, void** out_builder) {
    if (!factory || !out_builder) return (int)E_INVALIDARG;

    IDWriteFactory5* f5 = nullptr;
    HRESULT hr = static_cast<IUnknown*>(factory)->QueryInterface(__uuidof(IDWriteFactory5), reinterpret_cast<void**>(&f5));
    if (SUCCEEDED(hr) && f5) {
        IDWriteFontSetBuilder1* builder1 = nullptr;
        hr = f5->CreateFontSetBuilder(&builder1);
        f5->Release();
        if (SUCCEEDED(hr)) {
            *out_builder = builder1;
            return 0;
        }
    }

    IDWriteFactory3* f3 = nullptr;
    hr = static_cast<IUnknown*>(factory)->QueryInterface(__uuidof(IDWriteFactory3), reinterpret_cast<void**>(&f3));
    if (FAILED(hr)) return (int)hr;

    IDWriteFontSetBuilder* builder = nullptr;
    hr = f3->CreateFontSetBuilder(&builder);
    f3->Release();
    if (FAILED(hr)) return (int)hr;

    *out_builder = builder;
    return 0;
}

int cwin_dwrite_font_set_builder_add_file(void* builder, void* font_file) {
    if (!builder || !font_file) return (int)E_INVALIDARG;
    IDWriteFontSetBuilder1* b1 = static_cast<IDWriteFontSetBuilder1*>(builder);
    IDWriteFontFile* f = static_cast<IDWriteFontFile*>(font_file);
    HRESULT hr = b1->AddFontFile(f);
    return (int)hr;
}


int cwin_dwrite_font_set_builder_create_collection(void* builder, void* factory, void** out_collection) {
    if (!builder || !factory || !out_collection) return (int)E_INVALIDARG;

    IDWriteFontSetBuilder* b = static_cast<IDWriteFontSetBuilder*>(builder);
    IDWriteFontSet* font_set = nullptr;
    HRESULT hr = b->CreateFontSet(&font_set);
    if (FAILED(hr)) return (int)hr;

    IDWriteFactory3* f3 = nullptr;
    hr = static_cast<IUnknown*>(factory)->QueryInterface(__uuidof(IDWriteFactory3), reinterpret_cast<void**>(&f3));
    if (FAILED(hr)) {
        font_set->Release();
        return (int)hr;
    }

    IDWriteFontCollection1* collection = nullptr;
    hr = f3->CreateFontCollectionFromFontSet(font_set, &collection);
    font_set->Release();
    f3->Release();
    if (FAILED(hr)) return (int)hr;

    *out_collection = collection;
    return 0;
}

int cwin_dwrite_create_text_format(void* factory, const uint16_t* family_name, void* collection, uint32_t weight, uint32_t style, float font_size, void** out_format) {
    if (!factory || !family_name || !out_format) return (int)E_INVALIDARG;

    IDWriteFactory* f = static_cast<IDWriteFactory*>(factory);
    IDWriteFontCollection* col = static_cast<IDWriteFontCollection*>(collection);

    IDWriteTextFormat* tf = nullptr;
    HRESULT hr = f->CreateTextFormat(
        reinterpret_cast<const wchar_t*>(family_name),
        col,
        static_cast<DWRITE_FONT_WEIGHT>(weight),
        static_cast<DWRITE_FONT_STYLE>(style),
        DWRITE_FONT_STRETCH_NORMAL,
        font_size,
        L"",
        &tf
    );
    if (FAILED(hr)) return (int)hr;

    *out_format = tf;
    return 0;
}

int cwin_dwrite_create_text_layout(void* factory, const uint16_t* text, uint32_t text_len, void* format, float max_width, float max_height, void** out_layout) {
    if (!factory || !text || !format || !out_layout) return (int)E_INVALIDARG;

    IDWriteFactory* f = static_cast<IDWriteFactory*>(factory);
    IDWriteTextFormat* tf = static_cast<IDWriteTextFormat*>(format);

    IDWriteTextLayout* tl = nullptr;
    HRESULT hr = f->CreateTextLayout(
        reinterpret_cast<const wchar_t*>(text),
        text_len,
        tf,
        max_width,
        max_height,
        &tl
    );
    if (FAILED(hr)) return (int)hr;

    *out_layout = tl;
    return 0;
}

int cwin_dwrite_layout_get_metrics(void* layout, float* out_width, float* out_height, float* out_baseline) {
    if (!layout) return (int)E_INVALIDARG;

    IDWriteTextLayout* tl = static_cast<IDWriteTextLayout*>(layout);

    DWRITE_TEXT_METRICS tm = {};
    HRESULT hr = tl->GetMetrics(&tm);
    if (FAILED(hr)) return (int)hr;

    if (out_width) *out_width = tm.widthIncludingTrailingWhitespace;
    if (out_height) *out_height = tm.height;

    if (out_baseline) {
        DWRITE_LINE_METRICS lm = {};
        UINT32 actual_lines = 0;
        hr = tl->GetLineMetrics(&lm, 1, &actual_lines);
        if (SUCCEEDED(hr) && actual_lines > 0) {
            *out_baseline = lm.baseline;
        } else {
            *out_baseline = 0.0f;
        }
    }

    return 0;
}

int cwin_dwrite_get_system_font_collection(void* factory, void** out_collection) {
    if (!factory || !out_collection) return (int)E_INVALIDARG;
    IDWriteFactory* f = static_cast<IDWriteFactory*>(factory);
    IDWriteFontCollection* col = nullptr;
    HRESULT hr = f->GetSystemFontCollection(&col, FALSE);
    if (FAILED(hr)) return (int)hr;
    *out_collection = col;
    return 0;
}

uint32_t cwin_dwrite_collection_get_family_count(void* collection) {
    if (!collection) return 0;
    return static_cast<IDWriteFontCollection*>(collection)->GetFontFamilyCount();
}

int cwin_dwrite_collection_get_family_name(void* collection, uint32_t index, uint16_t* out_name, uint32_t max_chars) {
    if (!collection || !out_name || max_chars == 0) return (int)E_INVALIDARG;
    IDWriteFontCollection* col = static_cast<IDWriteFontCollection*>(collection);
    IDWriteFontFamily* family = nullptr;
    HRESULT hr = col->GetFontFamily(index, &family);
    if (FAILED(hr)) return (int)hr;

    IDWriteLocalizedStrings* names = nullptr;
    hr = family->GetFamilyNames(&names);
    family->Release();
    if (FAILED(hr)) return (int)hr;

    UINT32 name_index = 0;
    BOOL exists = FALSE;
    names->FindLocaleName(L"en-us", &name_index, &exists);
    if (!exists) name_index = 0;

    hr = names->GetString(name_index, reinterpret_cast<wchar_t*>(out_name), max_chars);
    out_name[max_chars - 1] = 0;
    names->Release();
    return (int)hr;
}

int cwin_dwrite_collection_find_family(void* collection, const uint16_t* family_name, uint32_t* out_index, int* out_exists) {
    if (!collection || !family_name || !out_index || !out_exists) return (int)E_INVALIDARG;
    IDWriteFontCollection* col = static_cast<IDWriteFontCollection*>(collection);
    UINT32 idx = 0;
    BOOL exists = FALSE;
    HRESULT hr = col->FindFamilyName(reinterpret_cast<const wchar_t*>(family_name), &idx, &exists);
    if (FAILED(hr)) return (int)hr;
    *out_index = idx;
    *out_exists = exists ? 1 : 0;
    return 0;
}

int cwin_dwrite_collection_get_font_face(void* collection, uint32_t family_index, uint32_t weight, uint32_t style, void** out_font_face) {
    if (!collection || !out_font_face) return (int)E_INVALIDARG;
    IDWriteFontCollection* col = static_cast<IDWriteFontCollection*>(collection);
    IDWriteFontFamily* family = nullptr;
    HRESULT hr = col->GetFontFamily(family_index, &family);
    if (FAILED(hr)) return (int)hr;

    IDWriteFont* font = nullptr;
    hr = family->GetFirstMatchingFont(
        static_cast<DWRITE_FONT_WEIGHT>(weight),
        DWRITE_FONT_STRETCH_NORMAL,
        static_cast<DWRITE_FONT_STYLE>(style),
        &font
    );
    family->Release();
    if (FAILED(hr)) return (int)hr;

    IDWriteFontFace* face = nullptr;
    hr = font->CreateFontFace(&face);
    font->Release();
    if (FAILED(hr)) return (int)hr;

    *out_font_face = face;
    return 0;
}

int cwin_dwrite_create_typography(void* factory, void** out_typography) {
    if (!factory || !out_typography) return (int)E_INVALIDARG;
    IDWriteFactory* f = static_cast<IDWriteFactory*>(factory);
    IDWriteTypography* typo = nullptr;
    HRESULT hr = f->CreateTypography(&typo);
    if (FAILED(hr)) return (int)hr;
    *out_typography = typo;
    return 0;
}

int cwin_dwrite_typography_add_feature(void* typography, uint32_t tag, uint32_t parameter) {
    if (!typography) return (int)E_INVALIDARG;
    IDWriteTypography* typo = static_cast<IDWriteTypography*>(typography);
    DWRITE_FONT_FEATURE feat = { static_cast<DWRITE_FONT_FEATURE_TAG>(tag), parameter };
    return (int)typo->AddFontFeature(feat);
}

int cwin_dwrite_layout_set_typography(void* layout, void* typography, uint32_t start_position, uint32_t length) {
    if (!layout || !typography) return (int)E_INVALIDARG;
    IDWriteTextLayout* tl = static_cast<IDWriteTextLayout*>(layout);
    IDWriteTypography* typo = static_cast<IDWriteTypography*>(typography);
    DWRITE_TEXT_RANGE range = { start_position, length };
    return (int)tl->SetTypography(typo, range);
}

int cwin_dwrite_layout_set_font_collection(void* layout, void* collection, uint32_t start_position, uint32_t length) {
    if (!layout || !collection) return (int)E_INVALIDARG;
    IDWriteTextLayout* tl = static_cast<IDWriteTextLayout*>(layout);
    IDWriteFontCollection* col = static_cast<IDWriteFontCollection*>(collection);
    DWRITE_TEXT_RANGE range = { start_position, length };
    return (int)tl->SetFontCollection(col, range);
}

int cwin_dwrite_layout_set_font_family_name(void* layout, const uint16_t* family_name, uint32_t start_position, uint32_t length) {
    if (!layout || !family_name) return (int)E_INVALIDARG;
    IDWriteTextLayout* tl = static_cast<IDWriteTextLayout*>(layout);
    DWRITE_TEXT_RANGE range = { start_position, length };
    return (int)tl->SetFontFamilyName(reinterpret_cast<const wchar_t*>(family_name), range);
}

int cwin_dwrite_layout_set_font_size(void* layout, float font_size, uint32_t start_position, uint32_t length) {
    if (!layout) return (int)E_INVALIDARG;
    IDWriteTextLayout* tl = static_cast<IDWriteTextLayout*>(layout);
    DWRITE_TEXT_RANGE range = { start_position, length };
    return (int)tl->SetFontSize(font_size, range);
}

int cwin_dwrite_layout_set_font_weight(void* layout, uint32_t weight, uint32_t start_position, uint32_t length) {
    if (!layout) return (int)E_INVALIDARG;
    IDWriteTextLayout* tl = static_cast<IDWriteTextLayout*>(layout);
    DWRITE_TEXT_RANGE range = { start_position, length };
    return (int)tl->SetFontWeight(static_cast<DWRITE_FONT_WEIGHT>(weight), range);
}

int cwin_dwrite_layout_set_font_style(void* layout, uint32_t style, uint32_t start_position, uint32_t length) {
    if (!layout) return (int)E_INVALIDARG;
    IDWriteTextLayout* tl = static_cast<IDWriteTextLayout*>(layout);
    DWRITE_TEXT_RANGE range = { start_position, length };
    return (int)tl->SetFontStyle(static_cast<DWRITE_FONT_STYLE>(style), range);
}

int cwin_dwrite_font_face_get_metrics(void* font_face, struct CWinFontMetrics* out_metrics) {
    if (!font_face || !out_metrics) return (int)E_INVALIDARG;
    IDWriteFontFace* face = static_cast<IDWriteFontFace*>(font_face);

    DWRITE_FONT_METRICS fm = {};
    face->GetMetrics(&fm);

    out_metrics->ascent = static_cast<float>(fm.ascent);
    out_metrics->descent = -static_cast<float>(fm.descent);
    out_metrics->line_gap = static_cast<float>(fm.lineGap);
    out_metrics->cap_height = static_cast<float>(fm.capHeight);
    out_metrics->x_height = static_cast<float>(fm.xHeight);
    out_metrics->underline_position = static_cast<float>(fm.underlinePosition);
    out_metrics->underline_thickness = static_cast<float>(fm.underlineThickness);
    out_metrics->units_per_em = fm.designUnitsPerEm;

    out_metrics->glyph_box_left = 0.0f;
    out_metrics->glyph_box_bottom = -static_cast<float>(fm.descent);
    out_metrics->glyph_box_right = static_cast<float>(fm.designUnitsPerEm);
    out_metrics->glyph_box_top = static_cast<float>(fm.ascent);

    out_metrics->is_color = 0;
    IDWriteFontFace2* face2 = nullptr;
    if (SUCCEEDED(face->QueryInterface(__uuidof(IDWriteFontFace2), reinterpret_cast<void**>(&face2)))) {
        out_metrics->is_color = face2->IsColorFont() ? 1 : 0;
        face2->Release();
    }
    return 0;
}

int cwin_dwrite_font_face_get_glyph_indices(void* font_face, const uint32_t* codepoints, uint32_t count, uint16_t* out_glyph_indices) {
    if (!font_face || !codepoints || !out_glyph_indices) return (int)E_INVALIDARG;
    IDWriteFontFace* face = static_cast<IDWriteFontFace*>(font_face);
    return (int)face->GetGlyphIndices(codepoints, count, out_glyph_indices);
}

int cwin_dwrite_font_face_get_design_glyph_metrics(void* font_face, const uint16_t* glyph_indices, uint32_t count, struct CWinGlyphDesignMetrics* out_metrics) {
    if (!font_face || !glyph_indices || !out_metrics) return (int)E_INVALIDARG;
    IDWriteFontFace* face = static_cast<IDWriteFontFace*>(font_face);
    std::vector<DWRITE_GLYPH_METRICS> gm(count);
    HRESULT hr = face->GetDesignGlyphMetrics(glyph_indices, count, gm.data(), FALSE);
    if (FAILED(hr)) return (int)hr;

    for (uint32_t i = 0; i < count; ++i) {
        out_metrics[i].advance_width = static_cast<float>(gm[i].advanceWidth);
        out_metrics[i].left_side_bearing = static_cast<float>(gm[i].leftSideBearing);
        out_metrics[i].right_side_bearing = static_cast<float>(gm[i].rightSideBearing);
        out_metrics[i].top_side_bearing = static_cast<float>(gm[i].topSideBearing);
        out_metrics[i].advance_height = static_cast<float>(gm[i].advanceHeight);
        out_metrics[i].bottom_side_bearing = static_cast<float>(gm[i].bottomSideBearing);
        out_metrics[i].vertical_origin_y = static_cast<float>(gm[i].verticalOriginY);
    }
    return 0;
}

// Run extraction helpers
struct CWinInternalRunData {
    IDWriteFontFace* font_face;
    float font_size;
    uint32_t text_position;
    uint32_t string_length;
    std::vector<uint16_t> glyph_indices;
    std::vector<float> glyph_advances;
    std::vector<float> glyph_offsets_x;
    std::vector<float> glyph_offsets_y;
    std::vector<uint16_t> cluster_map;
    int is_color;

    CWinInternalRunData()
        : font_face(nullptr), font_size(0), text_position(0), string_length(0), is_color(0) {}

    ~CWinInternalRunData() {
        if (font_face) {
            font_face->Release();
            font_face = nullptr;
        }
    }
};

struct CWinExtractedRunCollection {
    std::vector<CWinInternalRunData*> runs;

    ~CWinExtractedRunCollection() {
        for (auto* r : runs) {
            delete r;
        }
        runs.clear();
    }
};

class CWinRunExtractRenderer : public IDWriteTextRenderer {
    LONG ref_count_;
    CWinExtractedRunCollection* collection_;

public:
    CWinRunExtractRenderer(CWinExtractedRunCollection* col)
        : ref_count_(1), collection_(col) {}

    ULONG STDMETHODCALLTYPE AddRef() noexcept override { return InterlockedIncrement(&ref_count_); }
    ULONG STDMETHODCALLTYPE Release() noexcept override {
        ULONG count = InterlockedDecrement(&ref_count_);
        if (count == 0) delete this;
        return count;
    }
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void** ppv) noexcept override {
        if (!ppv) return E_POINTER;
        if (riid == __uuidof(IUnknown) || riid == __uuidof(IDWritePixelSnapping) || riid == __uuidof(IDWriteTextRenderer)) {
            *ppv = static_cast<IDWriteTextRenderer*>(this);
            AddRef();
            return S_OK;
        }
        *ppv = nullptr;
        return E_NOINTERFACE;
    }

    HRESULT STDMETHODCALLTYPE IsPixelSnappingDisabled(void*, BOOL* disabled) noexcept override {
        if (!disabled) return E_POINTER;
        *disabled = FALSE;
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE GetCurrentTransform(void*, DWRITE_MATRIX* transform) noexcept override {
        if (!transform) return E_POINTER;
        transform->m11 = 1.0f; transform->m12 = 0.0f;
        transform->m21 = 0.0f; transform->m22 = 1.0f;
        transform->dx = 0.0f;  transform->dy = 0.0f;
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE GetPixelsPerDip(void*, FLOAT* pixelsPerDip) noexcept override {
        if (!pixelsPerDip) return E_POINTER;
        *pixelsPerDip = 1.0f;
        return S_OK;
    }

    HRESULT STDMETHODCALLTYPE DrawGlyphRun(
        void* clientDrawingContext,
        FLOAT baselineOriginX,
        FLOAT baselineOriginY,
        DWRITE_MEASURING_MODE measuringMode,
        const DWRITE_GLYPH_RUN* glyphRun,
        const DWRITE_GLYPH_RUN_DESCRIPTION* glyphRunDescription,
        IUnknown* clientDrawingEffect
    ) noexcept override {
        if (!glyphRun || glyphRun->glyphCount == 0 || !collection_) return S_OK;

        auto* run = new CWinInternalRunData();
        run->font_face = glyphRun->fontFace;
        if (run->font_face) {
            run->font_face->AddRef();
            IDWriteFontFace2* face2 = nullptr;
            if (SUCCEEDED(run->font_face->QueryInterface(__uuidof(IDWriteFontFace2), reinterpret_cast<void**>(&face2)))) {
                run->is_color = face2->IsColorFont() ? 1 : 0;
                face2->Release();
            } else {
                run->is_color = 0;
            }
        } else {
            run->is_color = 0;
        }
        run->font_size = glyphRun->fontEmSize;
        run->text_position = glyphRunDescription ? glyphRunDescription->textPosition : 0;
        run->string_length = glyphRunDescription ? glyphRunDescription->stringLength : 0;

        uint32_t count = glyphRun->glyphCount;
        run->glyph_indices.assign(glyphRun->glyphIndices, glyphRun->glyphIndices + count);
        if (glyphRun->glyphAdvances) {
            run->glyph_advances.assign(glyphRun->glyphAdvances, glyphRun->glyphAdvances + count);
        } else {
            run->glyph_advances.resize(count, 0.0f);
        }
        run->glyph_offsets_x.resize(count, 0.0f);
        run->glyph_offsets_y.resize(count, 0.0f);
        if (glyphRun->glyphOffsets) {
            for (uint32_t i = 0; i < count; ++i) {
                run->glyph_offsets_x[i] = glyphRun->glyphOffsets[i].advanceOffset;
                run->glyph_offsets_y[i] = glyphRun->glyphOffsets[i].ascenderOffset;
            }
        }
        if (glyphRunDescription && glyphRunDescription->clusterMap && glyphRunDescription->stringLength > 0) {
            run->cluster_map.assign(glyphRunDescription->clusterMap, glyphRunDescription->clusterMap + glyphRunDescription->stringLength);
        }

        collection_->runs.push_back(run);
        return S_OK;
    }

    HRESULT STDMETHODCALLTYPE DrawUnderline(void*, FLOAT, FLOAT, const DWRITE_UNDERLINE*, IUnknown*) noexcept override { return S_OK; }
    HRESULT STDMETHODCALLTYPE DrawStrikethrough(void*, FLOAT, FLOAT, const DWRITE_STRIKETHROUGH*, IUnknown*) noexcept override { return S_OK; }
    HRESULT STDMETHODCALLTYPE DrawInlineObject(void*, FLOAT, FLOAT, IDWriteInlineObject*, BOOL, BOOL, IUnknown*) noexcept override { return S_OK; }
};

int cwin_dwrite_layout_extract_runs(void* layout, void** out_runs_handle, uint32_t* out_count) {
    if (!layout || !out_runs_handle || !out_count) return (int)E_INVALIDARG;
    IDWriteTextLayout* tl = static_cast<IDWriteTextLayout*>(layout);

    auto* coll = new CWinExtractedRunCollection();
    auto* renderer = new CWinRunExtractRenderer(coll);
    HRESULT hr = tl->Draw(nullptr, renderer, 0.0f, 0.0f);
    renderer->Release();
    if (FAILED(hr)) {
        delete coll;
        return (int)hr;
    }
    *out_runs_handle = coll;
    *out_count = static_cast<uint32_t>(coll->runs.size());
    return 0;
}

int cwin_dwrite_get_extracted_run(void* runs_handle, uint32_t index, struct CWinShapedRunView* out_run) {
    if (!runs_handle || !out_run) return (int)E_INVALIDARG;
    auto* coll = static_cast<CWinExtractedRunCollection*>(runs_handle);
    if (index >= coll->runs.size()) return (int)E_INVALIDARG;

    auto* r = coll->runs[index];
    out_run->font_face = r->font_face;
    out_run->font_size = r->font_size;
    out_run->text_position = r->text_position;
    out_run->string_length = r->string_length;
    out_run->glyph_count = static_cast<uint32_t>(r->glyph_indices.size());
    out_run->glyph_indices = r->glyph_indices.data();
    out_run->glyph_advances = r->glyph_advances.data();
    out_run->glyph_offsets_x = r->glyph_offsets_x.data();
    out_run->glyph_offsets_y = r->glyph_offsets_y.data();
    out_run->cluster_count = static_cast<uint32_t>(r->cluster_map.size());
    out_run->cluster_map = r->cluster_map.empty() ? nullptr : r->cluster_map.data();
    out_run->is_color = r->is_color;
    return 0;
}

void cwin_dwrite_free_extracted_runs(void* runs_handle) {
    if (runs_handle) {
        delete static_cast<CWinExtractedRunCollection*>(runs_handle);
    }
}

int cwin_dwrite_rasterize_glyph(void* factory, const struct CWinGlyphRasterParams* params, struct CWinGlyphRasterResult* out_result) {
    if (!factory || !params || !params->font_face || !out_result) return (int)E_INVALIDARG;
    IDWriteFactory* f = static_cast<IDWriteFactory*>(factory);
    IDWriteFontFace* face = static_cast<IDWriteFontFace*>(params->font_face);

    UINT16 glyph_id = params->glyph_id;
    FLOAT advance = 0.0f;
    DWRITE_GLYPH_OFFSET offset = { 0.0f, 0.0f };
    DWRITE_GLYPH_RUN glyph_run = {};
    glyph_run.fontFace = face;
    glyph_run.fontEmSize = params->font_size;
    glyph_run.glyphCount = 1;
    glyph_run.glyphIndices = &glyph_id;
    glyph_run.glyphAdvances = &advance;
    glyph_run.glyphOffsets = &offset;

    FLOAT scale = (params->scale_factor > 0.0f) ? params->scale_factor : 1.0f;
    DWRITE_MATRIX transform = {};
    transform.m11 = scale;
    transform.m12 = 0.0f;
    transform.m21 = 0.0f;
    transform.m22 = scale;
    transform.dx = 0.0f;
    transform.dy = 0.0f;

    FLOAT baseline_origin_x = params->subpixel_bias_x / scale;
    FLOAT baseline_origin_y = params->subpixel_bias_y / scale;

    IDWriteGlyphRunAnalysis* analysis = nullptr;
    HRESULT hr = f->CreateGlyphRunAnalysis(
        &glyph_run,
        1.0f,
        &transform,
        DWRITE_RENDERING_MODE_NATURAL_SYMMETRIC,
        DWRITE_MEASURING_MODE_NATURAL,
        baseline_origin_x,
        baseline_origin_y,
        &analysis
    );
    if (FAILED(hr)) return (int)hr;

    RECT bounds = {};
    // MANDATORY GOTCHA FIX: Always request DWRITE_TEXTURE_CLEARTYPE_3x1 to prevent E_INVALIDARG!
    hr = analysis->GetAlphaTextureBounds(DWRITE_TEXTURE_CLEARTYPE_3x1, &bounds);
    if (FAILED(hr)) {
        analysis->Release();
        return (int)hr;
    }

    if (bounds.right <= bounds.left || bounds.bottom <= bounds.top) {
        analysis->Release();
        out_result->left = bounds.left;
        out_result->top = bounds.top;
        out_result->width = 0;
        out_result->height = 0;
        out_result->pixels = nullptr;
        out_result->pixel_bytes = 0;
        return 0;
    }

    uint32_t width = static_cast<uint32_t>(bounds.right - bounds.left);
    uint32_t height = static_cast<uint32_t>(bounds.bottom - bounds.top);
    uint32_t pixel_count = width * height;

    std::vector<uint8_t> rgb_buffer(static_cast<size_t>(pixel_count) * 3, 0);
    hr = analysis->CreateAlphaTexture(
        DWRITE_TEXTURE_CLEARTYPE_3x1,
        &bounds,
        rgb_buffer.data(),
        static_cast<UINT32>(rgb_buffer.size())
    );
    analysis->Release();
    if (FAILED(hr)) return (int)hr;

    if (params->subpixel_rendering) {
        uint32_t byte_size = pixel_count * 4;
        uint8_t* out_buf = static_cast<uint8_t*>(malloc(byte_size));
        if (!out_buf) return (int)E_OUTOFMEMORY;
        for (uint32_t i = 0; i < pixel_count; ++i) {
            out_buf[i * 4 + 0] = rgb_buffer[i * 3 + 0]; // R
            out_buf[i * 4 + 1] = rgb_buffer[i * 3 + 1]; // G
            out_buf[i * 4 + 2] = rgb_buffer[i * 3 + 2]; // B
            out_buf[i * 4 + 3] = 0;                      // A
        }
        out_result->left = bounds.left;
        out_result->top = bounds.top;
        out_result->width = static_cast<int32_t>(width);
        out_result->height = static_cast<int32_t>(height);
        out_result->pixels = out_buf;
        out_result->pixel_bytes = byte_size;
    } else {
        uint32_t byte_size = pixel_count;
        uint8_t* out_buf = static_cast<uint8_t*>(malloc(byte_size));
        if (!out_buf) return (int)E_OUTOFMEMORY;
        for (uint32_t i = 0; i < pixel_count; ++i) {
            uint32_t r = rgb_buffer[i * 3 + 0];
            uint32_t g = rgb_buffer[i * 3 + 1];
            uint32_t b = rgb_buffer[i * 3 + 2];
            out_buf[i] = static_cast<uint8_t>((r + g + b) / 3);
        }
        out_result->left = bounds.left;
        out_result->top = bounds.top;
        out_result->width = static_cast<int32_t>(width);
        out_result->height = static_cast<int32_t>(height);
        out_result->pixels = out_buf;
        out_result->pixel_bytes = byte_size;
    }
    return 0;
}

void cwin_dwrite_free_raster_result(struct CWinGlyphRasterResult* result) {
    if (result && result->pixels) {
        free(result->pixels);
        result->pixels = nullptr;
        result->pixel_bytes = 0;
    }
}

// MARK: - Win32 Windowing, Dispatcher, Keyboard, Clipboard

int cwin_win32_register_window_class(const uint16_t* class_name, void* wndproc, void** out_atom) {
    if (!class_name || !wndproc) return (int)E_INVALIDARG;

    WNDCLASSEXW wc = {};
    wc.cbSize = sizeof(WNDCLASSEXW);
    wc.style = CS_HREDRAW | CS_VREDRAW | CS_DBLCLKS;
    wc.lpfnWndProc = reinterpret_cast<WNDPROC>(wndproc);
    wc.cbClsExtra = 0;
    wc.cbWndExtra = 0;
    wc.hInstance = GetModuleHandleW(nullptr);
    wc.hIcon = LoadIconW(nullptr, IDI_APPLICATION);
    wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    wc.hbrBackground = nullptr;
    wc.lpszMenuName = nullptr;
    wc.lpszClassName = reinterpret_cast<const wchar_t*>(class_name);
    wc.hIconSm = nullptr;

    ATOM atom = RegisterClassExW(&wc);
    if (!atom) {
        DWORD err = GetLastError();
        if (err == ERROR_CLASS_ALREADY_EXISTS) {
            if (out_atom) *out_atom = reinterpret_cast<void*>(1);
            return 0;
        }
        return (int)HRESULT_FROM_WIN32(err);
    }

    if (out_atom) *out_atom = reinterpret_cast<void*>(static_cast<uintptr_t>(atom));
    return 0;
}

void* cwin_win32_create_window(uint32_t ex_style, const uint16_t* class_name, const uint16_t* title, uint32_t style, int x, int y, int w, int h, void* parent, void* param) {
    HWND hwnd = CreateWindowExW(
        static_cast<DWORD>(ex_style),
        reinterpret_cast<const wchar_t*>(class_name),
        title ? reinterpret_cast<const wchar_t*>(title) : L"",
        static_cast<DWORD>(style),
        x, y, w, h,
        static_cast<HWND>(parent),
        nullptr,
        GetModuleHandleW(nullptr),
        param
    );
    return static_cast<void*>(hwnd);
}

int cwin_win32_post_message(void* hwnd, uint32_t msg, uintptr_t wparam, intptr_t lparam) {
    BOOL ok = PostMessageW(
        static_cast<HWND>(hwnd),
        static_cast<UINT>(msg),
        static_cast<WPARAM>(wparam),
        static_cast<LPARAM>(lparam)
    );
    return ok ? 0 : (int)HRESULT_FROM_WIN32(GetLastError());
}

int cwin_win32_get_dpi_for_window(void* hwnd, uint32_t* out_dpi) {
    if (!out_dpi) return (int)E_INVALIDARG;
    HWND h = static_cast<HWND>(hwnd);

    typedef UINT(WINAPI* PFN_GetDpiForWindow)(HWND);
    static PFN_GetDpiForWindow pfnGetDpiForWindow =
        reinterpret_cast<PFN_GetDpiForWindow>(GetProcAddress(GetModuleHandleW(L"user32.dll"), "GetDpiForWindow"));

    if (pfnGetDpiForWindow && h) {
        UINT dpi = pfnGetDpiForWindow(h);
        if (dpi > 0) {
            *out_dpi = dpi;
            return 0;
        }
    }

    HDC dc = GetDC(h);
    if (dc) {
        int dpi = GetDeviceCaps(dc, LOGPIXELSX);
        ReleaseDC(h, dc);
        if (dpi > 0) {
            *out_dpi = static_cast<uint32_t>(dpi);
            return 0;
        }
    }

    *out_dpi = 96;
    return 0;
}

int cwin_win32_clipboard_set_text(void* hwnd, const uint16_t* text, size_t len) {
    if (!text) return (int)E_INVALIDARG;
    HWND h = static_cast<HWND>(hwnd);

    if (!OpenClipboard(h)) {
        return (int)HRESULT_FROM_WIN32(GetLastError());
    }

    EmptyClipboard();

    size_t byte_count = (len + 1) * sizeof(uint16_t);
    HGLOBAL h_glob = GlobalAlloc(GMEM_MOVEABLE, byte_count);
    if (!h_glob) {
        CloseClipboard();
        return (int)E_OUTOFMEMORY;
    }

    void* dest = GlobalLock(h_glob);
    if (!dest) {
        GlobalFree(h_glob);
        CloseClipboard();
        return (int)E_FAIL;
    }

    memcpy(dest, text, len * sizeof(uint16_t));
    static_cast<wchar_t*>(dest)[len] = L'\0';
    GlobalUnlock(h_glob);

    if (!SetClipboardData(CF_UNICODETEXT, h_glob)) {
        GlobalFree(h_glob);
        CloseClipboard();
        return (int)HRESULT_FROM_WIN32(GetLastError());
    }

    CloseClipboard();
    return 0;
}

int cwin_win32_clipboard_get_text(void* hwnd, uint16_t** out_text, size_t* out_len) {
    if (!out_text || !out_len) return (int)E_INVALIDARG;
    HWND h = static_cast<HWND>(hwnd);

    if (!OpenClipboard(h)) {
        return (int)HRESULT_FROM_WIN32(GetLastError());
    }

    HANDLE h_data = GetClipboardData(CF_UNICODETEXT);
    if (!h_data) {
        CloseClipboard();
        *out_text = nullptr;
        *out_len = 0;
        return 0;
    }

    const wchar_t* src = static_cast<const wchar_t*>(GlobalLock(h_data));
    if (!src) {
        CloseClipboard();
        return (int)E_FAIL;
    }

    size_t len = wcslen(src);
    wchar_t* buf = static_cast<wchar_t*>(malloc((len + 1) * sizeof(wchar_t)));
    if (!buf) {
        GlobalUnlock(h_data);
        CloseClipboard();
        return (int)E_OUTOFMEMORY;
    }

    memcpy(buf, src, (len + 1) * sizeof(wchar_t));
    GlobalUnlock(h_data);
    CloseClipboard();

    *out_text = reinterpret_cast<uint16_t*>(buf);
    *out_len = len;
    return 0;
}

void cwin_win32_clipboard_free_text(uint16_t* text) {
    if (text) {
        free(text);
    }
}

// MARK: - Win32 Windowing, Message Loop & Platform Lifecycle

int cwin_win32_ole_initialize(void) {
    HRESULT hr = OleInitialize(nullptr);
    return SUCCEEDED(hr) ? 0 : (int)hr;
}

void cwin_win32_ole_uninitialize(void) {
    OleUninitialize();
}

void* cwin_win32_create_message_window(const uint16_t* class_name, void* wndproc, void* param) {
    if (!class_name) return nullptr;
    HWND hwnd = CreateWindowExW(
        0,
        reinterpret_cast<const wchar_t*>(class_name),
        L"",
        0,
        0, 0, 0, 0,
        HWND_MESSAGE,
        nullptr,
        GetModuleHandleW(nullptr),
        param
    );
    return static_cast<void*>(hwnd);
}


int cwin_win32_destroy_window(void* hwnd) {
    if (!hwnd) return (int)E_INVALIDARG;
    BOOL ok = DestroyWindow(static_cast<HWND>(hwnd));
    return ok ? 0 : (int)HRESULT_FROM_WIN32(GetLastError());
}

intptr_t cwin_win32_def_window_proc(void* hwnd, uint32_t msg, uintptr_t wparam, intptr_t lparam) {
    return static_cast<intptr_t>(DefWindowProcW(
        static_cast<HWND>(hwnd),
        static_cast<UINT>(msg),
        static_cast<WPARAM>(wparam),
        static_cast<LPARAM>(lparam)
    ));
}

int cwin_win32_get_window_long_ptr(void* hwnd, int index, intptr_t* out_val) {
    if (!hwnd || !out_val) return (int)E_INVALIDARG;
    SetLastError(0);
    LONG_PTR val = GetWindowLongPtrW(static_cast<HWND>(hwnd), index);
    DWORD err = GetLastError();
    if (val == 0 && err != 0) {
        return (int)HRESULT_FROM_WIN32(err);
    }
    *out_val = static_cast<intptr_t>(val);
    return 0;
}

int cwin_win32_set_window_long_ptr(void* hwnd, int index, intptr_t new_val, intptr_t* out_old_val) {
    if (!hwnd) return (int)E_INVALIDARG;
    SetLastError(0);
    LONG_PTR old = SetWindowLongPtrW(static_cast<HWND>(hwnd), index, static_cast<LONG_PTR>(new_val));
    DWORD err = GetLastError();
    if (old == 0 && err != 0) {
        return (int)HRESULT_FROM_WIN32(err);
    }
    if (out_old_val) *out_old_val = static_cast<intptr_t>(old);
    return 0;
}

void cwin_win32_post_quit_message(int exit_code) {
    PostQuitMessage(exit_code);
}

int cwin_win32_get_message(void* out_msg, void* hwnd, uint32_t filter_min, uint32_t filter_max) {
    if (!out_msg) return -1;
    BOOL res = GetMessageW(
        static_cast<MSG*>(out_msg),
        static_cast<HWND>(hwnd),
        filter_min,
        filter_max
    );
    return static_cast<int>(res);
}

int cwin_win32_peek_message(void* out_msg, void* hwnd, uint32_t filter_min, uint32_t filter_max, uint32_t remove_flag) {
    if (!out_msg) return 0;
    BOOL res = PeekMessageW(
        static_cast<MSG*>(out_msg),
        static_cast<HWND>(hwnd),
        filter_min,
        filter_max,
        remove_flag
    );
    return res ? 1 : 0;
}

int cwin_win32_translate_message(const void* msg) {
    if (!msg) return 0;
    return TranslateMessage(static_cast<const MSG*>(msg)) ? 1 : 0;
}

intptr_t cwin_win32_dispatch_message(const void* msg) {
    if (!msg) return 0;
    return static_cast<intptr_t>(DispatchMessageW(static_cast<const MSG*>(msg)));
}

void* cwin_win32_get_active_window(void) {
    return static_cast<void*>(GetActiveWindow());
}

void cwin_win32_redraw_window(void* hwnd) {
    if (hwnd) {
        RedrawWindow(static_cast<HWND>(hwnd), nullptr, nullptr, RDW_INVALIDATE);
    }
}

// MARK: - Win32 Display & Monitor Enumeration

struct MonitorEnumContext {
    CWinMonitorInfo* out_monitors;
    uint32_t max_count;
    uint32_t count;
};

static BOOL CALLBACK EnumMonitorsCallback(HMONITOR hmon, HDC, LPRECT, LPARAM lparam) {
    auto* ctx = reinterpret_cast<MonitorEnumContext*>(lparam);
    if (ctx->count < ctx->max_count) {
        cwin_win32_get_monitor_info(static_cast<void*>(hmon), &ctx->out_monitors[ctx->count]);
        ctx->count++;
    }
    return TRUE;
}

int cwin_win32_get_monitors(struct CWinMonitorInfo* out_monitors, uint32_t max_count, uint32_t* out_count) {
    if (!out_monitors || !out_count) return (int)E_INVALIDARG;
    MonitorEnumContext ctx = { out_monitors, max_count, 0 };
    EnumDisplayMonitors(nullptr, nullptr, EnumMonitorsCallback, reinterpret_cast<LPARAM>(&ctx));
    *out_count = ctx.count;
    return 0;
}

void* cwin_win32_primary_monitor(void) {
    POINT pt = { 0, 0 };
    HMONITOR mon = MonitorFromPoint(pt, MONITOR_DEFAULTTOPRIMARY);
    return static_cast<void*>(mon);
}

void* cwin_win32_monitor_from_point(int32_t x, int32_t y, uint32_t flags) {
    POINT pt = { x, y };
    HMONITOR mon = MonitorFromPoint(pt, flags);
    return static_cast<void*>(mon);
}

int cwin_win32_get_monitor_info(void* hmonitor, struct CWinMonitorInfo* out_info) {
    if (!hmonitor || !out_info) return (int)E_INVALIDARG;
    HMONITOR mon = static_cast<HMONITOR>(hmonitor);

    MONITORINFOEXW mi = {};
    mi.cbSize = sizeof(MONITORINFOEXW);
    if (!GetMonitorInfoW(mon, reinterpret_cast<MONITORINFO*>(&mi))) {
        return (int)HRESULT_FROM_WIN32(GetLastError());
    }

    out_info->handle = hmonitor;
    out_info->monitor_left = mi.rcMonitor.left;
    out_info->monitor_top = mi.rcMonitor.top;
    out_info->monitor_right = mi.rcMonitor.right;
    out_info->monitor_bottom = mi.rcMonitor.bottom;
    out_info->work_left = mi.rcWork.left;
    out_info->work_top = mi.rcWork.top;
    out_info->work_right = mi.rcWork.right;
    out_info->work_bottom = mi.rcWork.bottom;
    wcsncpy(reinterpret_cast<wchar_t*>(out_info->device_name), mi.szDevice, 31);
    out_info->device_name[31] = 0;

    typedef HRESULT(WINAPI* PFN_GetDpiForMonitor)(HMONITOR, int, UINT*, UINT*);
    static PFN_GetDpiForMonitor pfnGetDpiForMonitor =
        reinterpret_cast<PFN_GetDpiForMonitor>(GetProcAddress(GetModuleHandleW(L"shcore.dll"), "GetDpiForMonitor"));

    UINT dpi_x = 96, dpi_y = 96;
    if (pfnGetDpiForMonitor) {
        pfnGetDpiForMonitor(mon, 0 /* MDT_EFFECTIVE_DPI */, &dpi_x, &dpi_y);
    }
    out_info->dpi_x = dpi_x;
    out_info->dpi_y = dpi_y;
    return 0;
}

// MARK: - Win32 DWM & VSync

int cwin_win32_dwm_flush(void) {
    HRESULT hr = DwmFlush();
    return SUCCEEDED(hr) ? 0 : (int)hr;
}

int cwin_win32_dwm_get_refresh_interval(double* out_interval_seconds) {
    if (!out_interval_seconds) return (int)E_INVALIDARG;

    DWM_TIMING_INFO timing = {};
    timing.cbSize = sizeof(DWM_TIMING_INFO);
    HRESULT hr = DwmGetCompositionTimingInfo(nullptr, &timing);
    if (SUCCEEDED(hr)) {
        LARGE_INTEGER qpc_freq;
        if (QueryPerformanceFrequency(&qpc_freq) && qpc_freq.QuadPart > 0 && timing.qpcRefreshPeriod > 0) {
            double interval = static_cast<double>(timing.qpcRefreshPeriod) / static_cast<double>(qpc_freq.QuadPart);
            if (interval >= 0.001) {
                *out_interval_seconds = interval;
                return 0;
            }
        }
        if (timing.rateRefresh.uiNumerator > 0 && timing.rateRefresh.uiDenominator > 0) {
            *out_interval_seconds = static_cast<double>(timing.rateRefresh.uiDenominator) /
                                    static_cast<double>(timing.rateRefresh.uiNumerator);
            return 0;
        }
    }

    *out_interval_seconds = 1.0 / 60.0;
    return 0;
}

int cwin_win32_dwm_set_dark_mode(void* hwnd, int enabled) {
    if (!hwnd) return (int)E_INVALIDARG;
    BOOL dark = enabled ? TRUE : FALSE;
    // DWMWA_USE_IMMERSIVE_DARK_MODE = 20
    HRESULT hr = DwmSetWindowAttribute(static_cast<HWND>(hwnd), 20, &dark, sizeof(BOOL));
    return SUCCEEDED(hr) ? 0 : (int)hr;
}

// MARK: - Win32 System Settings & Appearance

int cwin_win32_get_system_appearance(int* out_dark_mode) {
    if (!out_dark_mode) return (int)E_INVALIDARG;

    DWORD val = 1;
    DWORD val_size = sizeof(DWORD);
    LSTATUS status = RegGetValueW(
        HKEY_CURRENT_USER,
        L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
        L"AppsUseLightTheme",
        RRF_RT_REG_DWORD,
        nullptr,
        &val,
        &val_size
    );
    if (status == ERROR_SUCCESS) {
        *out_dark_mode = (val == 0) ? 1 : 0;
    } else {
        *out_dark_mode = 0;
    }
    return 0;
}

int cwin_win32_get_wheel_scroll_lines(uint32_t* out_lines) {
    if (!out_lines) return (int)E_INVALIDARG;
    UINT lines = 3;
    if (SystemParametersInfoW(SPI_GETWHEELSCROLLLINES, 0, &lines, 0)) {
        *out_lines = static_cast<uint32_t>(lines);
        return 0;
    }
    *out_lines = 3;
    return 0;
}

int cwin_win32_get_wheel_scroll_chars(uint32_t* out_chars) {
    if (!out_chars) return (int)E_INVALIDARG;
    UINT chars = 3;
    if (SystemParametersInfoW(SPI_GETWHEELSCROLLCHARS, 0, &chars, 0)) {
        *out_chars = static_cast<uint32_t>(chars);
        return 0;
    }
    *out_chars = 3;
    return 0;
}

int cwin_win32_should_auto_hide_scrollbars(int* out_auto_hide) {
    if (!out_auto_hide) return (int)E_INVALIDARG;
    BOOL auto_hide = FALSE;
    // SPI_GETAUTOHIDESCROLLBARS = 0x2014
    if (SystemParametersInfoW(0x2014, 0, &auto_hide, 0)) {
        *out_auto_hide = auto_hide ? 1 : 0;
        return 0;
    }
    *out_auto_hide = 0;
    return 0;
}

// MARK: - Win32 Timer & Thread Priority

void cwin_win32_time_begin_period(uint32_t period_ms) {
    typedef MMRESULT(WINAPI* PFN_timeBeginPeriod)(UINT);
    static PFN_timeBeginPeriod pfn = reinterpret_cast<PFN_timeBeginPeriod>(
        GetProcAddress(GetModuleHandleW(L"winmm.dll"), "timeBeginPeriod")
    );
    if (pfn) {
        pfn(period_ms);
    }
}

void cwin_win32_time_end_period(uint32_t period_ms) {
    typedef MMRESULT(WINAPI* PFN_timeEndPeriod)(UINT);
    static PFN_timeEndPeriod pfn = reinterpret_cast<PFN_timeEndPeriod>(
        GetProcAddress(GetModuleHandleW(L"winmm.dll"), "timeEndPeriod")
    );
    if (pfn) {
        pfn(period_ms);
    }
}

void cwin_win32_set_thread_realtime(void) {
    SetPriorityClass(GetCurrentProcess(), HIGH_PRIORITY_CLASS);
    SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_TIME_CRITICAL);
}

// MARK: - Win32 Cursor

void* cwin_win32_load_cursor(uint32_t style) {
    LPCWSTR name = IDC_ARROW;
    switch (style) {
        case 1: name = IDC_IBEAM; break;
        case 2: name = IDC_CROSS; break;
        case 3:
        case 4: name = IDC_HAND; break;
        case 5:
        case 6:
        case 7: name = IDC_SIZEWE; break;
        case 8:
        case 9:
        case 10: name = IDC_SIZENS; break;
        case 11:
        case 12: name = IDC_SIZENWSE; break;
        case 13:
        case 14: name = IDC_SIZENESW; break;
        case 15: name = IDC_NO; break;
        case 16: name = IDC_WAIT; break;
        default: name = IDC_ARROW; break;
    }
    HCURSOR h = LoadCursorW(nullptr, name);
    return static_cast<void*>(h);
}

void cwin_win32_set_cursor(void* cursor) {
    SetCursor(static_cast<HCURSOR>(cursor));
}

// MARK: - Win32 Credentials

int cwin_win32_cred_write(const uint16_t* target, const uint16_t* username, const uint8_t* blob, size_t blob_len) {
    if (!target || !username) return (int)E_INVALIDARG;

    CREDENTIALW cred = {};
    cred.Type = CRED_TYPE_GENERIC;
    cred.TargetName = const_cast<LPWSTR>(reinterpret_cast<const wchar_t*>(target));
    cred.UserName = const_cast<LPWSTR>(reinterpret_cast<const wchar_t*>(username));
    cred.CredentialBlobSize = static_cast<DWORD>(blob_len);
    cred.CredentialBlob = const_cast<LPBYTE>(blob);
    cred.Persist = CRED_PERSIST_LOCAL_MACHINE;

    BOOL ok = CredWriteW(&cred, 0);
    return ok ? 0 : (int)HRESULT_FROM_WIN32(GetLastError());
}

int cwin_win32_cred_read(const uint16_t* target, uint16_t** out_username, uint8_t** out_blob, size_t* out_blob_len) {
    if (!target || !out_username || !out_blob || !out_blob_len) return (int)E_INVALIDARG;

    PCREDENTIALW cred = nullptr;
    if (!CredReadW(reinterpret_cast<const wchar_t*>(target), CRED_TYPE_GENERIC, 0, &cred) || !cred) {
        DWORD err = GetLastError();
        if (err == ERROR_NOT_FOUND) {
            *out_username = nullptr;
            *out_blob = nullptr;
            *out_blob_len = 0;
            return 0;
        }
        return (int)HRESULT_FROM_WIN32(err);
    }

    size_t ulen = wcslen(cred->UserName ? cred->UserName : L"");
    wchar_t* ubuf = static_cast<wchar_t*>(malloc((ulen + 1) * sizeof(wchar_t)));
    if (!ubuf) {
        CredFree(cred);
        return (int)E_OUTOFMEMORY;
    }
    memcpy(ubuf, cred->UserName ? cred->UserName : L"", (ulen + 1) * sizeof(wchar_t));

    uint8_t* bbuf = nullptr;
    if (cred->CredentialBlobSize > 0 && cred->CredentialBlob) {
        bbuf = static_cast<uint8_t*>(malloc(cred->CredentialBlobSize));
        if (!bbuf) {
            free(ubuf);
            CredFree(cred);
            return (int)E_OUTOFMEMORY;
        }
        memcpy(bbuf, cred->CredentialBlob, cred->CredentialBlobSize);
    }

    *out_username = reinterpret_cast<uint16_t*>(ubuf);
    *out_blob = bbuf;
    *out_blob_len = cred->CredentialBlobSize;
    CredFree(cred);
    return 0;
}

int cwin_win32_cred_delete(const uint16_t* target) {
    if (!target) return (int)E_INVALIDARG;
    BOOL ok = CredDeleteW(reinterpret_cast<const wchar_t*>(target), CRED_TYPE_GENERIC, 0);
    return ok ? 0 : (int)HRESULT_FROM_WIN32(GetLastError());
}

void cwin_win32_cred_free(void* ptr) {
    if (ptr) {
        free(ptr);
    }
}

// MARK: - Win32 Shell & Dialogs

int cwin_win32_shell_open(const uint16_t* path_or_url) {
    if (!path_or_url) return (int)E_INVALIDARG;
    HINSTANCE h = ShellExecuteW(nullptr, L"open", reinterpret_cast<const wchar_t*>(path_or_url), nullptr, nullptr, SW_SHOWDEFAULT);
    if (reinterpret_cast<intptr_t>(h) <= 32) {
        return (int)HRESULT_FROM_WIN32(GetLastError());
    }
    return 0;
}

int cwin_win32_shell_reveal(const uint16_t* path) {
    if (!path) return (int)E_INVALIDARG;
    PIDLIST_ABSOLUTE pidl = ILCreateFromPathW(reinterpret_cast<const wchar_t*>(path));
    if (!pidl) {
        return cwin_win32_shell_open(path);
    }
    HRESULT hr = SHOpenFolderAndSelectItems(pidl, 0, nullptr, 0);
    ILFree(pidl);
    return SUCCEEDED(hr) ? 0 : (int)hr;
}

int cwin_win32_file_open_dialog(void* hwnd, int allow_multi, int pick_folders, const uint16_t* ok_label, uint16_t*** out_paths, size_t* out_count) {
    if (!out_paths || !out_count) return (int)E_INVALIDARG;
    *out_paths = nullptr;
    *out_count = 0;

    IFileOpenDialog* dlg = nullptr;
    HRESULT hr = CoCreateInstance(__uuidof(FileOpenDialog), nullptr, CLSCTX_ALL, IID_PPV_ARGS(&dlg));
    if (FAILED(hr)) return (int)hr;

    FILEOPENDIALOGOPTIONS options = FOS_FILEMUSTEXIST;
    if (allow_multi) options |= FOS_ALLOWMULTISELECT;
    if (pick_folders) options |= FOS_PICKFOLDERS;
    dlg->SetOptions(options);

    if (ok_label && wcslen(reinterpret_cast<const wchar_t*>(ok_label)) > 0) {
        dlg->SetOkButtonLabel(reinterpret_cast<const wchar_t*>(ok_label));
    }

    hr = dlg->Show(static_cast<HWND>(hwnd));
    if (FAILED(hr)) {
        dlg->Release();
        return 0; // User cancelled
    }

    IShellItemArray* items = nullptr;
    hr = dlg->GetResults(&items);
    if (FAILED(hr)) {
        dlg->Release();
        return (int)hr;
    }

    DWORD count = 0;
    items->GetCount(&count);
    if (count == 0) {
        items->Release();
        dlg->Release();
        return 0;
    }

    wchar_t** paths = static_cast<wchar_t**>(malloc(count * sizeof(wchar_t*)));
    if (!paths) {
        items->Release();
        dlg->Release();
        return (int)E_OUTOFMEMORY;
    }

    size_t actual_count = 0;
    for (DWORD i = 0; i < count; ++i) {
        IShellItem* item = nullptr;
        if (SUCCEEDED(items->GetItemAt(i, &item))) {
            LPWSTR pszPath = nullptr;
            if (SUCCEEDED(item->GetDisplayName(SIGDN_FILESYSPATH, &pszPath)) && pszPath) {
                size_t len = wcslen(pszPath);
                wchar_t* copy = static_cast<wchar_t*>(malloc((len + 1) * sizeof(wchar_t)));
                if (copy) {
                    memcpy(copy, pszPath, (len + 1) * sizeof(wchar_t));
                    paths[actual_count++] = copy;
                }
                CoTaskMemFree(pszPath);
            }
            item->Release();
        }
    }

    items->Release();
    dlg->Release();

    *out_paths = reinterpret_cast<uint16_t**>(paths);
    *out_count = actual_count;
    return 0;
}

int cwin_win32_file_save_dialog(void* hwnd, const uint16_t* initial_dir, const uint16_t* default_name, uint16_t** out_path) {
    if (!out_path) return (int)E_INVALIDARG;
    *out_path = nullptr;

    IFileSaveDialog* dlg = nullptr;
    HRESULT hr = CoCreateInstance(__uuidof(FileSaveDialog), nullptr, CLSCTX_ALL, IID_PPV_ARGS(&dlg));
    if (FAILED(hr)) return (int)hr;

    if (default_name && wcslen(reinterpret_cast<const wchar_t*>(default_name)) > 0) {
        dlg->SetFileName(reinterpret_cast<const wchar_t*>(default_name));
    }
    if (initial_dir && wcslen(reinterpret_cast<const wchar_t*>(initial_dir)) > 0) {
        IShellItem* folder = nullptr;
        if (SUCCEEDED(SHCreateItemFromParsingName(reinterpret_cast<const wchar_t*>(initial_dir), nullptr, IID_PPV_ARGS(&folder)))) {
            dlg->SetFolder(folder);
            folder->Release();
        }
    }

    hr = dlg->Show(static_cast<HWND>(hwnd));
    if (FAILED(hr)) {
        dlg->Release();
        return 0; // User cancelled
    }

    IShellItem* item = nullptr;
    hr = dlg->GetResult(&item);
    if (FAILED(hr)) {
        dlg->Release();
        return (int)hr;
    }

    LPWSTR pszPath = nullptr;
    hr = item->GetDisplayName(SIGDN_FILESYSPATH, &pszPath);
    item->Release();
    dlg->Release();

    if (SUCCEEDED(hr) && pszPath) {
        size_t len = wcslen(pszPath);
        wchar_t* copy = static_cast<wchar_t*>(malloc((len + 1) * sizeof(wchar_t)));
        if (copy) {
            memcpy(copy, pszPath, (len + 1) * sizeof(wchar_t));
            *out_path = reinterpret_cast<uint16_t*>(copy);
        }
        CoTaskMemFree(pszPath);
    }
    return 0;
}

void cwin_win32_free_path_list(uint16_t** paths, size_t count) {
    if (paths) {
        for (size_t i = 0; i < count; ++i) {
            if (paths[i]) free(paths[i]);
        }
        free(paths);
    }
}


// MARK: - Win32 Keyboard & Input

int cwin_win32_get_keyboard_layout_name(uint16_t* out_name, size_t max_len) {
    if (!out_name || max_len < 9) return (int)E_INVALIDARG;
    wchar_t buf[KL_NAMELENGTH] = {0};
    if (!GetKeyboardLayoutNameW(buf)) {
        return (int)HRESULT_FROM_WIN32(GetLastError());
    }
    wcsncpy(reinterpret_cast<wchar_t*>(out_name), buf, max_len - 1);
    out_name[max_len - 1] = 0;
    return 0;
}

int cwin_win32_get_keyboard_layout_text(const uint16_t* layout_id, uint16_t* out_text, size_t max_len) {
    if (!layout_id || !out_text || max_len == 0) return (int)E_INVALIDARG;
    std::wstring subkey = L"System\\CurrentControlSet\\Control\\Keyboard Layouts\\";
    subkey += reinterpret_cast<const wchar_t*>(layout_id);

    HKEY hkey = nullptr;
    if (RegOpenKeyExW(HKEY_LOCAL_MACHINE, subkey.c_str(), 0, KEY_READ, &hkey) != ERROR_SUCCESS) {
        return (int)E_FAIL;
    }

    DWORD type = 0;
    DWORD byte_count = (DWORD)(max_len * sizeof(wchar_t));
    LONG res = RegQueryValueExW(hkey, L"Layout Text", nullptr, &type, reinterpret_cast<LPBYTE>(out_text), &byte_count);
    RegCloseKey(hkey);

    if (res != ERROR_SUCCESS) {
        return (int)E_FAIL;
    }
    out_text[max_len - 1] = 0;
    return 0;
}

uint32_t cwin_win32_map_virtual_key(uint32_t uCode, uint32_t uMapType) {
    return MapVirtualKeyW(uCode, uMapType);
}

int cwin_win32_to_unicode(uint32_t vkey, uint32_t scan_code, const uint8_t* key_state, uint16_t* out_buffer, int buffer_size, uint32_t flags) {
    if (!out_buffer || buffer_size <= 0) return 0;
    return ToUnicode(vkey, scan_code, key_state, reinterpret_cast<wchar_t*>(out_buffer), buffer_size, flags);
}

int16_t cwin_win32_get_key_state(int vkey) {
    return GetKeyState(vkey);
}

int cwin_win32_get_keyboard_state(uint8_t* out_state_256) {
    if (!out_state_256) return (int)E_INVALIDARG;
    return GetKeyboardState(out_state_256) ? 0 : (int)HRESULT_FROM_WIN32(GetLastError());
}

uint32_t cwin_win32_get_double_click_time(void) {
    return GetDoubleClickTime();
}

void cwin_win32_get_double_click_tolerance(int32_t* out_width, int32_t* out_height) {
    if (out_width) *out_width = GetSystemMetrics(SM_CXDOUBLECLK);
    if (out_height) *out_height = GetSystemMetrics(SM_CYDOUBLECLK);
}

int32_t cwin_win32_get_frame_thickness_x(uint32_t dpi) {
    int resize_frame = GetSystemMetricsForDpi(SM_CXSIZEFRAME, dpi);
    int padding = GetSystemMetricsForDpi(SM_CXPADDEDBORDER, dpi);
    return resize_frame + padding;
}

int32_t cwin_win32_get_frame_thickness_y(uint32_t dpi) {
    int resize_frame = GetSystemMetricsForDpi(SM_CYSIZEFRAME, dpi);
    int padding = GetSystemMetricsForDpi(SM_CXPADDEDBORDER, dpi);
    return resize_frame + padding;
}

void cwin_win32_notify_frame_changed(void* hwnd) {
    if (!hwnd) return;
    SetWindowPos(static_cast<HWND>(hwnd), nullptr, 0, 0, 0, 0,
                 SWP_FRAMECHANGED | SWP_NOACTIVATE | SWP_NOCOPYBITS | SWP_NOMOVE |
                 SWP_NOOWNERZORDER | SWP_NOREPOSITION | SWP_NOSENDCHANGING | SWP_NOSIZE | SWP_NOZORDER);
}

// MARK: - Win32 Enhanced Clipboard

int cwin_win32_clipboard_open(void* hwnd) {
    return OpenClipboard(static_cast<HWND>(hwnd)) ? 0 : (int)HRESULT_FROM_WIN32(GetLastError());
}

int cwin_win32_clipboard_close(void) {
    return CloseClipboard() ? 0 : (int)HRESULT_FROM_WIN32(GetLastError());
}

int cwin_win32_clipboard_empty(void) {
    return EmptyClipboard() ? 0 : (int)HRESULT_FROM_WIN32(GetLastError());
}

uint32_t cwin_win32_clipboard_register_format(const uint16_t* format_name) {
    if (!format_name) return 0;
    return RegisterClipboardFormatW(reinterpret_cast<const wchar_t*>(format_name));
}

int cwin_win32_clipboard_get_format_name(uint32_t format, uint16_t* out_name, size_t max_len) {
    if (!out_name || max_len == 0) return (int)E_INVALIDARG;
    int ret = GetClipboardFormatNameW(format, reinterpret_cast<wchar_t*>(out_name), (int)max_len);
    return ret > 0 ? 0 : (int)HRESULT_FROM_WIN32(GetLastError());
}

int cwin_win32_clipboard_is_format_available(uint32_t format) {
    return IsClipboardFormatAvailable(format) ? 1 : 0;
}

int cwin_win32_clipboard_count_formats(void) {
    return CountClipboardFormats();
}

uint32_t cwin_win32_clipboard_enum_formats(uint32_t format) {
    return EnumClipboardFormats(format);
}

int cwin_win32_clipboard_set_binary_data(uint32_t format, const void* data, size_t len) {
    if (!data && len > 0) return (int)E_INVALIDARG;
    HGLOBAL h_glob = GlobalAlloc(GMEM_MOVEABLE, len);
    if (!h_glob) return (int)E_OUTOFMEMORY;
    if (len > 0) {
        void* dest = GlobalLock(h_glob);
        if (!dest) {
            GlobalFree(h_glob);
            return (int)E_FAIL;
        }
        memcpy(dest, data, len);
        GlobalUnlock(h_glob);
    }
    if (!SetClipboardData(format, h_glob)) {
        GlobalFree(h_glob);
        return (int)HRESULT_FROM_WIN32(GetLastError());
    }
    return 0;
}

int cwin_win32_clipboard_get_binary_data(uint32_t format, void** out_data, size_t* out_len) {
    if (!out_data || !out_len) return (int)E_INVALIDARG;
    *out_data = nullptr;
    *out_len = 0;
    HANDLE h_data = GetClipboardData(format);
    if (!h_data) return (int)HRESULT_FROM_WIN32(GetLastError());
    SIZE_T sz = GlobalSize((HGLOBAL)h_data);
    if (sz == 0) return 0;
    const void* src = GlobalLock((HGLOBAL)h_data);
    if (!src) return (int)E_FAIL;
    void* copy = malloc(sz);
    if (!copy) {
        GlobalUnlock((HGLOBAL)h_data);
        return (int)E_OUTOFMEMORY;
    }
    memcpy(copy, src, sz);
    GlobalUnlock((HGLOBAL)h_data);
    *out_data = copy;
    *out_len = (size_t)sz;
    return 0;
}

void cwin_win32_clipboard_free_binary_data(void* data) {
    if (data) free(data);
}

int cwin_win32_clipboard_get_hdrop_files(void* hdrop, uint16_t*** out_files, size_t* out_count) {
    if (!hdrop || !out_files || !out_count) return (int)E_INVALIDARG;
    *out_files = nullptr;
    *out_count = 0;
    HDROP drop = static_cast<HDROP>(hdrop);
    UINT count = DragQueryFileW(drop, 0xFFFFFFFF, nullptr, 0);
    if (count == 0) return 0;
    wchar_t** files = static_cast<wchar_t**>(malloc(count * sizeof(wchar_t*)));
    if (!files) return (int)E_OUTOFMEMORY;
    for (UINT i = 0; i < count; ++i) {
        UINT len = DragQueryFileW(drop, i, nullptr, 0);
        wchar_t* buf = static_cast<wchar_t*>(malloc((len + 1) * sizeof(wchar_t)));
        if (!buf) {
            for (UINT j = 0; j < i; ++j) free(files[j]);
            free(files);
            return (int)E_OUTOFMEMORY;
        }
        DragQueryFileW(drop, i, buf, len + 1);
        files[i] = buf;
    }
    *out_files = reinterpret_cast<uint16_t**>(files);
    *out_count = (size_t)count;
    return 0;
}

void cwin_win32_clipboard_free_hdrop_files(uint16_t** files, size_t count) {
    if (files) {
        for (size_t i = 0; i < count; ++i) {
            if (files[i]) free(files[i]);
        }
        free(files);
    }
}

int cwin_win32_clipboard_get_files(uint16_t*** out_files, size_t* out_count) {
    if (!out_files || !out_count) return (int)E_INVALIDARG;
    *out_files = nullptr;
    *out_count = 0;
    HANDLE h_data = GetClipboardData(CF_HDROP);
    if (!h_data) return (int)HRESULT_FROM_WIN32(GetLastError());
    return cwin_win32_clipboard_get_hdrop_files(h_data, out_files, out_count);
}

// MARK: - Win32 DirectManipulation

class CWinDirectManipulationHandler : public IDirectManipulationViewportEventHandler {
public:
    CWinDirectManipulationHandler(HWND hwnd, float scale)
        : ref_count_(1), hwnd_(hwnd), scale_factor_(scale),
          gesture_kind_(0), last_scale_(1.0f), last_x_(0.0f), last_y_(0.0f),
          scroll_phase_(0), manager_(nullptr), update_manager_(nullptr),
          viewport_(nullptr), cookie_(0) {}

    void Shutdown() {
        if (viewport_) {
            if (cookie_ != 0) {
                viewport_->RemoveEventHandler(cookie_);
                cookie_ = 0;
            }
            viewport_->Stop();
            viewport_->Abandon();
            viewport_->Release();
            viewport_ = nullptr;
        }
        if (manager_) {
            manager_->Deactivate(hwnd_);
            manager_->Release();
            manager_ = nullptr;
        }
        if (update_manager_) {
            update_manager_->Release();
            update_manager_ = nullptr;
        }
    }

    virtual ~CWinDirectManipulationHandler() {
        Shutdown();
    }

    HRESULT Init() {
        HRESULT hr = CoCreateInstance(__uuidof(DirectManipulationManager), nullptr, CLSCTX_INPROC_SERVER,
                                      __uuidof(IDirectManipulationManager), reinterpret_cast<void**>(&manager_));
        if (FAILED(hr)) { Shutdown(); return hr; }

        hr = manager_->GetUpdateManager(__uuidof(IDirectManipulationUpdateManager), reinterpret_cast<void**>(&update_manager_));
        if (FAILED(hr)) { Shutdown(); return hr; }

        hr = manager_->CreateViewport(nullptr, hwnd_, __uuidof(IDirectManipulationViewport), reinterpret_cast<void**>(&viewport_));
        if (FAILED(hr)) { Shutdown(); return hr; }

        DWORD config = DIRECTMANIPULATION_CONFIGURATION_INTERACTION
                     | DIRECTMANIPULATION_CONFIGURATION_TRANSLATION_X
                     | DIRECTMANIPULATION_CONFIGURATION_TRANSLATION_Y
                     | DIRECTMANIPULATION_CONFIGURATION_TRANSLATION_INERTIA
                     | DIRECTMANIPULATION_CONFIGURATION_RAILS_X
                     | DIRECTMANIPULATION_CONFIGURATION_RAILS_Y
                     | DIRECTMANIPULATION_CONFIGURATION_SCALING;
        viewport_->ActivateConfiguration(config);
        viewport_->SetViewportOptions(DIRECTMANIPULATION_VIEWPORT_OPTIONS_MANUALUPDATE | DIRECTMANIPULATION_VIEWPORT_OPTIONS_DISABLEPIXELSNAPPING);

        RECT rc = { 0, 0, 1000, 1000 };
        viewport_->SetViewportRect(&rc);

        manager_->Activate(hwnd_);
        viewport_->Enable();

        viewport_->AddEventHandler(hwnd_, this, &cookie_);
        update_manager_->Update(nullptr);
        return S_OK;
    }

    // IUnknown
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void** ppvObject) noexcept override {
        if (!ppvObject) return E_POINTER;
        if (riid == __uuidof(IUnknown) || riid == __uuidof(IDirectManipulationViewportEventHandler)) {
            *ppvObject = static_cast<IDirectManipulationViewportEventHandler*>(this);
            AddRef();
            return S_OK;
        }
        *ppvObject = nullptr;
        return E_NOINTERFACE;
    }

    ULONG STDMETHODCALLTYPE AddRef() noexcept override {
        return InterlockedIncrement(&ref_count_);
    }

    ULONG STDMETHODCALLTYPE Release() noexcept override {
        ULONG count = InterlockedDecrement(&ref_count_);
        if (count == 0) delete this;
        return count;
    }

    // IDirectManipulationViewportEventHandler
    HRESULT STDMETHODCALLTYPE OnViewportStatusChanged(IDirectManipulationViewport* viewport, DIRECTMANIPULATION_STATUS current, DIRECTMANIPULATION_STATUS previous) noexcept override {
        if (current == previous) return S_OK;
        if (current == DIRECTMANIPULATION_RUNNING && previous == DIRECTMANIPULATION_INERTIA) {
            EndGesture();
        }
        if (current == DIRECTMANIPULATION_READY) {
            EndGesture();
            if (last_scale_ != 1.0f || last_x_ != 0.0f || last_y_ != 0.0f) {
                if (viewport) {
                    viewport->ZoomToRect(0.0f, 0.0f, 1000.0f, 1000.0f, FALSE);
                }
            }
            last_scale_ = 1.0f;
            last_x_ = 0.0f;
            last_y_ = 0.0f;
        }
        return S_OK;
    }

    HRESULT STDMETHODCALLTYPE OnViewportUpdated(IDirectManipulationViewport*) noexcept override {
        return S_OK;
    }

    HRESULT STDMETHODCALLTYPE OnContentUpdated(IDirectManipulationViewport*, IDirectManipulationContent* content) noexcept override {
        if (!content) return E_POINTER;
        float xform[6] = {0};
        HRESULT hr = content->GetContentTransform(xform, 6);
        if (FAILED(hr)) return hr;

        float scale = xform[0];
        float sf = scale_factor_ > 0.0f ? scale_factor_ : 1.0f;
        float x_offset = xform[4] / sf;
        float y_offset = xform[5] / sf;

        if (scale == 0.0f) return S_OK;
        if (FloatEquals(scale, last_scale_) && FloatEquals(x_offset, last_x_) && FloatEquals(y_offset, last_y_)) {
            return S_OK;
        }

        POINT pt = {0};
        GetCursorPos(&pt);
        ScreenToClient(hwnd_, &pt);
        float mouse_x = (float)pt.x / sf;
        float mouse_y = (float)pt.y / sf;

        if (!FloatEquals(scale, 1.0f)) {
            if (gesture_kind_ != 2 /* Pinch */) {
                EndGesture();
                gesture_kind_ = 2;
                CWinDmEvent ev = { 2, mouse_x, mouse_y, 0, 0, 0.0f, 0 /* Started */ };
                events_.push_back(ev);
            }
        } else if (gesture_kind_ == 0) {
            gesture_kind_ = 1; /* Scroll */
            scroll_phase_ = 0; /* Started */
        }

        if (gesture_kind_ == 1) {
            float dx = x_offset - last_x_;
            float dy = y_offset - last_y_;
            int phase = scroll_phase_;
            scroll_phase_ = 1; /* Moved */
            CWinDmEvent ev = { 1, mouse_x, mouse_y, dx, dy, 0.0f, phase };
            events_.push_back(ev);
        } else if (gesture_kind_ == 2) {
            float scale_delta = scale / (last_scale_ > 0.0f ? last_scale_ : 1.0f);
            CWinDmEvent ev = { 2, mouse_x, mouse_y, 0, 0, scale_delta - 1.0f, 1 /* Moved */ };
            events_.push_back(ev);
        }

        last_scale_ = scale;
        last_x_ = x_offset;
        last_y_ = y_offset;
        return S_OK;
    }

    void SetScaleFactor(float sf) { scale_factor_ = sf; }

    void OnPointerHitTest(uintptr_t wparam) {
        UINT32 pointer_id = LOWORD(wparam);
        POINTER_INPUT_TYPE type = PT_POINTER;
        if (GetPointerType(pointer_id, &type) && type == PT_TOUCHPAD && viewport_) {
            viewport_->SetContact(pointer_id);
        }
    }

    void Update() {
        if (update_manager_) update_manager_->Update(nullptr);
    }

    int DrainEvents(CWinDmEvent* out_events, uint32_t max_count, uint32_t* out_count) {
        if (!out_count) return (int)E_INVALIDARG;
        uint32_t count = (uint32_t)std::min<size_t>(events_.size(), max_count);
        for (uint32_t i = 0; i < count; ++i) {
            out_events[i] = events_[i];
        }
        events_.erase(events_.begin(), events_.begin() + count);
        *out_count = count;
        return 0;
    }

private:
    void EndGesture() {
        POINT pt = {0};
        GetCursorPos(&pt);
        ScreenToClient(hwnd_, &pt);
        float sf = scale_factor_ > 0.0f ? scale_factor_ : 1.0f;
        float mouse_x = (float)pt.x / sf;
        float mouse_y = (float)pt.y / sf;

        if (gesture_kind_ == 1) {
            CWinDmEvent ev = { 1, mouse_x, mouse_y, 0, 0, 0.0f, 2 /* Ended */ };
            events_.push_back(ev);
        } else if (gesture_kind_ == 2) {
            CWinDmEvent ev = { 2, mouse_x, mouse_y, 0, 0, 0.0f, 2 /* Ended */ };
            events_.push_back(ev);
        }
        gesture_kind_ = 0;
    }

    static bool FloatEquals(float a, float b) {
        float diff = std::abs(a - b);
        float max_val = std::max(std::abs(a), std::abs(b));
        return diff < 0.00001f * std::max(max_val, 0.00001f);
    }

    LONG ref_count_;
    HWND hwnd_;
    float scale_factor_;
    int gesture_kind_; // 0 = none, 1 = scroll, 2 = pinch
    float last_scale_;
    float last_x_;
    float last_y_;
    int scroll_phase_;
    IDirectManipulationManager* manager_;
    IDirectManipulationUpdateManager* update_manager_;
    IDirectManipulationViewport* viewport_;
    DWORD cookie_;
    std::vector<CWinDmEvent> events_;
};

void* cwin_dm_create_handler(void* hwnd, float scale_factor) {
    if (!hwnd) return nullptr;
    auto* handler = new CWinDirectManipulationHandler(static_cast<HWND>(hwnd), scale_factor);
    if (FAILED(handler->Init())) {
        handler->Shutdown();
        handler->Release();
        return nullptr;
    }
    return handler;
}

void cwin_dm_destroy_handler(void* handler) {
    if (handler) {
        auto* h = static_cast<CWinDirectManipulationHandler*>(handler);
        h->Shutdown();
        h->Release();
    }
}

void cwin_dm_set_scale_factor(void* handler, float scale_factor) {
    if (handler) {
        static_cast<CWinDirectManipulationHandler*>(handler)->SetScaleFactor(scale_factor);
    }
}

void cwin_dm_on_pointer_hit_test(void* handler, uintptr_t wparam) {
    if (handler) {
        static_cast<CWinDirectManipulationHandler*>(handler)->OnPointerHitTest(wparam);
    }
}

void cwin_dm_update(void* handler) {
    if (handler) {
        static_cast<CWinDirectManipulationHandler*>(handler)->Update();
    }
}

int cwin_dm_drain_events(void* handler, struct CWinDmEvent* out_events, uint32_t max_count, uint32_t* out_count) {
    if (!handler || !out_events || !out_count) {
        if (out_count) *out_count = 0;
        return 0;
    }
    return static_cast<CWinDirectManipulationHandler*>(handler)->DrainEvents(out_events, max_count, out_count);
}

#else

// Intentionally empty on non-Windows platforms.
typedef int gpua_winsys_unused_cpp_t;

#endif
