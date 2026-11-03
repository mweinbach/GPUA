// Tests ported from: crates/rune/src/image/mip_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

// PORT NOTE: `the_mip_chain_allocates_little_beyond_its_output` uses Rust's custom global allocator
// (`tooling::test_alloc::peak`); Swift has no global heap byte counter hook without replacing `malloc`.
// `the_byte_mip_chain_matches_the_float_one_within_one_per_channel` is ported verbatim below.

private func referenceMipChain(_ width: UInt32, _ height: UInt32, _ bytes: [UInt8]) -> [DecodedMipLevel] {
    var linear: [[Float]] = []
    linear.reserveCapacity(bytes.count / 4)
    for i in stride(from: 0, to: bytes.count, by: 4) {
        let a = Float(bytes[i + 3]) / 255.0
        linear.append([
            srgbDecode(Float(bytes[i]) / 255.0) * a,
            srgbDecode(Float(bytes[i + 1]) / 255.0) * a,
            srgbDecode(Float(bytes[i + 2]) / 255.0) * a,
            a,
        ])
    }
    var w = width
    var h = height
    var mips: [DecodedMipLevel] = []
    while true {
        var pixels: [UInt8] = []
        pixels.reserveCapacity(linear.count * 4)
        for p in linear {
            let a = quantizeByte(p[3])
            let cap = Float(a) / 255.0
            pixels.append(quantizeByte(srgbEncode(min(p[0], cap))))
            pixels.append(quantizeByte(srgbEncode(min(p[1], cap))))
            pixels.append(quantizeByte(srgbEncode(min(p[2], cap))))
            pixels.append(a)
        }
        mips.append(DecodedMipLevel(width: w, height: h, pixels: pixels))
        if w == 1 && h == 1 {
            break
        }
        let nw = max(1, w / 2)
        let nh = max(1, h / 2)
        var next: [[Float]] = []
        next.reserveCapacity(Int(nw * nh))
        for y in 0..<nh {
            for x in 0..<nw {
                let x0 = Float(x) * Float(w) / Float(nw)
                let x1 = Float(x + 1) * Float(w) / Float(nw)
                let y0 = Float(y) * Float(h) / Float(nh)
                let y1 = Float(y + 1) * Float(h) / Float(nh)
                var sum: [Float] = [0, 0, 0, 0]
                let sy0 = UInt32(y0.rounded(.down))
                let sy1 = min(h, UInt32(y1.rounded(.up)))
                let sx0 = UInt32(x0.rounded(.down))
                let sx1 = min(w, UInt32(x1.rounded(.up)))
                for sy in sy0..<sy1 {
                    for sx in sx0..<sx1 {
                        let wx = min(Float(sx + 1), x1) - max(Float(sx), x0)
                        let wy = min(Float(sy + 1), y1) - max(Float(sy), y0)
                        let weight = wx * wy
                        let px = linear[Int(sy * w + sx)]
                        for c in 0..<4 {
                            sum[c] += px[c] * weight
                        }
                    }
                }
                let area = (x1 - x0) * (y1 - y0)
                next.append(sum.map { $0 / area })
            }
        }
        linear = next
        w = nw
        h = nh
    }
    return mips
}

private func syntheticImage(_ w: UInt32, _ h: UInt32) -> [UInt8] {
    var out: [UInt8] = []
    out.reserveCapacity(Int(w * h * 4))
    for y in 0..<h {
        for x in 0..<w {
            let n = (((x &* 0x9e37_79b9) ^ (y &* 0x85eb_ca6b)) &* 0xc2b2_ae35) >> 24
            let alpha: UInt8
            switch (x / 7 + y / 5) % 5 {
            case 0: alpha = 255
            case 1: alpha = 0
            case 2: alpha = UInt8(x * 255 / w)
            case 3: alpha = UInt8(truncatingIfNeeded: n)
            default: alpha = 1 + UInt8(y % 3)
            }
            out.append(contentsOf: [
                UInt8(x * 255 / w),
                UInt8(y * 255 / h),
                UInt8(truncatingIfNeeded: n),
                alpha,
            ])
        }
    }
    return out
}

@Suite("ImageMipTests")
struct ImageMipTests {
    @Test("the byte mip chain matches the float one within one per channel")
    func byteMipChainMatchesFloatWithinOnePerChannel() throws {
        let sizes: [(UInt32, UInt32)] = [
            (1, 1), (2, 1), (3, 1), (1, 7), (17, 9), (64, 64), (257, 131), (300, 1),
        ]
        for (w, h) in sizes {
            let src = syntheticImage(w, h)
            let got = try mipChain(w, h, src).get().mips
            let want = referenceMipChain(w, h, src)
            #expect(got.count == want.count)
            for (g, r) in zip(got, want) {
                #expect(g.width == r.width && g.height == r.height)
                var worst = 0
                for (a, b) in zip(g.pixels, r.pixels) {
                    let diff = abs(Int(a) - Int(b))
                    if diff > worst { worst = diff }
                }
                #expect(worst <= 1)
                for i in stride(from: 0, to: g.pixels.count, by: 4) {
                    let clearLight = (g.pixels[i] == 0 && g.pixels[i + 1] == 0 && g.pixels[i + 2] == 0)
                    #expect(clearLight || g.pixels[i + 3] > 0)
                }
            }
            for i in stride(from: 0, to: src.count, by: 4) where src[i + 3] == 255 {
                #expect(got[0].pixels[i..<(i + 4)] == src[i..<(i + 4)])
            }
        }
    }
}
