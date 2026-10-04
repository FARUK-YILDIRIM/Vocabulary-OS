#!/usr/bin/env bash
# Keeps the String Catalogs in step with the code; the app ships in English and Turkish (SPEC).
#   scripts/strings.sh sync [DERIVED_DATA]  adds the strings a build found to each catalog and marks
#                                           unused ones stale (default: .build/DerivedData, which
#                                           scripts/verify.sh builds for iOS and macOS)
#   scripts/strings.sh check                fails when a string in use has no Turkish translation
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Each catalog filled from code, and the build target whose code fills it. InfoPlist and
# ServicesMenu catalogs are written by hand.
CATALOGS=(
    "App/Resources/Localizable.xcstrings:VocabularyOS"
    "Extensions/ShareExtension/Localizable.xcstrings:VocabularyOSShare"
    "Packages/VocabularyKit/Sources/VocabularyAI/Resources/Localizable.xcstrings:VocabularyAI"
    "Packages/VocabularyKit/Sources/VocabularyCapture/Resources/Localizable.xcstrings:VocabularyCapture"
    "Packages/VocabularyKit/Sources/VocabularyCore/Resources/Localizable.xcstrings:VocabularyCore"
    "Packages/VocabularyKit/Sources/VocabularyUI/Resources/Localizable.xcstrings:VocabularyUI"
)

sync_catalogs() {
    local intermediates="${1:-.build/DerivedData}/Build/Intermediates.noindex"
    for pair in "${CATALOGS[@]}"; do
        local catalog="${pair%%:*}" target="${pair##*:}" files=()
        while IFS= read -r -d '' file; do
            files+=("$file")
        done < <(find "$intermediates" -path "*/$target.build/Objects-normal/*" -name '*.stringsdata' -print0 2>/dev/null)
        if [[ ${#files[@]} -eq 0 ]]; then
            echo "error: no strings found for $target in $intermediates; build first" >&2
            exit 1
        fi
        xcrun xcstringstool sync "$catalog" --stringsdata "${files[@]}"
    done
}

case "${1:-}" in
    sync) sync_catalogs "${2:-}" ;;
    check) swift scripts/tools/check-strings.swift App/Resources/*.xcstrings Extensions/ShareExtension/*.xcstrings \
        Packages/VocabularyKit/Sources/*/Resources/*.xcstrings ;;
    *) echo "usage: scripts/strings.sh sync [DERIVED_DATA] | check" >&2; exit 2 ;;
esac
