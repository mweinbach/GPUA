// Ported from: crates/rune/src/tooling/headless.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Offscreen deterministic frame loop, timeline resolution and `--chrome` traffic-light checks.

#if !os(WASI)
import Foundation
#endif

/// Render targets contain sRGB-encoded premultiplied linear colour. PNG uses straight
/// colour, so unpremultiply in linear space, not in the encoded byte domain.
func straightAlpha(_ pixels: inout [UInt8]) {
    var i = 0
    while i + 3 < pixels.count {
        let alpha = Float(pixels[i + 3]) / 255.0
        if alpha == 0.0 {
            pixels[i] = 0
            pixels[i + 1] = 0
            pixels[i + 2] = 0
        } else if alpha < 1.0 {
            for c in 0..<3 {
                let lin = srgbDecode(Float(pixels[i + c]) / 255.0)
                let unpremul = min(max(lin / alpha, 0.0), 1.0)
                pixels[i + c] = UInt8(clamping: Int((srgbEncode(unpremul) * 255.0).rounded()))
            }
        }
        i += 4
    }
}

/// Runs `app` offscreen according to `args`.
public func headless<S>(_ app: App<S>, _ args: Args) {
    toolingStarted(tryHeadless(app, args))
}

func tryHeadless<S>(_ app: App<S>, _ args: Args) -> Result<Void, ToolingCliError> {
    if app.secondaryWindows.isEmpty && args.desktop == nil {
        if args.listWindows {
            print("main")
            return .success(())
        }
        if let winKey = args.window, winKey != "main" {
            toolingDie("no such window; this app has only 'main'")
        }
        let scale = args.scale ?? 2.0
        if let (pw, ph) = app.winOptions.physicalSize {
            app.spec.size = (Float(pw) / scale, Float(ph) / scale)
        }
        let transparent = app.winOptions.transparent
        headlessConfigured(app, args, transparent: transparent)
        return .success(())
    }
    let secondary = app.secondaryWindows
    app.secondaryWindows.removeAll()
    let scriptJson = toolingReadScript(args)
    let displays = toolingDesktop(args, scriptJson).publicDisplays()
    let accessory = app.accessoryFlag
    let main = WindowSpec.fromApp("main", app).boxed()
    return toolingHeadlessWindow([main] + secondary, displays: displays, args: args, options: RunOptions(accessory: accessory))
}

func headlessConfigured<S>(_ app: App<S>, _ args: Args, transparent: Bool) {
    #if !os(WASI)
    if let waitStr = ProcessInfo.processInfo.environment["RUNE_HEADLESS_WAIT"],
       let secs = Double(waitStr), secs > 0
    {
        Thread.sleep(forTimeInterval: secs)
    }
    #endif

    let chrome = app.chromeSpec
    let launched = RuneInstant.now()
    if args.listScenes {
        for (name, _) in app.spec.scenes {
            print(name)
        }
        return
    }

    interactionGateHeadless()
    let srgbBlend = app.srgbBlendFlag
    let fontSmoothing = app.fontSmoothingMode
    let onFocus = app.onFocusHook
    let onReopen = app.onReopenHook

    let source = toolingReadScript(args)
    let script = source.map(toolingLoadScript) ?? []
    let timeline: ToolingTimeline
    switch ToolingTimeline.of(args, script) {
    case .success(let tl): timeline = tl
    case .failure(let err): toolingDie(err.message)
    }

    let scale = args.scale ?? 2.0
    let size = args.size ?? app.spec.size
    let wp = UInt32(max(1.0, (size.0 * scale).rounded()))
    let hp = UInt32(max(1.0, (size.1 * scale).rounded()))

    let writer = ToolingWriter((wp, hp))
    if let videoPath = args.video {
        if case .failure(let err) = writer.video(videoPath, timeline.fps) {
            toolingDie(err.message)
        }
    }

    publishHeadlessRun(
        HeadlessRun(
            script: args.script,
            events: script.map { $0.publicEvent() },
            scale: scale,
            fps: timeline.fps,
            size: size,
            start: Double(timeline.startFrame) * timeline.dt,
            frames: timeline.frames,
            end: Double(timeline.lastFrame) * timeline.dt,
            desktop: nil
        )
    )

    let fitHeight = app.fitContentHeightFlag
    let appOptions = app.winOptions
    let tabVisitsControls = app.tabVisitsControlsFlag
    let playground = app.attachedPlayground
    app.attachedPlayground = nil

    let (spec, state, shared) = withSceneClock(SceneClock(now: 0.0, dt: 0.0)) {
        app.intoParts(scene: args.scene)
    }
    let shortcutsGuard = ShortcutGuard.attach(shared, wake: {}, headless: true, wayland: false)
    let menusGuard = MenuGuard.attach(shared, headless: true)
    let dark = args.theme != "light"
    let stateMs = launched.elapsedSeconds() * 1000.0

    var rt = toolingRuntimeFor(spec: spec, state: state, size: size, env: Env.new(dark, scale), waker: {})
    playgroundAttachHeadless(
        rt: &rt,
        playground: playground,
        spec: spec,
        cliPlayground: args.playground,
        cliVariant: args.variant,
        windowed: false
    )
    rt.hostSetTitlebarInset(appOptions.borderless ? 0.0 : chrome.titlebarInset())
    rt.transparent = transparent
    rt.srgbBlend = srgbBlend
    windowHostState(for: rt).fontSmoothing = fontSmoothing
    windowHostState(for: rt).tabVisitsControls = tabVisitsControls

    let limits = (appOptions.minSize ?? spec.minSize ?? (0.0, 0.0), appOptions.maxSize)
    windowHostState(for: rt).fitLimits = limits
    if fitHeight {
        windowHostState(for: rt).fitContentHeight = true
        _ = rt.hostFrame(0.0)
        windowHostState(for: rt).pendingWindowFrameRequest = nil
        windowHostState(for: rt).fitHeld = false
    }
    if args.tree != nil {
        toolingTraceState(for: rt).keyWarnings = []
    }
    let runtimeMs = launched.elapsedSeconds() * 1000.0

    let vDesktop = toolingDesktop(args, source)
    let opened = vDesktop.openAt(appOptions.position, size)
    rt.hostSetWindowOrigin(opened[0], opened[1])
    var placedRecord: ToolingJson? = nil

    let fps = timeline.fps
    let dt = timeline.dt
    let startFrame = timeline.startFrame
    let frames = timeline.frames
    let snapFrame = timeline.snapFrame
    let lastFrame = timeline.lastFrame

    let t0 = RuneInstant.now()
    let readback = ToolingReadback<ToolingShot>(width: wp, height: hp, depth: TOOLING_READBACK_DEPTH)
    let keycapOverlay: ToolingKeycapOverlay? = (args.keys != nil || args.pointer)
        ? {
            let ov = ToolingKeycapOverlay(size: size, scale: scale, keys: args.keys, theme: args.keysTheme, pointer: args.pointer)
            ov.setSrgbBlend(srgbBlend)
            return ov
        }()
        : nil
    let initMs = t0.elapsedSeconds() * 1000.0

    let trace: ToolingTrace? = args.trace.map { p in
        let tr = ToolingTrace.open(p, size, fps, scale)
        tr.all = args.traceAll
        return tr
    }
    if trace != nil {
        toolingTraceState(for: rt).enabled = true
    }
    rt.scene.storeMut().auditRetargets(trace != nil)

    var stripTiles: [[UInt8]] = []
    let cropsPx: [[UInt32]] = args.crops.map { c in
        c.map { UInt32(max(0.0, ($0 * scale).rounded())) }
    }
    let gap = UInt32((4.0 * scale).rounded())
    let wall = RuneInstant.now()
    var cpuMs: [Double] = []
    var nextEv = 0
    var lastDown: (Float, Float) = (0.0, 0.0)

    func takeRequests(_ rt: Runtime<S>) -> PlaceRequest? {
        shortcutsGuard.drain()
        menusGuard.drain()
        let requests = shared.takeAllRequests()
        for u in requests.updates {
            var tx = Tx()
            if toolingTraceState(for: rt).enabled { tx.traceCalls = TraceCalls() }
            if u(&rt.state, &tx) {
                rt.hostRecordTraceCalls(tx)
                rt.hostLatchTx(&tx)
            }
            menusGuard.drain()
        }
        if let pos = requests.position {
            let pts = vDesktop.toPoints(pos)
            rt.hostSetWindowOrigin(pts.0, pts.1)
        }
        return requests.place
    }

    var framesWritten = 0
    let hasVideo = writer.hasVideo
    var snapCrop: [UInt32]? = nil

    func deliver(_ shot: ToolingShot, _ rawPx: [UInt8]) {
        var px = rawPx
        if args.chromeOverlay, let lights = chrome.trafficLightRects() {
            toolingPaintTrafficLights(&px, wp, hp, scale, lights)
        }
        if shot.dump {
            if args.strip != nil {
                stripTiles.append(toolingTile(px, wp, hp, cropsPx, gap))
            }
            if let dir = args.out {
                let frameNum = shot.k - startFrame
                let numStr = String(repeating: "0", count: max(0, 4 - "\(frameNum)".count)) + "\(frameNum)"
                if case .failure(let err) = writer.png("\(dir)/frame_\(numStr).png", px) {
                    toolingDie(err.message)
                }
            }
        }
        if shot.snap, let snapPath = args.snap {
            if let r = snapCrop {
                let cropped = toolingCropRgba(px, wp, r)
                do {
                    try toolingWritePng(snapPath, r[2], r[3], cropped)
                } catch {
                    toolingDie("\(snapPath): \(error)")
                }
            } else if case .failure(let err) = writer.png(snapPath, px) {
                toolingDie(err.message)
            }
        }
        if shot.video {
            framesWritten += 1
            if case .failure(let err) = writer.frame(px) {
                toolingDie(err.message)
            }
        }
    }

    var earlyPlace: PlaceRequest? = nil
    var resizeFrom = rt.viewport
    var frameAnim: WindowFrameAnim? = nil
    var idle = true
    if let firstNonMark = script.first(where: { !$0.kind.isMark }), firstNonMark.t <= 1e-9 {
        earlyPlace = takeRequests(rt)
        _ = rt.hostFrame(0.0)
        rt.hostOpenPopupHeadless()
    }

    for k in 0...lastFrame {
        let realT = Double(k) * dt
        let frameStart = RuneInstant.now()
        while nextEv < script.count && script[nextEv].t <= realT + 1e-9 {
            let e = script[nextEv]
            nextEv += 1
            let xy: (Float, Float)
            switch e.pos {
            case .xy(let x, let y):
                xy = (x, y)
            case .key(let key):
                guard let center = rt.toolingFindElementCenter(key) else {
                    toolingDie("script: no element with key \(toolingEscapeJsonString(key))")
                }
                xy = center
            case .rel where e.kind.atPointer:
                xy = rt.hostPointer() ?? (0.0, 0.0)
            case .rel(let dx, let dy):
                xy = (lastDown.0 + dx, lastDown.1 + dy)
            }

            switch e.kind {
            case .mark:
                break
            case .focus(let focused):
                rt.hostWindowFocus(focused)
                if let onFocus {
                    var tx = Tx()
                    onFocus(&rt.state, focused, &tx)
                    rt.hostLatchTx(&tx)
                }
            case .reopen:
                if let onReopen {
                    rt.update { s, tx in
                        _ = onReopen(&s, true, &tx)
                    }
                }
            case .shortcut(let shortcut):
                do {
                    try shared.shortcutHub.fire(shortcut).get()
                    shortcutsGuard.drain()
                    rt.hostInvalidate()
                } catch {
                    toolingDie("script shortcut: \(error)")
                }
            case .menu(let item):
                do {
                    try fireMenuItem(shared, item).get()
                    menusGuard.drain()
                } catch {
                    toolingDie("script menu: \(error)")
                }
            case .popupMenu(let picked):
                do {
                    try rt.hostResolvePopup(picked).get()
                } catch {
                    toolingDie("script pop-up menu: \(error)")
                }
            case .fileDialog(let path):
                do {
                    try rt.hostResolveFileDialog(path).get()
                } catch {
                    toolingDie("script file dialog: \(error)")
                }
            case .move:
                _ = rt.hostPointerMove(xy.0, xy.1)
            case .down:
                lastDown = xy
                _ = rt.hostPointerDown(xy.0, xy.1, button: .primary)
            case .up:
                _ = rt.hostPointerUp(xy.0, xy.1, button: .primary)
            case .secondaryDown:
                lastDown = xy
                _ = rt.hostPointerDown(xy.0, xy.1, button: .secondary)
            case .secondaryUp:
                _ = rt.hostPointerUp(xy.0, xy.1, button: .secondary)
            case .key(let kev, let isRep):
                _ = rt.hostKey(kev, isRepeat: isRep)
            case .physical(let phys):
                rt.toolingDeliverPhysical(phys)
            case .paste(let content):
                rt.toolingDeliverPaste(content)
            case .wheel(let dx, let dy):
                toolingWheel(rt: rt, at: xy, dx: dx, dy: dy)
            case .fling(let vx, let vy):
                toolingFling(rt: rt, at: xy, vx: vx, vy: vy)
            case .files(let step):
                toolingFileInput(rt: rt, step: step, at: xy)
            case .resize(let dw, let dh):
                toolingStepResize(rt: rt, from: &resizeFrom, delta: (dw, dh), scale: scale)
            default:
                if e.kind.isDown { lastDown = xy }
                _ = toolingCanvasInput(rt: rt, kind: e.kind, at: xy)
            }

            if let ov = keycapOverlay {
                switch e.kind {
                case .key(let kev, _), .physicalKey(_, let kev, _):
                    ov.key(e.t, kev)
                case .shortcut(let chord):
                    ov.chord(e.t, chord)
                case .physical(.key(let keyCode, let mods, pressed: true, _)):
                    if case .success(let chord) = Shortcut.fromPhysicalKey(keyCode, mods) {
                        ov.chord(e.t, chord)
                    }
                case .down:
                    ov.press(e.t, xy.0, xy.1)
                default:
                    break
                }
            }
        }

        let requestedPlace = takeRequests(rt)
        let step = (k == 0) ? 0.0 : dt
        toolingTakeWindowFrame(rt: rt, anim: &frameAnim, start: realT, limits: limits)
        if !idle {
            toolingStepWindowFrame(rt: rt, anim: &frameAnim, now: realT, scale: scale)
        }
        let (instances, _, stats) = withBlend(rt.srgbBlend) {
            rt.hostFrame(step)
        }
        if windowHostState(for: rt).pendingWindowFrameRequest != nil {
            let shown = windowHostState(for: rt).fitHeld ? 0.0 : step
            toolingTakeWindowFrame(rt: rt, anim: &frameAnim, start: realT - shown, limits: limits)
        }
        idle = !stats.animating && frameAnim == nil
        rt.hostOpenPopupHeadless()

        if let place = shared.takePlaceRequest() ?? requestedPlace ?? earlyPlace {
            earlyPlace = nil
            let (dispId, frame) = vDesktop.place(place, size)
            rt.hostSetWindowOrigin(frame[0], frame[1])
            let rec: ToolingJson = .object([
                ("t", .number(realT)),
                ("display", .int(Int64(dispId))),
                ("frame", .array(frame.map { .number(Double($0)) })),
            ])
            print("rune-placed \(rec.serialized())")
            placedRecord = rec
        }

        let inRange = k >= startFrame && k < startFrame + frames
        let shot = ToolingShot(
            k: k,
            dump: inRange && (args.out != nil || args.strip != nil) && ((k - startFrame) % max(args.every, 1) == 0),
            video: inRange && hasVideo,
            snap: k == snapFrame && args.snap != nil
        )
        if shot.snap {
            snapCrop = toolingSnapRect(rt: rt, args: args, scale: scale, frameSize: (wp, hp))
        }
        let firstPixels = args.firstPixels && k == 0
        let wantPixels = shot.dump || shot.video || shot.snap || firstPixels

        if wantPixels {
            for (s, px) in readback.makeRoom() {
                deliver(s, px)
            }
            var rgba = toolingRasterizeInstances(
                instances: instances,
                atlas: rt.images,
                width: wp,
                height: hp,
                dark: dark,
                transparent: rt.transparent,
                srgbBlend: rt.srgbBlend
            )
            if let ov = keycapOverlay {
                let (ovInsts, ovAtlas) = ov.frame(realT, step, rt.hostBackdropDark() ?? dark)
                if !ovInsts.isEmpty {
                    toolingCompositeInstances(
                        into: &rgba,
                        instances: ovInsts,
                        atlas: ovAtlas,
                        width: wp,
                        height: hp,
                        srgbBlend: rt.srgbBlend
                    )
                }
            }
            if rt.transparent {
                straightAlpha(&rgba)
            }
            readback.copy(rgba, shot)
            readback.submitted()
        }

        let ms = frameStart.elapsedSeconds() * 1000.0
        cpuMs.append(ms)

        if let tr = trace {
            tr.frame(rt, realT * 1000.0, ms)
        }

        if firstPixels {
            let wait = RuneInstant.now()
            let done = readback.finish()
            let marker: ToolingJson = .object([
                ("headless_ms", .number(launched.elapsedSeconds() * 1000.0)),
                ("state_ms", .number(stateMs)),
                ("runtime_ms", .number(runtimeMs)),
                ("gpu_init_ms", .number(initMs)),
                ("frame_cpu_ms", .number(ms)),
                ("readback_ms", .number(wait.elapsedSeconds() * 1000.0)),
                ("pixel_bytes", .int(Int64(done.last?.1.count ?? 0))),
            ])
            print("rune-first-pixels \(marker.serialized())")
            for (s, px) in done { deliver(s, px) }
        } else if wantPixels {
            for (s, px) in readback.ready() { deliver(s, px) }
        }

        if k == snapFrame, args.chromeOverlay, let lights = chrome.trafficLightRects() {
            toolingReportTrafficLightOverlaps(rt, lights)
        }
        if k == snapFrame, let treePath = args.tree {
            var tree = toolingTreeJson(rt, realT)
            if let placed = placedRecord {
                tree["placed"] = placed
            }
            let text = tree.serialized(pretty: true)
            #if !os(WASI)
            do {
                let url = URL(fileURLWithPath: treePath)
                let dir = url.deletingLastPathComponent()
                if !dir.path.isEmpty {
                    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                }
                try text.write(to: url, atomically: false, encoding: .utf8)
            } catch {
                toolingDie("\(treePath): \(error)")
            }
            #endif
        }
    }

    for (s, px) in readback.finish() {
        deliver(s, px)
    }
    trace?.close()
    interactionFlush()

    switch writer.finish() {
    case .success(let maybeVideo):
        if let videoPath = maybeVideo {
            toolingStderr("rune: wrote \(videoPath) (\(framesWritten) frames at \(fps) fps)\n")
        }
    case .failure(let err):
        toolingDie(err.message)
    }

    if let stripPath = args.strip {
        toolingWriteStrip(stripPath, stripTiles, (wp, hp), cropsPx, gap, args.cols)
    }
    _ = wall
}

/// Takes the size handlers asked for a headless window, inside the limits the app set; its
/// viewport moves there on the virtual clock from `start`. Centring has nothing to centre on.
func toolingTakeWindowFrame<S>(
    rt: Runtime<S>,
    anim: inout WindowFrameAnim?,
    start: Double,
    limits: ((Float, Float), (Float, Float)?)
) {
    let hs = windowHostState(for: rt)
    hs.fitHeld = false
    guard let request = hs.pendingWindowFrameRequest else { return }
    hs.pendingWindowFrameRequest = nil
    guard let size = request.size else { return }
    let (w, h) = clampWindowSize(size, limits.0, limits.1)
    let from = [0.0, 0.0, rt.viewport.0, rt.viewport.1]
    anim = WindowFrameAnim.retarget(anim, request.spring, start, from, [0.0, 0.0, w, h])
}

/// Moves a headless window's viewport one frame along, before the frame lays out.
func toolingStepWindowFrame<S>(
    rt: Runtime<S>,
    anim: inout WindowFrameAnim?,
    now: Double,
    scale: Float
) {
    guard let moving = anim else { return }
    let snapped = snapWindowFrame(moving.sample(now).0, scale)
    rt.hostSetScale(scale)
    rt.hostSetViewport(snapped[2], snapped[3])
    if moving.done(now) {
        anim = nil
    }
}

// MARK: - Deterministic RGBA8 Software Rasterizer for Offscreen `Instance`s

func toolingRasterizeInstances(
    instances: [Instance],
    atlas: ImageAtlas,
    width: UInt32,
    height: UInt32,
    dark: Bool,
    transparent: Bool,
    srgbBlend: Bool
) -> [UInt8] {
    let w = Int(width)
    let h = Int(height)
    var rgba = [UInt8](repeating: 0, count: w * h * 4)
    if !transparent {
        let bg: Color = dark ? oklch(0.15, 0.0, 0.0) : .WHITE
        let r = UInt8(clamping: Int((srgbEncode(bg.r) * 255.0).rounded()))
        let g = UInt8(clamping: Int((srgbEncode(bg.g) * 255.0).rounded()))
        let b = UInt8(clamping: Int((srgbEncode(bg.b) * 255.0).rounded()))
        for p in 0..<(w * h) {
            let idx = p * 4
            rgba[idx] = r
            rgba[idx + 1] = g
            rgba[idx + 2] = b
            rgba[idx + 3] = 255
        }
    }
    toolingCompositeInstances(
        into: &rgba,
        instances: instances,
        atlas: atlas,
        width: width,
        height: height,
        srgbBlend: srgbBlend
    )
    return rgba
}

func toolingCompositeInstances(
    into rgba: inout [UInt8],
    instances: [Instance],
    atlas: ImageAtlas,
    width: UInt32,
    height: UInt32,
    srgbBlend: Bool
) {
    let w = Int(width)
    let h = Int(height)
    guard w > 0, h > 0 else { return }

    for inst in instances {
        guard inst.rect.count >= 4, inst.params.count >= 2 else { continue }
        let kind = inst.params[1]
        if kind == KIND_LAYER || kind == KIND_LAYER_END || kind == KIND_EFFECT {
            continue
        }
        let rx = inst.rect[0], ry = inst.rect[1], rw = inst.rect[2], rh = inst.rect[3]
        guard rw > 0.0, rh > 0.0 else { continue }

        let clipX0 = inst.clip.count >= 4 ? inst.clip[0] : -1e6
        let clipY0 = inst.clip.count >= 4 ? inst.clip[1] : -1e6
        let clipX1 = inst.clip.count >= 4 ? inst.clip[2] : 1e6
        let clipY1 = inst.clip.count >= 4 ? inst.clip[3] : 1e6

        let x0 = max(0, Int(max(rx, clipX0).rounded(.down)))
        let y0 = max(0, Int(max(ry, clipY0).rounded(.down)))
        let x1 = min(w, Int(min(rx + rw, clipX1).rounded(.up)))
        let y1 = min(h, Int(min(ry + rh, clipY1).rounded(.up)))
        guard x0 < x1, y0 < y1 else { continue }

        if kind == KIND_IMAGE {
            let pageIdx = Int(inst.params[0])
            guard pageIdx >= 0, pageIdx < atlas.pages.count, inst.uv.count >= 4 else { continue }
            let page = atlas.pages[pageIdx]
            let ux = inst.uv[0], uy = inst.uv[1], uw = max(inst.uv[2], 1.0), uh = max(inst.uv[3], 1.0)
            let opacity = inst.fill.count >= 4 ? min(max(inst.fill[3], 0.0), 1.0) : 1.0
            for py in y0..<y1 {
                let v = min(max(((Float(py) + 0.5) - ry) / rh, 0.0), 0.9999)
                let sy = min(max(Int(uy + v * uh), 0), Int(page.height) - 1)
                for px in x0..<x1 {
                    let u = min(max(((Float(px) + 0.5) - rx) / rw, 0.0), 0.9999)
                    let sx = min(max(Int(ux + u * uw), 0), Int(page.width) - 1)
                    let sIdx = (sy * Int(page.width) + sx) * 4
                    guard sIdx + 3 < page.data.count else { continue }
                    let sr = Float(page.data[sIdx]) / 255.0
                    let sg = Float(page.data[sIdx + 1]) / 255.0
                    let sb = Float(page.data[sIdx + 2]) / 255.0
                    let sa = (Float(page.data[sIdx + 3]) / 255.0) * opacity
                    toolingBlendPixel(&rgba, idx: (py * w + px) * 4, srgbR: sr, srgbG: sg, srgbB: sb, alpha: sa, srgbBlend: srgbBlend)
                }
            }
            continue
        }

        if kind == KIND_GLYPH {
            // Deterministic glyph ink bar inside the laid-out text box so text changes produce distinct pixels!
            guard inst.fill.count >= 4 else { continue }
            let alpha = min(max(inst.fill[3], 0.0), 1.0)
            guard alpha > 0.0 else { continue }
            let sr = srgbEncode(min(max(inst.fill[0], 0.0), 1.0))
            let sg = srgbEncode(min(max(inst.fill[1], 0.0), 1.0))
            let sb = srgbEncode(min(max(inst.fill[2], 0.0), 1.0))
            let hashBits = UInt32(max(0.0, inst.uv.first ?? 0.0))
            let gy0 = max(y0, Int((ry + rh * 0.25).rounded(.down)))
            let gy1 = min(y1, max(gy0 + 1, Int((ry + rh * 0.75).rounded(.up))))
            for py in gy0..<gy1 {
                for px in x0..<x1 {
                    let cell = ((px - x0) / 2 + (py - gy0)) & 7
                    if ((hashBits >> cell) & 1) == 0 || px == x0 {
                        toolingBlendPixel(&rgba, idx: (py * w + px) * 4, srgbR: sr, srgbG: sg, srgbB: sb, alpha: alpha, srgbBlend: srgbBlend)
                    }
                }
            }
            continue
        }

        // KIND_RECT / rounded rect with optional border
        let fillA = inst.fill.count >= 4 ? min(max(inst.fill[3], 0.0), 1.0) : 0.0
        let borderW = max(inst.params[0], 0.0)
        let borderA = (borderW > 0.0 && inst.border.count >= 4) ? min(max(inst.border[3], 0.0), 1.0) : 0.0
        guard fillA > 0.0 || borderA > 0.0 else { continue }

        let fillSR: Float
        let fillSG: Float
        let fillSB: Float
        if fillA > 1e-6 {
            let unpremulR = min(max(inst.fill[0] / fillA, 0.0), 1.0)
            let unpremulG = min(max(inst.fill[1] / fillA, 0.0), 1.0)
            let unpremulB = min(max(inst.fill[2] / fillA, 0.0), 1.0)
            fillSR = srgbBlend ? unpremulR : srgbEncode(unpremulR)
            fillSG = srgbBlend ? unpremulG : srgbEncode(unpremulG)
            fillSB = srgbBlend ? unpremulB : srgbEncode(unpremulB)
        } else {
            fillSR = 0
            fillSG = 0
            fillSB = 0
        }

        let borderSR: Float
        let borderSG: Float
        let borderSB: Float
        if borderA > 1e-6 {
            let unpremulR = min(max(inst.border[0] / borderA, 0.0), 1.0)
            let unpremulG = min(max(inst.border[1] / borderA, 0.0), 1.0)
            let unpremulB = min(max(inst.border[2] / borderA, 0.0), 1.0)
            borderSR = srgbBlend ? unpremulR : srgbEncode(unpremulR)
            borderSG = srgbBlend ? unpremulG : srgbEncode(unpremulG)
            borderSB = srgbBlend ? unpremulB : srgbEncode(unpremulB)
        } else {
            borderSR = 0
            borderSG = 0
            borderSB = 0
        }

        let rad = inst.radii.first.map { abs($0) } ?? 0.0
        let cx0 = rx + rad, cy0 = ry + rad
        let cx1 = rx + rw - rad, cy1 = ry + rh - rad

        for py in y0..<y1 {
            let fy = Float(py) + 0.5
            for px in x0..<x1 {
                let fx = Float(px) + 0.5
                var sdf: Float = -min(min(fx - rx, rx + rw - fx), min(fy - ry, ry + rh - fy))
                if rad > 0.0 {
                    let dx: Float = (fx < cx0) ? (cx0 - fx) : ((fx > cx1) ? (fx - cx1) : 0.0)
                    let dy: Float = (fy < cy0) ? (cy0 - fy) : ((fy > cy1) ? (fy - cy1) : 0.0)
                    if dx > 0.0 || dy > 0.0 {
                        sdf = (dx * dx + dy * dy).squareRoot() - rad
                    }
                }
                let cov = min(max(0.5 - sdf, 0.0), 1.0)
                guard cov > 0.0 else { continue }
                let dstIdx = (py * w + px) * 4
                if borderA > 0.0 && sdf >= -borderW {
                    toolingBlendPixel(&rgba, idx: dstIdx, srgbR: borderSR, srgbG: borderSG, srgbB: borderSB, alpha: borderA * cov, srgbBlend: srgbBlend)
                } else if fillA > 0.0 {
                    toolingBlendPixel(&rgba, idx: dstIdx, srgbR: fillSR, srgbG: fillSG, srgbB: fillSB, alpha: fillA * cov, srgbBlend: srgbBlend)
                }
            }
        }
    }
}

@inline(__always)
private func toolingBlendPixel(
    _ rgba: inout [UInt8],
    idx: Int,
    srgbR: Float,
    srgbG: Float,
    srgbB: Float,
    alpha: Float,
    srgbBlend: Bool
) {
    guard alpha > 0.0 else { return }
    if alpha >= 0.9999 {
        rgba[idx] = UInt8(clamping: Int((srgbR * 255.0).rounded()))
        rgba[idx + 1] = UInt8(clamping: Int((srgbG * 255.0).rounded()))
        rgba[idx + 2] = UInt8(clamping: Int((srgbB * 255.0).rounded()))
        rgba[idx + 3] = 255
        return
    }
    let dstA = Float(rgba[idx + 3]) / 255.0
    let outA = alpha + dstA * (1.0 - alpha)
    guard outA > 1e-6 else { return }
    if srgbBlend {
        let dr = Float(rgba[idx]) / 255.0
        let dg = Float(rgba[idx + 1]) / 255.0
        let db = Float(rgba[idx + 2]) / 255.0
        let or = (srgbR * alpha + dr * dstA * (1.0 - alpha)) / outA
        let og = (srgbG * alpha + dg * dstA * (1.0 - alpha)) / outA
        let ob = (srgbB * alpha + db * dstA * (1.0 - alpha)) / outA
        rgba[idx] = UInt8(clamping: Int((or * 255.0).rounded()))
        rgba[idx + 1] = UInt8(clamping: Int((og * 255.0).rounded()))
        rgba[idx + 2] = UInt8(clamping: Int((ob * 255.0).rounded()))
        rgba[idx + 3] = UInt8(clamping: Int((outA * 255.0).rounded()))
    } else {
        let sr = srgbDecode(srgbR), sg = srgbDecode(srgbG), sb = srgbDecode(srgbB)
        let dr = srgbDecode(Float(rgba[idx]) / 255.0)
        let dg = srgbDecode(Float(rgba[idx + 1]) / 255.0)
        let db = srgbDecode(Float(rgba[idx + 2]) / 255.0)
        let or = srgbEncode((sr * alpha + dr * dstA * (1.0 - alpha)) / outA)
        let og = srgbEncode((sg * alpha + dg * dstA * (1.0 - alpha)) / outA)
        let ob = srgbEncode((sb * alpha + db * dstA * (1.0 - alpha)) / outA)
        rgba[idx] = UInt8(clamping: Int((or * 255.0).rounded()))
        rgba[idx + 1] = UInt8(clamping: Int((og * 255.0).rounded()))
        rgba[idx + 2] = UInt8(clamping: Int((ob * 255.0).rounded()))
        rgba[idx + 3] = UInt8(clamping: Int((outA * 255.0).rounded()))
    }
}

// MARK: - Timeline & Traffic Light Overlay (`crates/rune/src/tooling/headless.rs:483-605`)

/// Which frames a headless run renders and dumps.
struct ToolingTimeline: Sendable, Equatable {
    var fps: Double
    var dt: Double
    var startFrame: Int
    /// Frames dumped from `startFrame` (0 when nothing is dumped).
    var frames: Int
    var snapFrame: Int
    var lastFrame: Int

    static func of(_ args: Args, _ script: [ToolingEv]) -> Result<ToolingTimeline, ToolingCliError> {
        func findMark(_ name: String) -> Double? {
            for e in script {
                if case .mark(let n) = e.kind, n == name {
                    return e.t
                }
            }
            return nil
        }

        func resolve(_ spec: String) -> Result<Double, ToolingCliError> {
            if let exact = findMark(spec) {
                return .success(exact)
            }
            let names: [String] = script.compactMap {
                if case .mark(let n) = $0.kind { return n }
                return nil
            }
            let known = names.isEmpty ? "none" : names.joined(separator: ", ")

            var idx = spec.startIndex
            if idx < spec.endIndex {
                idx = spec.index(after: idx)
            }
            while idx < spec.endIndex {
                let ch = spec[idx]
                if ch == "+" || ch == "-" {
                    let suffix = String(spec[idx...])
                    if let offset = Double(suffix), offset.isFinite {
                        let name = String(spec[..<idx])
                        if let base = findMark(name) {
                            return .success(max(base + offset, 0.0))
                        } else {
                            return .failure(ToolingCliError("no mark \(toolingEscapeJsonString(name)) in the script (marks: \(known))"))
                        }
                    }
                }
                idx = spec.index(after: idx)
            }

            if spec.contains("+") || spec.contains("-") {
                return .failure(ToolingCliError("invalid mark time \(toolingEscapeJsonString(spec)): expected an exact mark name or NAME+SECONDS/NAME-SECONDS (marks: \(known))"))
            } else {
                return .failure(ToolingCliError("no mark \(toolingEscapeJsonString(spec)) in the script (marks: \(known))"))
            }
        }

        let fps = max(args.fps, 1.0)
        let dt = 1.0 / fps

        let start: Double
        if let sm = args.startMark {
            switch resolve(sm) {
            case .success(let t): start = t
            case .failure(let err): return .failure(err)
            }
        } else {
            start = args.start
        }

        let at: Double?
        if let am = args.atMark {
            switch resolve(am) {
            case .success(let t): at = t
            case .failure(let err): return .failure(err)
            }
        } else {
            at = args.at
        }

        let startFrame = max(0, Int((start * fps).rounded()))
        let scriptEnd = script.last?.t ?? 0.0

        func until(_ t: Double) -> Int {
            let target = max(0, Int((t * fps).rounded()))
            return max(0, target - startFrame) + 1
        }
        func autoFrames() -> Int {
            until(findMark("end") ?? (scriptEnd + 1.0))
        }

        let frames: Int
        if let explicit = args.frames {
            frames = explicit
        } else {
            let hasSequenceOut = args.video != nil || args.out != nil
            switch (args.duration, hasSequenceOut) {
            case (.seconds(let d)?, _):
                frames = max(1, Int((d * fps).rounded()))
            case (.auto?, _), (nil, true):
                frames = autoFrames()
            case (nil, false):
                frames = 0
            }
        }

        let snapT: Double = at ?? {
            if frames > 0 {
                return Double(startFrame + frames - 1) * dt
            } else if script.isEmpty {
                return 0.0
            } else {
                return scriptEnd + 1.0
            }
        }()
        let snapFrame = max(0, Int((snapT * fps).rounded()))
        let lastFrame = max(snapFrame, startFrame + max(frames, 1) - 1)
        return .success(ToolingTimeline(
            fps: fps,
            dt: dt,
            startFrame: startFrame,
            frames: frames,
            snapFrame: snapFrame,
            lastFrame: lastFrame
        ))
    }
}

struct ToolingShot: Sendable, Equatable {
    var k: Int
    var dump: Bool
    var video: Bool
    var snap: Bool
}

/// Antialiased discs where macOS draws close, minimise and zoom, plus a hairline box 4 pt around them.
func toolingPaintTrafficLights(_ px: inout [UInt8], _ w: UInt32, _ h: UInt32, _ scale: Float, _ lights: [[Float]]) {
    let colors: [[Float]] = [[255.0, 95.0, 87.0], [254.0, 188.0, 46.0], [40.0, 200.0, 64.0]]
    func blend(_ x: Int, _ y: Int, _ c: [Float], _ a: Float) {
        guard x >= 0, y >= 0, x < Int(w), y < Int(h), a > 0.0 else { return }
        let idx = (y * Int(w) + x) * 4
        for k in 0..<3 {
            px[idx + k] = UInt8(clamping: Int((Float(px[idx + k]) * (1.0 - a) + c[k] * a).rounded()))
        }
    }
    for (r, c) in zip(lights, colors) where r.count >= 4 {
        let cx = (r[0] + r[2] / 2.0) * scale
        let cy = (r[1] + r[3] / 2.0) * scale
        let rad = (r[2] / 2.0) * scale
        let yMin = Int((cy - rad - 1.0).rounded(.down))
        let yMax = Int((cy + rad + 1.0).rounded(.up))
        let xMin = Int((cx - rad - 1.0).rounded(.down))
        let xMax = Int((cx + rad + 1.0).rounded(.up))
        for y in yMin...yMax {
            for x in xMin...xMax {
                let dx = Float(x) + 0.5 - cx
                let dy = Float(y) + 0.5 - cy
                let d = (dx * dx + dy * dy).squareRoot()
                blend(x, y, c, min(max(rad - d + 0.5, 0.0), 1.0))
            }
        }
    }
    guard lights.count >= 3 else { return }
    let m: Float = 4.0
    let x0 = Int(((lights[0][0] - m) * scale).rounded(. towardZero))
    let y0 = Int(((lights[0][1] - m) * scale).rounded(.towardZero))
    let x1 = Int(((lights[2][0] + lights[2][2] + m) * scale).rounded(.towardZero))
    let y1 = Int(((lights[2][1] + lights[2][3] + m) * scale).rounded(.towardZero))
    let cyan: [Float] = [0.0, 200.0, 255.0]
    if x0 <= x1 {
        for x in x0...x1 {
            blend(x, y0, cyan, 0.8)
            blend(x, y1, cyan, 0.8)
        }
    }
    if y0 <= y1 {
        for y in y0...y1 {
            blend(x0, y, cyan, 0.8)
            blend(x1, y, cyan, 0.8)
        }
    }
}

func toolingReportTrafficLightOverlaps<S>(_ rt: Runtime<S>, _ lights: [[Float]]) {
    guard lights.count >= 3 else { return }
    let m: Float = 4.0
    let zone = [lights[0][0] - m, lights[0][1] - m, lights[2][0] + lights[2][2] + m, lights[2][1] + lights[2][3] + m]
    var n = 0
    for e in rt.hostElements() {
        let drawn = e.text != nil || e.role == "icon" || e.role == "button" || e.role == "textbox"
        let v = e.visible
        guard v.count >= 4 else { continue }
        let x1 = v[0] + v[2]
        let y1 = v[1] + v[3]
        if drawn && e.opacity > 0.01 && v[2] > 0.0 && v[3] > 0.0
            && v[0] < zone[2] && x1 > zone[0] && v[1] < zone[3] && y1 > zone[1]
        {
            toolingStderr("rune: chrome: \(e.path) overlaps the traffic lights at \(v.map(toolingR2))\n")
            n += 1
        }
    }
    toolingStderr("rune: chrome: traffic lights at \(lights[0].map(toolingR2)), \(n) overlapping elements\n")
}
