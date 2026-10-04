#!/usr/bin/env bash
# macOS smoke test for the Debug build: the app launches, shows a window, keeps running and logs no
# errors or faults from our subsystem. Visual review of macOS screens stays a manual checkpoint step.
#
# Usage:   scripts/mac-smoke.sh [--self-test [capture|page] | --services] [launch arguments...]
#          (run scripts/verify.sh first)
# Example: scripts/mac-smoke.sh -vos-preset-profile tr:en,de -vos-tab settings
# --self-test captures a word with the real on-device model inside the app (App/Debug/SelfTest.swift),
# which the iOS Simulator can't do because it has no model assets: from a sentence (capture, the
# default) or from a generated book page (page).
# --services sends text through Services → "Capture in Vocabulary-OS" and expects the capture window.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/.build/DerivedData/Build/Products/Debug/VocabularyOS.app"
[[ -d "$APP" ]] || { echo "error: $APP not found; run scripts/verify.sh first" >&2; exit 1; }
DISPLAY_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$APP/Contents/Info.plist")"
BINARY="$APP/Contents/MacOS/VocabularyOS"

self_test=0
self_test_mode=capture
services=0
if [[ "${1:-}" == "--self-test" ]]; then
    self_test=1
    shift
    if [[ "${1:-}" == "capture" || "${1:-}" == "page" ]]; then
        self_test_mode="$1"
        shift
    fi
elif [[ "${1:-}" == "--services" ]]; then
    services=1
    shift
fi

pkill -f "$BINARY" 2>/dev/null || true
start="$(date '+%Y-%m-%d %H:%M:%S')"

# Errors and faults our subsystem logged since this run started.
logged_problems() {
    /usr/bin/log show --start "$start" --style compact \
        --predicate 'subsystem == "app.vocabularyos" AND (messageType == error OR messageType == fault)' 2>/dev/null \
        | grep -v '^Timestamp' || true
}

if [[ $self_test -eq 1 ]]; then
    open -n "$APP" --args -ui-testing YES -vos-preset-profile tr:en,de -vos-self-test "$self_test_mode" "$@"
    for _ in $(seq 1 60); do
        pgrep -f "$BINARY" >/dev/null || break
        sleep 0.5
    done
    pkill -f "$BINARY" 2>/dev/null || true
    result="$(/usr/bin/log show --start "$start" --style compact \
        --predicate 'subsystem == "app.vocabularyos" AND category == "selftest"' 2>/dev/null | grep -v '^Timestamp' || true)"
    echo "$result"
    if grep -q "Self-test $self_test_mode passed" <<<"$result"; then
        echo "macOS self-test passed"
        exit 0
    fi
    echo "error: the self-test did not pass" >&2
    exit 1
fi

if [[ $services -eq 1 ]]; then
    open -n "$APP" --args -ui-testing YES -vos-preset-profile tr:en,de "$@"
    sleep 4
    # Make the Services registry pick up this build's NSServices entry (a debugging tool, see pbs(8)).
    /System/Library/CoreServices/pbs -update
    performed="$(swift "$ROOT/scripts/tools/perform-service.swift" "Capture in Vocabulary-OS" \
        "This website uses cookies for tracking.")"
    windows="$(swift "$ROOT/scripts/tools/count-windows.swift" "$DISPLAY_NAME")"
    pkill -f "$BINARY" 2>/dev/null || true
    problems="$(logged_problems)"
    echo "service=$performed windows=$windows"
    [[ "$performed" == "performed" ]] || { echo "error: the service was not performed" >&2; exit 1; }
    [[ $windows -ge 2 ]] || { echo "error: the capture window did not open" >&2; exit 1; }
    [[ -z "$problems" ]] || { echo "$problems" >&2; echo "error: the app logged errors" >&2; exit 1; }
    echo "macOS Services check passed"
    exit 0
fi

open -n "$APP" --args -ui-testing YES "$@"
sleep 4

windows="$(swift "$ROOT/scripts/tools/count-windows.swift" "$DISPLAY_NAME")"
running=0
pgrep -f "$BINARY" >/dev/null && running=1
pkill -f "$BINARY" 2>/dev/null || true

problems="$(logged_problems)"

echo "running=$running windows=$windows"
[[ $running -eq 1 ]] || { echo "error: the app exited early" >&2; exit 1; }
[[ $windows -ge 1 ]] || { echo "error: no window appeared" >&2; exit 1; }
if [[ -n "$problems" ]]; then
    echo "$problems" >&2
    echo "error: the app logged errors" >&2
    exit 1
fi
echo "macOS smoke test passed"
