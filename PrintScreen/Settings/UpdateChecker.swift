import Foundation
import Observation

/// GitHub Releases の最新版と今のバージョンを比べる。
@Observable
final class UpdateChecker {
    enum Status {
        case idle
        case checking
        case upToDate
        case available(version: String, url: URL)
        /// 通信できない、リリースがない、リポジトリが非公開のとき。
        case unavailable
    }

    private(set) var status: Status = .idle

    private let latestReleaseURL = URL(string: "https://github.com/morishin/printscreen/releases/latest")!

    func check() async {
        status = .checking
        var request = URLRequest(url: latestReleaseURL)
        request.httpMethod = "HEAD"

        // 最新リリースがあると /releases/tag/vX.Y にリダイレクトされる
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let finalURL = http.url,
              finalURL.pathComponents.dropLast().last == "tag" else {
            status = .unavailable
            return
        }

        let tag = finalURL.lastPathComponent
        let remoteVersion = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        if remoteVersion.compare(currentVersion, options: .numeric) == .orderedDescending {
            status = .available(version: remoteVersion, url: finalURL)
        } else {
            status = .upToDate
        }
    }
}
