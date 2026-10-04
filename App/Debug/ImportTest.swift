#if DEBUG
import Foundation
import VocabularyCore
import VocabularyData

/// Opens a sample word list file at launch (`-vos-import-sample YES`), through the same path as a
/// file opened from another app, so UI tests can import without a file manager (Debug builds only).
enum ImportTest {
    static func openSampleIfRequested(app: AppModel, options: LaunchOptions = LaunchOptions()) {
        guard options.importsSample else { return }
        let source = InsightSource(providerID: AIProviderSelection.onDevice.providerID)
        func word(_ term: String, _ translation: String, _ sentence: String) -> WordListDocument.Word {
            WordListDocument.Word(WordInsight(
                term: term, lemma: term, partOfSpeech: .noun, language: .german, nativeLanguage: .turkish,
                context: sentence, translation: translation, meaning: "\(translation.capitalized).", source: source
            ))
        }
        // Schlüssel is in the sample library already.
        let document = WordListDocument(name: "Reisen", language: .german, words: [
            word("Bahnhof", "istasyon", "Der Zug fährt um acht vom Bahnhof ab."),
            word("Fahrkarte", "bilet", "Ich kaufe eine Fahrkarte nach Berlin."),
            word("Schlüssel", "anahtar", "Ich habe meinen Schlüssel im Büro vergessen."),
        ])
        let url = FileManager.default.temporaryDirectory.appending(path: "Reisen.\(WordListDocument.fileExtension)")
        do {
            try document.data().write(to: url)
            app.open(url)
        } catch {
            app.navigation.importError = error.localizedDescription
        }
    }
}
#endif
