#!/usr/bin/env bash
# Makes the App Store screenshots of the sample library: iPhone 6.9" and iPad 13" from the
# Simulator with a clean status bar, and the Mac window on a 1440x900 canvas.
# Usage: scripts/store-screenshots.sh [output directory]   (default: .build/store-screenshots)
# The Mac screenshots need the Screen Recording permission, like scripts/mac-smoke.sh --screenshot.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
OUT="${1:-$ROOT/.build/store-screenshots}"
rm -rf "$OUT"
mkdir -p "$OUT"

xcodegen generate --quiet

udid_of() {
    xcrun simctl list devices available -j | python3 -c '
import json, sys
name = sys.argv[1]
for devices in json.load(sys.stdin)["devices"].values():
    for device in devices:
        if device["name"] == name:
            print(device["udid"]); sys.exit()
sys.exit("No available simulator named " + name)' "$1"
}

ios_screenshots() {
    local device="$1" folder="$2" udid
    udid="$(udid_of "$device")"
    xcrun simctl boot "$udid" 2>/dev/null || true
    xcrun simctl bootstatus "$udid" -b >/dev/null
    local bar=(--time "9:41" --dataNetwork wifi --wifiMode active --wifiBars 3 --batteryState discharging --batteryLevel 100)
    [[ "$device" == iPhone* ]] && bar+=(--cellularMode active --cellularBars 4 --operatorName "")
    xcrun simctl status_bar "$udid" override "${bar[@]}"

    local result="$OUT/$folder.xcresult" status=0
    TEST_RUNNER_VOS_STORE_SCREENSHOTS=1 xcodebuild test -project VocabularyOS.xcodeproj -scheme VocabularyOS \
        -destination "platform=iOS Simulator,id=$udid" -derivedDataPath "$ROOT/.build/DerivedData" \
        -resultBundlePath "$result" -only-testing:VocabularyOSUITests/StoreScreenshotsUITests \
        >"$OUT/$folder.log" 2>&1 || status=$?
    xcrun simctl status_bar "$udid" clear
    if [[ $status -ne 0 ]]; then
        grep -E "error:|\*\* TEST" "$OUT/$folder.log" || true
        echo "Screenshots failed on $device; see $OUT/$folder.log" >&2
        exit $status
    fi

    # Name the exported attachments after the screens.
    xcrun xcresulttool export attachments --path "$result" --output-path "$OUT/$folder.raw" >/dev/null
    python3 - "$OUT/$folder.raw" "$OUT/$folder" <<'EOF'
import json, os, shutil, sys
raw, folder = sys.argv[1], sys.argv[2]
os.makedirs(folder, exist_ok=True)
for test in json.load(open(os.path.join(raw, "manifest.json"))):
    for attachment in test.get("attachments", []):
        name = attachment["suggestedHumanReadableName"].split("_")[0]
        shutil.copy(os.path.join(raw, attachment["exportedFileName"]), os.path.join(folder, name + ".png"))
EOF
    rm -rf "$OUT/$folder.raw" "$result"
    echo "$device: $(ls "$OUT/$folder" | tr '\n' ' ')"
}

ios_screenshots "iPhone 17 Pro Max" "iphone-6.9"
ios_screenshots "iPad Pro 13-inch (M5)" "ipad-13"

# The Mac: each screen's window, in light mode and in front, centered on the App Store's 1440x900
# size. Uses the Debug build from scripts/verify.sh.
APP="$ROOT/.build/DerivedData/Build/Products/Debug/VocabularyOS.app"
[[ -d "$APP" ]] || { echo "error: $APP not found; run scripts/verify.sh first" >&2; exit 1; }
BINARY="$APP/Contents/MacOS/VocabularyOS"
DISPLAY_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$APP/Contents/Info.plist")"
mkdir -p "$OUT/mac"
mac_screen() {
    local name="$1" window=""
    shift
    pkill -f "$BINARY" 2>/dev/null || true
    open -n "$APP" --args -ui-testing YES -vos-preset-profile tr:en,de -vos-seed-library YES -vos-ai-stub YES -vos-store-screenshots YES \
        -AppleLanguages "(en)" -AppleLocale en_US -NSRequiresAquaSystemAppearance YES "$@"
    # Opening the running app brings it to the front: an app started in the background may not open
    # its window, and the window must look active.
    sleep 2
    open "$APP"
    for _ in $(seq 1 30); do
        sleep 0.5
        window="$(swift "$ROOT/scripts/tools/window-id.swift" "$DISPLAY_NAME" 2>/dev/null)" && break
    done
    [[ -n "$window" ]] || { echo "error: no Mac window for $name" >&2; exit 1; }
    open "$APP"
    sleep 2
    # With its shadow, which sets a light window apart from the background.
    screencapture -x -l"$window" "$OUT/mac/$name.window.png"
    pkill -f "$BINARY" 2>/dev/null || true
    swift "$ROOT/scripts/tools/compose-screenshot.swift" "$OUT/mac/$name.window.png" "$OUT/mac/$name.png" 1440 900
    rm -f "$OUT/mac/$name.window.png"
}
mac_screen 1-library -vos-tab library
mac_screen 2-practice -vos-tab practice
mac_screen 3-podcast -vos-tab practice -vos-podcast newest
mac_screen 4-today -vos-tab today
echo "Mac: $(ls "$OUT/mac" | tr '\n' ' ')"
echo "Screenshots: $OUT"
