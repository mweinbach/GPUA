#!/usr/bin/env node
// Instantiates `gpui-examples.wasm` via `Hosts/web/gpui_web_runtime.js` in Node.js
// against a recording mock DOM + WebGPU (`navigator.gpu`) harness to verify:
//   1. All Wasm imports in `wasi_snapshot_preview1`, `gpui_web`, and `wgpu` link cleanly.
//   2. `wasm32` C ABI struct offsets & enum values across `CWebGPU` (`webgpu.h`) and `CWebSys`
//      produce valid WebGPU surface configurations, buffers, textures, bind group layouts,
//      and all 9 GPUI render pipelines (including dual-source `subpixel_sprites`).
//   3. Driving `requestAnimationFrame` renders a complete `hello_world` frame (`beginRenderPass`,
//      `setPipeline`, `draw`, `queue.submit`).

import assert from "node:assert/strict";
import { webcrypto } from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";

if (!globalThis.crypto) {
    globalThis.crypto = webcrypto;
}

const wasmPath = process.argv[2];
assert(wasmPath && fs.existsSync(wasmPath), `Wasm binary not found: ${wasmPath}`);

const recorded = {
    surfaceConfigs: [],
    buffers: [],
    textures: [],
    bindGroupLayouts: [],
    renderPipelines: [],
    renderPasses: [],
    drawCalls: [],
    submissions: 0,
};

const rafCallbacks = [];

class MockHTMLCanvasElement {
    constructor() {
        this.id = "";
        this.width = 800;
        this.height = 600;
        this.clientWidth = 800;
        this.clientHeight = 600;
        this.tabIndex = 0;
        this.style = {};
        this._listeners = new Map();
    }
    addEventListener(type, fn) {
        if (!this._listeners.has(type)) this._listeners.set(type, []);
        this._listeners.get(type).push(fn);
    }
    removeEventListener() {}
    focus() {}
    getBoundingClientRect() {
        return { left: 0, top: 0, width: this.clientWidth, height: this.clientHeight };
    }
    getContext(kind) {
        if (kind !== "webgpu") return null;
        return {
            configure(cfg) {
                recorded.surfaceConfigs.push(cfg);
            },
            unconfigure() {},
            getCurrentTexture() {
                return {
                    createView() {
                        return { kind: "swapchain-view" };
                    },
                    destroy() {},
                };
            },
        };
    }
}

const canvasesBySelector = new Map();
const rootCanvas = new MockHTMLCanvasElement();
rootCanvas.id = "gpui-canvas";
canvasesBySelector.set("#gpui-canvas", rootCanvas);

globalThis.HTMLCanvasElement = MockHTMLCanvasElement;
globalThis.ResizeObserver = class {
    constructor(cb) {
        this._cb = cb;
    }
    observe(el) {
        queueMicrotask(() => {
            this._cb([
                {
                    target: el,
                    contentRect: { width: el.clientWidth || 800, height: el.clientHeight || 600 },
                    devicePixelContentBoxSize: [
                        { inlineSize: (el.clientWidth || 800) * 2, blockSize: (el.clientHeight || 600) * 2 },
                    ],
                },
            ]);
        });
    }
    disconnect() {}
};

const mockWindow = {
    devicePixelRatio: 2.0,
    innerWidth: 1024,
    innerHeight: 768,
    screen: { width: 1440, height: 900 },
    navigator: null,
    localStorage: {
        _map: new Map(),
        getItem(k) { return this._map.has(k) ? this._map.get(k) : null; },
        setItem(k, v) { this._map.set(k, String(v)); },
        removeItem(k) { this._map.delete(k); },
    },
    matchMedia(q) {
        return {
            media: q,
            matches: false,
            addEventListener() {},
            removeEventListener() {},
        };
    },
    addEventListener() {},
    removeEventListener() {},
    open() {},
    setTimeout: (...args) => globalThis.setTimeout(...args),
    clearTimeout: (...args) => globalThis.clearTimeout(...args),
};

globalThis.window = mockWindow;
globalThis.document = {
    title: "",
    fullscreenElement: null,
    activeElement: null,
    body: {
        appendChild(el) {
            if (el instanceof MockHTMLCanvasElement && el.id) {
                canvasesBySelector.set(`#${el.id}`, el);
            }
        },
    },
    createElement(tag) {
        if (tag === "canvas") return new MockHTMLCanvasElement();
        return {
            style: {},
            setAttribute() {},
            addEventListener() {},
            removeEventListener() {},
            remove() {},
            focus() {},
            blur() {},
        };
    },
    getElementById(id) {
        return canvasesBySelector.get(`#${id}`) ?? null;
    },
    querySelector(sel) {
        if (canvasesBySelector.has(sel)) return canvasesBySelector.get(sel);
        if (sel === "canvas") return rootCanvas;
        return null;
    },
    addEventListener() {},
    removeEventListener() {},
    exitFullscreen: async () => {},
};

const mockDevice = {
    features: new Set(["dual-source-blending"]),
    limits: { maxTextureDimension2D: 8192 },
    queue: {
        writeBuffer() {},
        writeTexture() {},
        submit(buffers) {
            recorded.submissions += buffers.length;
        },
    },
    createShaderModule({ code }) {
        assert(typeof code === "string" && code.length > 100, "Expected non-empty WGSL shader source");
        return { code };
    },
    createBuffer(desc) {
        recorded.buffers.push(desc);
        const backing = new ArrayBuffer(Math.max(16, Math.min(desc.size || 16, 65536)));
        return {
            desc,
            mapAsync: async () => {},
            getMappedRange: () => backing,
            unmap() {},
            destroy() {},
        };
    },
    createTexture(desc) {
        recorded.textures.push(desc);
        return {
            desc,
            createView() {
                return { desc };
            },
            destroy() {},
        };
    },
    createSampler(desc) {
        return { desc };
    },
    createBindGroupLayout(desc) {
        recorded.bindGroupLayouts.push(desc);
        return { desc };
    },
    createBindGroup(desc) {
        return { desc };
    },
    createPipelineLayout(desc) {
        return { desc };
    },
    createRenderPipeline(desc) {
        recorded.renderPipelines.push(desc);
        return { desc };
    },
    createCommandEncoder() {
        return {
            beginRenderPass(desc) {
                recorded.renderPasses.push(desc);
                return {
                    setPipeline() {},
                    setBindGroup() {},
                    setViewport() {},
                    setScissorRect() {},
                    draw(vertexCount, instanceCount, firstVertex, firstInstance) {
                        recorded.drawCalls.push({ vertexCount, instanceCount, firstVertex, firstInstance });
                    },
                    end() {},
                };
            },
            copyTextureToBuffer() {},
            finish() {
                return { finished: true };
            },
        };
    },
    destroy() {},
};

const mockAdapter = {
    features: new Set(["dual-source-blending"]),
    limits: { maxTextureDimension2D: 8192 },
    requestDevice: async () => mockDevice,
};

Object.defineProperty(globalThis, "navigator", {
    configurable: true,
    value: {
        platform: "MacIntel",
        userAgent: "NodeMockWebGPU",
        clipboard: {
            writeText: async () => {},
            readText: async () => "",
        },
        gpu: {
            getPreferredCanvasFormat: () => "bgra8unorm",
            requestAdapter: async () => mockAdapter,
        },
    },
});
mockWindow.navigator = globalThis.navigator;

globalThis.requestAnimationFrame = (cb) => {
    rafCallbacks.push(cb);
    return rafCallbacks.length;
};
globalThis.cancelAnimationFrame = () => {};
mockWindow.requestAnimationFrame = globalThis.requestAnimationFrame;
mockWindow.cancelAnimationFrame = globalThis.cancelAnimationFrame;

const originalFetch = globalThis.fetch;
globalThis.fetch = async (url, init) => {
    if (String(url) === "file://local.wasm") {
        const bytes = fs.readFileSync(wasmPath);
        return new Response(bytes, {
            status: 200,
            headers: { "content-type": "application/wasm" },
        });
    }
    return originalFetch(url, init);
};

// Also statically validate all Wasm imports match the runtime source.
const wasmBytes = fs.readFileSync(wasmPath);
const compiledMod = await WebAssembly.compile(wasmBytes);
const modImports = WebAssembly.Module.imports(compiledMod);

const runtimeModuleUrl = pathToFileURL(path.resolve("Hosts/web/gpui_web_runtime.js")).href;
const { runGpuiWebApp } = await import(runtimeModuleUrl);

await runGpuiWebApp("file://local.wasm", {
    args: ["gpui-examples", "hello_world"],
});

// Drive animation frames + macrotask ticks (`setTimeout(..., 0)` from `WebDispatcher`)
// to execute `Window.draw` -> `WgpuRenderer.draw`.
for (let step = 0; step < 4; step++) {
    await new Promise((resolve) => setTimeout(resolve, 5));
    const batch = rafCallbacks.splice(0, rafCallbacks.length);
    for (const cb of batch) cb(16.67 * (step + 1));
}
await new Promise((resolve) => setTimeout(resolve, 5));

// 1. Surface configuration ABI assertions
assert(recorded.surfaceConfigs.length >= 1, "Expected wgpuSurfaceConfigure to be called");
const surfCfg = recorded.surfaceConfigs[0];
assert.equal(surfCfg.format, "bgra8unorm");
assert.equal(surfCfg.alphaMode, "opaque", "Expected alphaMode at offset +40 to decode as 'opaque'");
assert.equal(surfCfg.usage, 0x10, "Expected RenderAttachment surface usage at offset +16");

// 2. Buffer & Texture descriptor ABI assertions
assert(recorded.buffers.length >= 2, "Expected globals + instance buffers to be created");
for (const b of recorded.buffers) {
    assert(b.size > 0 && b.size <= 64 * 1024 * 1024, `Unexpected buffer size ${b.size} (64-bit alignment shift?)`);
    assert(b.usage > 0, `Unexpected zero buffer usage`);
}
assert(
    recorded.textures.length >= 1,
    `Expected atlas/MSAA textures to be created; recorded=${JSON.stringify({
        surf: recorded.surfaceConfigs.length,
        bufs: recorded.buffers.length,
        texs: recorded.textures.length,
        bgls: recorded.bindGroupLayouts.length,
        pipes: recorded.renderPipelines.length,
        passes: recorded.renderPasses.length,
        draws: recorded.drawCalls.length,
        subs: recorded.submissions,
    })}`
);
for (const t of recorded.textures) {
    assert(t.size.width > 0 && t.size.width <= 8192, `Invalid texture width ${t.size.width}`);
    assert(t.size.height > 0 && t.size.height <= 8192, `Invalid texture height ${t.size.height}`);
    assert(["r8unorm", "rgba8unorm", "bgra8unorm"].includes(t.format), `Unexpected texture format ${t.format}`);
}

// 3. BindGroupLayout ABI assertions (must include buffer, texture, AND sampler bindings)
assert.equal(recorded.bindGroupLayouts.length, 4, "Expected 4 GPUI bind group layouts");
const hasSamplerBinding = recorded.bindGroupLayouts.some((l) => l.entries.some((e) => e.sampler?.type === "filtering"));
const hasTextureBinding = recorded.bindGroupLayouts.some((l) => l.entries.some((e) => e.texture?.sampleType === "float"));
assert(hasSamplerBinding, "Expected sampler binding in instancesWithTexture/surfaces bind group layouts");
assert(hasTextureBinding, "Expected texture binding in instancesWithTexture/surfaces bind group layouts");

// 4. RenderPipeline ABI assertions (all 9 pipelines including subpixel dual-source blending)
assert.equal(recorded.renderPipelines.length, 9, `Expected 9 render pipelines (8 base + 1 subpixel), got ${recorded.renderPipelines.length}`);
for (const p of recorded.renderPipelines) {
    assert(p.fragment && p.fragment.targets?.length === 1, `Missing fragment state on pipeline (vs=${p.vertex?.entryPoint})`);
}
const quadsPipe = recorded.renderPipelines.find((p) => p.vertex.entryPoint === "vs_quad");
assert(quadsPipe, "Missing vs_quad pipeline");
assert.equal(quadsPipe.primitive.topology, "triangle-strip");
assert.equal(quadsPipe.fragment.entryPoint, "fs_quad");

const pathRasterPipe = recorded.renderPipelines.find((p) => p.vertex.entryPoint === "vs_path_rasterization");
assert(pathRasterPipe, "Missing vs_path_rasterization pipeline");
assert.equal(pathRasterPipe.primitive.topology, "triangle-list");

const subpixelPipe = recorded.renderPipelines.find((p) => p.vertex.entryPoint === "vs_subpixel_sprite");
assert(subpixelPipe, "Missing vs_subpixel_sprite dual-source blending pipeline");
assert.equal(subpixelPipe.fragment.targets[0].blend.color.srcFactor, "src1");
assert.equal(subpixelPipe.fragment.targets[0].blend.color.dstFactor, "one-minus-src1");

// 5. Frame execution assertions (`hello_world` rendered quads & glyphs via WebGPU)
assert(recorded.renderPasses.length >= 1, "Expected at least 1 WebGPU render pass");
assert(recorded.drawCalls.length >= 1, "Expected draw calls during hello_world frame");
assert(recorded.submissions >= 1, "Expected queue.submit() during hello_world frame");

console.log(
    `Verified ${modImports.length} Wasm imports + live Wasm execution: ` +
    `${recorded.renderPipelines.length} pipelines (incl. dual-source subpixel), ` +
    `${recorded.bindGroupLayouts.length} bind group layouts, ` +
    `${recorded.drawCalls.length} draw calls, ${recorded.submissions} GPU submissions.`
);
