import SwiftUI
import VocabularyCore
import VocabularyData
import VocabularyUI

/// The Capture tab: paste or type text, pick a word, get its meaning, save it (SPEC C5).
struct CaptureScreen: View {
    @Environment(AppModel.self) private var app
    @State private var model: CaptureModel?

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    CaptureFlowView(model: model, providerName: app.providerDisplayName)
                }
            }
            .navigationTitle("Capture")
        }
        .onAppear {
            guard model == nil else { return }
            model = CaptureModel(
                settings: app.settings,
                destination: LibraryCaptureDestination(repository: app.repository),
                insightService: app.makeInsightService
            )
        }
    }
}

/// Saves captures into the SwiftData library.
struct LibraryCaptureDestination: CaptureDestination {
    let repository: WordRepository

    func savedTranslation(lemma: String, language: LanguageCode) -> String? {
        (try? repository.existingEntry(lemma: lemma, language: language))?.translation
    }

    func save(_ insight: WordInsight, captureSource: CaptureSource) throws {
        try repository.save(insight, captureSource: captureSource)
    }
}

#Preview {
    CaptureScreen().environment(AppModel.preview())
}
