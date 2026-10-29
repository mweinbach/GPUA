// Swift-only: C++ implementation of CWinSys COM and Win32 bridge functions
#if defined(_WIN32)

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

#include <cstdlib>
#include <cstring>
#include <vector>
#include <string>

#include "CWinSys.h"

// MARK: - Direct3D 11 & DXGI

void cwin_release_com_object(void* obj) {
    if (obj) {
        IUnknown* unk = static_cast<IUnknown*>(obj);
        unk->Release();
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

// MARK: - DirectWrite

namespace {

struct FontMemoryPayload {
    const void* data;
    UINT32 size;
};

class MemoryFontFileStream : public IDWriteFontFileStream {
    LONG ref_count_;
    const void* data_;
    UINT32 size_;

public:
    MemoryFontFileStream(const void* data, UINT32 size)
        : ref_count_(1), data_(data), size_(size) {}

    ULONG STDMETHODCALLTYPE AddRef() override { return InterlockedIncrement(&ref_count_); }
    ULONG STDMETHODCALLTYPE Release() override {
        ULONG count = InterlockedDecrement(&ref_count_);
        if (count == 0) delete this;
        return count;
    }
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void** ppv) override {
        if (!ppv) return E_POINTER;
        if (riid == __uuidof(IUnknown) || riid == __uuidof(IDWriteFontFileStream)) {
            *ppv = static_cast<IDWriteFontFileStream*>(this);
            AddRef();
            return S_OK;
        }
        *ppv = nullptr;
        return E_NOINTERFACE;
    }

    HRESULT STDMETHODCALLTYPE ReadFileFragment(const void** fragmentStart, UINT64 fileOffset, UINT64 fragmentSize, void** fragmentContext) override {
        if (fileOffset + fragmentSize > size_) return E_INVALIDARG;
        *fragmentStart = static_cast<const uint8_t*>(data_) + fileOffset;
        *fragmentContext = nullptr;
        return S_OK;
    }
    void STDMETHODCALLTYPE ReleaseFileFragment(void* fragmentContext) override {}
    HRESULT STDMETHODCALLTYPE GetFileSize(UINT64* fileSize) override {
        if (!fileSize) return E_POINTER;
        *fileSize = size_;
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE GetLastWriteTime(UINT64* lastWriteTime) override {
        if (!lastWriteTime) return E_POINTER;
        *lastWriteTime = 0;
        return S_OK;
    }
};

class MemoryFontFileLoader : public IDWriteFontFileLoader {
    LONG ref_count_;
public:
    MemoryFontFileLoader() : ref_count_(1) {}

    ULONG STDMETHODCALLTYPE AddRef() override { return InterlockedIncrement(&ref_count_); }
    ULONG STDMETHODCALLTYPE Release() override {
        ULONG count = InterlockedDecrement(&ref_count_);
        if (count == 0) delete this;
        return count;
    }
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void** ppv) override {
        if (!ppv) return E_POINTER;
        if (riid == __uuidof(IUnknown) || riid == __uuidof(IDWriteFontFileLoader)) {
            *ppv = static_cast<IDWriteFontFileLoader*>(this);
            AddRef();
            return S_OK;
        }
        *ppv = nullptr;
        return E_NOINTERFACE;
    }

    HRESULT STDMETHODCALLTYPE CreateStreamFromKey(const void* fontFileReferenceKey, UINT32 fontFileReferenceKeySize, IDWriteFontFileStream** fontFileStream) override {
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

    ULONG STDMETHODCALLTYPE AddRef() override { return InterlockedIncrement(&ref_count_); }
    ULONG STDMETHODCALLTYPE Release() override {
        ULONG count = InterlockedDecrement(&ref_count_);
        if (count == 0) delete this;
        return count;
    }
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void** ppv) override {
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

    IDWriteFactory3* f3 = nullptr;
    HRESULT hr = static_cast<IUnknown*>(factory)->QueryInterface(__uuidof(IDWriteFactory3), reinterpret_cast<void**>(&f3));
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
    IDWriteFontSetBuilder* b = static_cast<IDWriteFontSetBuilder*>(builder);
    IDWriteFontFile* f = static_cast<IDWriteFontFile*>(font_file);
    HRESULT hr = b->AddFontFile(f);
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

int cwin_dwrite_create_text_format(void* factory, const wchar_t* family_name, void* collection, uint32_t weight, uint32_t style, float font_size, void** out_format) {
    if (!factory || !family_name || !out_format) return (int)E_INVALIDARG;

    IDWriteFactory* f = static_cast<IDWriteFactory*>(factory);
    IDWriteFontCollection* col = static_cast<IDWriteFontCollection*>(collection);

    IDWriteTextFormat* tf = nullptr;
    HRESULT hr = f->CreateTextFormat(
        family_name,
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

int cwin_dwrite_create_text_layout(void* factory, const wchar_t* text, uint32_t text_len, void* format, float max_width, float max_height, void** out_layout) {
    if (!factory || !text || !format || !out_layout) return (int)E_INVALIDARG;

    IDWriteFactory* f = static_cast<IDWriteFactory*>(factory);
    IDWriteTextFormat* tf = static_cast<IDWriteTextFormat*>(format);

    IDWriteTextLayout* tl = nullptr;
    HRESULT hr = f->CreateTextLayout(
        text,
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

// MARK: - Win32 Windowing, Dispatcher, Keyboard, Clipboard

int cwin_win32_register_window_class(const wchar_t* class_name, void* wndproc, void** out_atom) {
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
    wc.lpszClassName = class_name;
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

void* cwin_win32_create_window(uint32_t ex_style, const wchar_t* class_name, const wchar_t* title, uint32_t style, int x, int y, int w, int h, void* parent, void* param) {
    HWND hwnd = CreateWindowExW(
        static_cast<DWORD>(ex_style),
        class_name,
        title ? title : L"",
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

int cwin_win32_clipboard_set_text(void* hwnd, const wchar_t* text, size_t len) {
    if (!text) return (int)E_INVALIDARG;
    HWND h = static_cast<HWND>(hwnd);

    if (!OpenClipboard(h)) {
        return (int)HRESULT_FROM_WIN32(GetLastError());
    }

    EmptyClipboard();

    size_t byte_count = (len + 1) * sizeof(wchar_t);
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

    memcpy(dest, text, len * sizeof(wchar_t));
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

int cwin_win32_clipboard_get_text(void* hwnd, wchar_t** out_text, size_t* out_len) {
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

    *out_text = buf;
    *out_len = len;
    return 0;
}

void cwin_win32_clipboard_free_text(wchar_t* text) {
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

void* cwin_win32_create_message_window(const wchar_t* class_name, void* wndproc, void* param) {
    if (!class_name) return nullptr;
    HWND hwnd = CreateWindowExW(
        0,
        class_name,
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
    wcsncpy(out_info->device_name, mi.szDevice, 31);
    out_info->device_name[31] = L'\0';

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

int cwin_win32_cred_write(const wchar_t* target, const wchar_t* username, const uint8_t* blob, size_t blob_len) {
    if (!target || !username) return (int)E_INVALIDARG;

    CREDENTIALW cred = {};
    cred.Type = CRED_TYPE_GENERIC;
    cred.TargetName = const_cast<LPWSTR>(target);
    cred.UserName = const_cast<LPWSTR>(username);
    cred.CredentialBlobSize = static_cast<DWORD>(blob_len);
    cred.CredentialBlob = const_cast<LPBYTE>(blob);
    cred.Persist = CRED_PERSIST_LOCAL_MACHINE;

    BOOL ok = CredWriteW(&cred, 0);
    return ok ? 0 : (int)HRESULT_FROM_WIN32(GetLastError());
}

int cwin_win32_cred_read(const wchar_t* target, wchar_t** out_username, uint8_t** out_blob, size_t* out_blob_len) {
    if (!target || !out_username || !out_blob || !out_blob_len) return (int)E_INVALIDARG;

    PCREDENTIALW cred = nullptr;
    if (!CredReadW(target, CRED_TYPE_GENERIC, 0, &cred) || !cred) {
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

    *out_username = ubuf;
    *out_blob = bbuf;
    *out_blob_len = cred->CredentialBlobSize;
    CredFree(cred);
    return 0;
}

int cwin_win32_cred_delete(const wchar_t* target) {
    if (!target) return (int)E_INVALIDARG;
    BOOL ok = CredDeleteW(target, CRED_TYPE_GENERIC, 0);
    return ok ? 0 : (int)HRESULT_FROM_WIN32(GetLastError());
}

void cwin_win32_cred_free(void* ptr) {
    if (ptr) {
        free(ptr);
    }
}

// MARK: - Win32 Shell & Dialogs

int cwin_win32_shell_open(const wchar_t* path_or_url) {
    if (!path_or_url) return (int)E_INVALIDARG;
    HINSTANCE h = ShellExecuteW(nullptr, L"open", path_or_url, nullptr, nullptr, SW_SHOWDEFAULT);
    if (reinterpret_cast<intptr_t>(h) <= 32) {
        return (int)HRESULT_FROM_WIN32(GetLastError());
    }
    return 0;
}

int cwin_win32_shell_reveal(const wchar_t* path) {
    if (!path) return (int)E_INVALIDARG;
    PIDLIST_ABSOLUTE pidl = ILCreateFromPathW(path);
    if (!pidl) {
        return cwin_win32_shell_open(path);
    }
    HRESULT hr = SHOpenFolderAndSelectItems(pidl, 0, nullptr, 0);
    ILFree(pidl);
    return SUCCEEDED(hr) ? 0 : (int)hr;
}

int cwin_win32_file_open_dialog(void* hwnd, int allow_multi, int pick_folders, const wchar_t* ok_label, wchar_t*** out_paths, size_t* out_count) {
    if (!out_paths || !out_count) return (int)E_INVALIDARG;
    *out_paths = nullptr;
    *out_count = 0;

    IFileOpenDialog* dlg = nullptr;
    HRESULT hr = CoCreateInstance(CLSID_FileOpenDialog, nullptr, CLSCTX_ALL, IID_PPV_ARGS(&dlg));
    if (FAILED(hr)) return (int)hr;

    FILEOPENDIALOGOPTIONS options = FOS_FILEMUSTEXIST;
    if (allow_multi) options |= FOS_ALLOWMULTISELECT;
    if (pick_folders) options |= FOS_PICKFOLDERS;
    dlg->SetOptions(options);

    if (ok_label && wcslen(ok_label) > 0) {
        dlg->SetOkButtonLabel(ok_label);
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

    *out_paths = paths;
    *out_count = actual_count;
    return 0;
}

int cwin_win32_file_save_dialog(void* hwnd, const wchar_t* initial_dir, const wchar_t* default_name, wchar_t** out_path) {
    if (!out_path) return (int)E_INVALIDARG;
    *out_path = nullptr;

    IFileSaveDialog* dlg = nullptr;
    HRESULT hr = CoCreateInstance(CLSID_FileSaveDialog, nullptr, CLSCTX_ALL, IID_PPV_ARGS(&dlg));
    if (FAILED(hr)) return (int)hr;

    if (default_name && wcslen(default_name) > 0) {
        dlg->SetFileName(default_name);
    }
    if (initial_dir && wcslen(initial_dir) > 0) {
        IShellItem* folder = nullptr;
        if (SUCCEEDED(SHCreateItemFromParsingName(initial_dir, nullptr, IID_PPV_ARGS(&folder)))) {
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
            *out_path = copy;
        }
        CoTaskMemFree(pszPath);
    }
    return 0;
}

void cwin_win32_free_path_list(wchar_t** paths, size_t count) {
    if (paths) {
        for (size_t i = 0; i < count; ++i) {
            if (paths[i]) free(paths[i]);
        }
        free(paths);
    }
}

#else

// Intentionally empty on non-Windows platforms.
typedef int gpua_winsys_unused_cpp_t;

#endif
