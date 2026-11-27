# Tools

These are maintenance tools for the website and README media. They are not part of the app target.

## Retake screenshots and videos

Requirements: Screen Recording permission for the Debug app, plus `ffmpeg` and `cwebp`.

Each harness is applied to the app temporarily. Commit or stash changes in the app first.

```bash
tools/media/media.sh apply flow
```

Build the app with Xcode, then capture each language. **This terminates any running PrintScreen and briefly takes over the screen.**

```bash
tools/media/media.sh run en /tmp/printscreen-media
tools/media/media.sh run ja /tmp/printscreen-media
```

Remove the harness, then repeat for the next one.

```bash
tools/media/media.sh remove
```

| Harness | Output |
|---|---|
| `flow` | Demo video and editor screenshot |
| `overlay` | Click ripple and pressed keys image |
| `settings` | Settings screenshots |

Encode the results into `public/` and `docs/images/`.

```bash
tools/media/media.sh encode /tmp/printscreen-media
```

`encode` prints the measured file sizes. If they change, update the numbers in `public/index.html` and `public/ja/index.html`.

If the English demo changes, upload `public/assets/shots/en/demo.webm` with `gh attach` and replace the video URL in the README.

## System Settings screenshot in the Shortcuts tab

The Shortcuts tab shows where to turn off the macOS screenshot shortcuts. Retake the image in every app language after a macOS update changes that sheet. The terminal needs Accessibility permission. **This quits System Settings and briefly takes over the screen.**

```bash
tools/media/system_shortcuts.sh          # all languages
tools/media/system_shortcuts.sh en ja    # only some
```

The script opens System Settings in each language with `-AppleLanguages`, so the Mac's language does not need to change. It writes `PrintScreen/Assets.xcassets/SystemScreenshotShortcuts.imageset/shortcuts-<lang>.png`.

## Social preview image

```bash
swift tools/media/og.swift /tmp/printscreen-media/en/flow-editor.png <icon-512.png> public/assets/og.png
```

## App icon legend

Generate the outlined legend from the Inter variable font. The font file is not stored in this repository.

```bash
swift tools/icon/gen_legend.swift <Inter.ttf> PrintScreen/PrintScreen.icon/Assets/legend.svg
```
