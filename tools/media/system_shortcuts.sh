#!/bin/bash
# Captures the Screenshots page of System Settings › Keyboard › Keyboard Shortcuts in each language
# and writes the annotated images into the app's asset catalog.
# Usage: tools/media/system_shortcuts.sh [lang ...]   (default: all app languages)
# Needs Accessibility permission for the terminal, and quits System Settings while it runs.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ASSET="$ROOT/PrintScreen/Assets.xcassets/SystemScreenshotShortcuts.imageset"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
LANGS=("$@")
[ ${#LANGS[@]} -eq 0 ] && LANGS=(en ja zh-Hans zh-Hant ko es de fr)

PATH_SHEET='sheet 1 of window 1'
PATH_OUTLINE="outline 1 of scroll area 1 of group 1 of scroll area 1 of group 2 of splitter group 1 of group 1 of $PATH_SHEET"

for lang in "${LANGS[@]}"; do
  echo "== $lang"
  osascript -e 'quit app "System Settings"' >/dev/null 2>&1 || true
  sleep 1.5
  open -n -a "System Settings" --args -AppleLanguages "($lang)" -AppleLocale "${lang/-/_}"
  sleep 2
  open "x-apple.systempreferences:com.apple.Keyboard-Settings.extension"
  sleep 3
  # Returns: sheetX sheetY sheetW sheetH, then x y w h of each checkbox
  geometry=$(osascript <<EOF
tell application "System Events" to tell process "System Settings"
  set frontmost to true
  click button 1 of group 2 of scroll area 1 of group 1 of group 3 of splitter group 1 of group 1 of window 1
  delay 1.5
  -- Row 7 of the sidebar is Screenshots
  select row 7 of outline 1 of scroll area 1 of group 1 of splitter group 1 of group 1 of $PATH_SHEET
  delay 1
  set s to $PATH_SHEET
  set {px, py} to position of s
  set {w, h} to size of s
  set out to (px as text) & " " & (py as text) & " " & (w as text) & " " & (h as text)
  repeat with r in rows of $PATH_OUTLINE
    set c to checkbox 1 of UI element 1 of r
    set {px, py} to position of c
    set {w, h} to size of c
    set out to out & " " & (px as text) & " " & (py as text) & " " & (w as text) & " " & (h as text)
  end repeat
  return out
end tell
EOF
)
  read -r sx sy sw sh rest <<<"$geometry"
  screencapture -x -o -R"$sx,$sy,$sw,$sh" "$WORK/$lang.png"
  # shellcheck disable=SC2086
  swift "$ROOT/tools/media/annotate_shortcuts.swift" "$WORK/$lang.png" "$ASSET/shortcuts-$lang.png" $geometry
done
osascript -e 'quit app "System Settings"' >/dev/null 2>&1 || true
