// Zero-dependency browser runtime for GPUA Web (`wasm32-unknown-wasip1`) per ADR-0013.
// Provides:
//   1. `wasi_snapshot_preview1` minimal browser shim for the Swift 6.3 Wasm stdlib
//   2. `gpui_web` (`CWebSys`) DOM, Canvas, ResizeObserver, IME, Clipboard, Timer, and Fetch bindings
//   3. `wgpu` (`CWebGPU`) handle table bridging C WebGPU calls onto `navigator.gpu`

const encoder = new TextEncoder();
const decoder = new TextDecoder("utf-8");

const WEB_MOD_CONTROL = 1 << 0;
const WEB_MOD_ALT = 1 << 1;
const WEB_MOD_SHIFT = 1 << 2;
const WEB_MOD_PLATFORM = 1 << 3;
const WEB_MOD_FUNCTION = 1 << 4;
const WEB_MOD_CAPSLOCK = 1 << 5;

function packModifiers(event) {
    let flags = 0;
    if (event.ctrlKey) flags |= WEB_MOD_CONTROL;
    if (event.altKey) flags |= WEB_MOD_ALT;
    if (event.shiftKey) flags |= WEB_MOD_SHIFT;
    if (event.metaKey) flags |= WEB_MOD_PLATFORM;
    if (typeof event.getModifierState === "function") {
        if (event.getModifierState("Fn")) flags |= WEB_MOD_FUNCTION;
        if (event.getModifierState("CapsLock")) flags |= WEB_MOD_CAPSLOCK;
    }
    return flags >>> 0;
}

const TEXTURE_FORMATS = new Map([
    [0x00000001, "r8unorm"],
    [0x00000012, "rgba8unorm"],
    [0x00000013, "rgba8unorm-srgb"],
    [0x00000017, "bgra8unorm"],
    [0x00000018, "bgra8unorm-srgb"],
]);

const REVERSE_TEXTURE_FORMATS = new Map([
    ["r8unorm", 0x00000001],
    ["rgba8unorm", 0x00000012],
    ["rgba8unorm-srgb", 0x00000013],
    ["bgra8unorm", 0x00000017],
    ["bgra8unorm-srgb", 0x00000018],
]);

const WGPU_FEATURE_DUAL_SOURCE_BLENDING = 0x00000010;

const BLEND_FACTORS = new Map([
    [0x00000001, "zero"],
    [0x00000002, "one"],
    [0x00000003, "src"],
    [0x00000004, "one-minus-src"],
    [0x00000005, "src-alpha"],
    [0x00000006, "one-minus-src-alpha"],
    [0x00000007, "dst"],
    [0x00000008, "one-minus-dst"],
    [0x00000009, "dst-alpha"],
    [0x0000000a, "one-minus-dst-alpha"],
    [0x0000000b, "src-alpha-saturated"],
    [0x0000000c, "constant"],
    [0x0000000d, "one-minus-constant"],
    [0x0000000e, "src1"],
    [0x0000000f, "one-minus-src1"],
    [0x00000010, "src1-alpha"],
    [0x00000011, "one-minus-src1-alpha"],
]);

const BLEND_OPS = new Map([
    [0x00000001, "add"],
    [0x00000002, "subtract"],
    [0x00000003, "reverse-subtract"],
    [0x00000004, "min"],
    [0x00000005, "max"],
]);

const PRIMITIVE_TOPOLOGIES = new Map([
    [0x00000001, "point-list"],
    [0x00000002, "line-list"],
    [0x00000003, "line-strip"],
    [0x00000004, "triangle-list"],
    [0x00000005, "triangle-strip"],
]);

const FILTER_MODES = new Map([
    [0x00000001, "nearest"],
    [0x00000002, "linear"],
]);

const ADDRESS_MODES = new Map([
    [0x00000001, "clamp-to-edge"],
    [0x00000002, "repeat"],
    [0x00000003, "mirror-repeat"],
]);

export async function runGpuiWebApp(wasmUrl, options = {}) {
    const cliArgs = options.args ?? ["gpui-web"];
    const envEntries = Object.entries(options.env ?? {});

    // Pre-acquire WebGPU adapter & device when available so synchronous or spontaneous
    // C WebGPU adapter/device queries resolve immediately inside the Wasm frame loop.
    let preloadedAdapter = null;
    let preloadedDevice = null;
    if (typeof navigator !== "undefined" && navigator.gpu) {
        try {
            preloadedAdapter = await navigator.gpu.requestAdapter({
                powerPreference: "high-performance",
            });
            if (preloadedAdapter) {
                const requiredFeatures = [];
                if (preloadedAdapter.features.has("dual-source-blending")) {
                    requiredFeatures.push("dual-source-blending");
                }
                preloadedDevice = await preloadedAdapter.requestDevice({
                    requiredFeatures,
                });
            }
        } catch (err) {
            console.warn("[gpui_web] WebGPU pre-initialization warning:", err);
        }
    }

    let wasmExports = null;
    const windows = new Map();
    let clipboardTextCache = "";

    const memU8 = () => new Uint8Array(wasmExports.memory.buffer);
    const memView = () => new DataView(wasmExports.memory.buffer);

    function readUtf8(ptr, len) {
        if (!ptr || !len) return "";
        if (len === 0xffffffff) {
            const bytes = memU8();
            let end = ptr;
            while (end < bytes.length && bytes[end] !== 0) end++;
            return decoder.decode(bytes.subarray(ptr, end));
        }
        return decoder.decode(memU8().subarray(ptr, ptr + len));
    }

    function readStringView(structOffset) {
        const dv = memView();
        const dataPtr = dv.getUint32(structOffset, true);
        const length = dv.getUint32(structOffset + 4, true);
        return readUtf8(dataPtr, length);
    }

    function withTempWasmSlice(bytes, fn) {
        if (!bytes || bytes.length === 0 || !wasmExports.gpui_web_alloc) {
            return fn(0, 0);
        }
        const ptr = wasmExports.gpui_web_alloc(bytes.length);
        if (!ptr) return fn(0, 0);
        try {
            memU8().set(bytes, ptr);
            return fn(ptr, bytes.length);
        } finally {
            wasmExports.gpui_web_free(ptr, bytes.length);
        }
    }

    // Handle table for WebGPU objects (1-based integer handles)
    let nextHandle = 2;
    const gpuHandles = new Map();
    function allocHandle(obj) {
        const id = nextHandle++;
        gpuHandles.set(id, obj);
        return id;
    }
    function getHandle(id) {
        return gpuHandles.get(id >>> 0) ?? null;
    }
    function releaseHandle(id) {
        gpuHandles.delete(id >>> 0);
    }

    let defaultAdapterHandle = 0;
    let defaultDeviceHandle = 0;
    let defaultQueueHandle = 0;
    let staticCapsPtr = 0;
    let zeroStringViewPtr = 0;
    function getZeroStringViewPtr() {
        if (!zeroStringViewPtr && wasmExports?.gpui_web_alloc) {
            zeroStringViewPtr = wasmExports.gpui_web_alloc(8);
            if (zeroStringViewPtr) {
                const dv = memView();
                dv.setUint32(zeroStringViewPtr, 0, true);
                dv.setUint32(zeroStringViewPtr + 4, 0, true);
            }
        }
        return zeroStringViewPtr;
    }
    if (preloadedAdapter) {
        defaultAdapterHandle = allocHandle({ kind: "adapter", adapter: preloadedAdapter });
    }
    if (preloadedDevice) {
        defaultDeviceHandle = allocHandle({ kind: "device", device: preloadedDevice });
        defaultQueueHandle = allocHandle({ kind: "queue", queue: preloadedDevice.queue, device: preloadedDevice });
    }

    function invokeIndirectCallback(funcTableIndex, ...args) {
        const table = wasmExports.__indirect_function_table;
        if (!table || !funcTableIndex) return;
        const fn = table.get(funcTableIndex >>> 0);
        if (typeof fn === "function") {
            fn(...args);
        }
    }

    // -------------------------------------------------------------------------
    // 1. WASI Snapshot Preview 1 Shim
    // -------------------------------------------------------------------------
    const wasi_snapshot_preview1 = {
        args_sizes_get(argcPtr, argvBufSizePtr) {
            const dv = memView();
            let total = 0;
            for (const arg of cliArgs) total += encoder.encode(arg).length + 1;
            dv.setUint32(argcPtr, cliArgs.length, true);
            dv.setUint32(argvBufSizePtr, total, true);
            return 0;
        },
        args_get(argvPtr, argvBufPtr) {
            const dv = memView();
            const u8 = memU8();
            let offset = argvBufPtr;
            cliArgs.forEach((arg, idx) => {
                dv.setUint32(argvPtr + idx * 4, offset, true);
                const encoded = encoder.encode(arg);
                u8.set(encoded, offset);
                u8[offset + encoded.length] = 0;
                offset += encoded.length + 1;
            });
            return 0;
        },
        environ_sizes_get(countPtr, bufSizePtr) {
            const dv = memView();
            let total = 0;
            for (const [k, v] of envEntries) total += encoder.encode(`${k}=${v}`).length + 1;
            dv.setUint32(countPtr, envEntries.length, true);
            dv.setUint32(bufSizePtr, total, true);
            return 0;
        },
        environ_get(environPtr, environBufPtr) {
            const dv = memView();
            const u8 = memU8();
            let offset = environBufPtr;
            envEntries.forEach(([k, v], idx) => {
                dv.setUint32(environPtr + idx * 4, offset, true);
                const encoded = encoder.encode(`${k}=${v}`);
                u8.set(encoded, offset);
                u8[offset + encoded.length] = 0;
                offset += encoded.length + 1;
            });
            return 0;
        },
        clock_res_get(clockId, resPtr) {
            memView().setBigUint64(resPtr, 1000n, true);
            return 0;
        },
        clock_time_get(clockId, precision, timePtr) {
            const ms = clockId === 0 ? Date.now() : performance.now();
            const ns = BigInt(Math.floor(ms * 1_000_000));
            memView().setBigUint64(timePtr, ns, true);
            return 0;
        },
        fd_write(fd, iovsPtr, iovsLen, nwrittenPtr) {
            const dv = memView();
            const u8 = memU8();
            let written = 0;
            const chunks = [];
            for (let i = 0; i < iovsLen; i++) {
                const ptr = dv.getUint32(iovsPtr + i * 8, true);
                const len = dv.getUint32(iovsPtr + i * 8 + 4, true);
                if (len > 0) {
                    chunks.push(decoder.decode(u8.subarray(ptr, ptr + len)));
                    written += len;
                }
            }
            const text = chunks.join("");
            if (text) {
                if (fd === 2) console.error(text);
                else console.log(text);
            }
            dv.setUint32(nwrittenPtr, written, true);
            return 0;
        },
        fd_read: () => 0,
        fd_close: () => 0,
        fd_seek: () => 70,
        fd_fdstat_get(fd, bufPtr) {
            const dv = memView();
            dv.setUint8(bufPtr, fd <= 2 ? 2 : 4);
            dv.setUint16(bufPtr + 2, 0, true);
            dv.setBigUint64(bufPtr + 8, 0n, true);
            dv.setBigUint64(bufPtr + 16, 0n, true);
            return 0;
        },
        fd_fdstat_set_flags: () => 0,
        fd_fdstat_set_rights: () => 0,
        fd_filestat_get: () => 8,
        fd_filestat_set_size: () => 8,
        fd_filestat_set_times: () => 8,
        fd_pread: () => 8,
        fd_pwrite: () => 8,
        fd_prestat_get: () => 8,
        fd_prestat_dir_name: () => 8,
        fd_advise: () => 0,
        fd_allocate: () => 8,
        fd_datasync: () => 0,
        fd_readdir: () => 8,
        fd_renumber: () => 8,
        fd_sync: () => 0,
        fd_tell: () => 70,
        path_create_directory: () => 8,
        path_filestat_get: () => 8,
        path_filestat_set_times: () => 8,
        path_link: () => 8,
        path_open: () => 8,
        path_readlink: () => 8,
        path_remove_directory: () => 8,
        path_rename: () => 8,
        path_symlink: () => 8,
        path_unlink_file: () => 8,
        poll_oneoff: () => 0,
        proc_exit(code) {
            if (code !== 0) {
                throw new Error(`WASI proc_exit(${code})`);
            }
        },
        proc_raise: () => 0,
        sched_yield: () => 0,
        random_get(bufPtr, bufLen) {
            const slice = memU8().subarray(bufPtr, bufPtr + bufLen);
            if (typeof globalThis.crypto?.getRandomValues === "function") {
                globalThis.crypto.getRandomValues(slice);
            } else {
                for (let i = 0; i < slice.length; i++) {
                    slice[i] = (Math.random() * 256) | 0;
                }
            }
            return 0;
        },
        sock_accept: () => 8,
        sock_recv: () => 8,
        sock_send: () => 8,
        sock_shutdown: () => 8,
    };

    // -------------------------------------------------------------------------
    // 2. `gpui_web` (`CWebSys`) Host Bindings
    // -------------------------------------------------------------------------
    const gpui_web = {
        cwebsys_console_log(level, ptr, len) {
            const msg = readUtf8(ptr, len);
            if (level === 0) console.error(msg);
            else if (level === 1) console.warn(msg);
            else if (level === 2) console.info(msg);
            else console.log(msg);
        },
        cwebsys_performance_now: () => performance.now(),
        cwebsys_date_now: () => Date.now(),
        cwebsys_schedule_timeout(callbackId, delayMs) {
            return window.setTimeout(() => {
                wasmExports.gpui_web_on_timer?.(callbackId >>> 0);
            }, Math.max(0, delayMs | 0));
        },
        cwebsys_queue_microtask(callbackId) {
            queueMicrotask(() => {
                wasmExports.gpui_web_on_microtask?.(callbackId >>> 0);
            });
        },
        cwebsys_request_animation_frame(windowId) {
            return window.requestAnimationFrame((ts) => {
                wasmExports.gpui_web_on_animation_frame?.(windowId >>> 0, ts);
            });
        },
        cwebsys_device_pixel_ratio: () => window.devicePixelRatio || 1.0,
        cwebsys_screen_width: () => window.screen?.width || 1920,
        cwebsys_screen_height: () => window.screen?.height || 1080,
        cwebsys_window_inner_width: () => window.innerWidth || 1920,
        cwebsys_window_inner_height: () => window.innerHeight || 1080,
        cwebsys_prefers_dark_mode: () =>
            window.matchMedia?.("(prefers-color-scheme: dark)")?.matches ? 1 : 0,
        cwebsys_is_mac_platform() {
            const p = navigator.platform || "";
            const ua = navigator.userAgent || "";
            return p.includes("Mac") || ua.includes("Mac") ? 1 : 0;
        },
        cwebsys_has_device_pixel_support() {
            if (typeof ResizeObserverEntry === "undefined") return 0;
            const desc = Object.getOwnPropertyDescriptor(
                ResizeObserverEntry.prototype,
                "devicePixelContentBoxSize"
            );
            return desc !== undefined ? 1 : 0;
        },
        cwebsys_document_is_visible: () =>
            document.visibilityState === "visible" ? 1 : 0,
        cwebsys_hardware_concurrency: () => navigator.hardwareConcurrency || 2,
        cwebsys_watch_dpr_media_query(windowId, queryPtr, queryLen) {
            const win = windows.get(windowId >>> 0);
            if (!win || !window.matchMedia) return;
            if (win.dprCleanup) {
                win.dprCleanup();
                win.dprCleanup = null;
            }
            const query = readUtf8(queryPtr, queryLen);
            const mql = window.matchMedia(query);
            const onChange = () => {
                wasmExports.gpui_web_on_dpr_change?.(
                    windowId >>> 0,
                    window.devicePixelRatio || 1.0
                );
            };
            mql.addEventListener("change", onChange);
            win.dprCleanup = () => mql.removeEventListener("change", onChange);
        },
        cwebsys_unwatch_dpr_media_query(windowId) {
            const win = windows.get(windowId >>> 0);
            if (win?.dprCleanup) {
                win.dprCleanup();
                win.dprCleanup = null;
            }
        },
        cwebsys_create_or_bind_canvas(windowId, selectorPtr, selectorLen, hasDevicePixelSupport) {
            const selector = readUtf8(selectorPtr, selectorLen);
            const idAttr = selector.startsWith("#") ? selector.slice(1) : `gpui-canvas-${windowId}`;
            let canvas = document.querySelector(selector);
            if (!(canvas instanceof HTMLCanvasElement)) {
                canvas = document.createElement("canvas");
                canvas.id = idAttr;
                canvas.tabIndex = -1;
                canvas.style.width = "100%";
                canvas.style.height = "100%";
                canvas.style.display = "block";
                canvas.style.outline = "none";
                canvas.style.touchAction = "none";
                document.body.appendChild(canvas);
            }

            const input = document.createElement("input");
            input.type = "text";
            input.autocomplete = "off";
            input.autocapitalize = "off";
            input.spellcheck = false;
            Object.assign(input.style, {
                position: "fixed",
                top: "0",
                left: "0",
                width: "1px",
                height: "1px",
                opacity: "0",
                pointerEvents: "none",
            });
            document.body.appendChild(input);

            const cleanups = [];
            const on = (target, type, handler, opts) => {
                target.addEventListener(type, handler, opts);
                cleanups.push(() => target.removeEventListener(type, handler, opts));
            };

            on(canvas, "pointerdown", (e) => {
                e.preventDefault();
                input.focus();
                wasmExports.gpui_web_on_pointer_event?.(
                    windowId,
                    0,
                    e.button,
                    e.offsetX,
                    e.offsetY,
                    packModifiers(e),
                    Date.now()
                );
            });
            on(canvas, "pointerup", (e) => {
                e.preventDefault();
                wasmExports.gpui_web_on_pointer_event?.(
                    windowId,
                    1,
                    e.button,
                    e.offsetX,
                    e.offsetY,
                    packModifiers(e),
                    Date.now()
                );
            });
            on(canvas, "pointermove", (e) => {
                e.preventDefault();
                wasmExports.gpui_web_on_pointer_event?.(
                    windowId,
                    2,
                    e.button,
                    e.offsetX,
                    e.offsetY,
                    packModifiers(e),
                    Date.now()
                );
            });
            on(canvas, "pointerleave", (e) => {
                wasmExports.gpui_web_on_pointer_event?.(
                    windowId,
                    3,
                    e.button,
                    e.offsetX,
                    e.offsetY,
                    packModifiers(e),
                    Date.now()
                );
            });
            on(canvas, "pointerenter", () => {
                wasmExports.gpui_web_on_pointer_event?.(windowId, 4, 0, 0, 0, 0, Date.now());
            });
            on(
                canvas,
                "wheel",
                (e) => {
                    e.preventDefault();
                    wasmExports.gpui_web_on_wheel_event?.(
                        windowId,
                        e.offsetX,
                        e.offsetY,
                        e.deltaX,
                        e.deltaY,
                        e.deltaMode >>> 0,
                        packModifiers(e)
                    );
                },
                { passive: false }
            );
            on(canvas, "contextmenu", (e) => e.preventDefault());
            on(canvas, "dragover", (e) => {
                e.preventDefault();
                wasmExports.gpui_web_on_file_drop_event?.(windowId, 0, e.offsetX, e.offsetY, 0, 0);
            });
            on(canvas, "drop", (e) => {
                e.preventDefault();
                const names = [];
                if (e.dataTransfer?.files) {
                    for (let i = 0; i < e.dataTransfer.files.length; i++) {
                        names.push(e.dataTransfer.files[i].name);
                    }
                }
                const bytes = encoder.encode(names.join("\n"));
                withTempWasmSlice(bytes, (ptr, len) => {
                    wasmExports.gpui_web_on_file_drop_event?.(
                        windowId,
                        1,
                        e.offsetX,
                        e.offsetY,
                        ptr,
                        len
                    );
                });
            });
            on(canvas, "dragleave", () => {
                wasmExports.gpui_web_on_file_drop_event?.(windowId, 2, 0, 0, 0, 0);
            });

            const forwardKey = (kind, e) => {
                const keyBytes = encoder.encode(e.key || "");
                const codeBytes = encoder.encode(e.code || "");
                const prevent = withTempWasmSlice(keyBytes, (kPtr, kLen) =>
                    withTempWasmSlice(codeBytes, (cPtr, cLen) =>
                        wasmExports.gpui_web_on_key_event?.(
                            windowId,
                            kind,
                            kPtr,
                            kLen,
                            cPtr,
                            cLen,
                            packModifiers(e),
                            e.repeat ? 1 : 0,
                            e.isComposing ? 1 : 0
                        ) ?? 0
                    )
                );
                if (prevent) e.preventDefault();
            };
            on(input, "keydown", (e) => forwardKey(0, e));
            on(input, "keyup", (e) => forwardKey(1, e));

            on(input, "compositionstart", () => {
                wasmExports.gpui_web_on_composition_event?.(windowId, 0, 0, 0);
            });
            on(input, "compositionupdate", (e) => {
                const bytes = encoder.encode(e.data || "");
                withTempWasmSlice(bytes, (ptr, len) => {
                    wasmExports.gpui_web_on_composition_event?.(windowId, 1, ptr, len);
                });
            });
            on(input, "compositionend", (e) => {
                const bytes = encoder.encode(e.data || "");
                withTempWasmSlice(bytes, (ptr, len) => {
                    wasmExports.gpui_web_on_composition_event?.(windowId, 2, ptr, len);
                });
                input.value = "";
            });
            on(input, "focus", () => wasmExports.gpui_web_on_focus_event?.(windowId, 1));
            on(input, "blur", () => wasmExports.gpui_web_on_focus_event?.(windowId, 0));

            on(document, "visibilitychange", () => {
                wasmExports.gpui_web_on_visibility_change?.(
                    windowId,
                    document.visibilityState === "visible" ? 1 : 0
                );
            });
            if (window.matchMedia) {
                const darkMql = window.matchMedia("(prefers-color-scheme: dark)");
                on(darkMql, "change", (ev) => {
                    wasmExports.gpui_web_on_appearance_change?.(windowId, ev.matches ? 1 : 0);
                });
            }

            let resizeObserver = null;
            if (typeof ResizeObserver !== "undefined") {
                resizeObserver = new ResizeObserver((entries) => {
                    const entry = entries[0];
                    if (!entry) return;
                    const dpr = window.devicePixelRatio || 1.0;
                    let physW = 0;
                    let physH = 0;
                    const logW = entry.contentRect.width;
                    const logH = entry.contentRect.height;
                    if (hasDevicePixelSupport && entry.devicePixelContentBoxSize?.[0]) {
                        physW = entry.devicePixelContentBoxSize[0].inlineSize >>> 0;
                        physH = entry.devicePixelContentBoxSize[0].blockSize >>> 0;
                    } else {
                        physW = Math.round(logW * dpr) >>> 0;
                        physH = Math.round(logH * dpr) >>> 0;
                    }
                    wasmExports.gpui_web_on_resize?.(windowId, physW, physH, logW, logH, dpr);
                });
                if (hasDevicePixelSupport) {
                    resizeObserver.observe(canvas, { box: "device-pixel-content-box" });
                } else {
                    resizeObserver.observe(canvas);
                }
            }

            windows.set(windowId >>> 0, {
                canvas,
                input,
                resizeObserver,
                dprCleanup: null,
                cleanups,
            });
            return 1;
        },
        cwebsys_destroy_canvas(windowId) {
            const win = windows.get(windowId >>> 0);
            if (!win) return;
            win.resizeObserver?.disconnect();
            win.dprCleanup?.();
            for (const fn of win.cleanups) fn();
            win.canvas.remove();
            win.input.remove();
            windows.delete(windowId >>> 0);
        },
        cwebsys_canvas_client_width(windowId) {
            return windows.get(windowId >>> 0)?.canvas.getBoundingClientRect().width ?? 0;
        },
        cwebsys_canvas_client_height(windowId) {
            return windows.get(windowId >>> 0)?.canvas.getBoundingClientRect().height ?? 0;
        },
        cwebsys_canvas_width(windowId) {
            return windows.get(windowId >>> 0)?.canvas.width ?? 0;
        },
        cwebsys_canvas_height(windowId) {
            return windows.get(windowId >>> 0)?.canvas.height ?? 0;
        },
        cwebsys_set_canvas_size(windowId, width, height) {
            const win = windows.get(windowId >>> 0);
            if (!win) return;
            win.canvas.width = width >>> 0;
            win.canvas.height = height >>> 0;
        },
        cwebsys_set_canvas_style_size(windowId, width, height) {
            const win = windows.get(windowId >>> 0);
            if (!win) return;
            win.canvas.style.width = `${width}px`;
            win.canvas.style.height = `${height}px`;
        },
        cwebsys_focus_input(windowId) {
            windows.get(windowId >>> 0)?.input.focus();
        },
        cwebsys_clear_input_value(windowId) {
            const win = windows.get(windowId >>> 0);
            if (win) win.input.value = "";
        },
        cwebsys_set_ime_position(windowId, x, y, width, height) {
            const win = windows.get(windowId >>> 0);
            if (!win) return;
            win.input.style.left = `${x}px`;
            win.input.style.top = `${y}px`;
            win.input.style.width = `${Math.max(1, width)}px`;
            win.input.style.height = `${Math.max(1, height)}px`;
        },
        cwebsys_set_fullscreen(windowId, fullscreen) {
            const win = windows.get(windowId >>> 0);
            if (!win) return;
            if (fullscreen) {
                win.canvas.requestFullscreen?.().catch(() => {});
            } else if (document.fullscreenElement) {
                document.exitFullscreen?.().catch(() => {});
            }
        },
        cwebsys_set_cursor_style(ptr, len) {
            if (document.body) {
                document.body.style.cursor = readUtf8(ptr, len);
            }
        },
        cwebsys_set_document_title(ptr, len) {
            document.title = readUtf8(ptr, len);
        },
        cwebsys_open_url(ptr, len) {
            const url = readUtf8(ptr, len);
            return window.open(url, "_blank") ? 1 : 0;
        },
        cwebsys_clipboard_write(ptr, len) {
            const text = readUtf8(ptr, len);
            clipboardTextCache = text;
            navigator.clipboard?.writeText?.(text).catch(() => {});
        },
        cwebsys_clipboard_read(bufPtr, bufCap) {
            if (!clipboardTextCache || !bufPtr || !bufCap) return 0;
            const bytes = encoder.encode(clipboardTextCache);
            const n = Math.min(bytes.length, bufCap >>> 0);
            memU8().set(bytes.subarray(0, n), bufPtr);
            return n;
        },
        cwebsys_keyboard_layout_id(bufPtr, bufCap) {
            const id = encoder.encode("us");
            const n = Math.min(id.length, bufCap >>> 0);
            memU8().set(id.subarray(0, n), bufPtr);
            return n;
        },
        cwebsys_fetch_start(
            requestId,
            methodPtr,
            methodLen,
            urlPtr,
            urlLen,
            headersPtr,
            headersLen,
            bodyPtr,
            bodyLen,
            redirectMode
        ) {
            const method = readUtf8(methodPtr, methodLen);
            const url = readUtf8(urlPtr, urlLen);
            const headers = new Headers();
            if (headersPtr && headersLen > 0) {
                const raw = memU8().subarray(headersPtr, headersPtr + headersLen);
                const parts = [];
                let start = 0;
                for (let i = 0; i < raw.length; i++) {
                    if (raw[i] === 0) {
                        parts.push(decoder.decode(raw.subarray(start, i)));
                        start = i + 1;
                    }
                }
                for (let i = 0; i + 1 < parts.length; i += 2) {
                    headers.set(parts[i], parts[i + 1]);
                }
            }
            const init = {
                method,
                headers,
                redirect: redirectMode === 0 ? "manual" : "follow",
            };
            if (bodyPtr && bodyLen > 0) {
                init.body = memU8().slice(bodyPtr, bodyPtr + bodyLen);
            }

            fetch(url, init)
                .then(async (resp) => {
                    const headerChunks = [];
                    resp.headers.forEach((value, name) => {
                        headerChunks.push(encoder.encode(name), new Uint8Array([0]));
                        headerChunks.push(encoder.encode(value), new Uint8Array([0]));
                    });
                    let totalHdr = 0;
                    for (const c of headerChunks) totalHdr += c.length;
                    const hdrBytes = new Uint8Array(totalHdr);
                    let pos = 0;
                    for (const c of headerChunks) {
                        hdrBytes.set(c, pos);
                        pos += c.length;
                    }
                    const bodyBytes = new Uint8Array(await resp.arrayBuffer());
                    withTempWasmSlice(hdrBytes, (hPtr, hLen) => {
                        withTempWasmSlice(bodyBytes, (bPtr, bLen) => {
                            wasmExports.gpui_web_on_fetch_complete?.(
                                requestId >>> 0,
                                resp.status | 0,
                                hPtr,
                                hLen,
                                bPtr,
                                bLen,
                                0,
                                0
                            );
                        });
                    });
                })
                .catch((err) => {
                    const errBytes = encoder.encode(String(err?.message || err));
                    withTempWasmSlice(errBytes, (ePtr, eLen) => {
                        wasmExports.gpui_web_on_fetch_complete?.(
                            requestId >>> 0,
                            0,
                            0,
                            0,
                            0,
                            0,
                            ePtr,
                            eLen
                        );
                    });
                });
        },
    };

    // -------------------------------------------------------------------------
    // 3. `wgpu` (`CWebGPU`) Browser WebGPU Handle Table
    // -------------------------------------------------------------------------
    let staticFeaturesPtr = 0;
    function getDualSourceFeatureBufPtr() {
        if (!staticFeaturesPtr && wasmExports?.gpui_web_alloc) {
            staticFeaturesPtr = wasmExports.gpui_web_alloc(4);
        }
        if (staticFeaturesPtr) {
            memView().setUint32(staticFeaturesPtr, WGPU_FEATURE_DUAL_SOURCE_BLENDING, true);
        }
        return staticFeaturesPtr;
    }

    const wgpu = {
        wgpuCreateInstance() {
            return allocHandle({ kind: "instance" });
        },
        wgpuInstanceRelease: releaseHandle,
        wgpuInstanceProcessEvents() {},
        wgpuInstanceEnumerateAdapters(instance, optionsPtr, adaptersPtr) {
            if (!defaultAdapterHandle) return 0;
            if (adaptersPtr) {
                memView().setUint32(adaptersPtr, defaultAdapterHandle, true);
            }
            return 1;
        },
        wgpuInstanceRequestAdapter(instance, optionsPtr, callbackInfoPtr) {
            const dv = memView();
            const callbackIdx = dv.getUint32(callbackInfoPtr + 8, true);
            const u1 = dv.getUint32(callbackInfoPtr + 12, true);
            const u2 = dv.getUint32(callbackInfoPtr + 16, true);
            if (typeof wasmExports.cwebgpu_wasm_invoke_request_adapter_cb === "function") {
                if (defaultAdapterHandle) {
                    wasmExports.cwebgpu_wasm_invoke_request_adapter_cb(callbackIdx, 1, defaultAdapterHandle, u1, u2);
                } else {
                    wasmExports.cwebgpu_wasm_invoke_request_adapter_cb(callbackIdx, 3, 0, u1, u2);
                }
            } else {
                const msgPtr = getZeroStringViewPtr();
                if (defaultAdapterHandle) {
                    invokeIndirectCallback(callbackIdx, 1, defaultAdapterHandle, msgPtr, u1, u2);
                } else {
                    invokeIndirectCallback(callbackIdx, 3, 0, msgPtr, u1, u2);
                }
            }
            return 1n;
        },
        wgpuInstanceCreateSurface(instance, descPtr) {
            const dv = memView();
            const nextPtr = dv.getUint32(descPtr, true);
            if (!nextPtr) return 0;
            const sType = dv.getUint32(nextPtr + 4, true);
            if (sType !== 0x00040001 && sType !== 0x00040002) return 0;
            const selector = readStringView(nextPtr + 8);
            const canvas = document.querySelector(selector);
            if (!(canvas instanceof HTMLCanvasElement)) return 0;
            const context = canvas.getContext("webgpu");
            if (!context) return 0;
            return allocHandle({
                kind: "surface",
                canvas,
                context,
                format: navigator.gpu?.getPreferredCanvasFormat?.() ?? "bgra8unorm",
            });
        },
        wgpuAdapterGetFeatures(adapterId, featuresPtr) {
            const dv = memView();
            const entry = getHandle(adapterId);
            const hasDual = entry?.adapter?.features?.has("dual-source-blending");
            const featBuf = hasDual ? getDualSourceFeatureBufPtr() : 0;
            if (featBuf) {
                dv.setUint32(featuresPtr, 1, true);
                dv.setUint32(featuresPtr + 4, featBuf, true);
            } else {
                dv.setUint32(featuresPtr, 0, true);
                dv.setUint32(featuresPtr + 4, 0, true);
            }
        },
        wgpuSupportedFeaturesFreeMembers() {},
        wgpuAdapterGetInfo(adapterId, infoPtr) {
            return 1;
        },
        wgpuAdapterInfoFreeMembers() {},
        wgpuAdapterGetLimits(adapterId, limitsPtr) {
            const entry = getHandle(adapterId);
            const maxDim = entry?.adapter?.limits?.maxTextureDimension2D ?? 8192;
            memView().setUint32(limitsPtr + 8, maxDim, true);
            return 1;
        },
        wgpuAdapterHasFeature(adapterId, feature) {
            const entry = getHandle(adapterId);
            if (feature === WGPU_FEATURE_DUAL_SOURCE_BLENDING) {
                return entry?.adapter?.features?.has("dual-source-blending") ? 1 : 0;
            }
            return 0;
        },
        wgpuAdapterRequestDevice(adapterId, descPtr, callbackInfoPtr) {
            const dv = memView();
            const callbackIdx = dv.getUint32(callbackInfoPtr + 8, true);
            const u1 = dv.getUint32(callbackInfoPtr + 12, true);
            const u2 = dv.getUint32(callbackInfoPtr + 16, true);
            if (typeof wasmExports.cwebgpu_wasm_invoke_request_device_cb === "function") {
                if (defaultDeviceHandle) {
                    wasmExports.cwebgpu_wasm_invoke_request_device_cb(callbackIdx, 1, defaultDeviceHandle, u1, u2);
                } else {
                    wasmExports.cwebgpu_wasm_invoke_request_device_cb(callbackIdx, 2, 0, u1, u2);
                }
            } else {
                const msgPtr = getZeroStringViewPtr();
                if (defaultDeviceHandle) {
                    invokeIndirectCallback(callbackIdx, 1, defaultDeviceHandle, msgPtr, u1, u2);
                } else {
                    invokeIndirectCallback(callbackIdx, 2, 0, msgPtr, u1, u2);
                }
            }
            return 1n;
        },
        wgpuAdapterRelease: releaseHandle,
        wgpuDeviceGetQueue(deviceId) {
            if (deviceId === defaultDeviceHandle && defaultQueueHandle) {
                return defaultQueueHandle;
            }
            const dev = getHandle(deviceId)?.device;
            return dev ? allocHandle({ kind: "queue", queue: dev.queue, device: dev }) : 0;
        },
        wgpuDeviceGetLimits(deviceId, limitsPtr) {
            const dev = getHandle(deviceId)?.device;
            const maxDim = dev?.limits?.maxTextureDimension2D ?? 8192;
            memView().setUint32(limitsPtr + 8, maxDim, true);
            return 1;
        },
        wgpuDeviceGetFeatures(deviceId, featuresPtr) {
            const dv = memView();
            const dev = getHandle(deviceId)?.device;
            const hasDual = dev?.features?.has("dual-source-blending");
            const featBuf = hasDual ? getDualSourceFeatureBufPtr() : 0;
            if (featBuf) {
                dv.setUint32(featuresPtr, 1, true);
                dv.setUint32(featuresPtr + 4, featBuf, true);
            } else {
                dv.setUint32(featuresPtr, 0, true);
                dv.setUint32(featuresPtr + 4, 0, true);
            }
        },
        wgpuDeviceHasFeature(deviceId, feature) {
            const dev = getHandle(deviceId)?.device;
            if (feature === WGPU_FEATURE_DUAL_SOURCE_BLENDING) {
                return dev?.features?.has("dual-source-blending") ? 1 : 0;
            }
            return 0;
        },
        wgpuDevicePoll: () => 1,
        wgpuDeviceDestroy(deviceId) {
            getHandle(deviceId)?.device?.destroy?.();
        },
        wgpuDeviceRelease: releaseHandle,
        wgpuSurfaceGetCapabilities(surfaceId, adapterId, capsPtr) {
            const surf = getHandle(surfaceId);
            if (!surf || !wasmExports.gpui_web_alloc) return 2;
            if (!staticCapsPtr) {
                staticCapsPtr = wasmExports.gpui_web_alloc(24);
            }
            const dv = memView();
            const preferredEnum = REVERSE_TEXTURE_FORMATS.get(surf.format) ?? 0x00000017;
            dv.setUint32(staticCapsPtr, preferredEnum, true);
            dv.setUint32(staticCapsPtr + 4, 0x00000001, true); // Fifo
            dv.setUint32(staticCapsPtr + 8, 0x00000001, true); // Opaque
            dv.setUint32(staticCapsPtr + 12, 0x00000002, true); // Premultiplied

            // WGPUSurfaceCapabilities (sizeof = 40, align = 8 on wasm32):
            // nextInChain: +0, usages: +8 (u64), formatCount: +16, formats: +20,
            // presentModeCount: +24, presentModes: +28, alphaModeCount: +32, alphaModes: +36
            dv.setUint32(capsPtr, 0, true);
            dv.setBigUint64(capsPtr + 8, 0x10n, true); // WGPUTextureUsage_RenderAttachment
            dv.setUint32(capsPtr + 16, 1, true);
            dv.setUint32(capsPtr + 20, staticCapsPtr, true);
            dv.setUint32(capsPtr + 24, 1, true);
            dv.setUint32(capsPtr + 28, staticCapsPtr + 4, true);
            dv.setUint32(capsPtr + 32, 2, true);
            dv.setUint32(capsPtr + 36, staticCapsPtr + 8, true);
            return 1;
        },
        wgpuSurfaceCapabilitiesFreeMembers() {},
        wgpuSurfaceConfigure(surfaceId, configPtr) {
            const surf = getHandle(surfaceId);
            if (!surf) return;
            const dv = memView();
            // WGPUSurfaceConfiguration (sizeof = 48, align = 8 on wasm32):
            // nextInChain: +0, device: +4, format: +8, usage: +16 (u64),
            // width: +24, height: +28, viewFormatCount: +32, viewFormats: +36,
            // alphaMode: +40, presentMode: +44
            const devId = dv.getUint32(configPtr + 4, true);
            const formatEnum = dv.getUint32(configPtr + 8, true);
            const usage = Number(dv.getBigUint64(configPtr + 16, true)) || 0x10;
            const alphaEnum = dv.getUint32(configPtr + 40, true);
            const dev = getHandle(devId)?.device;
            if (!dev) return;
            surf.context.configure({
                device: dev,
                format: TEXTURE_FORMATS.get(formatEnum) ?? surf.format,
                usage,
                alphaMode: alphaEnum === 2 ? "premultiplied" : "opaque",
            });
        },
        wgpuSurfaceGetCurrentTexture(surfaceId, outPtr) {
            const surf = getHandle(surfaceId);
            const dv = memView();
            if (!surf) {
                dv.setUint32(outPtr + 8, 6, true);
                return;
            }
            const tex = surf.context.getCurrentTexture();
            const texHandle = allocHandle({ kind: "texture", texture: tex });
            dv.setUint32(outPtr + 4, texHandle, true);
            dv.setUint32(outPtr + 8, 1, true); // SuccessOptimal
        },
        wgpuSurfacePresent: () => 1,
        wgpuSurfaceUnconfigure(surfaceId) {
            getHandle(surfaceId)?.context?.unconfigure?.();
        },
        wgpuSurfaceRelease: releaseHandle,
        wgpuDeviceCreateShaderModule(deviceId, descPtr) {
            const dev = getHandle(deviceId)?.device;
            if (!dev) return 0;
            const dv = memView();
            const chainPtr = dv.getUint32(descPtr, true);
            const wgslCode = chainPtr ? readStringView(chainPtr + 8) : "";
            const module = dev.createShaderModule({ code: wgslCode });
            return allocHandle({ kind: "shader", module });
        },
        wgpuShaderModuleRelease: releaseHandle,
        wgpuDeviceCreateBuffer(deviceId, descPtr) {
            const dev = getHandle(deviceId)?.device;
            if (!dev) return 0;
            const dv = memView();
            // WGPUBufferDescriptor (sizeof = 40, align = 8 on wasm32):
            // nextInChain: +0, label: +4..+12, (pad), usage: +16 (u64), size: +24 (u64), mappedAtCreation: +32
            const usage = Number(dv.getBigUint64(descPtr + 16, true));
            const size = Number(dv.getBigUint64(descPtr + 24, true));
            const mappedAtCreation = dv.getUint32(descPtr + 32, true) !== 0;
            const buffer = dev.createBuffer({ size, usage, mappedAtCreation });
            return allocHandle({ kind: "buffer", buffer, mappedPtr: 0, mappedSize: 0 });
        },
        wgpuBufferDestroy(bufId) {
            getHandle(bufId)?.buffer?.destroy?.();
        },
        wgpuBufferMapAsync(bufId, mode, offset, size, callbackInfoPtr) {
            const entry = getHandle(bufId);
            const dv = memView();
            const callbackIdx = dv.getUint32(callbackInfoPtr + 8, true);
            const u1 = dv.getUint32(callbackInfoPtr + 12, true);
            const u2 = dv.getUint32(callbackInfoPtr + 16, true);
            const invokeMapCb = (status) => {
                if (typeof wasmExports.cwebgpu_wasm_invoke_buffer_map_cb === "function") {
                    wasmExports.cwebgpu_wasm_invoke_buffer_map_cb(callbackIdx, status, u1, u2);
                } else {
                    invokeIndirectCallback(callbackIdx, status, getZeroStringViewPtr(), u1, u2);
                }
            };
            if (!entry) {
                invokeMapCb(3);
                return 1n;
            }
            entry.buffer
                .mapAsync(Number(mode), offset >>> 0, size >>> 0)
                .then(() => invokeMapCb(1))
                .catch(() => invokeMapCb(3));
            return 1n;
        },
        wgpuBufferGetConstMappedRange(bufId, offset, size) {
            const entry = getHandle(bufId);
            if (!entry || !wasmExports.gpui_web_alloc) return 0;
            const ab = entry.buffer.getMappedRange(offset >>> 0, size >>> 0);
            const ptr = wasmExports.gpui_web_alloc(ab.byteLength);
            memU8().set(new Uint8Array(ab), ptr);
            entry.mappedPtr = ptr;
            entry.mappedSize = ab.byteLength;
            return ptr;
        },
        wgpuBufferGetMappedRange(bufId, offset, size) {
            return wgpu.wgpuBufferGetConstMappedRange(bufId, offset, size);
        },
        wgpuBufferUnmap(bufId) {
            const entry = getHandle(bufId);
            if (!entry) return;
            if (entry.mappedPtr && entry.mappedSize) {
                wasmExports.gpui_web_free?.(entry.mappedPtr, entry.mappedSize);
                entry.mappedPtr = 0;
                entry.mappedSize = 0;
            }
            entry.buffer.unmap();
        },
        wgpuBufferRelease: releaseHandle,
        wgpuDeviceCreateTexture(deviceId, descPtr) {
            const dev = getHandle(deviceId)?.device;
            if (!dev) return 0;
            const dv = memView();
            // WGPUTextureDescriptor (sizeof = 64, align = 8 on wasm32):
            // nextInChain: +0, label: +4..+12, (pad), usage: +16 (u64), dimension: +24,
            // size: +28..+40 (width: +28, height: +32, depthOrArrayLayers: +36),
            // format: +40, mipLevelCount: +44, sampleCount: +48
            const usage = Number(dv.getBigUint64(descPtr + 16, true));
            const dimensionEnum = dv.getUint32(descPtr + 24, true);
            const dimension = dimensionEnum === 1 ? "1d" : dimensionEnum === 3 ? "3d" : "2d";
            const width = dv.getUint32(descPtr + 28, true);
            const height = dv.getUint32(descPtr + 32, true);
            const depthOrArrayLayers = dv.getUint32(descPtr + 36, true) || 1;
            const formatEnum = dv.getUint32(descPtr + 40, true);
            const mipLevelCount = dv.getUint32(descPtr + 44, true) || 1;
            const sampleCount = dv.getUint32(descPtr + 48, true) || 1;
            const texture = dev.createTexture({
                dimension,
                size: { width, height, depthOrArrayLayers },
                format: TEXTURE_FORMATS.get(formatEnum) ?? "bgra8unorm",
                usage,
                mipLevelCount,
                sampleCount,
            });
            return allocHandle({ kind: "texture", texture });
        },
        wgpuTextureCreateView(texId) {
            const tex = getHandle(texId)?.texture;
            if (!tex) return 0;
            return allocHandle({ kind: "view", view: tex.createView() });
        },
        wgpuTextureDestroy(texId) {
            getHandle(texId)?.texture?.destroy?.();
        },
        wgpuTextureRelease: releaseHandle,
        wgpuTextureViewRelease: releaseHandle,
        wgpuDeviceCreateSampler(deviceId, descPtr) {
            const dev = getHandle(deviceId)?.device;
            if (!dev) return 0;
            const dv = memView();
            const magFilter = FILTER_MODES.get(dv.getUint32(descPtr + 24, true)) ?? "linear";
            const minFilter = FILTER_MODES.get(dv.getUint32(descPtr + 28, true)) ?? "linear";
            const addressModeU = ADDRESS_MODES.get(dv.getUint32(descPtr + 12, true)) ?? "clamp-to-edge";
            const addressModeV = ADDRESS_MODES.get(dv.getUint32(descPtr + 16, true)) ?? "clamp-to-edge";
            return allocHandle({
                kind: "sampler",
                sampler: dev.createSampler({ magFilter, minFilter, addressModeU, addressModeV }),
            });
        },
        wgpuSamplerRelease: releaseHandle,
        wgpuDeviceCreateBindGroupLayout(deviceId, descPtr) {
            const dev = getHandle(deviceId)?.device;
            if (!dev) return 0;
            const dv = memView();
            const count = dv.getUint32(descPtr + 12, true);
            const entriesPtr = dv.getUint32(descPtr + 16, true);
            const entries = [];
            // WGPUBindGroupLayoutEntry (sizeof = 80, align = 8 on wasm32):
            // binding: +4, visibility: +8 (u64),
            // buffer: +16 (type: +20, hasDynamicOffset: +24, minBindingSize: +32),
            // sampler: +40 (type: +44),
            // texture: +48 (sampleType: +52, viewDimension: +56, multisampled: +60)
            const stride = 80;
            for (let i = 0; i < count; i++) {
                const base = entriesPtr + i * stride;
                const binding = dv.getUint32(base + 4, true);
                const visibility = Number(dv.getBigUint64(base + 8, true));
                const bufType = dv.getUint32(base + 20, true);
                const hasDynamicOffset = dv.getUint32(base + 24, true) !== 0;
                const minBindingSize = Number(dv.getBigUint64(base + 32, true));
                const sampType = dv.getUint32(base + 44, true);
                const texSampleType = dv.getUint32(base + 52, true);
                const texViewDim = dv.getUint32(base + 56, true);
                const texMultisampled = dv.getUint32(base + 60, true) !== 0;
                const entry = { binding, visibility };
                if (bufType !== 0 && bufType !== 1) {
                    const bufLayout = {
                        type: bufType === 2 ? "uniform" : bufType === 3 ? "storage" : "read-only-storage",
                        hasDynamicOffset,
                    };
                    if (minBindingSize > 0) bufLayout.minBindingSize = minBindingSize;
                    entry.buffer = bufLayout;
                } else if (sampType !== 0 && sampType !== 1) {
                    entry.sampler = {
                        type: sampType === 2 ? "filtering" : sampType === 4 ? "comparison" : "non-filtering",
                    };
                } else if (texSampleType !== 0 && texSampleType !== 1) {
                    const sampleTypeMap = {
                        2: "float",
                        3: "unfilterable-float",
                        4: "depth",
                        5: "sint",
                        6: "uint",
                    };
                    const viewDimMap = {
                        1: "1d",
                        2: "2d",
                        3: "2d-array",
                        4: "cube",
                        5: "cube-array",
                        6: "3d",
                    };
                    entry.texture = {
                        sampleType: sampleTypeMap[texSampleType] ?? "float",
                        viewDimension: viewDimMap[texViewDim] ?? "2d",
                        multisampled: texMultisampled,
                    };
                }
                entries.push(entry);
            }
            return allocHandle({ kind: "bgl", layout: dev.createBindGroupLayout({ entries }) });
        },
        wgpuBindGroupLayoutRelease: releaseHandle,
        wgpuDeviceCreateBindGroup(deviceId, descPtr) {
            const dev = getHandle(deviceId)?.device;
            if (!dev) return 0;
            const dv = memView();
            const layout = getHandle(dv.getUint32(descPtr + 12, true))?.layout;
            const count = dv.getUint32(descPtr + 16, true);
            const entriesPtr = dv.getUint32(descPtr + 20, true);
            const entries = [];
            const stride = 40;
            for (let i = 0; i < count; i++) {
                const base = entriesPtr + i * stride;
                const binding = dv.getUint32(base + 4, true);
                const bufId = dv.getUint32(base + 8, true);
                const offset = Number(dv.getBigUint64(base + 16, true));
                const size = Number(dv.getBigUint64(base + 24, true));
                const samplerId = dv.getUint32(base + 32, true);
                const viewId = dv.getUint32(base + 36, true);
                if (bufId) {
                    const buffer = getHandle(bufId)?.buffer;
                    const res = { buffer, offset };
                    if (size > 0 && size < 0xffffffffffff) res.size = size;
                    entries.push({ binding, resource: res });
                } else if (samplerId) {
                    entries.push({ binding, resource: getHandle(samplerId)?.sampler });
                } else if (viewId) {
                    entries.push({ binding, resource: getHandle(viewId)?.view });
                }
            }
            return allocHandle({ kind: "bg", group: dev.createBindGroup({ layout, entries }) });
        },
        wgpuBindGroupRelease: releaseHandle,
        wgpuDeviceCreatePipelineLayout(deviceId, descPtr) {
            const dev = getHandle(deviceId)?.device;
            if (!dev) return 0;
            const dv = memView();
            const count = dv.getUint32(descPtr + 12, true);
            const ptr = dv.getUint32(descPtr + 16, true);
            const bindGroupLayouts = [];
            for (let i = 0; i < count; i++) {
                bindGroupLayouts.push(getHandle(dv.getUint32(ptr + i * 4, true))?.layout);
            }
            return allocHandle({
                kind: "pl",
                layout: dev.createPipelineLayout({ bindGroupLayouts }),
            });
        },
        wgpuPipelineLayoutRelease: releaseHandle,
        wgpuDeviceCreateRenderPipeline(deviceId, descPtr) {
            const dev = getHandle(deviceId)?.device;
            if (!dev) return 0;
            const dv = memView();
            // WGPURenderPipelineDescriptor (sizeof = 96, align = 8 on wasm32):
            // layout: +12, vertex: +16 (module: +20, entryPoint: +24),
            // primitive: +48 (topology: +52, stripIndexFormat: +56),
            // depthStencil: +72, multisample: +76 (count: +80), fragment: +92
            const layout = getHandle(dv.getUint32(descPtr + 12, true))?.layout ?? "auto";
            const vertMod = getHandle(dv.getUint32(descPtr + 20, true))?.module;
            const vertEntry = readStringView(descPtr + 24);
            const topo = PRIMITIVE_TOPOLOGIES.get(dv.getUint32(descPtr + 52, true)) ?? "triangle-list";
            const stripIndexEnum = dv.getUint32(descPtr + 56, true);
            const primitive = { topology: topo };
            if (stripIndexEnum === 1) primitive.stripIndexFormat = "uint16";
            else if (stripIndexEnum === 2) primitive.stripIndexFormat = "uint32";
            const sampleCount = dv.getUint32(descPtr + 80, true) || 1;
            const fragPtr = dv.getUint32(descPtr + 92, true);
            let fragment = undefined;
            if (fragPtr) {
                const fragMod = getHandle(dv.getUint32(fragPtr + 4, true))?.module;
                const fragEntry = readStringView(fragPtr + 8);
                const targetCount = dv.getUint32(fragPtr + 24, true);
                const targetsPtr = dv.getUint32(fragPtr + 28, true);
                const targets = [];
                for (let i = 0; i < targetCount; i++) {
                    const tBase = targetsPtr + i * 24;
                    const fmt = TEXTURE_FORMATS.get(dv.getUint32(tBase + 4, true)) ?? "bgra8unorm";
                    const blendPtr = dv.getUint32(tBase + 8, true);
                    const writeMask = Number(dv.getBigUint64(tBase + 16, true));
                    const target = { format: fmt, writeMask };
                    if (blendPtr) {
                        target.blend = {
                            color: {
                                operation: BLEND_OPS.get(dv.getUint32(blendPtr, true)) ?? "add",
                                srcFactor: BLEND_FACTORS.get(dv.getUint32(blendPtr + 4, true)) ?? "one",
                                dstFactor: BLEND_FACTORS.get(dv.getUint32(blendPtr + 8, true)) ?? "zero",
                            },
                            alpha: {
                                operation: BLEND_OPS.get(dv.getUint32(blendPtr + 12, true)) ?? "add",
                                srcFactor: BLEND_FACTORS.get(dv.getUint32(blendPtr + 16, true)) ?? "one",
                                dstFactor: BLEND_FACTORS.get(dv.getUint32(blendPtr + 20, true)) ?? "zero",
                            },
                        };
                    }
                    targets.push(target);
                }
                fragment = { module: fragMod, entryPoint: fragEntry, targets };
            }
            const pipeline = dev.createRenderPipeline({
                layout,
                vertex: { module: vertMod, entryPoint: vertEntry },
                primitive,
                multisample: { count: sampleCount },
                fragment,
            });
            return allocHandle({ kind: "pipeline", pipeline });
        },
        wgpuRenderPipelineRelease: releaseHandle,
        wgpuDeviceCreateCommandEncoder(deviceId) {
            const dev = getHandle(deviceId)?.device;
            if (!dev) return 0;
            return allocHandle({ kind: "encoder", encoder: dev.createCommandEncoder() });
        },
        wgpuCommandEncoderBeginRenderPass(encId, descPtr) {
            const enc = getHandle(encId)?.encoder;
            if (!enc) return 0;
            const dv = memView();
            const count = dv.getUint32(descPtr + 12, true);
            const attPtr = dv.getUint32(descPtr + 16, true);
            const colorAttachments = [];
            for (let i = 0; i < count; i++) {
                const base = attPtr + i * 56;
                const view = getHandle(dv.getUint32(base + 4, true))?.view;
                const resolveId = dv.getUint32(base + 12, true);
                const loadOp = dv.getUint32(base + 16, true) === 2 ? "clear" : "load";
                const storeOp = dv.getUint32(base + 20, true) === 2 ? "discard" : "store";
                const r = dv.getFloat64(base + 24, true);
                const g = dv.getFloat64(base + 32, true);
                const b = dv.getFloat64(base + 40, true);
                const a = dv.getFloat64(base + 48, true);
                const att = { view, loadOp, storeOp, clearValue: { r, g, b, a } };
                if (resolveId) att.resolveTarget = getHandle(resolveId)?.view;
                colorAttachments.push(att);
            }
            return allocHandle({ kind: "pass", pass: enc.beginRenderPass({ colorAttachments }) });
        },
        wgpuCommandEncoderCopyTextureToBuffer(encId, srcPtr, dstPtr, sizePtr) {
            const enc = getHandle(encId)?.encoder;
            if (!enc) return;
            const dv = memView();
            const texture = getHandle(dv.getUint32(srcPtr, true))?.texture;
            const mipLevel = dv.getUint32(srcPtr + 4, true);
            const offset = Number(dv.getBigUint64(dstPtr, true));
            const bytesPerRow = dv.getUint32(dstPtr + 8, true);
            const rowsPerImage = dv.getUint32(dstPtr + 12, true);
            const buffer = getHandle(dv.getUint32(dstPtr + 16, true))?.buffer;
            const width = dv.getUint32(sizePtr, true);
            const height = dv.getUint32(sizePtr + 4, true);
            const depthOrArrayLayers = dv.getUint32(sizePtr + 8, true) || 1;
            enc.copyTextureToBuffer(
                { texture, mipLevel },
                { buffer, offset, bytesPerRow, rowsPerImage },
                { width, height, depthOrArrayLayers }
            );
        },
        wgpuCommandEncoderFinish(encId) {
            const enc = getHandle(encId)?.encoder;
            if (!enc) return 0;
            return allocHandle({ kind: "cmdbuf", cmd: enc.finish() });
        },
        wgpuCommandEncoderRelease: releaseHandle,
        wgpuCommandBufferRelease: releaseHandle,
        wgpuRenderPassEncoderSetPipeline(passId, pipeId) {
            const pass = getHandle(passId)?.pass;
            const pipe = getHandle(pipeId)?.pipeline;
            if (pass && pipe) pass.setPipeline(pipe);
        },
        wgpuRenderPassEncoderSetBindGroup(passId, index, bgId, dynCount, dynPtr) {
            const pass = getHandle(passId)?.pass;
            const group = getHandle(bgId)?.group;
            if (!pass || !group) return;
            if (dynCount > 0 && dynPtr) {
                const dv = memView();
                const offsets = [];
                for (let i = 0; i < dynCount; i++) {
                    offsets.push(dv.getUint32(dynPtr + i * 4, true));
                }
                pass.setBindGroup(index >>> 0, group, offsets);
            } else {
                pass.setBindGroup(index >>> 0, group);
            }
        },
        wgpuRenderPassEncoderSetViewport(passId, x, y, w, h, minD, maxD) {
            getHandle(passId)?.pass?.setViewport(x, y, w, h, minD, maxD);
        },
        wgpuRenderPassEncoderSetScissorRect(passId, x, y, w, h) {
            getHandle(passId)?.pass?.setScissorRect(x >>> 0, y >>> 0, w >>> 0, h >>> 0);
        },
        wgpuRenderPassEncoderDraw(passId, vCount, iCount, firstV, firstI) {
            getHandle(passId)?.pass?.draw(vCount >>> 0, iCount >>> 0, firstV >>> 0, firstI >>> 0);
        },
        wgpuRenderPassEncoderEnd(passId) {
            getHandle(passId)?.pass?.end();
        },
        wgpuRenderPassEncoderRelease: releaseHandle,
        wgpuQueueWriteBuffer(queueId, bufId, bufOffset, dataPtr, size) {
            const q = getHandle(queueId)?.queue;
            const buf = getHandle(bufId)?.buffer;
            if (!q || !buf) return;
            q.writeBuffer(buf, Number(bufOffset), wasmExports.memory.buffer, dataPtr >>> 0, size >>> 0);
        },
        wgpuQueueWriteTexture(queueId, dstPtr, dataPtr, dataSize, layoutPtr, sizePtr) {
            const q = getHandle(queueId)?.queue;
            if (!q) return;
            const dv = memView();
            const texture = getHandle(dv.getUint32(dstPtr, true))?.texture;
            const mipLevel = dv.getUint32(dstPtr + 4, true);
            const origin = {
                x: dv.getUint32(dstPtr + 8, true),
                y: dv.getUint32(dstPtr + 12, true),
                z: dv.getUint32(dstPtr + 16, true),
            };
            const offset = Number(dv.getBigUint64(layoutPtr, true));
            const bytesPerRow = dv.getUint32(layoutPtr + 8, true);
            const rowsPerImage = dv.getUint32(layoutPtr + 12, true);
            const width = dv.getUint32(sizePtr, true);
            const height = dv.getUint32(sizePtr + 4, true);
            const depthOrArrayLayers = dv.getUint32(sizePtr + 8, true) || 1;
            q.writeTexture(
                { texture, mipLevel, origin },
                memU8().subarray(dataPtr >>> 0, (dataPtr >>> 0) + (dataSize >>> 0)),
                { offset, bytesPerRow, rowsPerImage },
                { width, height, depthOrArrayLayers }
            );
        },
        wgpuQueueSubmit(queueId, count, cmdsPtr) {
            const q = getHandle(queueId)?.queue;
            if (!q) return;
            const dv = memView();
            const buffers = [];
            for (let i = 0; i < count; i++) {
                const cmd = getHandle(dv.getUint32(cmdsPtr + i * 4, true))?.cmd;
                if (cmd) buffers.push(cmd);
            }
            q.submit(buffers);
        },
        wgpuQueueRelease: releaseHandle,
    };

    const imports = {
        wasi_snapshot_preview1,
        gpui_web,
        wgpu,
    };

    const response = fetch(wasmUrl);
    const { instance } = WebAssembly.instantiateStreaming
        ? await WebAssembly.instantiateStreaming(response, imports)
        : await WebAssembly.instantiate(await (await response).arrayBuffer(), imports);

    wasmExports = instance.exports;
    options.onReady?.(instance);

    if (typeof wasmExports._initialize === "function") {
        wasmExports._initialize();
    } else if (typeof wasmExports._start === "function") {
        wasmExports._start();
    }

    return instance;
}
