// Ported from: crates/rune/src/render.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! The instanced uber-quad renderer, with lazy bounded group layers and offscreen readback.

#if !os(WASI)
import Foundation
#endif
import CWebGPU

public let KIND_RECT: Float = 0.0
public let KIND_SHADOW: Float = 1.0
public let KIND_GLYPH: Float = 2.0
public let KIND_INSET: Float = 3.0
public let KIND_GRADIENT: Float = 4.0
public let KIND_SEGMENT: Float = 5.0
public let KIND_TRIANGLE: Float = 6.0
public let KIND_IMAGE: Float = 7.0
public let KIND_LAYER: Float = 8.0
public let KIND_LAYER_END: Float = 9.0
public let KIND_DASHED: Float = 10.0
public let KIND_RADIAL: Float = 11.0
public let KIND_EFFECT: Float = 12.0
public let KIND_BACKDROP_BLUR: Float = 13.0

public let NO_CLIP: [Float] = [-1e6, -1e6, 1e6, 1e6]
public let OFFSCREEN_FORMAT: WGPUTextureFormat = WGPUTextureFormat_RGBA8UnormSrgb
let CONTINUOUS_K: Float = 1.528_664_8

/// How far a corner of radius `radius` reaches along each edge. Negative radii draw continuous corners.
func cornerExtent(_ radius: Float) -> Float {
    radius < 0.0 ? (-radius * CONTINUOUS_K) : radius
}

/// WGSL for clipping like Rune does: `sd_rounded`, `ramp`, and `clip_alpha(p, clip, fade)`.
public let CLIP_WGSL: String = """
// Shared clip maths: the uber shader and compositor shaders (`rune::render::CLIP_WGSL`) use these.
// `clip_alpha(p, clip, fade)` takes a window device-pixel position, an instance's `clip` and its
// `fade` words (`vec4<u32>`), and returns the coverage of its rectangular, soft-edged and rounded
// (circular or continuous) clip.

// Apple's continuous corner of radius r: its curve leaves each edge K·r from the corner, and
// from the point (K·r, K·r) inside the corner it lies K·r·g(u) away, u running -1..1 across
// the quarter turn (0 on the diagonal; within 0.32% of r). Each quadrant takes its own
// corner's whole curve, as Core Animation does when K·r passes half the shorter side.
const CONTINUOUS_K: f32 = 1.52866483;
fn sd_continuous(p: vec2<f32>, half: vec2<f32>, r: f32) -> f32 {
    let e = CONTINUOUS_K * r;
    let q = half - abs(p);
    let v = vec2<f32>(e) - q;
    if (v.x <= 0.0 || v.y <= 0.0) { return max(-q.x, -q.y); }
    let u = atan2(v.y, v.x) * (4.0 / 3.14159265) - 1.0;
    let u2 = u * u;
    return length(v) - e * (1.14602295 + u2 * (-0.37573161 + u2 * (0.30796609 - 0.07724354 * u2)));
}

fn sd_rounded(p: vec2<f32>, half: vec2<f32>, radii: vec4<f32>) -> f32 {
    // radii: top-left, top-right, bottom-right, bottom-left (y down). Negative is continuous.
    var r = radii.x;
    if (p.x > 0.0) {
        r = select(radii.y, radii.z, p.y > 0.0);
    } else {
        r = select(radii.x, radii.w, p.y > 0.0);
    }
    if (r < 0.0) { return sd_continuous(p, half, min(-r, min(half.x, half.y))); }
    r = min(r, min(half.x, half.y));
    let q = abs(p) - half + vec2<f32>(r);
    return min(max(q.x, q.y), 0.0) + length(max(q, vec2<f32>(0.0))) - r;
}

fn ramp(d: f32, fade: f32) -> f32 {
    if (fade <= 0.0) {
        return clamp(d + 0.5, 0.0, 1.0);
    }
    let x = clamp(d / fade, 0.0, 1.0);
    return x * x * (3.0 - 2.0 * x);
}

fn unpack_clip_radii(w: u32) -> vec4<f32> {
    if (w == 0u) { return vec4<f32>(0.0); }
    if ((w & 0x60000000u) != 0x60000000u) {
        return vec4<f32>(bitcast<f32>(w));
    }
    let step = select(0.5, 2.0, (w & 0x10000000u) != 0u);
    let sgn = select(1.0, -1.0, (w & 0x80000000u) != 0u);
    return vec4<f32>(
        f32(w & 0x7fu),
        f32((w >> 7u) & 0x7fu),
        f32((w >> 14u) & 0x7fu),
        f32((w >> 21u) & 0x7fu),
    ) * (step * sgn);
}

fn clip_alpha(p: vec2<f32>, c: vec4<f32>, packed: vec4<u32>) -> f32 {
    let f = vec4<f32>(unpack2x16float(packed.x), unpack2x16float(packed.y));
    let offset = unpack4x8unorm(packed.z);
    let hard = vec4<f32>(p - c.xy, c.zw - p);
    var alpha = 1.0;
    for (var edge = 0u; edge < 4u; edge++) {
        // Keep the original sub-pixel ramp exactly when its origin is the hard edge.
        var a = ramp(hard[edge], f[edge]);
        if offset[edge] >= 1.0 {
            a = ramp(hard[edge], 0.0);
        } else if offset[edge] > 0.0 {
            a = min(ramp(hard[edge], 0.0), ramp(hard[edge] + offset[edge] * f[edge], f[edge]));
        }
        alpha *= a;
    }
    if packed.w != 0u {
        let half = (c.zw - c.xy) * 0.5;
        alpha *= clamp(0.5 - sd_rounded(p - c.xy - half, half, unpack_clip_radii(packed.w)), 0.0, 1.0);
    }
    return alpha;
}

"""

let SHADER_WGSL: String = """
// One instanced "uber-quad": rounded rects with per-corner radius and border (kind 0), analytic
// Gaussian rounded-rect shadows (kind 1), glyph-atlas text (kind 2), inset shadows (kind 3),
// vertical-gradient rounded rects or borders (kind 4), stroke segments (kind 5) and filled
// triangles (kind 6) for vector shapes, RGBA images (kind 7), and premultiplied layer composites
// (kind 8), dashed borders (kind 10), and radial or angled linear gradients (kind 11).
// Scope-end records (kind 9) never reach this shader. Every ordinary instance carries a
// soft-edge clip. Output is premultiplied linear colour into an sRGB target (or sRGB into a
// non-sRGB target when `srgb_blend` is enabled).

struct Globals {
    viewport: vec2<f32>,
    pad: vec2<f32>,
    flags: vec4<f32>,
};

@group(0) @binding(0) var<uniform> g: Globals;
@group(0) @binding(1) var atlas: texture_2d<f32>;
@group(0) @binding(2) var images: texture_2d<f32>;
// Zero size selects the window viewport. Layer targets keep all geometry/clip coordinates
// absolute and change only the final projection, including GPU-spring translations.
@group(0) @binding(3) var<uniform> projection: vec4<f32>;

struct In {
    @builtin(vertex_index) vi: u32,
    @location(0) rect: vec4<f32>,
    @location(1) radii: vec4<f32>,
    @location(2) fill: vec4<f32>,
    @location(3) border: vec4<f32>,
    @location(4) params: vec4<f32>,
    @location(5) uv: vec4<f32>,
    @location(6) clip: vec4<f32>,
    @location(7) fade: vec4<u32>,
};

struct Out {
    @builtin(position) pos: vec4<f32>,
    @location(0) p: vec2<f32>,
    @location(1) @interpolate(flat) rect: vec4<f32>,
    @location(2) @interpolate(flat) radii: vec4<f32>,
    @location(3) @interpolate(flat) fill: vec4<f32>,
    @location(4) @interpolate(flat) border: vec4<f32>,
    @location(5) @interpolate(flat) params: vec4<f32>,
    @location(6) @interpolate(flat) uv: vec4<f32>,
    @location(7) @interpolate(flat) clip: vec4<f32>,
    @location(8) @interpolate(flat) fade: vec4<u32>,
};

// Layer composites use `vs` even with GPU springs: the layer's contents already sampled the
// retained instance tracks using their original absolute instance indices.
@vertex
fn vs(i: In) -> Out {
    return base_vs(i);
}

fn base_vs(i: In) -> Out {
    let corner = vec2<f32>(f32(i.vi & 1u), f32(i.vi >> 1u));
    let kind = i.params.y;
    var grow = 1.0 + i.params.z * 2.0;
    if (kind > 0.5 && kind < 1.5) {
        grow = i.params.z * 3.0 + 1.0;
    } else if (kind > 1.5 && kind < 2.5) {
        grow = 0.0;
    } else if (kind > 2.5 && kind < 3.5) {
        grow = 1.0;
    } else if (kind > 4.5 && kind < 9.5) {
        grow = 1.0;
    }
    var lo = i.rect.xy - vec2<f32>(grow);
    // Effect slots (kind 12) reserve their place in the stream and cover no pixels.
    let size = select(i.rect.zw + vec2<f32>(2.0 * grow), vec2<f32>(0.0), kind > 11.5);
    var hi = lo + size;
    // One band of a big shadow or border ring rasterizes only its window (runtime/bands.rs).
    // Neighbouring bands compute a shared edge the same way, so they meet without a seam.
    if (kind < 1.5 && i.uv.z < 0.0) {
        lo = max(lo, i.rect.xy + i.uv.xy);
        hi = max(min(hi, i.rect.xy + vec2<f32>(-i.uv.z, i.uv.w)), lo);
    }
    let p = select(lo, hi, corner > vec2<f32>(0.5));
    var screen = p;
    // Icon loops rotate the quad, not its atlas allocation. Local p still samples the glyph.
    if (kind > 1.5 && kind < 2.5 && i.params.x != 0.0) {
        let center = i.rect.xy + i.rect.zw * 0.5;
        let q = p - center;
        let c = cos(i.params.x);
        let s = sin(i.params.x);
        screen = center + vec2<f32>(c * q.x - s * q.y, s * q.x + c * q.y);
    }
    // A turned layer composite (`Instance::turned`): border.y radians about border.zw.
    if (kind > 7.5 && kind < 8.5 && i.border.y != 0.0) {
        let q = p - i.border.zw;
        let c = cos(i.border.y);
        let s = sin(i.border.y);
        screen = i.border.zw + vec2<f32>(c * q.x - s * q.y, s * q.x + c * q.y);
    }
    var o: Out;
    let size_px = select(g.viewport, projection.zw, projection.z > 0.0);
    let local = screen - projection.xy;
    o.pos = vec4<f32>(local.x / size_px.x * 2.0 - 1.0, 1.0 - local.y / size_px.y * 2.0, 0.0, 1.0);
    o.p = p;
    o.rect = i.rect;
    o.radii = i.radii;
    o.fill = i.fill;
    o.border = i.border;
    o.params = i.params;
    o.uv = i.uv;
    o.clip = i.clip;
    o.fade = i.fade;
    return o;
}

// Evan Wallace's analytic rounded-box shadow (as in GPUI): exact along x, 4 samples along y.
fn gaussian(x: f32, sigma: f32) -> f32 {
    return exp(-(x * x) / (2.0 * sigma * sigma)) / (sqrt(2.0 * 3.14159265) * sigma);
}

fn erf2(x: vec2<f32>) -> vec2<f32> {
    let s = sign(x);
    let a = abs(x);
    var r = 1.0 + (0.278393 + (0.230389 + 0.078108 * (a * a)) * a) * a;
    r = r * r;
    return s - s / (r * r);
}

fn shadow_x(x: f32, y: f32, sigma: f32, corner: f32, half: vec2<f32>) -> f32 {
    let delta = min(half.y - corner - abs(y), 0.0);
    let curved = half.x - corner + sqrt(max(0.0, corner * corner - delta * delta));
    let integral = 0.5 + 0.5 * erf2((x + vec2<f32>(-curved, curved)) * (sqrt(0.5) / sigma));
    return integral.y - integral.x;
}

// What `shadow` sums to well inside the box, where every row it samples is fully covered: the
// four midpoint weights of the ±3σ window, 3·(g(0.75) + g(2.25)) for a unit Gaussian g.
const SHADOW_INSIDE: f32 = 0.99863125;

fn shadow(p: vec2<f32>, half: vec2<f32>, sigma: f32, corner: f32) -> f32 {
    // A big panel's shadow is mostly interior, and its erf rows there cost a 5K frame
    // milliseconds. 6σ in, each row is within 1e-6 of fully covered.
    if (abs(p.x) <= half.x - 6.0 * sigma && abs(p.y) <= half.y - corner - 6.0 * sigma) {
        return SHADOW_INSIDE;
    }
    let lo = p.y - half.y;
    let hi = p.y + half.y;
    let start = clamp(-3.0 * sigma, lo, hi);
    let end = clamp(3.0 * sigma, lo, hi);
    let step = (end - start) / 4.0;
    var y = start + step * 0.5;
    var v = 0.0;
    for (var i = 0; i < 4; i = i + 1) {
        v = v + shadow_x(p.x, p.y - y, sigma, corner, half) * gaussian(y, sigma) * step;
        y = y + step;
    }
    return v;
}

// Coverage of a stroke segment from a to b, `hw` half width, round or butt caps. Strokes
// thinner than a pixel draw a pixel wide at proportionally lower coverage.
fn segment(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>, hw: f32, round: bool) -> f32 {
    let w = max(hw, 0.5);
    let weight = min(hw * 2.0, 1.0);
    let ab = b - a;
    let len = length(ab);
    let ap = p - a;
    var d: f32;
    if (len < 1e-4) {
        if (!round) {
            return 0.0;
        }
        d = length(ap) - w;
    } else {
        let dir = ab / len;
        let along = dot(ap, dir);
        if (round) {
            d = length(ap - dir * clamp(along, 0.0, len)) - w;
        } else {
            let across = abs(dir.x * ap.y - dir.y * ap.x);
            let q = vec2<f32>(abs(along - len * 0.5) - len * 0.5, across - w);
            d = min(max(q.x, q.y), 0.0) + length(max(q, vec2<f32>(0.0)));
        }
    }
    return clamp(0.5 - d, 0.0, 1.0) * weight;
}

// Signed distance from p to the edge a->b, positive on the side `c` lies on.
fn edge(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>, c: vec2<f32>) -> f32 {
    let e = b - a;
    let l = max(length(e), 1e-6);
    let n = vec2<f32>(-e.y, e.x) / l;
    let s = select(-1.0, 1.0, dot(c - a, n) >= 0.0);
    return dot(p - a, n) * s;
}

// Whether p is on c's side of the edge a-b, decided so that the two triangles sharing the edge
// compute the same value with opposite signs and exactly one of them owns every pixel: the
// endpoints are put in a fixed order and ties go to the positive side.
fn owns(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>, c: vec2<f32>) -> bool {
    let swap = a.x > b.x || (a.x == b.x && a.y > b.y);
    let lo = select(a, b, swap);
    let hi = select(b, a, swap);
    let e = hi - lo;
    let side = e.x * (c.y - lo.y) - e.y * (c.x - lo.x);
    let v = e.x * (p.y - lo.y) - e.y * (p.x - lo.x);
    if (side > 0.0) {
        return v >= 0.0;
    }
    return v < 0.0;
}

// Coverage across a polygon edge a->b. Only the edge itself is antialiased: past its ends
// (where a concave polygon's interior continues along the edge's line) the edge cuts hard, so
// the neighbouring triangle that owns those pixels is not shaded through.
fn soft(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>, c: vec2<f32>) -> f32 {
    let d = edge(p, a, b, c);
    let e = b - a;
    let t = dot(p - a, e) / max(dot(e, e), 1e-6);
    if (t < 0.0 || t > 1.0) {
        return select(0.0, 1.0, d >= 0.0);
    }
    return clamp(d + 0.5, 0.0, 1.0);
}

// Coverage of a filled triangle; `aa` marks the polygon-boundary edges, which are antialiased
// (bits 0, 1, 2 for a->b, b->c, c->a). Other edges are shared with a neighbouring triangle and
// cut hard, with exactly one of the two owning each pixel.
fn triangle(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>, c: vec2<f32>, aa: u32) -> f32 {
    var cov = 1.0;
    if ((aa & 1u) == 1u) {
        cov = cov * soft(p, a, b, c);
    } else if (!owns(p, a, b, c)) {
        return 0.0;
    }
    if ((aa & 2u) == 2u) {
        cov = cov * soft(p, b, c, a);
    } else if (!owns(p, b, c, a)) {
        return 0.0;
    }
    if ((aa & 4u) == 4u) {
        cov = cov * soft(p, c, a, b);
    } else if (!owns(p, c, a, b)) {
        return 0.0;
    }
    return cov;
}

fn srgb_encode(x: vec3<f32>) -> vec3<f32> {
    let v = clamp(x, vec3<f32>(0.0), vec3<f32>(1.0));
    return select(1.055 * pow(v, vec3<f32>(1.0 / 2.4)) - 0.055, v * 12.92, v <= vec3<f32>(0.0031308));
}

/// One image texel, premultiplied (the atlas holds straight alpha) so filtering doesn't darken edges.
fn image_texel(t: vec2<i32>, premultiplied: bool) -> vec4<f32> {
    let c = textureLoad(images, t, 0);
    if (g.flags.x > 0.5) {
        if (c.a <= 0.0) { return vec4<f32>(0.0); }
        let lin = select(c.rgb, c.rgb / c.a, premultiplied);
        return vec4<f32>(srgb_encode(lin) * c.a, c.a);
    }
    if premultiplied { return c; }
    return vec4<f32>(c.rgb * c.a, c.a);
}

// Arc length to the point nearest `p` (rect-local) on the centre line of a `bw`-wide ring inside
// the rounded rect, and the line's full length. It runs clockwise from where the top edge leaves
// the top-left corner; corners count along their arcs.
fn ring_arc(p: vec2<f32>, size: vec2<f32>, radii: vec4<f32>, bw: f32) -> vec2<f32> {
    let h = bw * 0.5;
    let half = size * 0.5;
    let rc = max(min(abs(radii), vec4<f32>(min(half.x, half.y))) - vec4<f32>(h), vec4<f32>(0.0));
    let e = rc + vec4<f32>(h);
    let arc = rc * 1.5707964;
    let s_tr = max(size.x - bw - rc.x - rc.y, 0.0);
    let s_right = s_tr + arc.y;
    let s_br = s_right + max(size.y - bw - rc.y - rc.z, 0.0);
    let s_bottom = s_br + arc.z;
    let s_bl = s_bottom + max(size.x - bw - rc.z - rc.w, 0.0);
    let s_left = s_bl + arc.w;
    let s_tl = s_left + max(size.y - bw - rc.w - rc.x, 0.0);
    let top = p.x - e.x;
    let right = s_right + p.y - e.y;
    let bottom = s_bottom + size.x - e.z - p.x;
    let left = s_left + size.y - e.w - p.y;
    var s: f32;
    if (p.x > half.x) {
        if (p.y > half.y) {
            let v = p - (size - vec2<f32>(e.z));
            if (v.x > 0.0 && v.y > 0.0) { s = s_br + atan2(v.y, v.x) * rc.z; }
            else { s = select(bottom, right, size.x - p.x < size.y - p.y); }
        } else {
            let v = p - vec2<f32>(size.x - e.y, e.y);
            if (v.x > 0.0 && v.y < 0.0) { s = s_tr + atan2(v.x, -v.y) * rc.y; }
            else { s = select(top, right, size.x - p.x < p.y); }
        }
    } else if (p.y > half.y) {
        let v = p - vec2<f32>(e.w, size.y - e.w);
        if (v.x < 0.0 && v.y > 0.0) { s = s_bl + atan2(-v.x, v.y) * rc.w; }
        else { s = select(bottom, left, p.x < size.y - p.y); }
    } else {
        let v = p - vec2<f32>(e.x);
        if (v.x < 0.0 && v.y < 0.0) { s = s_tl + atan2(-v.y, -v.x) * rc.x; }
        else { s = select(top, left, p.x < p.y); }
    }
    return vec2<f32>(s, s_tl + arc.x);
}

// Coverage of a dash pattern (dash, gap, phase) at arc length `s`. The period stretches or
// shrinks so a whole number of periods fills `total`, and the pattern meets itself at the seam.
fn dash_cov(s: f32, total: f32, d: vec3<f32>) -> f32 {
    let nominal = d.x + d.y;
    let k = max(total, 0.001) / (max(floor(total / nominal + 0.5), 1.0) * nominal);
    let period = nominal * k;
    let dash = d.x * k;
    let a = s + d.z * k - dash * 0.5;
    let m = a - period * floor(a / period + 0.5);
    return clamp(dash * 0.5 - abs(m) + 0.5, 0.0, 1.0);
}

// A texel of a layer `size` pixels across; transparent outside it.
fn layer_texel(t: vec2<i32>, size: vec2<f32>) -> vec4<f32> {
    if (any(t < vec2<i32>(0)) || any(t >= vec2<i32>(size))) { return vec4<f32>(0.0); }
    return textureLoad(images, t, 0);
}

@fragment
fn fs(i: Out) -> @location(0) vec4<f32> {
    if (i.params.y == 8.0) {
        // Filters consume unmasked source pixels. Decode the same packed clip as primitives
        // only here, on the completed layer, including the radius in word 3.
        let screen = i.pos.xy + projection.xy;
        var p = screen - i.rect.xy;
        var color: vec4<f32>;
        if (i.border.y != 0.0) {
            // Turned: sample the upright contents where this pixel turns back to, bilinearly,
            // with nothing outside the layer.
            let q = screen - i.border.zw;
            let c = cos(i.border.y);
            let s = sin(i.border.y);
            p = i.border.zw + vec2<f32>(c * q.x + s * q.y, c * q.y - s * q.x) - i.rect.xy;
            let local = p - vec2<f32>(0.5);
            let base = floor(local);
            let f = local - base;
            let t0 = vec2<i32>(base);
            color = mix(mix(layer_texel(t0, i.rect.zw), layer_texel(t0 + vec2<i32>(1, 0), i.rect.zw), f.x),
                        mix(layer_texel(t0 + vec2<i32>(0, 1), i.rect.zw), layer_texel(t0 + vec2<i32>(1, 1), i.rect.zw), f.x), f.y);
        } else if (any(p < vec2<f32>(0.0)) || any(p >= i.rect.zw)) {
            discard;
        } else if (i.uv.z > 0.0) {
            let local = p * i.uv.zw / i.rect.zw - vec2<f32>(0.5);
            let hi = vec2<i32>(i.uv.zw) - vec2<i32>(1);
            let base = floor(local);
            let f = local - base;
            let t0 = clamp(vec2<i32>(base), vec2<i32>(0), hi);
            let t1 = clamp(vec2<i32>(base) + vec2<i32>(1, 1), vec2<i32>(0), hi);
            color = mix(mix(textureLoad(images, t0, 0), textureLoad(images, vec2<i32>(t1.x, t0.y), 0), f.x),
                        mix(textureLoad(images, vec2<i32>(t0.x, t1.y), 0), textureLoad(images, t1, 0), f.x), f.y);
        } else {
            color = textureLoad(images, vec2<i32>(floor(p)), 0);
        }
        // Float intermediates accumulate One/One without saturation. Clamp before applying
        // this scope's opacity so nesting preserves plus-lighter's bounded coverage.
        return select(color, clamp(color, vec4(0.0), vec4(1.0)), i.params.x == 1.0) * i.fill.a
            * clip_alpha(i.pos.xy + projection.xy, i.clip, i.fade);
    }
    let kind = i.params.y;
    if (kind > 11.5) { discard; }
    let half = i.rect.zw * 0.5;
    let center = i.rect.xy + half;
    var col = vec4<f32>(0.0);
    var clip_p = i.p;
    if (kind < 0.5) {
        let d = sd_rounded(i.p - center, half, i.radii);
        let soft = max(i.params.z, 0.5);
        let cov = clamp(0.5 - d / (soft * 2.0), 0.0, 1.0);
        let bw = i.params.x;
        if (bw > 0.0) {
            let inner = clamp(0.5 - (d + bw) / (soft * 2.0), 0.0, 1.0);
            col = i.fill * inner + i.border * (cov - inner);
        } else {
            col = i.fill * cov;
        }
    } else if (kind < 1.5) {
        let sigma = max(i.params.z, 0.01);
        let corner = min(abs(i.radii.x), min(half.x, half.y));
        col = i.fill * shadow(i.p - center, half, sigma, corner);
        // A shadow under a native system material leaves its interior clear: `uv` holds the
        // hole relative to this rect and `radii.w` its corner radius.
        if (i.uv.z > 0.0) {
            let hole = i.uv.zw * 0.5;
            col = col * clamp(0.5 + sd_rounded(i.p - (i.rect.xy + i.uv.xy + hole), hole, vec4<f32>(i.radii.w)), 0.0, 1.0);
        }
    } else if (kind > 6.5) {
        let d = sd_rounded(i.p - center, half, i.radii);
        if (kind > 10.5) {
            // Radial (`uv.z > 0`) or angled linear (`uv.z == 0`) gradient stop segment from
            // `fill` at t0 (`params.x`) to `border` at t1 (`params.w`); `+ 2.0` marks an open
            // interior stop boundary so adjacent segments partition the quad without overlap.
            let soft = max(i.params.z, 0.5);
            let cov = clamp(0.5 - d / (soft * 2.0), 0.0, 1.0);
            let t0_raw = i.params.x;
            let t1_raw = i.params.w;
            let lower_open = t0_raw >= 1.5;
            let upper_open = t1_raw >= 1.5;
            let t0 = select(t0_raw, t0_raw - 2.0, lower_open);
            let t1 = select(t1_raw, t1_raw - 2.0, upper_open);
            var t: f32;
            if (i.uv.z > 0.0) {
                t = length((i.p - i.rect.xy - i.uv.xy) / i.uv.zw);
            } else {
                t = 0.5 + dot(i.p - center, i.uv.xy);
            }
            if ((lower_open && t < t0) || (upper_open && t >= t1)) {
                col = vec4<f32>(0.0);
            } else {
                let u = select(clamp((t - t0) / (t1 - t0), 0.0, 1.0), select(0.0, 1.0, t >= t0), t1 <= t0 + 1e-6);
                col = mix(i.fill, i.border, u) * cov;
            }
        } else if (kind > 9.5) {
            // Dashed border: kind 0's ring, colour running from `fill` (top) to `border`
            // (bottom), masked by the dash pattern in `uv.xyz` along the ring's centre line.
            let soft = max(i.params.z, 0.5);
            let bw = i.params.x;
            let ring = clamp(0.5 - d / (soft * 2.0), 0.0, 1.0) - clamp(0.5 - (d + bw) / (soft * 2.0), 0.0, 1.0);
            let t = clamp((i.p.y - i.rect.y) / max(i.rect.w, 1.0), 0.0, 1.0);
            // The pixel centre, not `p`: inside a tight corner s jumps across the diagonal, and
            // interpolation could put a pixel on that diagonal on the other side of it.
            let arc = ring_arc(i.pos.xy + projection.xy - i.rect.xy, i.rect.zw, i.radii, bw);
            col = mix(i.fill, i.border, t) * (ring * dash_cov(arc.x, arc.y, i.uv.xyz));
        } else {
            // Bilinear, clamped to the image's own texels so neighbours in the atlas never bleed.
            let local = (i.p - i.rect.xy) * i.uv.zw / i.rect.zw - vec2<f32>(0.5);
            let lo = vec2<i32>(i.uv.xy);
            let hi = lo + vec2<i32>(i.uv.zw) - vec2<i32>(1);
            let base = floor(local);
            let f = local - base;
            let t0 = clamp(lo + vec2<i32>(base), lo, hi);
            let t1 = clamp(lo + vec2<i32>(base) + vec2<i32>(1, 1), lo, hi);
            let premultiplied = i.params.z > 0.5;
            let c = mix(mix(image_texel(t0, premultiplied), image_texel(vec2<i32>(t1.x, t0.y), premultiplied), f.x),
                        mix(image_texel(vec2<i32>(t0.x, t1.y), premultiplied), image_texel(t1, premultiplied), f.x), f.y);
            col = c * (i.fill.a * clamp(0.5 - d, 0.0, 1.0));
        }
    } else if (kind > 4.5 && kind < 5.5) {
        col = i.fill * segment(i.pos.xy + projection.xy, i.radii.xy, i.radii.zw, i.params.x, i.params.z > 0.5);
    } else if (kind > 5.5 && kind < 6.5) {
        // The pixel centre itself, not `p`: `p` is interpolated over each triangle's own quad, so
        // neighbours would disagree in the last bits about who owns a pixel on a shared edge.
        col = i.fill * triangle(i.pos.xy + projection.xy, i.radii.xy, i.radii.zw, i.uv.xy, u32(i.params.x + 0.5));
    } else if (kind > 2.5) {
        let d = sd_rounded(i.p - center, half, i.radii);
        let cov = clamp(0.5 - d, 0.0, 1.0);
        if (kind < 3.5) {
            // Inset shadow: the element's shape minus a blurred copy of it shrunk by the spread
            // and moved by the offset.
            let spread = i.params.x;
            let ih = max(half - vec2<f32>(spread), vec2<f32>(0.0));
            let q = i.p - center - i.uv.xy;
            var lit: f32;
            if (i.params.z < 0.3) {
                lit = clamp(0.5 - sd_rounded(q, ih, sign(i.radii) * max(abs(i.radii) - vec4<f32>(spread), vec4<f32>(0.0))), 0.0, 1.0);
            } else {
                lit = shadow(q, ih, i.params.z, max(min(abs(i.radii.x) - spread, min(ih.x, ih.y)), 0.0));
            }
            col = i.fill * cov * (1.0 - clamp(lit, 0.0, 1.0));
        } else {
            // With a border width, kind 0 whose ring runs from `border` (top) to `uv` (bottom).
            let t = clamp((i.p.y - i.rect.y) / max(i.rect.w, 1.0), 0.0, 1.0);
            let soft = max(i.params.z, 0.5);
            let soft_cov = clamp(0.5 - d / (soft * 2.0), 0.0, 1.0);
            let bw = i.params.x;
            if (bw > 0.0) {
                let inner = clamp(0.5 - (d + bw) / (soft * 2.0), 0.0, 1.0);
                col = i.fill * inner + mix(i.border, i.uv, t) * (soft_cov - inner);
            } else {
                col = mix(i.fill, i.uv, t) * soft_cov;
            }
        }
    } else {
        // Interpolated screen coordinates can round below an integer texel
        // boundary. Fragment position is the rasterizer's exact pixel center.
        let screen = i.pos.xy + projection.xy;
        let rotated = i.params.x != 0.0;
        // A turned glyph clips on screen, where its quad is.
        if rotated { clip_p = screen; }
        var cov: f32;
        if i.uv.z > 0.0 || rotated {
            // Flying text keeps the original atlas footprint while its quad scales uniformly.
            // A turned icon samples at its unturned point, filtered: no texel lines up with a pixel.
            let p = select(screen, i.p, rotated);
            let span = select(i.rect.zw, i.uv.zw, i.uv.z > 0.0);
            let local = (p - i.rect.xy) * span / i.rect.zw - vec2<f32>(0.5);
            let uv = vec2<i32>(i.uv.xy + floor(local));
            let f = fract(local);
            cov = mix(mix(textureLoad(atlas, uv, 0).r, textureLoad(atlas, uv + vec2<i32>(1, 0), 0).r, f.x),
                      mix(textureLoad(atlas, uv + vec2<i32>(0, 1), 0).r, textureLoad(atlas, uv + vec2<i32>(1, 1), 0).r, f.x), f.y);
        } else {
            let texel = vec2<i32>(i.uv.xy + floor(screen - i.rect.xy));
            cov = textureLoad(atlas, texel, 0).r;
        }
        col = i.fill * pow(cov, i.params.w);
    }
    return col * clip_alpha(clip_p, i.clip, i.fade);
}

"""

public enum Blend: Sendable, Equatable, Hashable {
    case sourceOver
    case plusLighter

    public static let SourceOver: Blend = .sourceOver
    public static let PlusLighter: Blend = .plusLighter

    var metalStyle: MetalBlendStyle {
        switch self {
        case .sourceOver: return .premultipliedAlpha
        case .plusLighter: return .plusLighter
        }
    }
}

public struct LayerSpec: Sendable, Equatable {
    public var opacity: Float
    public var blend: Blend
    public var blur: Float
    public var clipRadius: Float

    public init(
        opacity: Float = 1.0,
        blend: Blend = .sourceOver,
        blur: Float = 0.0,
        clipRadius: Float = 0.0
    ) {
        self.opacity = opacity
        self.blend = blend
        self.blur = blur
        self.clipRadius = clipRadius
    }
}

/// Where a compositor is asked to draw an effect slot (`Renderer.drawRangeWith`).
public struct EffectSite {
    public let index: UInt32
    public let instance: Instance
    public let mark: UInt32
    public let data: [Float]
    public let scale: Float
    public let format: WGPUTextureFormat
    public let origin: [Float]
    public let size: [UInt32]
    public let inLayer: Bool
    public let srgbBlend: Bool
    public let backdrop: MetalView?

    public init(
        index: UInt32,
        instance: Instance,
        mark: UInt32,
        data: [Float],
        scale: Float,
        format: WGPUTextureFormat,
        origin: [Float],
        size: [UInt32],
        inLayer: Bool,
        srgbBlend: Bool,
        backdrop: MetalView?
    ) {
        self.index = index
        self.instance = instance
        self.mark = mark
        self.data = data
        self.scale = scale
        self.format = format
        self.origin = origin
        self.size = size
        self.inLayer = inLayer
        self.srgbBlend = srgbBlend
        self.backdrop = backdrop
    }
}

public enum EffectPhase {
    case backdrop(MetalCommandEncoder)
    case draw(MetalRenderPass)
}

public typealias EffectHook = (MetalRenderPass, EffectSite) -> Void
public typealias EffectBackdropHook = (EffectPhase, EffectSite) -> Void

/// One instance, in device pixels (8 × vec4 = 128 bytes).
public struct Instance: Sendable, Equatable {
    public var rect: [Float]
    public var radii: [Float]
    public var fill: [Float]
    public var border: [Float]
    /// border width, kind, shadow sigma, glyph coverage exponent
    public var params: [Float]
    public var uv: [Float]
    /// x0, y0, x1, y1
    public var clip: [Float]
    public var fade: [UInt32]

    public init(
        rect: [Float] = [0, 0, 0, 0],
        radii: [Float] = [0, 0, 0, 0],
        fill: [Float] = [0, 0, 0, 0],
        border: [Float] = [0, 0, 0, 0],
        params: [Float] = [0, 0, 0, 0],
        uv: [Float] = [0, 0, 0, 0],
        clip: [Float] = NO_CLIP,
        fade: [UInt32] = [0, 0, 0, 0]
    ) {
        self.rect = rect
        self.radii = radii
        self.fill = fill
        self.border = border
        self.params = params
        self.uv = uv
        self.clip = clip
        self.fade = fade
    }

    public static func zeroed() -> Instance {
        Instance(clip: [0, 0, 0, 0])
    }

    public mutating func roundClip(_ radius: Float) {
        roundClipCorners([radius, radius, radius, radius])
    }

    public mutating func roundClipCorners(_ radii: [Float]) {
        fade[3] = packClipRadii(clip, radii)
    }

    public static func beginLayer(_ bounds: [Float], _ clip: [Float], _ spec: LayerSpec) -> Instance {
        var inst = Instance(
            rect: bounds,
            radii: [0, 0, 0, 0],
            fill: [0.0, 0.0, 0.0, min(max(spec.opacity, 0.0), 1.0)],
            border: [0, 0, 0, 0],
            params: [
                spec.blend == .plusLighter ? 1.0 : 0.0,
                KIND_LAYER,
                layerBlurSigma(spec.blur),
                0.0,
            ],
            uv: [0, 0, 0, 0],
            clip: clip,
            fade: [0, 0, 0, 0]
        )
        inst.roundClip(spec.clipRadius)
        return inst
    }

    public static func beginCachedLayer(
        _ bounds: [Float],
        _ clip: [Float],
        _ node: UInt64,
        _ sig: UInt64,
        _ spec: LayerSpec = LayerSpec()
    ) -> Instance {
        var inst = beginLayer(bounds, clip, spec)
        inst.radii = packU64F32(node)
        inst.uv = packU64F32(sig)
        inst.params[3] = 1.0
        return inst
    }

    public func turned(_ angle: Float, _ pivot: [Float]) -> Instance {
        var copy = self
        copy.border = [0.0, angle, pivot[0], pivot[1]]
        return copy
    }

    public static func endLayer() -> Instance {
        Instance(params: [0.0, KIND_LAYER_END, 0.0, 0.0], clip: [0, 0, 0, 0])
    }
}

// Pure IEEE-754 f32 <-> f16 conversion so `packFade`/`unpackFade` work identically across arm64, x86_64, Android, and Wasm32.
@inline(__always)
func f32ToF16Bits(_ value: Float) -> UInt16 {
    let bits = value.bitPattern
    let sign = UInt16((bits >> 16) & 0x8000)
    let exp = Int((bits >> 23) & 0xff) - 127 + 15
    var mant = bits & 0x007f_ffff
    if exp <= 0 {
        if exp < -10 { return sign }
        mant |= 0x0080_0000
        let shift = UInt32(14 - exp)
        let roundBit: UInt32 = 1 << (shift - 1)
        let sticky = (mant & (roundBit - 1)) != 0
        var halfMant = UInt16(mant >> shift)
        if (mant & roundBit) != 0 && (sticky || (halfMant & 1) != 0) {
            halfMant &+= 1
        }
        return sign | halfMant
    } else if exp == 0xff - 127 + 15 {
        return mant == 0 ? (sign | 0x7c00) : (sign | 0x7e00)
    } else if exp > 30 {
        return sign | 0x7c00
    } else {
        let roundBit: UInt32 = 0x0000_1000
        let sticky = (mant & (roundBit - 1)) != 0
        var half = sign | UInt16(exp << 10) | UInt16(mant >> 13)
        if (mant & roundBit) != 0 && (sticky || (half & 1) != 0) {
            half &+= 1
        }
        return half
    }
}

@inline(__always)
func f16BitsToF32(_ half: UInt16) -> Float {
    let sign = UInt32(half & 0x8000) << 16
    let exp = UInt32((half >> 10) & 0x1f)
    let mant = UInt32(half & 0x03ff)
    if exp == 0 {
        if mant == 0 {
            return Float(bitPattern: sign)
        }
        var m = mant
        var e: Int32 = -14
        while (m & 0x0400) == 0 {
            m <<= 1
            e -= 1
        }
        m &= 0x03ff
        let fExp = UInt32(bitPattern: e + 127) << 23
        return Float(bitPattern: sign | fExp | (m << 13))
    } else if exp == 31 {
        return Float(bitPattern: sign | 0x7f80_0000 | (mant << 13))
    } else {
        let fExp = (exp + 127 - 15) << 23
        return Float(bitPattern: sign | fExp | (mant << 13))
    }
}

public func packFade(_ width: [Float], _ origin: [Float], _ clip: [Float]) -> [UInt32] {
    let halves = width.map { UInt32(f32ToF16Bits(min(max($0, 0.0), 65504.0))) }
    var offsets: UInt32 = 0
    for edge in 0..<4 {
        let distance = edge < 2 ? (clip[edge] - origin[edge]) : (origin[edge] - clip[edge])
        let offset: Float = width[edge] > 0.0 ? min(max(distance / width[edge], 0.0), 1.0) : 0.0
        offsets |= UInt32(offset * 255.0 + 0.5) << (edge * 8)
    }
    return [halves[0] | (halves[1] << 16), halves[2] | (halves[3] << 16), offsets, 0]
}

public func unpackFade(_ fade: [UInt32]) -> ([Float], [Float]) {
    let widths = (0..<4).map { e -> Float in
        let word = fade[e / 2]
        let bits = UInt16((word >> ((e % 2) * 16)) & 0xffff)
        return f16BitsToF32(bits)
    }
    let offsets = (0..<4).map { e -> Float in
        Float((fade[2] >> (e * 8)) & 0xff) / 255.0
    }
    return (widths, offsets)
}

public func packClipRadii(_ clip: [Float], _ radii: [Float]) -> UInt32 {
    let halfSide = max(min(clip[2] - clip[0], clip[3] - clip[1]) * 0.5, 0.0)
    let maxUniform = Float(bitPattern: 0x5fff_ffff)
    let clamped = radii.map { radius -> Float in
        let r = min(min(abs(radius), halfSide), maxUniform)
        return (radius < 0.0 && r > 0.0) ? -r : r
    }
    if clamped[0] == clamped[1] && clamped[1] == clamped[2] && clamped[2] == clamped[3] {
        return clamped[0] == 0.0 ? 0 : clamped[0].bitPattern
    }
    let continuous = clamped.contains(where: { $0 < 0.0 })
    let maxR = clamped.reduce(Float(0.0)) { max($0, abs($1)) }
    let coarse = maxR > 63.5
    let invStep: Float = coarse ? 0.5 : 2.0
    var bits: UInt32 = 0x6000_0000
        | (continuous ? 0x8000_0000 : 0)
        | (coarse ? 0x1000_0000 : 0)
    for (idx, r) in clamped.enumerated() {
        let q = UInt32(min(max((abs(r) * invStep).rounded(), 0.0), 127.0))
        bits |= q << (idx * 7)
    }
    return bits
}

public func unpackClipRadii(_ w: UInt32) -> [Float] {
    if w == 0 {
        return [0.0, 0.0, 0.0, 0.0]
    }
    if (w & 0x6000_0000) != 0x6000_0000 {
        let v = Float(bitPattern: w)
        return [v, v, v, v]
    }
    let step: Float = (w & 0x1000_0000) != 0 ? 2.0 : 0.5
    let sign: Float = (w & 0x8000_0000) != 0 ? -1.0 : 1.0
    return (0..<4).map { idx in
        let q = (w >> (idx * 7)) & 0x7f
        return q == 0 ? 0.0 : Float(q) * step * sign
    }
}

func effectMark(_ i: Instance) -> UInt32 {
    (UInt32(i.border[0]) & 0xffff) | ((UInt32(i.border[1]) & 0xffff) << 16)
}

func packU64F32(_ v: UInt64) -> [Float] {
    [
        Float(v & 0xffff),
        Float((v >> 16) & 0xffff),
        Float((v >> 32) & 0xffff),
        Float((v >> 48) & 0xffff),
    ]
}

func unpackU64F32(_ a: [Float]) -> UInt64 {
    (UInt64(a[0]) & 0xffff)
        | ((UInt64(a[1]) & 0xffff) << 16)
        | ((UInt64(a[2]) & 0xffff) << 32)
        | ((UInt64(a[3]) & 0xffff) << 48)
}

// MARK: - Gpu

public final class Gpu {
    public var device: WGPUDevice?
    public var queue: WGPUQueue?
    public let metalDevice: MetalDevice
    public let metalQueue: MetalQueue

    public init(device: WGPUDevice? = nil, queue: WGPUQueue? = nil) {
        self.device = device
        self.queue = queue
        let (md, mq) = metalGpu(timestampQuery: true)
        self.metalDevice = md
        self.metalQueue = mq
    }

    public init(metalDevice: MetalDevice, metalQueue: MetalQueue) {
        self.device = nil
        self.queue = nil
        self.metalDevice = metalDevice
        self.metalQueue = metalQueue
    }

    public static func headless() -> Gpu {
        Gpu()
    }
}

// MARK: - Renderer

enum BatchBind: Equatable {
    case image(Int)
    case glyph(Int)
}

enum FormatUtils {
    static func isSrgb(_ format: WGPUTextureFormat) -> Bool {
        format == WGPUTextureFormat_RGBA8UnormSrgb || format == WGPUTextureFormat_BGRA8UnormSrgb
    }
}

public final class Renderer {
    #if !os(WASI)
    var surfaces: SurfaceRenderer? = nil
    #endif
    var pipeline: MetalRenderPipeline
    public private(set) var format: WGPUTextureFormat
    let shader: MetalShaderModule
    let pipelineLayout: MetalPipelineLayout
    let vertexEntry: String
    var extra: [(WGPUTextureFormat, MetalRenderPipeline)] = []
    let bindGroup: MetalBindGroup
    let bindLayout: MetalBindGroupLayout
    let globals: MetalBuffer
    let atlas: MetalTexture
    var atlasPages: [(MetalTexture, MetalBindGroup)] = []
    var images: [(MetalTexture, MetalBindGroup)?] = []
    var imageBatches: [(Range<UInt32>, BatchBind)] = []
    var instancesBuffer: MetalBuffer
    var capacity: Int
    var count: UInt32 = 0
    var springsState: springs.Bindings? = nil
    var springInstances: Int = 0
    let layers = Layers()
    public var srgbBlendEnabled: Bool = false
    var effects: [(UInt32, Instance)] = []
    var backdrops: [Backdrop] = []
    var backdropBlur: BackdropBlur? = nil
    let uploads = Uploads()

    private static let projectionOffset: UInt64 = 256

    public convenience init() {
        let (md, _) = metalGpu(timestampQuery: false)
        self.init(md, OFFSCREEN_FORMAT)
    }

    public convenience init(_ device: MetalDevice, _ format: WGPUTextureFormat) {
        self.init(device: device, format: format, properties: nil)
    }

    public static func new(_ device: MetalDevice, _ format: WGPUTextureFormat) -> Renderer {
        Renderer(device, format)
    }

    public static func withSprings(
        _ device: MetalDevice,
        _ format: WGPUTextureFormat,
        _ nodes: [springs.Node],
        _ ids: [UInt32]
    ) -> Renderer {
        Renderer(device: device, format: format, properties: (nodes, ids))
    }

    private init(
        device: MetalDevice,
        format: WGPUTextureFormat,
        properties: ([springs.Node], [UInt32])?
    ) {
        let springShader: MetalShaderModule?
        if properties != nil {
            let src = CLIP_WGSL + "\n" + SHADER_WGSL + "\n" + springs.SHADER
            springShader = device.createShaderModule(label: "uber", wgsl: src)
        } else {
            springShader = nil
        }

        let bgl = device.createBindGroupLayout(label: "uber", entries: uberBindEntries())
        let globalsBuf = device.createBuffer(label: "globals", size: Int(Self.projectionOffset + 16))
        let glyphAtlas = Self.makeTexture(device, "glyph atlas", WGPUTextureFormat_R8Unorm, ATLAS_SIZE, ATLAS_SIZE)
        let standIn = Self.makeImageTexture(device, 1, 1)
        let bg = Self.makeBindGroup(device, bgl, globalsBuf, glyphAtlas, standIn, nil)

        let springLayout = properties != nil ? springs.Bindings.layout(device) : nil
        let layouts: [MetalBindGroupLayout] = springLayout != nil ? [bgl, springLayout!] : [bgl]
        let pl = device.createPipelineLayout(label: "uber", bindGroupLayouts: layouts)
        let vEntry = properties != nil ? "vs_springs" : "vs"

        let (compiledShader, compiledPipeline): (MetalShaderModule, MetalRenderPipeline)
        if let sShader = springShader {
            compiledShader = sShader
            compiledPipeline = Self.makePipeline(device, pl, sShader, format, vEntry, .sourceOver)
        } else {
            (compiledShader, compiledPipeline) = uberShaderAndPipeline(device, pl, format)
        }

        let initialCap = 256
        let instBuf = Self.makeInstanceBuffer(device, initialCap)
        if let (nodes, ids) = properties {
            self.springInstances = ids.count
            self.springsState = springs.Bindings(device: device, layout: springLayout!, nodes: nodes, ids: ids)
        } else {
            self.springInstances = 0
            self.springsState = nil
        }

        self.pipeline = compiledPipeline
        self.format = format
        self.shader = compiledShader
        self.pipelineLayout = pl
        self.vertexEntry = vEntry
        self.bindGroup = bg
        self.bindLayout = bgl
        self.globals = globalsBuf
        self.atlas = glyphAtlas
        self.instancesBuffer = instBuf
        self.capacity = initialCap
        self.srgbBlendEnabled = false
    }

    static func makePipeline(
        _ device: MetalDevice,
        _ layout: MetalPipelineLayout,
        _ shader: MetalShaderModule,
        _ format: WGPUTextureFormat,
        _ vertexEntry: String,
        _ blend: Blend
    ) -> MetalRenderPipeline {
        let desc = MetalRenderPipelineDescriptor(
            label: "uber",
            layout: layout,
            vertexModule: shader,
            vertexEntryPoint: vertexEntry,
            vertexBuffers: [uberVertexLayout()],
            fragmentModule: shader,
            fragmentEntryPoint: "fs",
            colorTargets: [MetalColorTargetState(format: format, blend: blend.metalStyle)],
            topology: uberPrimitive()
        )
        do {
            return try device.createRenderPipeline(desc)
        } catch {
            fatalError("Renderer.makePipeline failed: \(error)")
        }
    }

    static func makeImageTexture(_ device: MetalDevice, _ width: UInt32, _ height: UInt32) -> MetalTexture {
        makeTexture(device, "image atlas", WGPUTextureFormat_RGBA8UnormSrgb, width, height)
    }

    static func makeTexture(
        _ device: MetalDevice,
        _ label: String,
        _ format: WGPUTextureFormat,
        _ width: UInt32,
        _ height: UInt32
    ) -> MetalTexture {
        device.createTexture(
            label: label,
            format: format,
            width: width,
            height: height,
            usage: UInt32(WGPUTextureUsage_TextureBinding | WGPUTextureUsage_CopyDst)
        )
    }

    static func makeBindGroup(
        _ device: MetalDevice,
        _ layout: MetalBindGroupLayout,
        _ globals: MetalBuffer,
        _ atlas: MetalTexture,
        _ images: MetalTexture,
        _ target: MetalBuffer?
    ) -> MetalBindGroup {
        let atlasView = atlas.createView()
        let imageView = images.createView()
        let projBuf = target ?? globals
        let projOff: UInt64 = target != nil ? 0 : projectionOffset
        return device.createBindGroup(
            label: "uber",
            layout: layout,
            entries: [
                .buffer(binding: 0, globals, offset: 0, size: 32),
                .textureView(binding: 1, atlasView),
                .textureView(binding: 2, imageView),
                .buffer(binding: 3, projBuf, offset: projOff, size: 16),
            ]
        )
    }

    public func srgbBlend() -> Bool {
        srgbBlendEnabled
    }

    public func setSrgbBlend(_ enabled: Bool) {
        srgbBlendEnabled = enabled
        #if !os(WASI)
        surfaces?.setSrgbBlend(enabled)
        #endif
    }

    public func addFormat(_ device: MetalDevice, _ fmt: WGPUTextureFormat) {
        if fmt != format && !extra.contains(where: { $0.0 == fmt }) {
            let p = Self.makePipeline(device, pipelineLayout, shader, fmt, vertexEntry, .sourceOver)
            extra.append((fmt, p))
        }
        if layerStats().targets > 0 {
            addLayerFormat(device, fmt)
        }
        let vp = targetFrame(nil).1
        if !backdrops.isEmpty && vp[0] > 0 && vp[1] > 0 {
            ensureBackdrop(device, fmt, (vp[0], vp[1]))
        }
        #if !os(WASI)
        surfaces?.addFormat(device, fmt)
        #endif
    }

    public func setFormat(_ device: MetalDevice, _ nextFormat: WGPUTextureFormat) {
        if format == nextFormat { return }
        let nextPipe: MetalRenderPipeline
        if let idx = extra.firstIndex(where: { $0.0 == nextFormat }) {
            nextPipe = extra.remove(at: idx).1
        } else {
            nextPipe = Self.makePipeline(device, pipelineLayout, shader, nextFormat, vertexEntry, .sourceOver)
        }
        let oldPipe = pipeline
        pipeline = nextPipe
        extra.append((format, oldPipe))
        format = nextFormat
        srgbBlendEnabled = !FormatUtils.isSrgb(nextFormat)
        if layerStats().targets > 0 {
            addLayerFormat(device, nextFormat)
        }
        let vp = targetFrame(nil).1
        if !backdrops.isEmpty && vp[0] > 0 && vp[1] > 0 {
            ensureBackdrop(device, nextFormat, (vp[0], vp[1]))
        }
        #if !os(WASI)
        if let sr = surfaces {
            sr.setSrgbBlend(srgbBlendEnabled)
            sr.addFormat(device, nextFormat)
        }
        #endif
    }

    public func drawRange(_ pass: MetalRenderPass, _ fmt: WGPUTextureFormat, _ range: Range<UInt32>) {
        if range.isEmpty && range.upperBound != count { return }
        submitUploads()
        validateLayerRange(range)
        let active = ActivePass.borrowed(pass)
        drawLayerRange(active, fmt, range, nil) { _, _ in }
    }

    public func drawRangeWith(
        _ pass: MetalRenderPass,
        _ fmt: WGPUTextureFormat,
        _ range: Range<UInt32>,
        _ hook: @escaping EffectHook
    ) {
        if range.isEmpty && range.upperBound != count { return }
        submitUploads()
        validateLayerRange(range)
        let active = ActivePass.borrowed(pass)
        drawLayerRange(active, fmt, range, nil) { phase, site in
            if case .draw(let p) = phase {
                hook(p, site)
            }
        }
    }

    public func drawWith(
        _ encoder: MetalCommandEncoder,
        _ view: MetalView,
        _ clear: [Float],
        _ hook: @escaping EffectHook
    ) {
        drawWithBackdrop(encoder, view, clear) { phase, site in
            if case .draw(let p) = phase {
                hook(p, site)
            }
        }
    }

    public func drawWithBackdrop(
        _ encoder: MetalCommandEncoder,
        _ view: MetalView,
        _ clear: [Float],
        _ hook: EffectBackdropHook
    ) {
        encodeLayersWithBackdrop(encoder, hook)
        let load = MetalLoadOp.clear(r: Double(clear[0]), g: Double(clear[1]), b: Double(clear[2]), a: Double(clear[3]))
        drawTargetRangeWith(encoder, view, format, load, 0..<count, hook)
    }

    public func drawTargetRangeWith(
        _ encoder: MetalCommandEncoder,
        _ view: MetalView,
        _ fmt: WGPUTextureFormat,
        _ load: MetalLoadOp,
        _ range: Range<UInt32>,
        _ hook: EffectBackdropHook
    ) {
        if range.isEmpty && range.upperBound != count { return }
        validateLayerRange(range)
        flushUploads(encoder)
        let pass = encoder.beginRenderPass(
            label: "frame",
            colorAttachment: MetalRenderPassColorAttachment(view: view, loadOp: load, storeOp: .store)
        )
        let vp = targetFrame(nil).1
        if vp[0] > 0 && vp[1] > 0 {
            pass.setViewport(x: 0, y: 0, width: Float(vp[0]), height: Float(vp[1]))
        }
        let active = ActivePass.owned(pass, encoder, view)
        drawLayerRange(active, fmt, range, nil, hook)
        active.endIfOwned()
    }

    func drawWithEffects(
        _ activePass: ActivePass,
        _ fmt: WGPUTextureFormat,
        _ range: Range<UInt32>,
        _ target: Int?,
        _ hook: EffectBackdropHook
    ) {
        var first = 0
        while first < effects.count && effects[first].0 < range.lowerBound {
            first += 1
        }
        var cursor = range.lowerBound
        for idx in first..<effects.count {
            let (at, instance) = effects[idx]
            if at >= range.upperBound { break }
            drawInstances(activePass.pass, fmt, cursor..<(at + 1), target)
            cursor = at + 1
            if instance.params[1] == KIND_BACKDROP_BLUR {
                drawBackdropBlur(activePass, fmt, at, instance, target)
                continue
            }
            let (origin, size) = targetFrame(target)
            let c = instance.clip
            func edge(_ v: Float, _ o: Float, _ maxVal: UInt32) -> UInt32 {
                UInt32(min(max(v - o, 0.0), Float(maxVal)))
            }
            let x0 = edge(c[0].rounded(.down), origin[0], size[0])
            let y0 = edge(c[1].rounded(.down), origin[1], size[1])
            let x1 = edge(c[2].rounded(.up), origin[0], size[0])
            let y1 = edge(c[3].rounded(.up), origin[1], size[1])
            if x1 <= x0 || y1 <= y0 { continue }

            let backdropView: MetalView?
            if instance.params[0] != 0.0 {
                backdropView = activePass.splitForBackdrop(self, at, instance, fmt, origin, size, target != nil, hook)
            } else {
                backdropView = nil
            }
            activePass.pass.setScissorRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
            let site = EffectSite(
                index: at,
                instance: instance,
                mark: effectMark(instance),
                data: instance.uv,
                scale: instance.params[3],
                format: fmt,
                origin: origin,
                size: size,
                inLayer: target != nil,
                srgbBlend: srgbBlendEnabled,
                backdrop: backdropView
            )
            hook(.draw(activePass.pass), site)
            if size[0] > 0 && size[1] > 0 {
                activePass.pass.setViewport(x: 0, y: 0, width: Float(size[0]), height: Float(size[1]))
            }
            activePass.setScissor(activePass.scissor, size)
        }
        drawInstances(activePass.pass, fmt, cursor..<range.upperBound, target)
    }

    private func drawInstances(
        _ pass: MetalRenderPass,
        _ fmt: WGPUTextureFormat,
        _ range: Range<UInt32>,
        _ target: Int?
    ) {
        if range.isEmpty { return }
        let selectedPipeline: MetalRenderPipeline
        if layerBlend(target) == .plusLighter {
            selectedPipeline = layers.additive!.0
        } else if fmt == format {
            selectedPipeline = pipeline
        } else {
            guard let found = extra.first(where: { $0.0 == fmt })?.1 else {
                fatalError("Renderer.addFormat first")
            }
            selectedPipeline = found
        }
        pass.setPipeline(selectedPipeline)
        if let group = springsState?.group {
            pass.setBindGroup(1, group)
        }
        pass.setVertexBuffer(0, instancesBuffer)

        var start = 0
        while start < imageBatches.count && imageBatches[start].0.upperBound <= range.lowerBound {
            start += 1
        }
        for idx in start..<imageBatches.count {
            let (batch, bindKind) = imageBatches[idx]
            if batch.lowerBound >= range.upperBound { break }
            let bind: MetalBindGroup
            switch (bindKind, target) {
            case (.image(let page), .some(let tIdx)):
                let t = layers.targets[tIdx]!
                bind = (page < t.images.count ? t.images[page] : nil) ?? t.base
            case (.image(let page), .none):
                bind = (page < images.count ? images[page]?.1 : nil) ?? bindGroup
            case (.glyph(let page), .some(let tIdx)):
                let t = layers.targets[tIdx]!
                bind = (page < t.glyphs.count ? t.glyphs[page] : nil) ?? t.base
            case (.glyph(let page), .none):
                bind = (page < atlasPages.count ? atlasPages[page].1 : nil) ?? bindGroup
            }
            pass.setBindGroup(0, bind)
            let lo = max(batch.lowerBound, range.lowerBound)
            let hi = min(batch.upperBound, range.upperBound)
            if hi > lo {
                pass.draw(vertices: 0..<4, instances: lo..<hi)
            }
        }
    }

    @discardableResult
    public func submit(_ queue: MetalQueue, _ encoder: MetalCommandEncoder) -> UInt64 {
        beforeSubmit(encoder)
        #if !os(WASI)
        if let sr = surfaces {
            return sr.submit(queue, encoder)
        }
        #endif
        return queue.submit([encoder.finish()])
    }

    #if os(macOS)
    func submitsPlainly() -> Bool {
        surfaces?.drawsNothing() ?? true
    }
    #endif

    public func draw(_ encoder: MetalCommandEncoder, _ view: MetalView, _ clear: [Float]) {
        drawTimed(encoder, view, clear, nil)
    }

    public func springsAnimating(_ time: Double) -> Bool {
        springsState.map { time < $0.settleAt } ?? false
    }

    func drawOver(_ encoder: MetalCommandEncoder, _ view: MetalView) {
        drawLoad(encoder, view, .load, nil)
    }

    public func drawTimed(
        _ encoder: MetalCommandEncoder,
        _ view: MetalView,
        _ clear: [Float],
        _ timestamps: MetalPassTimestampWrites?
    ) {
        let load = MetalLoadOp.clear(r: Double(clear[0]), g: Double(clear[1]), b: Double(clear[2]), a: Double(clear[3]))
        drawLoad(encoder, view, load, timestamps)
    }

    private func drawLoad(
        _ encoder: MetalCommandEncoder,
        _ view: MetalView,
        _ load: MetalLoadOp,
        _ timestamps: MetalPassTimestampWrites?
    ) {
        #if !os(WASI)
        let resolvedTs = timestamps ?? surfaces?.timestampWrites()
        #else
        let resolvedTs = timestamps
        #endif
        let noop: EffectBackdropHook = { _, _ in }
        encodeLayersTimed(encoder, resolvedTs, noop)

        let frameTs: MetalPassTimestampWrites?
        if let t = resolvedTs {
            if layerStats().extraPasses > 0 {
                frameTs = MetalPassTimestampWrites(querySet: t.querySet, beginningIndex: nil, endIndex: t.endIndex)
            } else {
                frameTs = t
            }
        } else {
            frameTs = nil
        }

        let blurs = hasBackdropBlur()
        let pass = encoder.beginRenderPass(
            label: "frame",
            colorAttachment: MetalRenderPassColorAttachment(view: view, loadOp: load, storeOp: .store),
            timestampWrites: frameTs
        )
        let vp = targetFrame(nil).1
        if vp[0] > 0 && vp[1] > 0 {
            pass.setViewport(x: 0, y: 0, width: Float(vp[0]), height: Float(vp[1]))
        }
        if !blurs {
            drawRange(pass, format, 0..<count)
            pass.end()
            return
        }
        let active = ActivePass.owned(pass, encoder, view).withTimestamps(frameTs)
        drawLayerRange(active, format, 0..<count, nil, noop)
        active.endIfOwned()
    }
}

// MARK: - Offscreen

public final class Offscreen {
    public let texture: MetalTexture
    public let view: MetalView
    public let buffer: MetalBuffer
    public let width: UInt32
    public let height: UInt32
    public let paddedRow: UInt32
    public var pixels: [UInt8]

    public convenience init(width: UInt32, height: UInt32) {
        let (md, _) = metalGpu(timestampQuery: false)
        self.init(md, width, height)
    }

    public convenience init(_ device: MetalDevice, _ width: UInt32, _ height: UInt32) {
        self.init(device, width, height, OFFSCREEN_FORMAT)
    }

    public init(_ device: MetalDevice, _ width: UInt32, _ height: UInt32, _ format: WGPUTextureFormat) {
        let w = max(width, 1)
        let h = max(height, 1)
        self.width = w
        self.height = h
        let tex = device.createTexture(
            label: "offscreen",
            format: format,
            width: w,
            height: h,
            usage: UInt32(WGPUTextureUsage_RenderAttachment | WGPUTextureUsage_CopySrc)
        )
        self.texture = tex
        self.view = tex.createView()
        let bpp = UInt32(metalFormatBytesPerPixel(format))
        let pr = ((w * bpp + 255) / 256) * 256
        self.paddedRow = pr
        self.buffer = device.createBuffer(label: "readback", size: Int(pr * h))
        self.pixels = [UInt8](repeating: 0, count: Int(w) * Int(h) * Int(bpp))
    }

    public static func new(_ device: MetalDevice, _ width: UInt32, _ height: UInt32) -> Offscreen {
        Offscreen(device, width, height)
    }

    public static func withFormat(
        _ device: MetalDevice,
        _ width: UInt32,
        _ height: UInt32,
        _ format: WGPUTextureFormat
    ) -> Offscreen {
        Offscreen(device, width, height, format)
    }

    public func copy(_ encoder: MetalCommandEncoder) {
        copyTo(encoder, buffer)
    }

    public func copyTo(_ encoder: MetalCommandEncoder, _ dst: MetalBuffer) {
        encoder.copyTextureToBuffer(
            texture: texture,
            mipLevel: 0,
            originX: 0,
            originY: 0,
            arrayLayer: 0,
            destination: dst,
            destinationOffset: 0,
            bytesPerRow: paddedRow,
            rowsPerImage: height,
            width: width,
            height: height
        )
    }

    public func read(_ device: MetalDevice) -> [UInt8] {
        #if os(WASI)
        fatalError("blocking GPU readback is unsupported on web")
        #else
        buffer.mapAsync { _ in }
        _ = device.poll(.waitIndefinitely())
        let data = buffer.getMappedRange(0..<Int(paddedRow * height))
        buffer.unmap()
        let bpp = metalFormatBytesPerPixel(texture.format)
        let rowBytes = Int(width) * bpp
        let stride = Int(paddedRow)
        var out = [UInt8](repeating: 0, count: rowBytes * Int(height))
        for y in 0..<Int(height) {
            let srcStart = y * stride
            let dstStart = y * rowBytes
            if srcStart + rowBytes <= data.count {
                out.replaceSubrange(dstStart..<(dstStart + rowBytes), with: data[srcStart..<(srcStart + rowBytes)])
            }
        }
        return out
        #endif
    }

    public static func renderScene(
        gpu: Gpu,
        renderer: Renderer,
        atlas: inout Atlas,
        instances: [Instance],
        width: UInt32,
        height: UInt32,
        clear: [Float]
    ) -> [UInt8] {
        #if canImport(ObjectiveC)
        // PORT NOTE: Drains transient Metal Objective-C objects immediately when called repeatedly
        // inside Swift Testing cooperative worker threads without an outer NSRunLoop autorelease pool.
        return autoreleasepool {
            renderer.prepare(gpu.metalDevice, gpu.metalQueue, &atlas, instances, (width, height))
            let target = Offscreen(gpu.metalDevice, width, height, renderer.format)
            let encoder = gpu.metalDevice.createCommandEncoder(label: "offscreen-scene")
            renderer.draw(encoder, target.view, clear)
            target.copy(encoder)
            _ = renderer.submit(gpu.metalQueue, encoder)
            return target.read(gpu.metalDevice)
        }
        #else
        renderer.prepare(gpu.metalDevice, gpu.metalQueue, &atlas, instances, (width, height))
        let target = Offscreen(gpu.metalDevice, width, height, renderer.format)
        let encoder = gpu.metalDevice.createCommandEncoder(label: "offscreen-scene")
        renderer.draw(encoder, target.view, clear)
        target.copy(encoder)
        _ = renderer.submit(gpu.metalQueue, encoder)
        return target.read(gpu.metalDevice)
        #endif
    }
}

// MARK: - Portable PNG Writer (`write_png`)

private func pngCrc32(_ bytes: [UInt8]) -> UInt32 {
    var crc: UInt32 = 0xffff_ffff
    for b in bytes {
        var c = (crc ^ UInt32(b)) & 0xff
        for _ in 0..<8 {
            c = (c & 1) != 0 ? (0xedb8_8320 ^ (c >> 1)) : (c >> 1)
        }
        crc = (crc >> 8) ^ c
    }
    return crc ^ 0xffff_ffff
}

private func pngAdler32(_ bytes: [UInt8]) -> UInt32 {
    var a: UInt32 = 1
    var b: UInt32 = 0
    for byte in bytes {
        a = (a + UInt32(byte)) % 65521
        b = (b + a) % 65521
    }
    return (b << 16) | a
}

private func appendPngChunk(_ out: inout [UInt8], type: String, payload: [UInt8]) {
    let len = UInt32(payload.count)
    out.append(UInt8(truncatingIfNeeded: len >> 24))
    out.append(UInt8(truncatingIfNeeded: len >> 16))
    out.append(UInt8(truncatingIfNeeded: len >> 8))
    out.append(UInt8(truncatingIfNeeded: len))
    let typeBytes = Array(type.utf8)
    var crcInput = typeBytes
    crcInput.append(contentsOf: payload)
    out.append(contentsOf: crcInput)
    let crc = pngCrc32(crcInput)
    out.append(UInt8(truncatingIfNeeded: crc >> 24))
    out.append(UInt8(truncatingIfNeeded: crc >> 16))
    out.append(UInt8(truncatingIfNeeded: crc >> 8))
    out.append(UInt8(truncatingIfNeeded: crc))
}

/// Encodes `rgba` (`width * height * 4` sRGB bytes) into a valid PNG byte buffer.
func encodePngBytes(_ width: UInt32, _ height: UInt32, _ rgba: [UInt8]) -> [UInt8] {
    let rowBytes = Int(width) * 4
    var rawScanlines = [UInt8]()
    rawScanlines.reserveCapacity((rowBytes + 1) * Int(height))
    for y in 0..<Int(height) {
        rawScanlines.append(0) // filter type None
        let start = y * rowBytes
        rawScanlines.append(contentsOf: rgba[start..<(start + rowBytes)])
    }

    // Stored zlib stream (RFC 1950 + RFC 1951 uncompressed blocks, max 65535 bytes each).
    var zlib = [UInt8]([0x78, 0x01])
    var pos = 0
    let total = rawScanlines.count
    while true {
        let remain = total - pos
        let blockLen = min(remain, 65535)
        let isFinal: UInt8 = (pos + blockLen >= total) ? 0x01 : 0x00
        zlib.append(isFinal)
        let len16 = UInt16(blockLen)
        let nlen16 = ~len16
        zlib.append(UInt8(truncatingIfNeeded: len16))
        zlib.append(UInt8(truncatingIfNeeded: len16 >> 8))
        zlib.append(UInt8(truncatingIfNeeded: nlen16))
        zlib.append(UInt8(truncatingIfNeeded: nlen16 >> 8))
        if blockLen > 0 {
            zlib.append(contentsOf: rawScanlines[pos..<(pos + blockLen)])
        }
        pos += blockLen
        if isFinal == 0x01 { break }
    }
    let adler = pngAdler32(rawScanlines)
    zlib.append(UInt8(truncatingIfNeeded: adler >> 24))
    zlib.append(UInt8(truncatingIfNeeded: adler >> 16))
    zlib.append(UInt8(truncatingIfNeeded: adler >> 8))
    zlib.append(UInt8(truncatingIfNeeded: adler))

    var out: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]
    let ihdr: [UInt8] = [
        UInt8(truncatingIfNeeded: width >> 24),
        UInt8(truncatingIfNeeded: width >> 16),
        UInt8(truncatingIfNeeded: width >> 8),
        UInt8(truncatingIfNeeded: width),
        UInt8(truncatingIfNeeded: height >> 24),
        UInt8(truncatingIfNeeded: height >> 16),
        UInt8(truncatingIfNeeded: height >> 8),
        UInt8(truncatingIfNeeded: height),
        8, // bit depth
        6, // RGBA
        0, 0, 0,
    ]
    appendPngChunk(&out, type: "IHDR", payload: ihdr)
    appendPngChunk(&out, type: "sRGB", payload: [0]) // Perceptual
    appendPngChunk(&out, type: "IDAT", payload: zlib)
    appendPngChunk(&out, type: "IEND", payload: [])
    return out
}

public func writePng(_ path: String, _ width: UInt32, _ height: UInt32, _ rgba: [UInt8]) throws {
    #if !os(WASI)
    let url = URL(fileURLWithPath: path)
    let parent = url.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    let png = encodePngBytes(width, height, rgba)
    try Data(png).write(to: url)
    #else
    _ = (path, width, height, rgba)
    #endif
}

/// Namespace mirroring `rune::render::*`.
public enum render {
    public typealias Instance = Rune.Instance
    public typealias LayerSpec = Rune.LayerSpec
    public typealias LayerStats = Rune.LayerStats
    public typealias Blend = Rune.Blend
    public typealias Renderer = Rune.Renderer
    public typealias Gpu = Rune.Gpu
    public typealias Offscreen = Rune.Offscreen
    public typealias EffectSite = Rune.EffectSite
    public typealias EffectPhase = Rune.EffectPhase
    public typealias EffectHook = Rune.EffectHook
    public typealias EffectBackdropHook = Rune.EffectBackdropHook
    public typealias AlphaSurface = Rune.AlphaSurface

    public static let KIND_RECT = Rune.KIND_RECT
    public static let KIND_SHADOW = Rune.KIND_SHADOW
    public static let KIND_GLYPH = Rune.KIND_GLYPH
    public static let KIND_INSET = Rune.KIND_INSET
    public static let KIND_GRADIENT = Rune.KIND_GRADIENT
    public static let KIND_SEGMENT = Rune.KIND_SEGMENT
    public static let KIND_TRIANGLE = Rune.KIND_TRIANGLE
    public static let KIND_IMAGE = Rune.KIND_IMAGE
    public static let KIND_LAYER = Rune.KIND_LAYER
    public static let KIND_LAYER_END = Rune.KIND_LAYER_END
    public static let KIND_DASHED = Rune.KIND_DASHED
    public static let KIND_RADIAL = Rune.KIND_RADIAL
    public static let KIND_EFFECT = Rune.KIND_EFFECT
    public static let KIND_BACKDROP_BLUR = Rune.KIND_BACKDROP_BLUR
    public static let NO_CLIP = Rune.NO_CLIP
    public static let OFFSCREEN_FORMAT = Rune.OFFSCREEN_FORMAT
    public static let CLIP_WGSL = Rune.CLIP_WGSL
    public static let DEFAULT_CACHE_BUDGET = Rune.DEFAULT_CACHE_BUDGET
    public static let MAX_BACKDROP_BLURS = Rune.MAX_BACKDROP_BLURS

    public static func packFade(_ width: [Float], _ origin: [Float], _ clip: [Float]) -> [UInt32] {
        Rune.packFade(width, origin, clip)
    }
    public static func unpackFade(_ fade: [UInt32]) -> ([Float], [Float]) {
        Rune.unpackFade(fade)
    }
    public static func packClipRadii(_ clip: [Float], _ radii: [Float]) -> UInt32 {
        Rune.packClipRadii(clip, radii)
    }
    public static func unpackClipRadii(_ w: UInt32) -> [Float] {
        Rune.unpackClipRadii(w)
    }
    public static func writePng(_ path: String, _ width: UInt32, _ height: UInt32, _ rgba: [UInt8]) throws {
        try Rune.writePng(path, width, height, rgba)
    }
}
