import AVFoundation
import Foundation
import os

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
            case .notInstalled: String(localized: "ffmpeg not found")
            case .failed(let log): String(localized: "ffmpeg conversion failed\n\(log)")
            }
        }
    }

    /// VP9 の WebM に変換する。progress には進み具合（0〜1）をメインスレッドで渡す。
    static func convertToWebM(input: URL, output: URL, progress: ((Double) -> Void)? = nil) async throws {
        guard let ffmpeg = executableURL else { throw ConversionError.notInstalled }
        // 進み具合は、ffmpeg が書き出した位置を動画の長さで割って出す
        let duration = (try? await AVURLAsset(url: input).load(.duration).seconds) ?? 0
        let process = Process()
        process.executableURL = ffmpeg
        process.arguments = [
            "-y", "-hide_banner", "-loglevel", "error", "-nostats", "-progress", "pipe:1",
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
        let outPipe = Pipe()
        process.standardOutput = outPipe
        if let progress, duration > 0 {
            // -progress は「out_time_us=1234567」のような行を書き出す
            let buffer = OSAllocatedUnfairLock(initialState: "")
            outPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = String(decoding: handle.availableData, as: UTF8.self)
                let latest = buffer.withLock { buffer -> Double? in
                    buffer += chunk
                    var latest: Double?
                    while let newline = buffer.firstIndex(of: "\n") {
                        let line = buffer[..<newline]
                        if line.hasPrefix("out_time_us="), let us = Double(line.dropFirst("out_time_us=".count)) {
                            latest = us / 1_000_000 / duration
                        }
                        buffer.removeSubrange(...newline)
                    }
                    return latest
                }
                if let latest {
                    DispatchQueue.main.async { progress(latest) }
                }
            }
        } else {
            outPipe.fileHandleForReading.readabilityHandler = { handle in _ = handle.availableData }
        }
        defer { outPipe.fileHandleForReading.readabilityHandler = nil }

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
