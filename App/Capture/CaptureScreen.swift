import SwiftUI
import VocabularyCore
import VocabularyData
import VocabularyUI

/// The Capture tab: text the learner pastes or types, or a photo of a page (SPEC C5, C6).
struct CaptureScreen: View {
    enum Mode: String, CaseIterable, Identifiable {
        case text, page

        var id: Self { self }

        var title: LocalizedStringKey {
            switch self {
            case .text: "Text"
            case .page: "Page"
            }
        }
    }

    @Environment(AppModel.self) private var app
    @State private var mode = LaunchOptions().captureMode ?? .text
    @State private var textModel: CaptureModel?
    @State private var pageModel: PageCaptureModel?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Capture from", selection: $mode) {
                    ForEach(Mode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 360)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .accessibilityIdentifier("capture-mode")

                switch mode {
                case .text:
                    if let textModel {
                        CaptureFlowView(model: textModel, providerName: app.providerDisplayName)
                    }
                case .page:
                    if let pageModel {
                        PageCaptureView(model: pageModel)
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .navigationTitle("Capture")
        }
        .onAppear(perform: makeModels)
    }

    private func makeModels() {
        if textModel == nil {
            textModel = CaptureModel(
                settings: app.settings,
                destination: LibraryCaptureDestination(repository: app.repository),
                insightService: app.makeInsightService
            )
        }
        if pageModel == nil {
            pageModel = PageCaptureModel(
                settings: app.settings,
                destination: { [repository = app.repository] photo in
                    LibraryCaptureDestination(repository: repository, photo: photo)
                },
                insightService: app.makeInsightService
            )
        }
    }
}

/// Saves captures into the SwiftData library.
struct LibraryCaptureDestination: CaptureDestination {
    let repository: WordRepository
    /// A small copy of the photo the word came from, saved with it (ADR-005).
    var photo: Data?

    func savedTranslation(lemma: String, language: LanguageCode) -> String? {
        (try? repository.existingEntry(lemma: lemma, language: language))?.translation
    }

    func save(_ insight: WordInsight, captureSource: CaptureSource) throws {
        try repository.save(insight, captureSource: captureSource, imageData: photo)
    }
}

#Preview {
    CaptureScreen().environment(AppModel.preview())
}
