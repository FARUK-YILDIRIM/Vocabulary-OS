#!/usr/bin/env bash
# macOS smoke test for the Debug build: the app launches, shows a window, keeps running and logs no
# errors or faults from our subsystem. Visual review of macOS screens stays a manual checkpoint step.
# Usage: scripts/mac-smoke.sh [launch arguments...]   (run scripts/verify.sh first)
# Example: scripts/mac-smoke.sh -vos-preset-profile tr:en,de -vos-tab settings
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/.build/DerivedData/Build/Products/Debug/VocabularyOS.app"
[[ -d "$APP" ]] || { echo "error: $APP not found; run scripts/verify.sh first" >&2; exit 1; }
DISPLAY_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$APP/Contents/Info.plist")"
BINARY="$APP/Contents/MacOS/VocabularyOS"
pkill -f "$BINARY" 2>/dev/null || true

start="$(date '+%Y-%m-%d %H:%M:%S')"
open -n "$APP" --args -ui-testing YES "$@"
sleep 4

windows="$(swift "$ROOT/scripts/tools/count-windows.swift" "$DISPLAY_NAME")"
running=0
pgrep -f "$BINARY" >/dev/null && running=1
pkill -f "$BINARY" 2>/dev/null || true

problems="$(/usr/bin/log show --start "$start" --style compact \
    --predicate 'subsystem == "app.vocabularyos" AND (messageType == error OR messageType == fault)' 2>/dev/null \
    | grep -v '^Timestamp' || true)"

echo "running=$running windows=$windows"
[[ $running -eq 1 ]] || { echo "error: the app exited early" >&2; exit 1; }
[[ $windows -ge 1 ]] || { echo "error: no window appeared" >&2; exit 1; }
if [[ -n "$problems" ]]; then
    echo "$problems" >&2
    echo "error: the app logged errors" >&2
    exit 1
fi
echo "macOS smoke test passed"
