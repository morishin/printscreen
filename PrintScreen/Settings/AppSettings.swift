import Foundation
import Observation

enum ImageFormat: String, CaseIterable, Identifiable {
    case webp, png, jpeg
    var id: String { rawValue }
    var label: String {
        switch self {
        case .webp: "WebP"
        case .png: "PNG"
        case .jpeg: "JPEG"
        }
    }
    var fileExtension: String {
        switch self {
        case .webp: "webp"
        case .png: "png"
        case .jpeg: "jpg"
        }
    }
}

enum VideoFormat: String, CaseIterable, Identifiable {
    case webm, mp4, mov
    var id: String { rawValue }
    var label: String {
        switch self {
        case .webm: "WebM (VP9)"
        case .mp4: "MP4 (HEVC)"
        case .mov: "MOV (HEVC)"
        }
    }
    var fileExtension: String { rawValue }
    /// WebM は ffmpeg が入っているときだけ使える。
    var isAvailable: Bool {
        self != .webm || FFmpeg.executableURL != nil
    }
}

/// アプリの設定。UserDefaults に保存する。
@Observable
final class AppSettings {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    var saveDirectory: URL {
        didSet { defaults.set(saveDirectory.path, forKey: "saveDirectory") }
    }
    var imageFormat: ImageFormat {
        didSet { defaults.set(imageFormat.rawValue, forKey: "imageFormat") }
    }
    /// 0〜100。WebP と JPEG の品質。
    var imageQuality: Double {
        didSet { defaults.set(imageQuality, forKey: "imageQuality") }
    }
    /// 保存したい形式。WebM が選ばれていても ffmpeg が無いときは `effectiveVideoFormat` が MP4 になる。
    var videoFormat: VideoFormat {
        didSet { defaults.set(videoFormat.rawValue, forKey: "videoFormat") }
    }
    var showClicks: Bool {
        didSet { defaults.set(showClicks, forKey: "showClicks") }
    }
    var showKeystrokes: Bool {
        didSet { defaults.set(showKeystrokes, forKey: "showKeystrokes") }
    }
    /// メニューバーにアイコンを出す。オフでも録画中は停止ボタンとして表示する。
    var showMenuBarIcon: Bool {
        didSet {
            defaults.set(showMenuBarIcon, forKey: "showMenuBarIcon")
            StatusItemController.shared.update(isRecording: AppController.shared.isRecording)
        }
    }

    /// 録画の保存後に Finder で自動表示する（トーストは出さない）。
    var revealRecordingInFinder: Bool {
        didSet { defaults.set(revealRecordingInFinder, forKey: "revealRecordingInFinder") }
    }

    var effectiveVideoFormat: VideoFormat {
        videoFormat.isAvailable ? videoFormat : .mp4
    }

    private init() {
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        if let path = defaults.string(forKey: "saveDirectory") {
            saveDirectory = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            saveDirectory = desktop
        }
        imageFormat = ImageFormat(rawValue: defaults.string(forKey: "imageFormat") ?? "") ?? .webp
        imageQuality = defaults.object(forKey: "imageQuality") as? Double ?? 90
        videoFormat = VideoFormat(rawValue: defaults.string(forKey: "videoFormat") ?? "") ?? .webm
        showClicks = defaults.object(forKey: "showClicks") as? Bool ?? true
        showKeystrokes = defaults.object(forKey: "showKeystrokes") as? Bool ?? false
        showMenuBarIcon = defaults.object(forKey: "showMenuBarIcon") as? Bool ?? true
        defaults.removeObject(forKey: "copyToClipboardOnSave") // 廃止した設定
        revealRecordingInFinder = defaults.object(forKey: "revealRecordingInFinder") as? Bool ?? false
    }
}
