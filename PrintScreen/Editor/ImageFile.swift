import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Finder などから開いた画像ファイルを読み込む。
enum ImageFile {
    struct Loaded {
        let image: CGImage
        /// 1 ポイントあたりのピクセル数。線の太さや文字の大きさの基準になる。
        let pixelScale: CGFloat
        /// 元のファイルの形式。保存できない形式なら nil で、設定の形式を使う。
        let format: ImageFormat?
    }

    static func load(_ url: URL) -> Loaded? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        // 写真の向き（EXIF）を反映して、見たままの向きで読む
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height),
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return Loaded(image: image, pixelScale: pixelScale(properties), format: format(of: source))
    }

    /// macOS のスクリーンショットのように 144 dpi なら 2。解像度の情報が無ければ画面の倍率とみなす。
    private static func pixelScale(_ properties: [CFString: Any]) -> CGFloat {
        if let dpi = properties[kCGImagePropertyDPIWidth] as? Double, dpi > 72 {
            return max(1, (dpi / 72).rounded())
        }
        return NSScreen.main?.backingScaleFactor ?? 2
    }

    private static func format(of source: CGImageSource) -> ImageFormat? {
        guard let identifier = CGImageSourceGetType(source) as String?, let type = UTType(identifier) else { return nil }
        if type.conforms(to: .png) { return .png }
        if type.conforms(to: .jpeg) { return .jpeg }
        if type.conforms(to: .webP) { return .webp }
        return nil
    }
}
