import Foundation
import Testing
@testable import VocabularyCore

@Suite struct LanguageCodeTests {
    @Test(arguments: ["en", "de", "tr", "zh-Hans", "pt-BR", "EN", " de "])
    func acceptsBCP47Identifiers(_ raw: String) {
        #expect(LanguageCode(rawValue: raw) != nil)
    }

    @Test(arguments: ["", "e", "english", "12", "de_DE", "zh-", "-en"])
    func rejectsMalformedIdentifiers(_ raw: String) {
        #expect(LanguageCode(rawValue: raw) == nil)
    }

    @Test func normalizesCase() throws {
        #expect(try #require(LanguageCode(rawValue: "EN")).rawValue == "en")
        #expect(try #require(LanguageCode(rawValue: "zh-hans")).rawValue == "zh-Hans")
        #expect(try #require(LanguageCode(rawValue: "pt-br")).rawValue == "pt-BR")
    }

    @Test func exposesLanguageSubtag() {
        #expect(LanguageCode.chineseSimplified.languageSubtag == "zh")
        #expect(LanguageCode.german.languageSubtag == "de")
    }

    @Test func englishNameIsUsableInPrompts() {
        #expect(LanguageCode.german.englishName == "German")
        #expect(LanguageCode.turkish.englishName == "Turkish")
    }

    @Test func autonymIsTheLanguageNameInItself() {
        #expect(LanguageCode.german.autonym.localizedCaseInsensitiveCompare("Deutsch") == .orderedSame)
        #expect(LanguageCode.turkish.autonym.localizedCaseInsensitiveCompare("Türkçe") == .orderedSame)
    }
}

@Suite struct LanguageCatalogTests {
    @Test func containsTheOnDeviceModelLanguages() {
        // Apple Intelligence languages observed on macOS 26.5 (ADR-003).
        for raw in ["da", "de", "en", "es", "fr", "it", "ja", "ko", "nb", "nl", "pt", "sv", "tr", "vi", "zh-Hans"] {
            let code = LanguageCode(rawValue: raw)
            #expect(code.map(LanguageCatalog.contains) == true, "missing \(raw)")
        }
    }

    @Test func entriesAreUnique() {
        let codes = LanguageCatalog.all.map(\.rawValue)
        #expect(Set(codes).count == codes.count)
    }

    @Test func everyEntryHasNames() {
        for code in LanguageCatalog.all {
            #expect(!code.englishName.isEmpty)
            #expect(!code.autonym.isEmpty)
        }
    }
}

@Suite struct LearnerProfileTests {
    @Test func startsWithNativeAndLearningLanguages() throws {
        let profile = try LearnerProfile(native: .turkish, learning: [.english, .german])
        #expect(profile.native == .turkish)
        #expect(profile.learning == [.english, .german])
        #expect(profile.isReadyToLearn)
    }

    @Test func profileWithoutLearningLanguagesIsNotReady() throws {
        let profile = try LearnerProfile(native: .turkish, learning: [])
        #expect(!profile.isReadyToLearn)
    }

    @Test func addingKeepsOrder() throws {
        var profile = try LearnerProfile(native: .turkish, learning: [.english])
        try profile.addLearning(.german)
        try profile.addLearning(.spanish)
        #expect(profile.learning == [.english, .german, .spanish])
    }

    @Test func rejectsDuplicates() throws {
        var profile = try LearnerProfile(native: .turkish, learning: [.english])
        #expect(throws: LearnerProfileError.duplicate(.english)) {
            try profile.addLearning(.english)
        }
        #expect(throws: LearnerProfileError.duplicate(.german)) {
            try LearnerProfile(native: .turkish, learning: [.german, .german])
        }
    }

    @Test func nativeLanguageCannotBeLearned() throws {
        var profile = try LearnerProfile(native: .turkish, learning: [.english])
        #expect(throws: LearnerProfileError.nativeCannotBeLearning(.turkish)) {
            try profile.addLearning(.turkish)
        }
        #expect(throws: LearnerProfileError.nativeCannotBeLearning(.english)) {
            try LearnerProfile(native: .english, learning: [.english])
        }
    }

    @Test func rejectsLanguagesOutsideTheCatalog() throws {
        var profile = try LearnerProfile(native: .turkish, learning: [])
        let klingon = try #require(LanguageCode(rawValue: "tlh"))
        #expect(throws: LearnerProfileError.unsupported(klingon)) {
            try profile.addLearning(klingon)
        }
    }

    @Test func removingKeepsTheOthersInOrder() throws {
        var profile = try LearnerProfile(native: .turkish, learning: [.english, .german, .spanish])
        profile.removeLearning(.german)
        #expect(profile.learning == [.english, .spanish])
        profile.removeLearning(.french)
        #expect(profile.learning == [.english, .spanish])
    }

    @Test func movingReordersLearningLanguages() throws {
        var profile = try LearnerProfile(native: .turkish, learning: [.english, .german, .spanish])
        profile.moveLearning(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        #expect(profile.learning == [.spanish, .english, .german])
    }

    @Test func changingNativeToALearningLanguageDropsItFromLearning() throws {
        var profile = try LearnerProfile(native: .turkish, learning: [.english, .german])
        try profile.setNative(.german)
        #expect(profile.native == .german)
        #expect(profile.learning == [.english])
    }

    @Test func roundTripsThroughCodable() throws {
        let profile = try LearnerProfile(native: .turkish, learning: [.english, .german])
        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(LearnerProfile.self, from: data)
        #expect(decoded == profile)
    }

    @Test func decodingRejectsInvalidProfiles() {
        let json = Data(#"{"native":"tr","learning":["tr"]}"#.utf8)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(LearnerProfile.self, from: json)
        }
    }
}

@Suite struct NativeLanguageSuggestionTests {
    @Test(arguments: [
        ("tr_TR", "tr"), ("de_AT", "de"), ("en_GB", "en"), ("pt_BR", "pt"),
        ("zh_CN", "zh-Hans"), ("zh_TW", "zh-Hant"), ("zh-Hant_HK", "zh-Hant"),
        ("nb_NO", "nb"), ("no_NO", "nb"), ("nn_NO", "nb"),
        ("ar_SA", "en"), ("xx", "en"),
    ])
    func suggestsTheDeviceLanguageWhenSupported(locale: String, expected: String) {
        let suggestion = LanguageCatalog.suggestedNative(for: Locale(identifier: locale))
        #expect(suggestion.rawValue == expected)
    }
}
