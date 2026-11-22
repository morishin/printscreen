import AppKit
import SwiftUI

/// 設定の「このアプリについて」タブ。
struct AboutView: View {
    @State private var checker = UpdateChecker()

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)

            VStack(spacing: 4) {
                Text("PrintScreen")
                    .font(.title.bold())
                Text("Version \(version)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            updateSection

            Divider()

            VStack(spacing: 12) {
                LabeledContent("Author") {
                    Link("morishin", destination: URL(string: "https://github.com/morishin")!)
                }
                .frame(maxWidth: 240)

                HStack {
                    Link(destination: URL(string: "https://github.com/morishin/printscreen")!) {
                        Label {
                            Text("GitHub")
                        } icon: {
                            Image("GitHubMark")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 14, height: 14)
                        }
                    }
                    Link(destination: URL(string: "https://github.com/sponsors/morishin?frequency=one-time")!) {
                        Label("Buy me a coffee", systemImage: "cup.and.saucer.fill")
                    }
                }
                .buttonStyle(.bordered)
            }

            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await checker.check() }
    }

    @ViewBuilder
    private var updateSection: some View {
        switch checker.status {
        case .idle:
            checkButton
        case .checking:
            ProgressView("Checking…")
                .controlSize(.small)
        case .upToDate:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Up to date")
                    .foregroundStyle(.secondary)
                checkButton
                    .buttonStyle(.link)
            }
            .font(.callout)
        case .available(let version, let url):
            Link(destination: url) {
                Label("Version \(version) Available", systemImage: "arrow.down.circle.fill")
            }
            .buttonStyle(.borderedProminent)
        case .unavailable:
            HStack(spacing: 6) {
                Text("Couldn't check for updates")
                    .foregroundStyle(.secondary)
                Button("Retry") {
                    Task { await checker.check() }
                }
                .buttonStyle(.link)
            }
            .font(.callout)
        }
    }

    private var checkButton: some View {
        Button("Check for Updates") {
            Task { await checker.check() }
        }
    }
}
