#!/bin/bash
# サイトと README の素材を実際のアプリで撮り直すためのスクリプト。使い方は tools/README.md を参照。
set -euo pipefail

ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
cd "$ROOT"
HOOKED=(
  PrintScreen/PrintScreenApp.swift
  PrintScreen/Capture/AreaSelector.swift
  PrintScreen/Editor/EditorWindowController.swift
  PrintScreen/Recording/KeystrokeOverlay.swift
  PrintScreen/Settings/SettingsView.swift
)

usage() {
  echo "usage: $0 apply <flow|overlay|settings> | remove | run <en|ja> <out-dir> | encode <out-dir>" >&2
  exit 2
}

apply() {
  local harness="$1"
  [ -f "tools/media/harness/$harness.swift" ] || usage
  [ ! -e PrintScreen/TempShots.swift ] || { echo "A harness is already applied. Run: $0 remove" >&2; exit 1; }
  git diff --quiet HEAD -- "${HOOKED[@]}" || { echo "Commit or stash changes in the hooked files first." >&2; exit 1; }
  cp "tools/media/harness/$harness.swift" PrintScreen/TempShots.swift
  perl -0pi -e 's/(AppController\.shared\.start\(\)\n)/$1            if let lang = UserDefaults.standard.string(forKey: "TempLang") { DispatchQueue.main.asyncAfter(deadline: .now() + 1) { TempShots.run(lang: lang) } }\n/' PrintScreen/PrintScreenApp.swift
  case "$harness" in
    flow)
      perl -pi -e 's/^private final class SelectionWindow/final class SelectionWindow/; s/^private final class SelectionView/final class SelectionView/; s/^    private var (start|current|mouse): CGPoint\?/    var $1: CGPoint?/' PrintScreen/Capture/AreaSelector.swift
      perl -pi -e 's/private static var openControllers/static var openControllers/; s/^    private let model: EditorModel/    let model: EditorModel/' PrintScreen/Editor/EditorWindowController.swift
      perl -pi -e 's/private let model = KeystrokeModel/let model = KeystrokeModel/' PrintScreen/Recording/KeystrokeOverlay.swift
      ;;
    overlay)
      perl -pi -e 's/private let model = KeystrokeModel/let model = KeystrokeModel/' PrintScreen/Recording/KeystrokeOverlay.swift
      ;;
    settings)
      perl -0pi -e 's/struct SettingsView: View \{\n    var body: some View \{\n        TabView \{/struct SettingsView: View {\n    \@State private var temp = TempShots.state\n    var body: some View {\n        TabView(selection: \$temp.tab) {/; s/(Tab\("General", systemImage: "gearshape")\)/$1, value: 0)/; s/(Tab\("Image", systemImage: "photo")\)/$1, value: 1)/; s/(Tab\("Video", systemImage: "video")\)/$1, value: 2)/; s/(Tab\("Shortcuts", systemImage: "command")\)/$1, value: 3)/; s/(Tab\("About", systemImage: "info\.circle")\)/$1, value: 4)/' PrintScreen/Settings/SettingsView.swift
      ;;
  esac
  echo "Applied $harness. Build with Xcode, then use: $0 run <en|ja> <out-dir>"
}

remove() {
  git checkout -- "${HOOKED[@]}"
  rm -f PrintScreen/TempShots.swift
  echo "Removed the harness. Build again before continuing."
}

run_app() {
  local lang="$1" out="$2"
  mkdir -p "$out"
  local app
  app="$(ls -td "$HOME"/Library/Developer/Xcode/DerivedData/PrintScreen-*/Build/Products/Debug/PrintScreen.app | head -1)"
  # 起動すると、動いている PrintScreen は終了する
  open -n -W "$app" --args -AppleLanguages "($lang)" -TempLang "$lang" -TempOut "$(cd "$out" && pwd)"
}

encode() {
  local out="$1" lang f
  for lang in en ja; do
    local src="$out/$lang" dst="public/assets/shots/$lang"
    [ -d "$src" ] || continue
    if [ -f "$src/flow-raw.mp4" ]; then
      # アプリの WebM 変換と同じ設定
      ffmpeg -y -hide_banner -loglevel error -i "$src/flow-raw.mp4" -c:v libvpx-vp9 -crf 36 -b:v 0 -deadline good -cpu-used 4 -row-mt 1 -pix_fmt yuv420p -an "$dst/demo.webm"
      ffmpeg -y -hide_banner -loglevel error -i "$src/flow-raw.mp4" -vf scale=1280:-2 -r 30 -c:v libx264 -crf 25 -preset slow -pix_fmt yuv420p -movflags +faststart -an "$dst/demo.mp4"
      ffmpeg -y -hide_banner -loglevel error -ss 9.5 -i "$src/flow-raw.mp4" -frames:v 1 "$src/flow-poster.png"
      cwebp -quiet -q 80 -resize 1280 0 "$src/flow-poster.png" -o "$dst/demo-poster.webp"
      echo "$lang video: h264=$(stat -f%z "$src/flow-raw.mp4") webm=$(stat -f%z "$dst/demo.webm")"
    fi
    if [ -f "$src/flow-editor.png" ]; then
      cwebp -quiet -q 84 -alpha_q 90 -resize 1800 0 "$src/flow-editor.png" -o "$dst/editor.webp"
      cwebp -quiet -q 90 "$src/flow-editor.png" -o "$src/flow-editor-q90.webp"
      echo "$lang image: png=$(stat -f%z "$src/flow-editor.png") webp=$(stat -f%z "$src/flow-editor-q90.webp")"
      [ "$lang" != en ] || cp "$dst/editor.webp" docs/images/editor.webp
    fi
    if [ -f "$src/overlay.png" ]; then
      swift tools/media/overlay_cursor.swift "$src/overlay.png" "$src/overlay-cursor.png"
      cwebp -quiet -q 86 "$src/overlay-cursor.png" -o "$dst/overlay.webp"
    fi
    f="$src/settings-video.png"
    if [ "$lang" = en ] && [ -f "$f" ]; then
      cwebp -quiet -q 84 -alpha_q 90 -resize 900 0 "$f" -o docs/images/settings.webp
    fi
  done
}

case "${1:-}" in
  apply) [ $# -eq 2 ] || usage; apply "$2" ;;
  remove) [ $# -eq 1 ] || usage; remove ;;
  run) [ $# -eq 3 ] || usage; run_app "$2" "$3" ;;
  encode) [ $# -eq 2 ] || usage; encode "$2" ;;
  *) usage ;;
esac
