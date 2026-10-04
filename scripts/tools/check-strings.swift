// Fails when a string in use has no Turkish translation; the app ships in English and Turkish (SPEC).
// Usage: swift scripts/tools/check-strings.swift <catalog.xcstrings>...
import Foundation

let languages = ["tr"]

/// Whether every form of the localization is translated: a single string, or each plural or device
/// variation.
func isTranslated(_ localization: [String: Any]) -> Bool {
    if let unit = localization["stringUnit"] as? [String: Any] {
        return unit["state"] as? String == "translated"
    }
    if let variations = localization["variations"] as? [String: [String: Any]] {
        return variations.values.allSatisfy { cases in
            cases.values.allSatisfy { ($0 as? [String: Any]).map(isTranslated) ?? false }
        }
    }
    return false
}

var problems: [String] = []
var checked = 0
for path in CommandLine.arguments.dropFirst() {
    guard let data = FileManager.default.contents(atPath: path),
          let catalog = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let strings = catalog["strings"] as? [String: [String: Any]]
    else {
        problems.append("\(path): not a string catalog")
        continue
    }
    for (key, entry) in strings.sorted(by: { $0.key < $1.key }) {
        // Strings the code no longer uses, and strings marked as not to translate, need nothing.
        if entry["extractionState"] as? String == "stale" || entry["shouldTranslate"] as? Bool == false { continue }
        checked += 1
        let localizations = entry["localizations"] as? [String: Any] ?? [:]
        for language in languages where !((localizations[language] as? [String: Any]).map(isTranslated) ?? false) {
            problems.append("\(path): \"\(key)\" has no \(language) translation")
        }
    }
}

if problems.isEmpty {
    print("\(checked) strings translated into \(languages.joined(separator: ", "))")
} else {
    problems.forEach { FileHandle.standardError.write(Data("\($0)\n".utf8)) }
    exit(1)
}
