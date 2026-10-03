#!/usr/bin/env bash
# Runs the XCUITests on an iOS Simulator and exports their screenshots for review.
# Usage: scripts/ui-test.sh [TestClass[/testMethod]]
# Set VOS_UI_TEST_DEVICE to pick another simulator (default: iPhone 17).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DEVICE="${VOS_UI_TEST_DEVICE:-iPhone 17}"
OUT="$ROOT/.build/ui-tests"
RESULT="$OUT/UITests.xcresult"
rm -rf "$OUT"
mkdir -p "$OUT"

xcodegen generate --quiet

only=()
if [[ $# -gt 0 ]]; then
    only=(-only-testing:"VocabularyOSUITests/$1")
fi

status=0
xcodebuild test -project VocabularyOS.xcodeproj -scheme VocabularyOS \
    -destination "platform=iOS Simulator,name=$DEVICE" \
    -derivedDataPath "$ROOT/.build/DerivedData" \
    -resultBundlePath "$RESULT" "${only[@]+"${only[@]}"}" >"$OUT/xcodebuild.log" 2>&1 || status=$?

grep -E "Test Case .*(passed|failed)|error:|\*\* TEST" "$OUT/xcodebuild.log" || true
xcrun xcresulttool export attachments --path "$RESULT" --output-path "$OUT/screenshots" >/dev/null 2>&1 || true
echo "Screenshots: $OUT/screenshots"
exit $status
