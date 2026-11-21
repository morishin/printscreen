import Foundation

/// Homebrew などで入れた ffmpeg を使って WebM に変換する。
enum FFmpeg {
    private static let candidates = [
        "/opt/homebrew/bin/ffmpeg",
        "/usr/local/bin/ffmpeg",
        "/opt/local/bin/ffmpeg",
    ]

    /// 見つかった ffmpeg の場所。無ければ nil。
    static var executableURL: URL? {
        candidates
            .first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    enum ConversionError: LocalizedError {
        case notInstalled
        case failed(String)
        var errorDescription: String? {
            switch self {
            case .notInstalled: "ffmpeg が見つかりません"
            case .failed(let log): "ffmpeg での変換に失敗しました\n\(log)"
            }
        }
    }

    /// VP9 の WebM に変換する。
    static func convertToWebM(input: URL, output: URL) async throws {
        guard let ffmpeg = executableURL else { throw ConversionError.notInstalled }
        let process = Process()
        process.executableURL = ffmpeg
        process.arguments = [
            "-y", "-hide_banner", "-loglevel", "error",
            "-i", input.path,
            "-c:v", "libvpx-vp9",
            "-crf", "36", "-b:v", "0",
            "-deadline", "good", "-cpu-used", "4", "-row-mt", "1",
            "-pix_fmt", "yuv420p",
            "-an",
            output.path,
        ]
        let errPipe = Pipe()
        process.standardError = errPipe
        process.standardOutput = FileHandle.nullDevice

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { p in
                let data = errPipe.fileHandleForReading.readDataToEndOfFile()
                if p.terminationStatus == 0 {
                    cont.resume()
                } else {
                    cont.resume(throwing: ConversionError.failed(String(decoding: data, as: UTF8.self)))
                }
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                cont.resume(throwing: error)
            }
        }
    }
}
