/// The languages the app offers, both as native languages and as learning languages (SPEC C1).
///
/// The list covers every language the on-device model supported on macOS 26.5 (ADR-003). It also
/// includes a few widely learned languages that need a cloud provider for AI features. Whether a given
/// capability (on-device AI, text recognition, speech) is available is checked at runtime by the
/// modules that own it, not here.
public enum LanguageCatalog {
    public static let all: [LanguageCode] = [
        .english, .german, .spanish, .french, .italian, .portuguese, .dutch,
        .swedish, .danish, .norwegianBokmal, .turkish, .polish, .russian, .ukrainian,
        .japanese, .korean, .chineseSimplified, .chineseTraditional, .vietnamese,
    ]

    private static let members = Set(all)

    public static func contains(_ code: LanguageCode) -> Bool {
        members.contains(code)
    }
}
