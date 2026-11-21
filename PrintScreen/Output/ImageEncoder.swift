import AppKit
import ImageIO
import UniformTypeIdentifiers
import libwebp

enum ImageEncoder {
    enum EncodeError: LocalizedError {
        case failed
        var errorDescription: String? { "画像の書き出しに失敗しました" }
    }

    static func encode(_ image: CGImage, format: ImageFormat, quality: Double) throws -> Data {
        switch format {
        case .webp: return try encodeWebP(image, quality: quality)
        case .png: return try encodeImageIO(image, type: .png, properties: [:])
        case .jpeg:
            return try encodeImageIO(flattenedOnWhite(image) ?? image, type: .jpeg,
                                     properties: [kCGImageDestinationLossyCompressionQuality: quality / 100])
        }
    }

    /// JPEG は透過できないので、透明な部分を白で埋める。
    private static func flattenedOnWhite(_ image: CGImage) -> CGImage? {
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        guard let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.setFillColor(.white)
        ctx.fill(rect)
        ctx.draw(image, in: rect)
        return ctx.makeImage()
    }

    private static func encodeImageIO(_ image: CGImage, type: UTType, properties: [CFString: Any]) throws -> Data {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else {
            throw EncodeError.failed
        }
        CGImageDestinationAddImage(dest, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw EncodeError.failed }
        return data as Data
    }

    private static func encodeWebP(_ image: CGImage, quality: Double) throws -> Data {
        let width = image.width
        let height = image.height
        let stride = width * 4
        var pixels = [UInt8](repeating: 0, count: stride * height)
        // libwebp は非プリマルチプライの RGBA を受け取る。sRGB に揃えて描き直す。
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(data: buffer.baseAddress, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: stride,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { throw EncodeError.failed }
        // プリマルチプライを戻す（スクリーンショットはほぼ不透明なので多くは何もしない）
        for i in Swift.stride(from: 0, to: pixels.count, by: 4) {
            let a = pixels[i + 3]
            if a != 255 && a != 0 {
                pixels[i] = UInt8(min(255, Int(pixels[i]) * 255 / Int(a)))
                pixels[i + 1] = UInt8(min(255, Int(pixels[i + 1]) * 255 / Int(a)))
                pixels[i + 2] = UInt8(min(255, Int(pixels[i + 2]) * 255 / Int(a)))
            }
        }
        var output: UnsafeMutablePointer<UInt8>?
        let size = pixels.withUnsafeBufferPointer { buf in
            WebPEncodeRGBA(buf.baseAddress, Int32(width), Int32(height), Int32(stride), Float(quality), &output)
        }
        guard size > 0, let output else { throw EncodeError.failed }
        defer { WebPFree(output) }
        return Data(bytes: output, count: size)
    }
}

enum OutputFiles {
    /// macOS 標準に合わせた「スクリーンショット 2026-11-21 0.52.13」のような名前。
    static func baseName(prefix: String, date: Date = .now) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd H.mm.ss"
        return "\(prefix) \(f.string(from: date))"
    }

    /// 同名のファイルがあれば「(2)」などをつけて重ならない URL を返す。
    static func uniqueURL(directory: URL, baseName: String, ext: String) -> URL {
        var url = directory.appendingPathComponent(baseName).appendingPathExtension(ext)
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = directory.appendingPathComponent("\(baseName) (\(n))").appendingPathExtension(ext)
            n += 1
        }
        return url
    }

    static func ensureDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
