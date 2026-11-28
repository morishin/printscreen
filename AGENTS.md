# Operating Rules

## Git

- Commit each time a task is complete. Ask the developer to verify first unless they told you to proceed.
- Pushing a `v*` tag publishes a release, so confirm before pushing one.

## Building

- Verify builds with the Xcode MCP after implementing. Do not run `xcodebuild` locally. CI is the exception.
- Keep `objectVersion = 77` in `project.pbxproj`. The release runner uses Xcode 26 and cannot open newer formats. Xcode 27 rewrites this to `110` when it saves the project, so do not commit that change. The release workflow also resets it to `77` as a safeguard.
- Prefer the Xcode MCP for build settings. After editing `project.pbxproj` directly, close and reopen the project in Xcode, or it may build with stale settings.
- Sources use file-system-synchronized groups. A new file may need a second build to be picked up.

# Project Structure

- `PrintScreen/PrintScreenApp.swift`, `AppController.swift`, `StatusItemController.swift` — App lifecycle, capture and recording flow, menu bar
- `PrintScreen/Capture/` — Area and window selection, screenshots with ScreenCaptureKit
- `PrintScreen/Editor/` — Annotation model, canvas, toolbar, editor window
- `PrintScreen/Recording/` — Screen recording, click ripples, pressed keys
- `PrintScreen/Output/` — Image encoding, file naming, ffmpeg conversion, toast
- `PrintScreen/Settings/` — Settings tabs, hotkeys, update check, About
- `public/` — Website
- `tools/` — Scripts to retake website and README media, see `tools/README.md`
- `PrintScreenTests/`, `PrintScreenUITests/` — Still the Xcode templates, so there is no real automated test coverage. Verify capture and editor behavior in the running app.

# Product Decisions

- The editor's `Esc` switches to the Select tool. `⌘W` discards, and asks first if there are annotations.
- Copy and Save close the editor when it has no annotations, hiding it before the image is converted. With annotations it stays open, because people often keep editing.
- Mosaic uses the exact average color of each block through Accelerate. `CIPixellate` samples pixels and looks harsh.
- Recordings have no audio, neither system audio nor microphone.
- ffmpeg is not bundled. The app calls the user's install. Without it, WebM is disabled and recordings are saved as MP4.

# Implementation Notes

- `@ObservationIgnored` state does not update SwiftUI. Undo and Redo broke this way, so keep state that drives UI observed.
- Add every new UI string to `PrintScreen/Localizable.xcstrings` in all languages: English (source), ja, zh-Hans, zh-Hant, ko, es, de, and fr. Use `String(localized:)` in AppKit and plain `String` contexts.
- The editor's minimum width depends on the localized Save label. Check the toolbar in long languages such as German and French.
- To test key equivalents such as `⌘W`, send events with `NSApp.postEvent`. `NSApp.sendEvent` does not exercise them.
- The About tab loads the bundled `.icns`, because `NSApp.applicationIconImage` can be a placeholder with `.icon` assets.

# Licensing

- PrintScreen is GPL v3.
- When updating libwebp, update `PrintScreen/ThirdPartyNotices.txt` too.
- The icon legend in `PrintScreen/PrintScreen.icon/Assets/legend.svg` is Inter (SIL OFL) converted to outlines. Do not replace it with a font whose license does not allow redistribution in an icon.

# Website and Media

- `public/` is a static site with no build step, hosted on Netlify at <https://printscreen.morishin.me>. Edit the HTML directly, and keep `index.html` and `ja/index.html` in sync.
- Retake media with `tools/media/media.sh`. Use only fictional sample content in screenshots and videos.
- While a window is being recorded, macOS can draw a recording indicator over its traffic light buttons. Take stills of the editor with no recording running.
- The size savings on the site are measured from the sample media on the page. Measure again if the media changes.
- To show a video in the README, upload it with `gh attach` and put the `user-attachments` URL on its own line. A `<video>` tag or a repository file does not play.

# Reference

- `docs/release.md` — Signing, notarization, GitHub Secrets, and the release procedure
