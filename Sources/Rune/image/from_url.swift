// Ported from: crates/rune/src/image/from_url.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

/// The largest side a fetched image may have, as for decoded files: 8192 pixels, so at most
/// 256 MiB of decoded RGBA before mips.
internal let IMAGE_URL_MAX_SIDE: UInt32 = 8192

extension ImageCache {
    /// The image at `url`, shared by URL, size and scale like ``ImageCache/file(_:_:_:)``.
    ///
    /// On native, where Rune has no HTTP client, a path or `file:` URL loads like
    /// ``ImageCache/file(_:_:_:)`` and other URLs fail; fetch those bytes yourself and call
    /// ``ImageCache/load(_:)``.
    public func url(_ url: String, _ sizePt: Float, _ scale: Float) -> Image {
        let px = iconPixels(sizePt, scale)
        var hasher = RuneSha256()
        hasher.update(Array("rune-url\0".utf8))
        hasher.update(Array(url.utf8))
        hasher.update([0])
        hasher.updateUInt32LE(px)
        return request(hasher.finalize(), .url(url, px))
    }
}

/// What the browser handed back for a URL.
internal enum FetchedImage: Sendable {
    /// Straight-alpha sRGB RGBA8 the browser decoded.
    case rgba(UInt32, UInt32, [UInt8])
    /// SVG or SVGZ bytes, which Rune rasterizes at `px`.
    case svg([UInt8])
}

/// The mips for a fetched image, or why not, naming the URL.
internal func landFetchedImage(_ url: String, _ fetched: FetchedImage, _ px: UInt32) -> Result<DecodedImageMips, ImageError> {
    let outcome: Result<DecodedImageMips, ImageError>
    switch fetched {
    case .rgba(let w, let h, let bytes):
        outcome = mipChain(w, h, bytes)
    case .svg(let bytes):
        outcome = svgRgba(bytes, px).flatMap { mipChain($0.0, $0.1, $0.2) }
    }
    return outcome.mapError { err in
        ImageError("\(url): \(err.message)")
    }
}

/// The file a native `url` names: a path with no scheme, or a `file:` URL.
internal func imageFilePathFromUrl(_ url: String) -> Result<String, ImageError> {
    let scheme: Substring? = {
        guard let colonIdx = url.firstIndex(of: ":") else { return nil }
        let candidate = url[..<colonIdx]
        // A one-letter "scheme" is a Windows drive (`C:\...`).
        guard candidate.count > 1,
              let first = candidate.first,
              first.isASCII && first.isLetter else {
            return nil
        }
        let validScheme = candidate.allSatisfy { ch in
            ch.isASCII && (ch.isLetter || ch.isNumber || ch == "+" || ch == "-" || ch == ".")
        }
        return validScheme ? candidate : nil
    }()

    guard let scheme else {
        return .success(url)
    }

    func unsupported() -> ImageError {
        ImageError("\(url): only web fetches URLs; on native fetch the bytes and call ImageCache::load")
    }

    guard scheme.lowercased() == "file" else {
        return .failure(unsupported())
    }

    let afterColon = url[url.index(url.startIndex, offsetBy: scheme.count + 1)...]
    let pathSlice: Substring
    if afterColon.hasPrefix("//") {
        let strippedSlashes = afterColon.dropFirst(2)
        if strippedSlashes.hasPrefix("localhost") {
            pathSlice = strippedSlashes.dropFirst("localhost".count)
        } else {
            pathSlice = strippedSlashes
        }
    } else {
        pathSlice = afterColon
    }

    guard pathSlice.hasPrefix("/") else {
        return .failure(unsupported())
    }
    guard let decoded = percentDecodeUrlPath(String(pathSlice)) else {
        return .failure(ImageError("\(url): not a valid file URL"))
    }

    #if os(Windows)
    let utf8 = Array(decoded.utf8)
    if utf8.count >= 3 && utf8[0] == UInt8(ascii: "/")
        && ((utf8[1] >= UInt8(ascii: "A") && utf8[1] <= UInt8(ascii: "Z"))
            || (utf8[1] >= UInt8(ascii: "a") && utf8[1] <= UInt8(ascii: "z")))
        && utf8[2] == UInt8(ascii: ":") {
        return .success(String(decoded.dropFirst()))
    }
    #endif
    return .success(decoded)
}

internal func percentDecodeUrlPath(_ s: String) -> String? {
    let bytes = Array(s.utf8)
    var out = [UInt8]()
    out.reserveCapacity(bytes.count)
    var i = 0
    func hexDigit(_ b: UInt8) -> UInt8? {
        switch b {
        case UInt8(ascii: "0")...UInt8(ascii: "9"):
            return b - UInt8(ascii: "0")
        case UInt8(ascii: "a")...UInt8(ascii: "f"):
            return b - UInt8(ascii: "a") + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"):
            return b - UInt8(ascii: "A") + 10
        default:
            return nil
        }
    }
    while i < bytes.count {
        let b = bytes[i]
        i += 1
        if b != UInt8(ascii: "%") {
            out.append(b)
            continue
        }
        guard i + 1 < bytes.count + 1, i < bytes.count, i + 1 <= bytes.count else {
            return nil
        }
        guard i + 1 < bytes.count + 0 || (i < bytes.count && i + 1 - 1 < bytes.count) else {
            return nil
        }
        guard i + 1 <= bytes.count - 1 + 1, i + 1 < bytes.count + 1 else {
            return nil
        }
        // Need two hex bytes at `i` and `i + 1`:
        guard i + 1 < bytes.count,
              let hi = hexDigit(bytes[i]),
              let lo = hexDigit(bytes[i + 1]) else {
            return nil
        }
        i += 2
        out.append((hi << 4) | lo)
    }
    return String(bytes: out, encoding: .utf8)
}
