#!/usr/bin/env bash
# The quality gate run before every commit (see CLAUDE.md → Definition of Done):
#   1. regenerate the Xcode project from project.yml
#   2. run the VocabularyKit package tests on the Mac host
#   3. build the app for the iOS Simulator and for macOS
#   4. sync the String Catalogs with both builds, and check every string has a Turkish translation
# Fails on any error, and on any compiler warning that points at project sources.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

LOG_DIR="$ROOT/.build/verify"
DERIVED_DATA="$ROOT/.build/DerivedData"
mkdir -p "$LOG_DIR"

step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
fail() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# Only warnings from our own sources count; SDK and toolchain noise is ignored.
check_warnings() {
    local log="$1" label="$2" found
    found="$(grep -E "^($ROOT/)?(App|Extensions|UITests|Packages/VocabularyKit/(Sources|Tests))/[^:]+:[0-9]+:[0-9]+: warning:" "$log" | sort -u || true)"
    if [[ -n "$found" ]]; then
        printf '%s\n' "$found" >&2
        fail "$label produced warnings in project code"
    fi
}

command -v xcodegen >/dev/null || fail "xcodegen is not installed (brew install xcodegen)"

step "Generate VocabularyOS.xcodeproj"
xcodegen generate --quiet

step "Package tests"
if ! swift test --package-path Packages/VocabularyKit >"$LOG_DIR/swift-test.log" 2>&1; then
    tail -n 60 "$LOG_DIR/swift-test.log" >&2
    fail "package tests failed (full log: $LOG_DIR/swift-test.log)"
fi
grep -E "Test run with [0-9]+ tests|Executed [0-9]+ tests?," "$LOG_DIR/swift-test.log" | tail -n 2 || true
check_warnings "$LOG_DIR/swift-test.log" "swift test"

build_app() {
    local name="$1" destination="$2"
    step "Build app for $name"
    if ! xcodebuild -project VocabularyOS.xcodeproj -scheme VocabularyOS \
        -destination "$destination" -derivedDataPath "$DERIVED_DATA" \
        build >"$LOG_DIR/build-$name.log" 2>&1; then
        grep -E "error:|BUILD FAILED" "$LOG_DIR/build-$name.log" | head -n 40 >&2
        fail "$name build failed (full log: $LOG_DIR/build-$name.log)"
    fi
    check_warnings "$LOG_DIR/build-$name.log" "$name build"
    echo "BUILD SUCCEEDED"
}

build_app iOS-Simulator 'generic/platform=iOS Simulator'
build_app macOS 'platform=macOS'

step "String catalogs"
# New strings from both builds go into the catalogs; each needs a Turkish translation.
scripts/strings.sh sync "$DERIVED_DATA"
scripts/strings.sh check || fail "translate the strings above (scripts/strings.sh)"

step "All checks passed"
