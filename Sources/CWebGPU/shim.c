// Swift-only: C bridge shim for WebGPU C API
#include "CWebGPU.h"
#include <string.h>

#if defined(__ANDROID__)

#include <dlfcn.h>
#include <pthread.h>

typedef size_t (*WGPUProcInstanceEnumerateAdapters)(
    WGPUInstance instance,
    WGPUInstanceEnumerateAdapterOptions const * options,
    WGPUAdapter * adapters
);
typedef WGPUBool (*WGPUProcDevicePoll)(
    WGPUDevice device,
    WGPUBool wait,
    WGPUSubmissionIndex const * wrappedSubmissionIndex
);

typedef struct CWebGPUAndroidProcs {
    WGPUProcCreateInstance CreateInstance;
    WGPUProcInstanceCreateSurface InstanceCreateSurface;
    WGPUProcInstanceEnumerateAdapters InstanceEnumerateAdapters;
    WGPUProcInstanceProcessEvents InstanceProcessEvents;
    WGPUProcInstanceRequestAdapter InstanceRequestAdapter;
    WGPUProcInstanceRelease InstanceRelease;

    WGPUProcAdapterGetFeatures AdapterGetFeatures;
    WGPUProcAdapterGetInfo AdapterGetInfo;
    WGPUProcAdapterGetLimits AdapterGetLimits;
    WGPUProcAdapterHasFeature AdapterHasFeature;
    WGPUProcAdapterRequestDevice AdapterRequestDevice;
    WGPUProcAdapterRelease AdapterRelease;
    WGPUProcAdapterInfoFreeMembers AdapterInfoFreeMembers;
    WGPUProcSupportedFeaturesFreeMembers SupportedFeaturesFreeMembers;

    WGPUProcDeviceCreateBindGroup DeviceCreateBindGroup;
    WGPUProcDeviceCreateBindGroupLayout DeviceCreateBindGroupLayout;
    WGPUProcDeviceCreateBuffer DeviceCreateBuffer;
    WGPUProcDeviceCreateCommandEncoder DeviceCreateCommandEncoder;
    WGPUProcDeviceCreatePipelineLayout DeviceCreatePipelineLayout;
    WGPUProcDeviceCreateRenderPipeline DeviceCreateRenderPipeline;
    WGPUProcDeviceCreateSampler DeviceCreateSampler;
    WGPUProcDeviceCreateShaderModule DeviceCreateShaderModule;
    WGPUProcDeviceCreateTexture DeviceCreateTexture;
    WGPUProcDeviceDestroy DeviceDestroy;
    WGPUProcDeviceGetFeatures DeviceGetFeatures;
    WGPUProcDeviceGetLimits DeviceGetLimits;
    WGPUProcDeviceGetQueue DeviceGetQueue;
    WGPUProcDeviceHasFeature DeviceHasFeature;
    WGPUProcDevicePopErrorScope DevicePopErrorScope;
    WGPUProcDevicePushErrorScope DevicePushErrorScope;
    WGPUProcDeviceRelease DeviceRelease;
    WGPUProcDevicePoll DevicePoll;

    WGPUProcQueueSubmit QueueSubmit;
    WGPUProcQueueWriteBuffer QueueWriteBuffer;
    WGPUProcQueueWriteTexture QueueWriteTexture;
    WGPUProcQueueRelease QueueRelease;

    WGPUProcSurfaceConfigure SurfaceConfigure;
    WGPUProcSurfaceGetCapabilities SurfaceGetCapabilities;
    WGPUProcSurfaceCapabilitiesFreeMembers SurfaceCapabilitiesFreeMembers;
    WGPUProcSurfaceGetCurrentTexture SurfaceGetCurrentTexture;
    WGPUProcSurfacePresent SurfacePresent;
    WGPUProcSurfaceUnconfigure SurfaceUnconfigure;
    WGPUProcSurfaceRelease SurfaceRelease;

    WGPUProcTextureCreateView TextureCreateView;
    WGPUProcTextureDestroy TextureDestroy;
    WGPUProcTextureRelease TextureRelease;
    WGPUProcTextureViewRelease TextureViewRelease;

    WGPUProcBufferDestroy BufferDestroy;
    WGPUProcBufferGetConstMappedRange BufferGetConstMappedRange;
    WGPUProcBufferGetMappedRange BufferGetMappedRange;
    WGPUProcBufferMapAsync BufferMapAsync;
    WGPUProcBufferUnmap BufferUnmap;
    WGPUProcBufferRelease BufferRelease;

    WGPUProcBindGroupRelease BindGroupRelease;
    WGPUProcBindGroupLayoutRelease BindGroupLayoutRelease;
    WGPUProcPipelineLayoutRelease PipelineLayoutRelease;
    WGPUProcRenderPipelineRelease RenderPipelineRelease;
    WGPUProcSamplerRelease SamplerRelease;
    WGPUProcShaderModuleRelease ShaderModuleRelease;

    WGPUProcCommandEncoderBeginRenderPass CommandEncoderBeginRenderPass;
    WGPUProcCommandEncoderCopyBufferToBuffer CommandEncoderCopyBufferToBuffer;
    WGPUProcCommandEncoderCopyBufferToTexture CommandEncoderCopyBufferToTexture;
    WGPUProcCommandEncoderCopyTextureToBuffer CommandEncoderCopyTextureToBuffer;
    WGPUProcCommandEncoderCopyTextureToTexture CommandEncoderCopyTextureToTexture;
    WGPUProcCommandEncoderFinish CommandEncoderFinish;
    WGPUProcCommandEncoderRelease CommandEncoderRelease;
    WGPUProcCommandBufferRelease CommandBufferRelease;

    WGPUProcRenderPassEncoderDraw RenderPassEncoderDraw;
    WGPUProcRenderPassEncoderDrawIndexed RenderPassEncoderDrawIndexed;
    WGPUProcRenderPassEncoderEnd RenderPassEncoderEnd;
    WGPUProcRenderPassEncoderRelease RenderPassEncoderRelease;
    WGPUProcRenderPassEncoderSetBindGroup RenderPassEncoderSetBindGroup;
    WGPUProcRenderPassEncoderSetIndexBuffer RenderPassEncoderSetIndexBuffer;
    WGPUProcRenderPassEncoderSetPipeline RenderPassEncoderSetPipeline;
    WGPUProcRenderPassEncoderSetScissorRect RenderPassEncoderSetScissorRect;
    WGPUProcRenderPassEncoderSetVertexBuffer RenderPassEncoderSetVertexBuffer;
    WGPUProcRenderPassEncoderSetViewport RenderPassEncoderSetViewport;
} CWebGPUAndroidProcs;

static pthread_once_t g_cwebgpu_once = PTHREAD_ONCE_INIT;
static void *g_cwebgpu_lib = NULL;
static CWebGPUAndroidProcs g_procs;

#define CWEBGPU_LOAD_SYM(field, sym) \
    g_procs.field = (__typeof__(g_procs.field))dlsym(g_cwebgpu_lib, sym)

static void cwebgpu_android_init(void) {
    memset(&g_procs, 0, sizeof(g_procs));
    g_cwebgpu_lib = dlopen("libwgpu_native.so", RTLD_NOW | RTLD_LOCAL);
    if (!g_cwebgpu_lib) {
        return;
    }

    CWEBGPU_LOAD_SYM(CreateInstance, "wgpuCreateInstance");
    CWEBGPU_LOAD_SYM(InstanceCreateSurface, "wgpuInstanceCreateSurface");
    CWEBGPU_LOAD_SYM(InstanceEnumerateAdapters, "wgpuInstanceEnumerateAdapters");
    CWEBGPU_LOAD_SYM(InstanceProcessEvents, "wgpuInstanceProcessEvents");
    CWEBGPU_LOAD_SYM(InstanceRequestAdapter, "wgpuInstanceRequestAdapter");
    CWEBGPU_LOAD_SYM(InstanceRelease, "wgpuInstanceRelease");

    CWEBGPU_LOAD_SYM(AdapterGetFeatures, "wgpuAdapterGetFeatures");
    CWEBGPU_LOAD_SYM(AdapterGetInfo, "wgpuAdapterGetInfo");
    CWEBGPU_LOAD_SYM(AdapterGetLimits, "wgpuAdapterGetLimits");
    CWEBGPU_LOAD_SYM(AdapterHasFeature, "wgpuAdapterHasFeature");
    CWEBGPU_LOAD_SYM(AdapterRequestDevice, "wgpuAdapterRequestDevice");
    CWEBGPU_LOAD_SYM(AdapterRelease, "wgpuAdapterRelease");
    CWEBGPU_LOAD_SYM(AdapterInfoFreeMembers, "wgpuAdapterInfoFreeMembers");
    CWEBGPU_LOAD_SYM(SupportedFeaturesFreeMembers, "wgpuSupportedFeaturesFreeMembers");

    CWEBGPU_LOAD_SYM(DeviceCreateBindGroup, "wgpuDeviceCreateBindGroup");
    CWEBGPU_LOAD_SYM(DeviceCreateBindGroupLayout, "wgpuDeviceCreateBindGroupLayout");
    CWEBGPU_LOAD_SYM(DeviceCreateBuffer, "wgpuDeviceCreateBuffer");
    CWEBGPU_LOAD_SYM(DeviceCreateCommandEncoder, "wgpuDeviceCreateCommandEncoder");
    CWEBGPU_LOAD_SYM(DeviceCreatePipelineLayout, "wgpuDeviceCreatePipelineLayout");
    CWEBGPU_LOAD_SYM(DeviceCreateRenderPipeline, "wgpuDeviceCreateRenderPipeline");
    CWEBGPU_LOAD_SYM(DeviceCreateSampler, "wgpuDeviceCreateSampler");
    CWEBGPU_LOAD_SYM(DeviceCreateShaderModule, "wgpuDeviceCreateShaderModule");
    CWEBGPU_LOAD_SYM(DeviceCreateTexture, "wgpuDeviceCreateTexture");
    CWEBGPU_LOAD_SYM(DeviceDestroy, "wgpuDeviceDestroy");
    CWEBGPU_LOAD_SYM(DeviceGetFeatures, "wgpuDeviceGetFeatures");
    CWEBGPU_LOAD_SYM(DeviceGetLimits, "wgpuDeviceGetLimits");
    CWEBGPU_LOAD_SYM(DeviceGetQueue, "wgpuDeviceGetQueue");
    CWEBGPU_LOAD_SYM(DeviceHasFeature, "wgpuDeviceHasFeature");
    CWEBGPU_LOAD_SYM(DevicePopErrorScope, "wgpuDevicePopErrorScope");
    CWEBGPU_LOAD_SYM(DevicePushErrorScope, "wgpuDevicePushErrorScope");
    CWEBGPU_LOAD_SYM(DeviceRelease, "wgpuDeviceRelease");
    CWEBGPU_LOAD_SYM(DevicePoll, "wgpuDevicePoll");

    CWEBGPU_LOAD_SYM(QueueSubmit, "wgpuQueueSubmit");
    CWEBGPU_LOAD_SYM(QueueWriteBuffer, "wgpuQueueWriteBuffer");
    CWEBGPU_LOAD_SYM(QueueWriteTexture, "wgpuQueueWriteTexture");
    CWEBGPU_LOAD_SYM(QueueRelease, "wgpuQueueRelease");

    CWEBGPU_LOAD_SYM(SurfaceConfigure, "wgpuSurfaceConfigure");
    CWEBGPU_LOAD_SYM(SurfaceGetCapabilities, "wgpuSurfaceGetCapabilities");
    CWEBGPU_LOAD_SYM(SurfaceCapabilitiesFreeMembers, "wgpuSurfaceCapabilitiesFreeMembers");
    CWEBGPU_LOAD_SYM(SurfaceGetCurrentTexture, "wgpuSurfaceGetCurrentTexture");
    CWEBGPU_LOAD_SYM(SurfacePresent, "wgpuSurfacePresent");
    CWEBGPU_LOAD_SYM(SurfaceUnconfigure, "wgpuSurfaceUnconfigure");
    CWEBGPU_LOAD_SYM(SurfaceRelease, "wgpuSurfaceRelease");

    CWEBGPU_LOAD_SYM(TextureCreateView, "wgpuTextureCreateView");
    CWEBGPU_LOAD_SYM(TextureDestroy, "wgpuTextureDestroy");
    CWEBGPU_LOAD_SYM(TextureRelease, "wgpuTextureRelease");
    CWEBGPU_LOAD_SYM(TextureViewRelease, "wgpuTextureViewRelease");

    CWEBGPU_LOAD_SYM(BufferDestroy, "wgpuBufferDestroy");
    CWEBGPU_LOAD_SYM(BufferGetConstMappedRange, "wgpuBufferGetConstMappedRange");
    CWEBGPU_LOAD_SYM(BufferGetMappedRange, "wgpuBufferGetMappedRange");
    CWEBGPU_LOAD_SYM(BufferMapAsync, "wgpuBufferMapAsync");
    CWEBGPU_LOAD_SYM(BufferUnmap, "wgpuBufferUnmap");
    CWEBGPU_LOAD_SYM(BufferRelease, "wgpuBufferRelease");

    CWEBGPU_LOAD_SYM(BindGroupRelease, "wgpuBindGroupRelease");
    CWEBGPU_LOAD_SYM(BindGroupLayoutRelease, "wgpuBindGroupLayoutRelease");
    CWEBGPU_LOAD_SYM(PipelineLayoutRelease, "wgpuPipelineLayoutRelease");
    CWEBGPU_LOAD_SYM(RenderPipelineRelease, "wgpuRenderPipelineRelease");
    CWEBGPU_LOAD_SYM(SamplerRelease, "wgpuSamplerRelease");
    CWEBGPU_LOAD_SYM(ShaderModuleRelease, "wgpuShaderModuleRelease");

    CWEBGPU_LOAD_SYM(CommandEncoderBeginRenderPass, "wgpuCommandEncoderBeginRenderPass");
    CWEBGPU_LOAD_SYM(CommandEncoderCopyBufferToBuffer, "wgpuCommandEncoderCopyBufferToBuffer");
    CWEBGPU_LOAD_SYM(CommandEncoderCopyBufferToTexture, "wgpuCommandEncoderCopyBufferToTexture");
    CWEBGPU_LOAD_SYM(CommandEncoderCopyTextureToBuffer, "wgpuCommandEncoderCopyTextureToBuffer");
    CWEBGPU_LOAD_SYM(CommandEncoderCopyTextureToTexture, "wgpuCommandEncoderCopyTextureToTexture");
    CWEBGPU_LOAD_SYM(CommandEncoderFinish, "wgpuCommandEncoderFinish");
    CWEBGPU_LOAD_SYM(CommandEncoderRelease, "wgpuCommandEncoderRelease");
    CWEBGPU_LOAD_SYM(CommandBufferRelease, "wgpuCommandBufferRelease");

    CWEBGPU_LOAD_SYM(RenderPassEncoderDraw, "wgpuRenderPassEncoderDraw");
    CWEBGPU_LOAD_SYM(RenderPassEncoderDrawIndexed, "wgpuRenderPassEncoderDrawIndexed");
    CWEBGPU_LOAD_SYM(RenderPassEncoderEnd, "wgpuRenderPassEncoderEnd");
    CWEBGPU_LOAD_SYM(RenderPassEncoderRelease, "wgpuRenderPassEncoderRelease");
    CWEBGPU_LOAD_SYM(RenderPassEncoderSetBindGroup, "wgpuRenderPassEncoderSetBindGroup");
    CWEBGPU_LOAD_SYM(RenderPassEncoderSetIndexBuffer, "wgpuRenderPassEncoderSetIndexBuffer");
    CWEBGPU_LOAD_SYM(RenderPassEncoderSetPipeline, "wgpuRenderPassEncoderSetPipeline");
    CWEBGPU_LOAD_SYM(RenderPassEncoderSetScissorRect, "wgpuRenderPassEncoderSetScissorRect");
    CWEBGPU_LOAD_SYM(RenderPassEncoderSetVertexBuffer, "wgpuRenderPassEncoderSetVertexBuffer");
    CWEBGPU_LOAD_SYM(RenderPassEncoderSetViewport, "wgpuRenderPassEncoderSetViewport");
}

static inline void cwebgpu_ensure_init(void) {
    pthread_once(&g_cwebgpu_once, cwebgpu_android_init);
}

WGPUInstance wgpuCreateInstance(WGPUInstanceDescriptor const * descriptor) {
    cwebgpu_ensure_init();
    return g_procs.CreateInstance ? g_procs.CreateInstance(descriptor) : NULL;
}

WGPUSurface wgpuInstanceCreateSurface(WGPUInstance instance, WGPUSurfaceDescriptor const * descriptor) {
    cwebgpu_ensure_init();
    return g_procs.InstanceCreateSurface ? g_procs.InstanceCreateSurface(instance, descriptor) : NULL;
}

size_t wgpuInstanceEnumerateAdapters(
    WGPUInstance instance,
    WGPUInstanceEnumerateAdapterOptions const * options,
    WGPUAdapter * adapters
) {
    cwebgpu_ensure_init();
    return g_procs.InstanceEnumerateAdapters ? g_procs.InstanceEnumerateAdapters(instance, options, adapters) : 0;
}

void wgpuInstanceProcessEvents(WGPUInstance instance) {
    cwebgpu_ensure_init();
    if (g_procs.InstanceProcessEvents) {
        g_procs.InstanceProcessEvents(instance);
    }
}

WGPUFuture wgpuInstanceRequestAdapter(
    WGPUInstance instance,
    WGPURequestAdapterOptions const * options,
    WGPURequestAdapterCallbackInfo callbackInfo
) {
    cwebgpu_ensure_init();
    if (g_procs.InstanceRequestAdapter) {
        return g_procs.InstanceRequestAdapter(instance, options, callbackInfo);
    }
    if (callbackInfo.callback) {
        WGPUStringView msg = { "libwgpu_native.so not loaded", 28 };
        callbackInfo.callback(
            WGPURequestAdapterStatus_Unavailable,
            NULL,
            msg,
            callbackInfo.userdata1,
            callbackInfo.userdata2
        );
    }
    WGPUFuture fut = { 0 };
    return fut;
}

void wgpuInstanceRelease(WGPUInstance instance) {
    cwebgpu_ensure_init();
    if (g_procs.InstanceRelease) {
        g_procs.InstanceRelease(instance);
    }
}

void wgpuAdapterGetFeatures(WGPUAdapter adapter, WGPUSupportedFeatures * features) {
    cwebgpu_ensure_init();
    if (g_procs.AdapterGetFeatures) {
        g_procs.AdapterGetFeatures(adapter, features);
    } else if (features) {
        memset(features, 0, sizeof(*features));
    }
}

WGPUStatus wgpuAdapterGetInfo(WGPUAdapter adapter, WGPUAdapterInfo * info) {
    cwebgpu_ensure_init();
    if (g_procs.AdapterGetInfo) {
        return g_procs.AdapterGetInfo(adapter, info);
    }
    if (info) {
        memset(info, 0, sizeof(*info));
    }
    return WGPUStatus_Error;
}

WGPUStatus wgpuAdapterGetLimits(WGPUAdapter adapter, WGPULimits * limits) {
    cwebgpu_ensure_init();
    return g_procs.AdapterGetLimits ? g_procs.AdapterGetLimits(adapter, limits) : WGPUStatus_Error;
}

WGPUBool wgpuAdapterHasFeature(WGPUAdapter adapter, WGPUFeatureName feature) {
    cwebgpu_ensure_init();
    return g_procs.AdapterHasFeature ? g_procs.AdapterHasFeature(adapter, feature) : 0;
}

WGPUFuture wgpuAdapterRequestDevice(
    WGPUAdapter adapter,
    WGPUDeviceDescriptor const * descriptor,
    WGPURequestDeviceCallbackInfo callbackInfo
) {
    cwebgpu_ensure_init();
    if (g_procs.AdapterRequestDevice) {
        return g_procs.AdapterRequestDevice(adapter, descriptor, callbackInfo);
    }
    if (callbackInfo.callback) {
        WGPUStringView msg = { "libwgpu_native.so not loaded", 28 };
        callbackInfo.callback(
            WGPURequestDeviceStatus_Error,
            NULL,
            msg,
            callbackInfo.userdata1,
            callbackInfo.userdata2
        );
    }
    WGPUFuture fut = { 0 };
    return fut;
}

void wgpuAdapterRelease(WGPUAdapter adapter) {
    cwebgpu_ensure_init();
    if (g_procs.AdapterRelease) {
        g_procs.AdapterRelease(adapter);
    }
}

void wgpuAdapterInfoFreeMembers(WGPUAdapterInfo adapterInfo) {
    cwebgpu_ensure_init();
    if (g_procs.AdapterInfoFreeMembers) {
        g_procs.AdapterInfoFreeMembers(adapterInfo);
    }
}

void wgpuSupportedFeaturesFreeMembers(WGPUSupportedFeatures supportedFeatures) {
    cwebgpu_ensure_init();
    if (g_procs.SupportedFeaturesFreeMembers) {
        g_procs.SupportedFeaturesFreeMembers(supportedFeatures);
    }
}

WGPUBindGroup wgpuDeviceCreateBindGroup(WGPUDevice device, WGPUBindGroupDescriptor const * descriptor) {
    cwebgpu_ensure_init();
    return g_procs.DeviceCreateBindGroup ? g_procs.DeviceCreateBindGroup(device, descriptor) : NULL;
}

WGPUBindGroupLayout wgpuDeviceCreateBindGroupLayout(WGPUDevice device, WGPUBindGroupLayoutDescriptor const * descriptor) {
    cwebgpu_ensure_init();
    return g_procs.DeviceCreateBindGroupLayout ? g_procs.DeviceCreateBindGroupLayout(device, descriptor) : NULL;
}

WGPUBuffer wgpuDeviceCreateBuffer(WGPUDevice device, WGPUBufferDescriptor const * descriptor) {
    cwebgpu_ensure_init();
    return g_procs.DeviceCreateBuffer ? g_procs.DeviceCreateBuffer(device, descriptor) : NULL;
}

WGPUCommandEncoder wgpuDeviceCreateCommandEncoder(WGPUDevice device, WGPUCommandEncoderDescriptor const * descriptor) {
    cwebgpu_ensure_init();
    return g_procs.DeviceCreateCommandEncoder ? g_procs.DeviceCreateCommandEncoder(device, descriptor) : NULL;
}

WGPUPipelineLayout wgpuDeviceCreatePipelineLayout(WGPUDevice device, WGPUPipelineLayoutDescriptor const * descriptor) {
    cwebgpu_ensure_init();
    return g_procs.DeviceCreatePipelineLayout ? g_procs.DeviceCreatePipelineLayout(device, descriptor) : NULL;
}

WGPURenderPipeline wgpuDeviceCreateRenderPipeline(WGPUDevice device, WGPURenderPipelineDescriptor const * descriptor) {
    cwebgpu_ensure_init();
    return g_procs.DeviceCreateRenderPipeline ? g_procs.DeviceCreateRenderPipeline(device, descriptor) : NULL;
}

WGPUSampler wgpuDeviceCreateSampler(WGPUDevice device, WGPUSamplerDescriptor const * descriptor) {
    cwebgpu_ensure_init();
    return g_procs.DeviceCreateSampler ? g_procs.DeviceCreateSampler(device, descriptor) : NULL;
}

WGPUShaderModule wgpuDeviceCreateShaderModule(WGPUDevice device, WGPUShaderModuleDescriptor const * descriptor) {
    cwebgpu_ensure_init();
    return g_procs.DeviceCreateShaderModule ? g_procs.DeviceCreateShaderModule(device, descriptor) : NULL;
}

WGPUTexture wgpuDeviceCreateTexture(WGPUDevice device, WGPUTextureDescriptor const * descriptor) {
    cwebgpu_ensure_init();
    return g_procs.DeviceCreateTexture ? g_procs.DeviceCreateTexture(device, descriptor) : NULL;
}

void wgpuDeviceDestroy(WGPUDevice device) {
    cwebgpu_ensure_init();
    if (g_procs.DeviceDestroy) {
        g_procs.DeviceDestroy(device);
    }
}

void wgpuDeviceGetFeatures(WGPUDevice device, WGPUSupportedFeatures * features) {
    cwebgpu_ensure_init();
    if (g_procs.DeviceGetFeatures) {
        g_procs.DeviceGetFeatures(device, features);
    } else if (features) {
        memset(features, 0, sizeof(*features));
    }
}

WGPUStatus wgpuDeviceGetLimits(WGPUDevice device, WGPULimits * limits) {
    cwebgpu_ensure_init();
    return g_procs.DeviceGetLimits ? g_procs.DeviceGetLimits(device, limits) : WGPUStatus_Error;
}

WGPUQueue wgpuDeviceGetQueue(WGPUDevice device) {
    cwebgpu_ensure_init();
    return g_procs.DeviceGetQueue ? g_procs.DeviceGetQueue(device) : NULL;
}

WGPUBool wgpuDeviceHasFeature(WGPUDevice device, WGPUFeatureName feature) {
    cwebgpu_ensure_init();
    return g_procs.DeviceHasFeature ? g_procs.DeviceHasFeature(device, feature) : 0;
}

WGPUFuture wgpuDevicePopErrorScope(WGPUDevice device, WGPUPopErrorScopeCallbackInfo callbackInfo) {
    cwebgpu_ensure_init();
    if (g_procs.DevicePopErrorScope) {
        return g_procs.DevicePopErrorScope(device, callbackInfo);
    }
    if (callbackInfo.callback) {
        WGPUStringView msg = { NULL, 0 };
        callbackInfo.callback(
            WGPUPopErrorScopeStatus_InstanceDropped,
            WGPUErrorType_NoError,
            msg,
            callbackInfo.userdata1,
            callbackInfo.userdata2
        );
    }
    WGPUFuture fut = { 0 };
    return fut;
}

void wgpuDevicePushErrorScope(WGPUDevice device, WGPUErrorFilter filter) {
    cwebgpu_ensure_init();
    if (g_procs.DevicePushErrorScope) {
        g_procs.DevicePushErrorScope(device, filter);
    }
}

void wgpuDeviceRelease(WGPUDevice device) {
    cwebgpu_ensure_init();
    if (g_procs.DeviceRelease) {
        g_procs.DeviceRelease(device);
    }
}

WGPUBool wgpuDevicePoll(
    WGPUDevice device,
    WGPUBool wait,
    WGPUSubmissionIndex const * wrappedSubmissionIndex
) {
    cwebgpu_ensure_init();
    return g_procs.DevicePoll ? g_procs.DevicePoll(device, wait, wrappedSubmissionIndex) : 1;
}

void wgpuQueueSubmit(WGPUQueue queue, size_t commandCount, WGPUCommandBuffer const * commands) {
    cwebgpu_ensure_init();
    if (g_procs.QueueSubmit) {
        g_procs.QueueSubmit(queue, commandCount, commands);
    }
}

void wgpuQueueWriteBuffer(WGPUQueue queue, WGPUBuffer buffer, uint64_t bufferOffset, void const * data, size_t size) {
    cwebgpu_ensure_init();
    if (g_procs.QueueWriteBuffer) {
        g_procs.QueueWriteBuffer(queue, buffer, bufferOffset, data, size);
    }
}

void wgpuQueueWriteTexture(
    WGPUQueue queue,
    WGPUTexelCopyTextureInfo const * destination,
    void const * data,
    size_t dataSize,
    WGPUTexelCopyBufferLayout const * dataLayout,
    WGPUExtent3D const * writeSize
) {
    cwebgpu_ensure_init();
    if (g_procs.QueueWriteTexture) {
        g_procs.QueueWriteTexture(queue, destination, data, dataSize, dataLayout, writeSize);
    }
}

void wgpuQueueRelease(WGPUQueue queue) {
    cwebgpu_ensure_init();
    if (g_procs.QueueRelease) {
        g_procs.QueueRelease(queue);
    }
}

void wgpuSurfaceConfigure(WGPUSurface surface, WGPUSurfaceConfiguration const * config) {
    cwebgpu_ensure_init();
    if (g_procs.SurfaceConfigure) {
        g_procs.SurfaceConfigure(surface, config);
    }
}

WGPUStatus wgpuSurfaceGetCapabilities(WGPUSurface surface, WGPUAdapter adapter, WGPUSurfaceCapabilities * capabilities) {
    cwebgpu_ensure_init();
    if (g_procs.SurfaceGetCapabilities) {
        return g_procs.SurfaceGetCapabilities(surface, adapter, capabilities);
    }
    if (capabilities) {
        memset(capabilities, 0, sizeof(*capabilities));
    }
    return WGPUStatus_Error;
}

void wgpuSurfaceCapabilitiesFreeMembers(WGPUSurfaceCapabilities surfaceCapabilities) {
    cwebgpu_ensure_init();
    if (g_procs.SurfaceCapabilitiesFreeMembers) {
        g_procs.SurfaceCapabilitiesFreeMembers(surfaceCapabilities);
    }
}

void wgpuSurfaceGetCurrentTexture(WGPUSurface surface, WGPUSurfaceTexture * surfaceTexture) {
    cwebgpu_ensure_init();
    if (g_procs.SurfaceGetCurrentTexture) {
        g_procs.SurfaceGetCurrentTexture(surface, surfaceTexture);
    } else if (surfaceTexture) {
        memset(surfaceTexture, 0, sizeof(*surfaceTexture));
        surfaceTexture->status = WGPUSurfaceGetCurrentTextureStatus_Error;
    }
}

WGPUStatus wgpuSurfacePresent(WGPUSurface surface) {
    cwebgpu_ensure_init();
    return g_procs.SurfacePresent ? g_procs.SurfacePresent(surface) : WGPUStatus_Error;
}

void wgpuSurfaceUnconfigure(WGPUSurface surface) {
    cwebgpu_ensure_init();
    if (g_procs.SurfaceUnconfigure) {
        g_procs.SurfaceUnconfigure(surface);
    }
}

void wgpuSurfaceRelease(WGPUSurface surface) {
    cwebgpu_ensure_init();
    if (g_procs.SurfaceRelease) {
        g_procs.SurfaceRelease(surface);
    }
}

WGPUTextureView wgpuTextureCreateView(WGPUTexture texture, WGPUTextureViewDescriptor const * descriptor) {
    cwebgpu_ensure_init();
    return g_procs.TextureCreateView ? g_procs.TextureCreateView(texture, descriptor) : NULL;
}

void wgpuTextureDestroy(WGPUTexture texture) {
    cwebgpu_ensure_init();
    if (g_procs.TextureDestroy) {
        g_procs.TextureDestroy(texture);
    }
}

void wgpuTextureRelease(WGPUTexture texture) {
    cwebgpu_ensure_init();
    if (g_procs.TextureRelease) {
        g_procs.TextureRelease(texture);
    }
}

void wgpuTextureViewRelease(WGPUTextureView textureView) {
    cwebgpu_ensure_init();
    if (g_procs.TextureViewRelease) {
        g_procs.TextureViewRelease(textureView);
    }
}

void wgpuBufferDestroy(WGPUBuffer buffer) {
    cwebgpu_ensure_init();
    if (g_procs.BufferDestroy) {
        g_procs.BufferDestroy(buffer);
    }
}

void const * wgpuBufferGetConstMappedRange(WGPUBuffer buffer, size_t offset, size_t size) {
    cwebgpu_ensure_init();
    return g_procs.BufferGetConstMappedRange ? g_procs.BufferGetConstMappedRange(buffer, offset, size) : NULL;
}

void * wgpuBufferGetMappedRange(WGPUBuffer buffer, size_t offset, size_t size) {
    cwebgpu_ensure_init();
    return g_procs.BufferGetMappedRange ? g_procs.BufferGetMappedRange(buffer, offset, size) : NULL;
}

WGPUFuture wgpuBufferMapAsync(
    WGPUBuffer buffer,
    WGPUMapMode mode,
    size_t offset,
    size_t size,
    WGPUBufferMapCallbackInfo callbackInfo
) {
    cwebgpu_ensure_init();
    if (g_procs.BufferMapAsync) {
        return g_procs.BufferMapAsync(buffer, mode, offset, size, callbackInfo);
    }
    if (callbackInfo.callback) {
        WGPUStringView msg = { "libwgpu_native.so not loaded", 28 };
        callbackInfo.callback(
            WGPUMapAsyncStatus_Error,
            msg,
            callbackInfo.userdata1,
            callbackInfo.userdata2
        );
    }
    WGPUFuture fut = { 0 };
    return fut;
}

void wgpuBufferUnmap(WGPUBuffer buffer) {
    cwebgpu_ensure_init();
    if (g_procs.BufferUnmap) {
        g_procs.BufferUnmap(buffer);
    }
}

void wgpuBufferRelease(WGPUBuffer buffer) {
    cwebgpu_ensure_init();
    if (g_procs.BufferRelease) {
        g_procs.BufferRelease(buffer);
    }
}

void wgpuBindGroupRelease(WGPUBindGroup bindGroup) {
    cwebgpu_ensure_init();
    if (g_procs.BindGroupRelease) {
        g_procs.BindGroupRelease(bindGroup);
    }
}

void wgpuBindGroupLayoutRelease(WGPUBindGroupLayout bindGroupLayout) {
    cwebgpu_ensure_init();
    if (g_procs.BindGroupLayoutRelease) {
        g_procs.BindGroupLayoutRelease(bindGroupLayout);
    }
}

void wgpuPipelineLayoutRelease(WGPUPipelineLayout pipelineLayout) {
    cwebgpu_ensure_init();
    if (g_procs.PipelineLayoutRelease) {
        g_procs.PipelineLayoutRelease(pipelineLayout);
    }
}

void wgpuRenderPipelineRelease(WGPURenderPipeline renderPipeline) {
    cwebgpu_ensure_init();
    if (g_procs.RenderPipelineRelease) {
        g_procs.RenderPipelineRelease(renderPipeline);
    }
}

void wgpuSamplerRelease(WGPUSampler sampler) {
    cwebgpu_ensure_init();
    if (g_procs.SamplerRelease) {
        g_procs.SamplerRelease(sampler);
    }
}

void wgpuShaderModuleRelease(WGPUShaderModule shaderModule) {
    cwebgpu_ensure_init();
    if (g_procs.ShaderModuleRelease) {
        g_procs.ShaderModuleRelease(shaderModule);
    }
}

WGPURenderPassEncoder wgpuCommandEncoderBeginRenderPass(
    WGPUCommandEncoder commandEncoder,
    WGPURenderPassDescriptor const * descriptor
) {
    cwebgpu_ensure_init();
    return g_procs.CommandEncoderBeginRenderPass ? g_procs.CommandEncoderBeginRenderPass(commandEncoder, descriptor) : NULL;
}

void wgpuCommandEncoderCopyBufferToBuffer(
    WGPUCommandEncoder commandEncoder,
    WGPUBuffer source,
    uint64_t sourceOffset,
    WGPUBuffer destination,
    uint64_t destinationOffset,
    uint64_t size
) {
    cwebgpu_ensure_init();
    if (g_procs.CommandEncoderCopyBufferToBuffer) {
        g_procs.CommandEncoderCopyBufferToBuffer(commandEncoder, source, sourceOffset, destination, destinationOffset, size);
    }
}

void wgpuCommandEncoderCopyBufferToTexture(
    WGPUCommandEncoder commandEncoder,
    WGPUTexelCopyBufferInfo const * source,
    WGPUTexelCopyTextureInfo const * destination,
    WGPUExtent3D const * copySize
) {
    cwebgpu_ensure_init();
    if (g_procs.CommandEncoderCopyBufferToTexture) {
        g_procs.CommandEncoderCopyBufferToTexture(commandEncoder, source, destination, copySize);
    }
}

void wgpuCommandEncoderCopyTextureToBuffer(
    WGPUCommandEncoder commandEncoder,
    WGPUTexelCopyTextureInfo const * source,
    WGPUTexelCopyBufferInfo const * destination,
    WGPUExtent3D const * copySize
) {
    cwebgpu_ensure_init();
    if (g_procs.CommandEncoderCopyTextureToBuffer) {
        g_procs.CommandEncoderCopyTextureToBuffer(commandEncoder, source, destination, copySize);
    }
}

void wgpuCommandEncoderCopyTextureToTexture(
    WGPUCommandEncoder commandEncoder,
    WGPUTexelCopyTextureInfo const * source,
    WGPUTexelCopyTextureInfo const * destination,
    WGPUExtent3D const * copySize
) {
    cwebgpu_ensure_init();
    if (g_procs.CommandEncoderCopyTextureToTexture) {
        g_procs.CommandEncoderCopyTextureToTexture(commandEncoder, source, destination, copySize);
    }
}

WGPUCommandBuffer wgpuCommandEncoderFinish(
    WGPUCommandEncoder commandEncoder,
    WGPUCommandBufferDescriptor const * descriptor
) {
    cwebgpu_ensure_init();
    return g_procs.CommandEncoderFinish ? g_procs.CommandEncoderFinish(commandEncoder, descriptor) : NULL;
}

void wgpuCommandEncoderRelease(WGPUCommandEncoder commandEncoder) {
    cwebgpu_ensure_init();
    if (g_procs.CommandEncoderRelease) {
        g_procs.CommandEncoderRelease(commandEncoder);
    }
}

void wgpuCommandBufferRelease(WGPUCommandBuffer commandBuffer) {
    cwebgpu_ensure_init();
    if (g_procs.CommandBufferRelease) {
        g_procs.CommandBufferRelease(commandBuffer);
    }
}

void wgpuRenderPassEncoderDraw(
    WGPURenderPassEncoder renderPassEncoder,
    uint32_t vertexCount,
    uint32_t instanceCount,
    uint32_t firstVertex,
    uint32_t firstInstance
) {
    cwebgpu_ensure_init();
    if (g_procs.RenderPassEncoderDraw) {
        g_procs.RenderPassEncoderDraw(renderPassEncoder, vertexCount, instanceCount, firstVertex, firstInstance);
    }
}

void wgpuRenderPassEncoderDrawIndexed(
    WGPURenderPassEncoder renderPassEncoder,
    uint32_t indexCount,
    uint32_t instanceCount,
    uint32_t firstIndex,
    int32_t baseVertex,
    uint32_t firstInstance
) {
    cwebgpu_ensure_init();
    if (g_procs.RenderPassEncoderDrawIndexed) {
        g_procs.RenderPassEncoderDrawIndexed(renderPassEncoder, indexCount, instanceCount, firstIndex, baseVertex, firstInstance);
    }
}

void wgpuRenderPassEncoderEnd(WGPURenderPassEncoder renderPassEncoder) {
    cwebgpu_ensure_init();
    if (g_procs.RenderPassEncoderEnd) {
        g_procs.RenderPassEncoderEnd(renderPassEncoder);
    }
}

void wgpuRenderPassEncoderRelease(WGPURenderPassEncoder renderPassEncoder) {
    cwebgpu_ensure_init();
    if (g_procs.RenderPassEncoderRelease) {
        g_procs.RenderPassEncoderRelease(renderPassEncoder);
    }
}

void wgpuRenderPassEncoderSetBindGroup(
    WGPURenderPassEncoder renderPassEncoder,
    uint32_t groupIndex,
    WGPUBindGroup group,
    size_t dynamicOffsetCount,
    uint32_t const * dynamicOffsets
) {
    cwebgpu_ensure_init();
    if (g_procs.RenderPassEncoderSetBindGroup) {
        g_procs.RenderPassEncoderSetBindGroup(renderPassEncoder, groupIndex, group, dynamicOffsetCount, dynamicOffsets);
    }
}

void wgpuRenderPassEncoderSetIndexBuffer(
    WGPURenderPassEncoder renderPassEncoder,
    WGPUBuffer buffer,
    WGPUIndexFormat format,
    uint64_t offset,
    uint64_t size
) {
    cwebgpu_ensure_init();
    if (g_procs.RenderPassEncoderSetIndexBuffer) {
        g_procs.RenderPassEncoderSetIndexBuffer(renderPassEncoder, buffer, format, offset, size);
    }
}

void wgpuRenderPassEncoderSetPipeline(WGPURenderPassEncoder renderPassEncoder, WGPURenderPipeline pipeline) {
    cwebgpu_ensure_init();
    if (g_procs.RenderPassEncoderSetPipeline) {
        g_procs.RenderPassEncoderSetPipeline(renderPassEncoder, pipeline);
    }
}

void wgpuRenderPassEncoderSetScissorRect(
    WGPURenderPassEncoder renderPassEncoder,
    uint32_t x,
    uint32_t y,
    uint32_t width,
    uint32_t height
) {
    cwebgpu_ensure_init();
    if (g_procs.RenderPassEncoderSetScissorRect) {
        g_procs.RenderPassEncoderSetScissorRect(renderPassEncoder, x, y, width, height);
    }
}

void wgpuRenderPassEncoderSetVertexBuffer(
    WGPURenderPassEncoder renderPassEncoder,
    uint32_t slot,
    WGPUBuffer buffer,
    uint64_t offset,
    uint64_t size
) {
    cwebgpu_ensure_init();
    if (g_procs.RenderPassEncoderSetVertexBuffer) {
        g_procs.RenderPassEncoderSetVertexBuffer(renderPassEncoder, slot, buffer, offset, size);
    }
}

void wgpuRenderPassEncoderSetViewport(
    WGPURenderPassEncoder renderPassEncoder,
    float x,
    float y,
    float width,
    float height,
    float minDepth,
    float maxDepth
) {
    cwebgpu_ensure_init();
    if (g_procs.RenderPassEncoderSetViewport) {
        g_procs.RenderPassEncoderSetViewport(renderPassEncoder, x, y, width, height, minDepth, maxDepth);
    }
}

#elif defined(__wasi__)

#define WGPU_WASI_IMPORT(name) __attribute__((import_module("wgpu"), import_name(name)))

extern WGPUInstance _wasi_wgpuCreateInstance(WGPUInstanceDescriptor const * descriptor) WGPU_WASI_IMPORT("wgpuCreateInstance");
WGPUInstance wgpuCreateInstance(WGPUInstanceDescriptor const * descriptor) {
    return _wasi_wgpuCreateInstance(descriptor);
}

extern WGPUSurface _wasi_wgpuInstanceCreateSurface(WGPUInstance instance, WGPUSurfaceDescriptor const * descriptor) WGPU_WASI_IMPORT("wgpuInstanceCreateSurface");
WGPUSurface wgpuInstanceCreateSurface(WGPUInstance instance, WGPUSurfaceDescriptor const * descriptor) {
    return _wasi_wgpuInstanceCreateSurface(instance, descriptor);
}

extern size_t _wasi_wgpuInstanceEnumerateAdapters(WGPUInstance instance, WGPUInstanceEnumerateAdapterOptions const * options, WGPUAdapter * adapters) WGPU_WASI_IMPORT("wgpuInstanceEnumerateAdapters");
size_t wgpuInstanceEnumerateAdapters(WGPUInstance instance, WGPUInstanceEnumerateAdapterOptions const * options, WGPUAdapter * adapters) {
    return _wasi_wgpuInstanceEnumerateAdapters(instance, options, adapters);
}

extern void _wasi_wgpuInstanceProcessEvents(WGPUInstance instance) WGPU_WASI_IMPORT("wgpuInstanceProcessEvents");
void wgpuInstanceProcessEvents(WGPUInstance instance) {
    _wasi_wgpuInstanceProcessEvents(instance);
}

extern WGPUFuture _wasi_wgpuInstanceRequestAdapter(WGPUInstance instance, WGPURequestAdapterOptions const * options, WGPURequestAdapterCallbackInfo callbackInfo) WGPU_WASI_IMPORT("wgpuInstanceRequestAdapter");
WGPUFuture wgpuInstanceRequestAdapter(WGPUInstance instance, WGPURequestAdapterOptions const * options, WGPURequestAdapterCallbackInfo callbackInfo) {
    return _wasi_wgpuInstanceRequestAdapter(instance, options, callbackInfo);
}

extern void _wasi_wgpuInstanceRelease(WGPUInstance instance) WGPU_WASI_IMPORT("wgpuInstanceRelease");
void wgpuInstanceRelease(WGPUInstance instance) {
    _wasi_wgpuInstanceRelease(instance);
}

extern void _wasi_wgpuAdapterGetFeatures(WGPUAdapter adapter, WGPUSupportedFeatures * features) WGPU_WASI_IMPORT("wgpuAdapterGetFeatures");
void wgpuAdapterGetFeatures(WGPUAdapter adapter, WGPUSupportedFeatures * features) {
    _wasi_wgpuAdapterGetFeatures(adapter, features);
}

extern WGPUStatus _wasi_wgpuAdapterGetInfo(WGPUAdapter adapter, WGPUAdapterInfo * info) WGPU_WASI_IMPORT("wgpuAdapterGetInfo");
WGPUStatus wgpuAdapterGetInfo(WGPUAdapter adapter, WGPUAdapterInfo * info) {
    return _wasi_wgpuAdapterGetInfo(adapter, info);
}

extern WGPUStatus _wasi_wgpuAdapterGetLimits(WGPUAdapter adapter, WGPULimits * limits) WGPU_WASI_IMPORT("wgpuAdapterGetLimits");
WGPUStatus wgpuAdapterGetLimits(WGPUAdapter adapter, WGPULimits * limits) {
    return _wasi_wgpuAdapterGetLimits(adapter, limits);
}

extern WGPUBool _wasi_wgpuAdapterHasFeature(WGPUAdapter adapter, WGPUFeatureName feature) WGPU_WASI_IMPORT("wgpuAdapterHasFeature");
WGPUBool wgpuAdapterHasFeature(WGPUAdapter adapter, WGPUFeatureName feature) {
    return _wasi_wgpuAdapterHasFeature(adapter, feature);
}

extern WGPUFuture _wasi_wgpuAdapterRequestDevice(WGPUAdapter adapter, WGPUDeviceDescriptor const * descriptor, WGPURequestDeviceCallbackInfo callbackInfo) WGPU_WASI_IMPORT("wgpuAdapterRequestDevice");
WGPUFuture wgpuAdapterRequestDevice(WGPUAdapter adapter, WGPUDeviceDescriptor const * descriptor, WGPURequestDeviceCallbackInfo callbackInfo) {
    return _wasi_wgpuAdapterRequestDevice(adapter, descriptor, callbackInfo);
}

extern void _wasi_wgpuAdapterRelease(WGPUAdapter adapter) WGPU_WASI_IMPORT("wgpuAdapterRelease");
void wgpuAdapterRelease(WGPUAdapter adapter) {
    _wasi_wgpuAdapterRelease(adapter);
}

extern void _wasi_wgpuAdapterInfoFreeMembers(WGPUAdapterInfo adapterInfo) WGPU_WASI_IMPORT("wgpuAdapterInfoFreeMembers");
void wgpuAdapterInfoFreeMembers(WGPUAdapterInfo adapterInfo) {
    _wasi_wgpuAdapterInfoFreeMembers(adapterInfo);
}

extern void _wasi_wgpuSupportedFeaturesFreeMembers(WGPUSupportedFeatures supportedFeatures) WGPU_WASI_IMPORT("wgpuSupportedFeaturesFreeMembers");
void wgpuSupportedFeaturesFreeMembers(WGPUSupportedFeatures supportedFeatures) {
    _wasi_wgpuSupportedFeaturesFreeMembers(supportedFeatures);
}

extern WGPUBindGroup _wasi_wgpuDeviceCreateBindGroup(WGPUDevice device, WGPUBindGroupDescriptor const * descriptor) WGPU_WASI_IMPORT("wgpuDeviceCreateBindGroup");
WGPUBindGroup wgpuDeviceCreateBindGroup(WGPUDevice device, WGPUBindGroupDescriptor const * descriptor) {
    return _wasi_wgpuDeviceCreateBindGroup(device, descriptor);
}

extern WGPUBindGroupLayout _wasi_wgpuDeviceCreateBindGroupLayout(WGPUDevice device, WGPUBindGroupLayoutDescriptor const * descriptor) WGPU_WASI_IMPORT("wgpuDeviceCreateBindGroupLayout");
WGPUBindGroupLayout wgpuDeviceCreateBindGroupLayout(WGPUDevice device, WGPUBindGroupLayoutDescriptor const * descriptor) {
    return _wasi_wgpuDeviceCreateBindGroupLayout(device, descriptor);
}

extern WGPUBuffer _wasi_wgpuDeviceCreateBuffer(WGPUDevice device, WGPUBufferDescriptor const * descriptor) WGPU_WASI_IMPORT("wgpuDeviceCreateBuffer");
WGPUBuffer wgpuDeviceCreateBuffer(WGPUDevice device, WGPUBufferDescriptor const * descriptor) {
    return _wasi_wgpuDeviceCreateBuffer(device, descriptor);
}

extern WGPUCommandEncoder _wasi_wgpuDeviceCreateCommandEncoder(WGPUDevice device, WGPUCommandEncoderDescriptor const * descriptor) WGPU_WASI_IMPORT("wgpuDeviceCreateCommandEncoder");
WGPUCommandEncoder wgpuDeviceCreateCommandEncoder(WGPUDevice device, WGPUCommandEncoderDescriptor const * descriptor) {
    return _wasi_wgpuDeviceCreateCommandEncoder(device, descriptor);
}

extern WGPUPipelineLayout _wasi_wgpuDeviceCreatePipelineLayout(WGPUDevice device, WGPUPipelineLayoutDescriptor const * descriptor) WGPU_WASI_IMPORT("wgpuDeviceCreatePipelineLayout");
WGPUPipelineLayout wgpuDeviceCreatePipelineLayout(WGPUDevice device, WGPUPipelineLayoutDescriptor const * descriptor) {
    return _wasi_wgpuDeviceCreatePipelineLayout(device, descriptor);
}

extern WGPURenderPipeline _wasi_wgpuDeviceCreateRenderPipeline(WGPUDevice device, WGPURenderPipelineDescriptor const * descriptor) WGPU_WASI_IMPORT("wgpuDeviceCreateRenderPipeline");
WGPURenderPipeline wgpuDeviceCreateRenderPipeline(WGPUDevice device, WGPURenderPipelineDescriptor const * descriptor) {
    return _wasi_wgpuDeviceCreateRenderPipeline(device, descriptor);
}

extern WGPUSampler _wasi_wgpuDeviceCreateSampler(WGPUDevice device, WGPUSamplerDescriptor const * descriptor) WGPU_WASI_IMPORT("wgpuDeviceCreateSampler");
WGPUSampler wgpuDeviceCreateSampler(WGPUDevice device, WGPUSamplerDescriptor const * descriptor) {
    return _wasi_wgpuDeviceCreateSampler(device, descriptor);
}

extern WGPUShaderModule _wasi_wgpuDeviceCreateShaderModule(WGPUDevice device, WGPUShaderModuleDescriptor const * descriptor) WGPU_WASI_IMPORT("wgpuDeviceCreateShaderModule");
WGPUShaderModule wgpuDeviceCreateShaderModule(WGPUDevice device, WGPUShaderModuleDescriptor const * descriptor) {
    return _wasi_wgpuDeviceCreateShaderModule(device, descriptor);
}

extern WGPUTexture _wasi_wgpuDeviceCreateTexture(WGPUDevice device, WGPUTextureDescriptor const * descriptor) WGPU_WASI_IMPORT("wgpuDeviceCreateTexture");
WGPUTexture wgpuDeviceCreateTexture(WGPUDevice device, WGPUTextureDescriptor const * descriptor) {
    return _wasi_wgpuDeviceCreateTexture(device, descriptor);
}

extern void _wasi_wgpuDeviceDestroy(WGPUDevice device) WGPU_WASI_IMPORT("wgpuDeviceDestroy");
void wgpuDeviceDestroy(WGPUDevice device) {
    _wasi_wgpuDeviceDestroy(device);
}

extern void _wasi_wgpuDeviceGetFeatures(WGPUDevice device, WGPUSupportedFeatures * features) WGPU_WASI_IMPORT("wgpuDeviceGetFeatures");
void wgpuDeviceGetFeatures(WGPUDevice device, WGPUSupportedFeatures * features) {
    _wasi_wgpuDeviceGetFeatures(device, features);
}

extern WGPUStatus _wasi_wgpuDeviceGetLimits(WGPUDevice device, WGPULimits * limits) WGPU_WASI_IMPORT("wgpuDeviceGetLimits");
WGPUStatus wgpuDeviceGetLimits(WGPUDevice device, WGPULimits * limits) {
    return _wasi_wgpuDeviceGetLimits(device, limits);
}

extern WGPUQueue _wasi_wgpuDeviceGetQueue(WGPUDevice device) WGPU_WASI_IMPORT("wgpuDeviceGetQueue");
WGPUQueue wgpuDeviceGetQueue(WGPUDevice device) {
    return _wasi_wgpuDeviceGetQueue(device);
}

extern WGPUBool _wasi_wgpuDeviceHasFeature(WGPUDevice device, WGPUFeatureName feature) WGPU_WASI_IMPORT("wgpuDeviceHasFeature");
WGPUBool wgpuDeviceHasFeature(WGPUDevice device, WGPUFeatureName feature) {
    return _wasi_wgpuDeviceHasFeature(device, feature);
}

extern void _wasi_wgpuDeviceRelease(WGPUDevice device) WGPU_WASI_IMPORT("wgpuDeviceRelease");
void wgpuDeviceRelease(WGPUDevice device) {
    _wasi_wgpuDeviceRelease(device);
}

extern WGPUBool _wasi_wgpuDevicePoll(WGPUDevice device, WGPUBool wait, WGPUSubmissionIndex const * wrappedSubmissionIndex) WGPU_WASI_IMPORT("wgpuDevicePoll");
WGPUBool wgpuDevicePoll(WGPUDevice device, WGPUBool wait, WGPUSubmissionIndex const * wrappedSubmissionIndex) {
    return _wasi_wgpuDevicePoll(device, wait, wrappedSubmissionIndex);
}

extern void _wasi_wgpuQueueSubmit(WGPUQueue queue, size_t commandCount, WGPUCommandBuffer const * commands) WGPU_WASI_IMPORT("wgpuQueueSubmit");
void wgpuQueueSubmit(WGPUQueue queue, size_t commandCount, WGPUCommandBuffer const * commands) {
    _wasi_wgpuQueueSubmit(queue, commandCount, commands);
}

extern void _wasi_wgpuQueueWriteBuffer(WGPUQueue queue, WGPUBuffer buffer, uint64_t bufferOffset, void const * data, size_t size) WGPU_WASI_IMPORT("wgpuQueueWriteBuffer");
void wgpuQueueWriteBuffer(WGPUQueue queue, WGPUBuffer buffer, uint64_t bufferOffset, void const * data, size_t size) {
    _wasi_wgpuQueueWriteBuffer(queue, buffer, bufferOffset, data, size);
}

extern void _wasi_wgpuQueueWriteTexture(WGPUQueue queue, WGPUTexelCopyTextureInfo const * destination, void const * data, size_t dataSize, WGPUTexelCopyBufferLayout const * dataLayout, WGPUExtent3D const * writeSize) WGPU_WASI_IMPORT("wgpuQueueWriteTexture");
void wgpuQueueWriteTexture(WGPUQueue queue, WGPUTexelCopyTextureInfo const * destination, void const * data, size_t dataSize, WGPUTexelCopyBufferLayout const * dataLayout, WGPUExtent3D const * writeSize) {
    _wasi_wgpuQueueWriteTexture(queue, destination, data, dataSize, dataLayout, writeSize);
}

extern void _wasi_wgpuQueueRelease(WGPUQueue queue) WGPU_WASI_IMPORT("wgpuQueueRelease");
void wgpuQueueRelease(WGPUQueue queue) {
    _wasi_wgpuQueueRelease(queue);
}

extern void _wasi_wgpuSurfaceConfigure(WGPUSurface surface, WGPUSurfaceConfiguration const * config) WGPU_WASI_IMPORT("wgpuSurfaceConfigure");
void wgpuSurfaceConfigure(WGPUSurface surface, WGPUSurfaceConfiguration const * config) {
    _wasi_wgpuSurfaceConfigure(surface, config);
}

extern WGPUStatus _wasi_wgpuSurfaceGetCapabilities(WGPUSurface surface, WGPUAdapter adapter, WGPUSurfaceCapabilities * capabilities) WGPU_WASI_IMPORT("wgpuSurfaceGetCapabilities");
WGPUStatus wgpuSurfaceGetCapabilities(WGPUSurface surface, WGPUAdapter adapter, WGPUSurfaceCapabilities * capabilities) {
    return _wasi_wgpuSurfaceGetCapabilities(surface, adapter, capabilities);
}

extern void _wasi_wgpuSurfaceCapabilitiesFreeMembers(WGPUSurfaceCapabilities surfaceCapabilities) WGPU_WASI_IMPORT("wgpuSurfaceCapabilitiesFreeMembers");
void wgpuSurfaceCapabilitiesFreeMembers(WGPUSurfaceCapabilities surfaceCapabilities) {
    _wasi_wgpuSurfaceCapabilitiesFreeMembers(surfaceCapabilities);
}

extern void _wasi_wgpuSurfaceGetCurrentTexture(WGPUSurface surface, WGPUSurfaceTexture * surfaceTexture) WGPU_WASI_IMPORT("wgpuSurfaceGetCurrentTexture");
void wgpuSurfaceGetCurrentTexture(WGPUSurface surface, WGPUSurfaceTexture * surfaceTexture) {
    _wasi_wgpuSurfaceGetCurrentTexture(surface, surfaceTexture);
}

extern WGPUStatus _wasi_wgpuSurfacePresent(WGPUSurface surface) WGPU_WASI_IMPORT("wgpuSurfacePresent");
WGPUStatus wgpuSurfacePresent(WGPUSurface surface) {
    return _wasi_wgpuSurfacePresent(surface);
}

extern void _wasi_wgpuSurfaceUnconfigure(WGPUSurface surface) WGPU_WASI_IMPORT("wgpuSurfaceUnconfigure");
void wgpuSurfaceUnconfigure(WGPUSurface surface) {
    _wasi_wgpuSurfaceUnconfigure(surface);
}

extern void _wasi_wgpuSurfaceRelease(WGPUSurface surface) WGPU_WASI_IMPORT("wgpuSurfaceRelease");
void wgpuSurfaceRelease(WGPUSurface surface) {
    _wasi_wgpuSurfaceRelease(surface);
}

extern WGPUTextureView _wasi_wgpuTextureCreateView(WGPUTexture texture, WGPUTextureViewDescriptor const * descriptor) WGPU_WASI_IMPORT("wgpuTextureCreateView");
WGPUTextureView wgpuTextureCreateView(WGPUTexture texture, WGPUTextureViewDescriptor const * descriptor) {
    return _wasi_wgpuTextureCreateView(texture, descriptor);
}

extern void _wasi_wgpuTextureDestroy(WGPUTexture texture) WGPU_WASI_IMPORT("wgpuTextureDestroy");
void wgpuTextureDestroy(WGPUTexture texture) {
    _wasi_wgpuTextureDestroy(texture);
}

extern void _wasi_wgpuTextureRelease(WGPUTexture texture) WGPU_WASI_IMPORT("wgpuTextureRelease");
void wgpuTextureRelease(WGPUTexture texture) {
    _wasi_wgpuTextureRelease(texture);
}

extern void _wasi_wgpuTextureViewRelease(WGPUTextureView textureView) WGPU_WASI_IMPORT("wgpuTextureViewRelease");
void wgpuTextureViewRelease(WGPUTextureView textureView) {
    _wasi_wgpuTextureViewRelease(textureView);
}

extern void _wasi_wgpuBufferDestroy(WGPUBuffer buffer) WGPU_WASI_IMPORT("wgpuBufferDestroy");
void wgpuBufferDestroy(WGPUBuffer buffer) {
    _wasi_wgpuBufferDestroy(buffer);
}

extern void const * _wasi_wgpuBufferGetConstMappedRange(WGPUBuffer buffer, size_t offset, size_t size) WGPU_WASI_IMPORT("wgpuBufferGetConstMappedRange");
void const * wgpuBufferGetConstMappedRange(WGPUBuffer buffer, size_t offset, size_t size) {
    return _wasi_wgpuBufferGetConstMappedRange(buffer, offset, size);
}

extern void * _wasi_wgpuBufferGetMappedRange(WGPUBuffer buffer, size_t offset, size_t size) WGPU_WASI_IMPORT("wgpuBufferGetMappedRange");
void * wgpuBufferGetMappedRange(WGPUBuffer buffer, size_t offset, size_t size) {
    return _wasi_wgpuBufferGetMappedRange(buffer, offset, size);
}

extern WGPUFuture _wasi_wgpuBufferMapAsync(WGPUBuffer buffer, WGPUMapMode mode, size_t offset, size_t size, WGPUBufferMapCallbackInfo callbackInfo) WGPU_WASI_IMPORT("wgpuBufferMapAsync");
WGPUFuture wgpuBufferMapAsync(WGPUBuffer buffer, WGPUMapMode mode, size_t offset, size_t size, WGPUBufferMapCallbackInfo callbackInfo) {
    return _wasi_wgpuBufferMapAsync(buffer, mode, offset, size, callbackInfo);
}

extern void _wasi_wgpuBufferUnmap(WGPUBuffer buffer) WGPU_WASI_IMPORT("wgpuBufferUnmap");
void wgpuBufferUnmap(WGPUBuffer buffer) {
    _wasi_wgpuBufferUnmap(buffer);
}

extern void _wasi_wgpuBufferRelease(WGPUBuffer buffer) WGPU_WASI_IMPORT("wgpuBufferRelease");
void wgpuBufferRelease(WGPUBuffer buffer) {
    _wasi_wgpuBufferRelease(buffer);
}

extern void _wasi_wgpuBindGroupRelease(WGPUBindGroup bindGroup) WGPU_WASI_IMPORT("wgpuBindGroupRelease");
void wgpuBindGroupRelease(WGPUBindGroup bindGroup) {
    _wasi_wgpuBindGroupRelease(bindGroup);
}

extern void _wasi_wgpuBindGroupLayoutRelease(WGPUBindGroupLayout bindGroupLayout) WGPU_WASI_IMPORT("wgpuBindGroupLayoutRelease");
void wgpuBindGroupLayoutRelease(WGPUBindGroupLayout bindGroupLayout) {
    _wasi_wgpuBindGroupLayoutRelease(bindGroupLayout);
}

extern void _wasi_wgpuPipelineLayoutRelease(WGPUPipelineLayout pipelineLayout) WGPU_WASI_IMPORT("wgpuPipelineLayoutRelease");
void wgpuPipelineLayoutRelease(WGPUPipelineLayout pipelineLayout) {
    _wasi_wgpuPipelineLayoutRelease(pipelineLayout);
}

extern void _wasi_wgpuRenderPipelineRelease(WGPURenderPipeline renderPipeline) WGPU_WASI_IMPORT("wgpuRenderPipelineRelease");
void wgpuRenderPipelineRelease(WGPURenderPipeline renderPipeline) {
    _wasi_wgpuRenderPipelineRelease(renderPipeline);
}

extern void _wasi_wgpuSamplerRelease(WGPUSampler sampler) WGPU_WASI_IMPORT("wgpuSamplerRelease");
void wgpuSamplerRelease(WGPUSampler sampler) {
    _wasi_wgpuSamplerRelease(sampler);
}

extern void _wasi_wgpuShaderModuleRelease(WGPUShaderModule shaderModule) WGPU_WASI_IMPORT("wgpuShaderModuleRelease");
void wgpuShaderModuleRelease(WGPUShaderModule shaderModule) {
    _wasi_wgpuShaderModuleRelease(shaderModule);
}

extern WGPURenderPassEncoder _wasi_wgpuCommandEncoderBeginRenderPass(WGPUCommandEncoder commandEncoder, WGPURenderPassDescriptor const * descriptor) WGPU_WASI_IMPORT("wgpuCommandEncoderBeginRenderPass");
WGPURenderPassEncoder wgpuCommandEncoderBeginRenderPass(WGPUCommandEncoder commandEncoder, WGPURenderPassDescriptor const * descriptor) {
    return _wasi_wgpuCommandEncoderBeginRenderPass(commandEncoder, descriptor);
}

extern void _wasi_wgpuCommandEncoderCopyTextureToBuffer(WGPUCommandEncoder commandEncoder, WGPUTexelCopyTextureInfo const * source, WGPUTexelCopyBufferInfo const * destination, WGPUExtent3D const * copySize) WGPU_WASI_IMPORT("wgpuCommandEncoderCopyTextureToBuffer");
void wgpuCommandEncoderCopyTextureToBuffer(WGPUCommandEncoder commandEncoder, WGPUTexelCopyTextureInfo const * source, WGPUTexelCopyBufferInfo const * destination, WGPUExtent3D const * copySize) {
    _wasi_wgpuCommandEncoderCopyTextureToBuffer(commandEncoder, source, destination, copySize);
}

extern WGPUCommandBuffer _wasi_wgpuCommandEncoderFinish(WGPUCommandEncoder commandEncoder, WGPUCommandBufferDescriptor const * descriptor) WGPU_WASI_IMPORT("wgpuCommandEncoderFinish");
WGPUCommandBuffer wgpuCommandEncoderFinish(WGPUCommandEncoder commandEncoder, WGPUCommandBufferDescriptor const * descriptor) {
    return _wasi_wgpuCommandEncoderFinish(commandEncoder, descriptor);
}

extern void _wasi_wgpuCommandEncoderRelease(WGPUCommandEncoder commandEncoder) WGPU_WASI_IMPORT("wgpuCommandEncoderRelease");
void wgpuCommandEncoderRelease(WGPUCommandEncoder commandEncoder) {
    _wasi_wgpuCommandEncoderRelease(commandEncoder);
}

extern void _wasi_wgpuCommandBufferRelease(WGPUCommandBuffer commandBuffer) WGPU_WASI_IMPORT("wgpuCommandBufferRelease");
void wgpuCommandBufferRelease(WGPUCommandBuffer commandBuffer) {
    _wasi_wgpuCommandBufferRelease(commandBuffer);
}

extern void _wasi_wgpuRenderPassEncoderDraw(WGPURenderPassEncoder renderPassEncoder, uint32_t vertexCount, uint32_t instanceCount, uint32_t firstVertex, uint32_t firstInstance) WGPU_WASI_IMPORT("wgpuRenderPassEncoderDraw");
void wgpuRenderPassEncoderDraw(WGPURenderPassEncoder renderPassEncoder, uint32_t vertexCount, uint32_t instanceCount, uint32_t firstVertex, uint32_t firstInstance) {
    _wasi_wgpuRenderPassEncoderDraw(renderPassEncoder, vertexCount, instanceCount, firstVertex, firstInstance);
}

extern void _wasi_wgpuRenderPassEncoderEnd(WGPURenderPassEncoder renderPassEncoder) WGPU_WASI_IMPORT("wgpuRenderPassEncoderEnd");
void wgpuRenderPassEncoderEnd(WGPURenderPassEncoder renderPassEncoder) {
    _wasi_wgpuRenderPassEncoderEnd(renderPassEncoder);
}

extern void _wasi_wgpuRenderPassEncoderRelease(WGPURenderPassEncoder renderPassEncoder) WGPU_WASI_IMPORT("wgpuRenderPassEncoderRelease");
void wgpuRenderPassEncoderRelease(WGPURenderPassEncoder renderPassEncoder) {
    _wasi_wgpuRenderPassEncoderRelease(renderPassEncoder);
}

extern void _wasi_wgpuRenderPassEncoderSetBindGroup(WGPURenderPassEncoder renderPassEncoder, uint32_t groupIndex, WGPUBindGroup group, size_t dynamicOffsetCount, uint32_t const * dynamicOffsets) WGPU_WASI_IMPORT("wgpuRenderPassEncoderSetBindGroup");
void wgpuRenderPassEncoderSetBindGroup(WGPURenderPassEncoder renderPassEncoder, uint32_t groupIndex, WGPUBindGroup group, size_t dynamicOffsetCount, uint32_t const * dynamicOffsets) {
    _wasi_wgpuRenderPassEncoderSetBindGroup(renderPassEncoder, groupIndex, group, dynamicOffsetCount, dynamicOffsets);
}

extern void _wasi_wgpuRenderPassEncoderSetPipeline(WGPURenderPassEncoder renderPassEncoder, WGPURenderPipeline pipeline) WGPU_WASI_IMPORT("wgpuRenderPassEncoderSetPipeline");
void wgpuRenderPassEncoderSetPipeline(WGPURenderPassEncoder renderPassEncoder, WGPURenderPipeline pipeline) {
    _wasi_wgpuRenderPassEncoderSetPipeline(renderPassEncoder, pipeline);
}

extern void _wasi_wgpuRenderPassEncoderSetScissorRect(WGPURenderPassEncoder renderPassEncoder, uint32_t x, uint32_t y, uint32_t width, uint32_t height) WGPU_WASI_IMPORT("wgpuRenderPassEncoderSetScissorRect");
void wgpuRenderPassEncoderSetScissorRect(WGPURenderPassEncoder renderPassEncoder, uint32_t x, uint32_t y, uint32_t width, uint32_t height) {
    _wasi_wgpuRenderPassEncoderSetScissorRect(renderPassEncoder, x, y, width, height);
}

extern void _wasi_wgpuRenderPassEncoderSetViewport(WGPURenderPassEncoder renderPassEncoder, float x, float y, float width, float height, float minDepth, float maxDepth) WGPU_WASI_IMPORT("wgpuRenderPassEncoderSetViewport");
void wgpuRenderPassEncoderSetViewport(WGPURenderPassEncoder renderPassEncoder, float x, float y, float width, float height, float minDepth, float maxDepth) {
    _wasi_wgpuRenderPassEncoderSetViewport(renderPassEncoder, x, y, width, height, minDepth, maxDepth);
}

__attribute__((export_name("cwebgpu_wasm_invoke_request_adapter_cb"), used))
void cwebgpu_wasm_invoke_request_adapter_cb(
    uintptr_t cb_addr,
    uint32_t status,
    uintptr_t adapter_handle,
    uintptr_t u1,
    uintptr_t u2
) {
    if (!cb_addr) return;
    WGPURequestAdapterCallback fn = (WGPURequestAdapterCallback)cb_addr;
    WGPUStringView msg = { NULL, 0 };
    fn((WGPURequestAdapterStatus)status, (WGPUAdapter)adapter_handle, msg, (void *)u1, (void *)u2);
}

__attribute__((export_name("cwebgpu_wasm_invoke_request_device_cb"), used))
void cwebgpu_wasm_invoke_request_device_cb(
    uintptr_t cb_addr,
    uint32_t status,
    uintptr_t device_handle,
    uintptr_t u1,
    uintptr_t u2
) {
    if (!cb_addr) return;
    WGPURequestDeviceCallback fn = (WGPURequestDeviceCallback)cb_addr;
    WGPUStringView msg = { NULL, 0 };
    fn((WGPURequestDeviceStatus)status, (WGPUDevice)device_handle, msg, (void *)u1, (void *)u2);
}

__attribute__((export_name("cwebgpu_wasm_invoke_buffer_map_cb"), used))
void cwebgpu_wasm_invoke_buffer_map_cb(
    uintptr_t cb_addr,
    uint32_t status,
    uintptr_t u1,
    uintptr_t u2
) {
    if (!cb_addr) return;
    WGPUBufferMapCallback fn = (WGPUBufferMapCallback)cb_addr;
    WGPUStringView msg = { NULL, 0 };
    fn((WGPUMapAsyncStatus)status, msg, (void *)u1, (void *)u2);
}

#endif // defined(__ANDROID__) / defined(__wasi__)

WGPUSurface cwebgpu_create_surface_android(WGPUInstance instance, void * a_native_window) {
#if defined(__ANDROID__)
    if (!instance || !a_native_window) {
        return NULL;
    }
    WGPUSurfaceSourceAndroidNativeWindow source;
    memset(&source, 0, sizeof(source));
    source.chain.next = NULL;
    source.chain.sType = WGPUSType_SurfaceSourceAndroidNativeWindow;
    source.window = a_native_window;

    WGPUSurfaceDescriptor desc;
    memset(&desc, 0, sizeof(desc));
    desc.nextInChain = &source.chain;
    desc.label.data = NULL;
    desc.label.length = 0;
    return wgpuInstanceCreateSurface(instance, &desc);
#else
    (void)instance;
    (void)a_native_window;
    return NULL;
#endif
}

WGPUSurface cwebgpu_create_surface_canvas(WGPUInstance instance, char const * selector, size_t selector_len) {
#if defined(__wasi__)
    if (!instance || !selector) {
        return NULL;
    }
    WGPUSurfaceSourceCanvasHTMLSelector source;
    memset(&source, 0, sizeof(source));
    source.chain.next = NULL;
    source.chain.sType = WGPUSType_SurfaceSourceCanvasHTMLSelector;
    source.selector.data = selector;
    source.selector.length = selector_len;

    WGPUSurfaceDescriptor desc;
    memset(&desc, 0, sizeof(desc));
    desc.nextInChain = &source.chain;
    desc.label.data = NULL;
    desc.label.length = 0;
    return wgpuInstanceCreateSurface(instance, &desc);
#else
    (void)instance;
    (void)selector;
    (void)selector_len;
    return NULL;
#endif
}
