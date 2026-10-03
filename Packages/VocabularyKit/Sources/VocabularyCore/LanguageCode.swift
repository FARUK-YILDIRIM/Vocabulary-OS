import Foundation

/// A language, identified by a BCP-47 tag such as `en`, `de` or `zh-Hans`.
///
/// The value is a normalized string, so it can be stored in SwiftData, the key-value store and export
/// files unchanged, and converted to `Locale.Language` or `NLLanguage` where an Apple API needs one.
public struct LanguageCode: RawRepresentable, Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String

    /// Accepts `language[-Script][-REGION]` (for example `en`, `zh-Hans`, `pt-BR`), ignoring case and
    /// surrounding spaces. Returns `nil` for anything else.
    public init?(rawValue: String) {
        let parts = rawValue.trimmingCharacters(in: .whitespaces)
            .split(separator: "-", omittingEmptySubsequences: false)
        guard let language = parts.first, (2...3).contains(language.count), language.allSatisfy(\.isASCIILetter) else {
            return nil
        }
        var normalized = [language.lowercased()]
        for part in parts.dropFirst() {
            switch part.count {
            case 4 where part.allSatisfy(\.isASCIILetter):
                normalized.append(part.prefix(1).uppercased() + part.dropFirst().lowercased())
            case 2 where part.allSatisfy(\.isASCIILetter):
                normalized.append(part.uppercased())
            case 3 where part.allSatisfy(\.isASCIIDigit):
                normalized.append(String(part))
            default:
                return nil
            }
        }
        self.rawValue = normalized.joined(separator: "-")
    }

    /// For the constants below, which are known to be valid.
    private init(verified rawValue: String) {
        self.rawValue = rawValue
    }

    /// The primary language subtag, e.g. `zh` for `zh-Hans`.
    public var languageSubtag: String {
        String(rawValue.prefix { $0 != "-" })
    }

    /// The English name ("German"); this is what AI prompts use.
    public var englishName: String {
        Locale(identifier: "en").localizedString(forIdentifier: rawValue) ?? rawValue
    }

    /// The language's name in itself ("Deutsch", "Türkçe"), capitalized for display.
    public var autonym: String {
        let locale = Locale(identifier: rawValue)
        guard let name = locale.localizedString(forIdentifier: rawValue), let first = name.first else {
            return englishName
        }
        return String(first).uppercased(with: locale) + name.dropFirst()
    }

    /// The name in the given locale, for UI ("Almanca" when the UI is Turkish).
    public func localizedName(in locale: Locale = .current) -> String {
        locale.localizedString(forIdentifier: rawValue) ?? englishName
    }

    public var locale: Locale { Locale(identifier: rawValue) }

    public var description: String { rawValue }

    public static func < (lhs: LanguageCode, rhs: LanguageCode) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

extension LanguageCode {
    public static let danish = LanguageCode(verified: "da")
    public static let german = LanguageCode(verified: "de")
    public static let english = LanguageCode(verified: "en")
    public static let spanish = LanguageCode(verified: "es")
    public static let french = LanguageCode(verified: "fr")
    public static let italian = LanguageCode(verified: "it")
    public static let japanese = LanguageCode(verified: "ja")
    public static let korean = LanguageCode(verified: "ko")
    public static let norwegianBokmal = LanguageCode(verified: "nb")
    public static let dutch = LanguageCode(verified: "nl")
    public static let polish = LanguageCode(verified: "pl")
    public static let portuguese = LanguageCode(verified: "pt")
    public static let russian = LanguageCode(verified: "ru")
    public static let swedish = LanguageCode(verified: "sv")
    public static let turkish = LanguageCode(verified: "tr")
    public static let ukrainian = LanguageCode(verified: "uk")
    public static let vietnamese = LanguageCode(verified: "vi")
    public static let chineseSimplified = LanguageCode(verified: "zh-Hans")
    public static let chineseTraditional = LanguageCode(verified: "zh-Hant")
}

private extension Character {
    var isASCIILetter: Bool { isASCII && isLetter }
    var isASCIIDigit: Bool { isASCII && isNumber }
}
