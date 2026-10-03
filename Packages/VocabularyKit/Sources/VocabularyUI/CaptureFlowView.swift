import SwiftUI
import VocabularyAI
import VocabularyCore

/// The capture flow UI, shared by the app and the Share extension (SPEC C5).
public struct CaptureFlowView: View {
    @Bindable private var model: CaptureModel
    private let providerName: String
    @State private var isEditing: Bool

    public init(model: CaptureModel, providerName: String) {
        self.model = model
        self.providerName = providerName
        _isEditing = State(initialValue: model.tokens.tokens.isEmpty)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                textSection
                if model.term != nil {
                    Divider()
                    selectionSection
                }
                resultSection
            }
            .padding()
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .animation(.default, value: model.phase)
    }

    // MARK: Text

    @ViewBuilder
    private var textSection: some View {
        if isEditing {
            VStack(alignment: .leading, spacing: 10) {
                TextEditor(text: $model.text)
                    .font(.title3)
                    .frame(minHeight: 140)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
                    .overlay(alignment: .topLeading) {
                        if model.text.isEmpty {
                            Text("Paste or type the sentence where you found the word.", bundle: .module)
                                .font(.title3)
                                .foregroundStyle(.tertiary)
                                .padding(16)
                                .allowsHitTesting(false)
                        }
                    }
                    .accessibilityIdentifier("capture-input")
                HStack {
                    PasteButton(payloadType: String.self) { strings in
                        model.text = strings.first ?? ""
                        isEditing = model.tokens.tokens.isEmpty
                    }
                    .labelStyle(.titleAndIcon)
                    Spacer()
                    Button {
                        isEditing = false
                    } label: {
                        Text("Select a Word", bundle: .module)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.tokens.tokens.isEmpty)
                    .accessibilityIdentifier("capture-done-editing")
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Tap a word. Tap a second word to select a phrase.", bundle: .module)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        isEditing = true
                    } label: {
                        Text("Edit Text", bundle: .module)
                    }
                    .font(.footnote)
                }
                SelectableTextView(text: model.tokens, selection: model.selection) { index in
                    model.tap(tokenAt: index)
                }
            }
        }
    }

    // MARK: Selection

    @ViewBuilder
    private var selectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let term = model.term {
                Text(verbatim: term)
                    .font(.title2.bold())
                    .accessibilityIdentifier("capture-term")
            }
            if let newLanguage = model.suggestedNewLanguage {
                VStack(alignment: .leading, spacing: 8) {
                    Text("This looks like \(newLanguage.localizedName()), which isn't one of your languages.", bundle: .module)
                        .font(.callout)
                    Button {
                        model.addToLearningLanguages(newLanguage)
                    } label: {
                        Text("Add \(newLanguage.localizedName())", bundle: .module)
                    }
                    .buttonStyle(.bordered)
                }
            }
            LanguageChips(choices: model.languageChoices, selection: $model.language)
            switch model.phase {
            case .explaining:
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Explaining…", bundle: .module).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityIdentifier("capture-explaining")
            case .explained, .saved:
                EmptyView()
            default:
                Button {
                    model.explain()
                } label: {
                    Text("Explain", bundle: .module).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!model.canExplain)
                .accessibilityIdentifier("capture-explain")
            }
        }
    }

    // MARK: Result

    @ViewBuilder
    private var resultSection: some View {
        if case .failed(let error) = model.phase {
            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text(verbatim: error.localizedDescription)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                Button {
                    model.explain()
                } label: {
                    Text("Try Again", bundle: .module)
                }
                .buttonStyle(.bordered)
            }
            .accessibilityIdentifier("capture-error")
        }

        if let insight = model.insight {
            VStack(alignment: .leading, spacing: 16) {
                InsightCard(insight: insight, providerName: providerName)
                if insight.examples.isEmpty {
                    Button {
                        Task { await model.loadExamples() }
                    } label: {
                        HStack {
                            if model.isLoadingExamples { ProgressView().controlSize(.small) }
                            Text("Show Examples", bundle: .module)
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.isLoadingExamples)
                }
                if let duplicate = model.duplicateTranslation, model.phase != .saved {
                    Text("Already in your library as “\(duplicate)”.", bundle: .module)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if let message = model.saveErrorMessage {
                    Text(verbatim: message).foregroundStyle(.red)
                }
                if model.phase == .saved {
                    Label {
                        Text("Saved to your library", bundle: .module)
                    } icon: {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                    .accessibilityIdentifier("capture-saved")
                    Button {
                        model.reset()
                        isEditing = true
                    } label: {
                        Text("Capture Another Word", bundle: .module)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button {
                        model.save()
                    } label: {
                        Text("Save to Library", bundle: .module).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityIdentifier("capture-save")
                }
            }
        }
    }
}

/// One-tap language choice for a captured term (ADR-004).
struct LanguageChips: View {
    let choices: [LanguageCode]
    @Binding var selection: LanguageCode?

    var body: some View {
        FlowLayout(lineSpacing: 8) {
            ForEach(choices, id: \.self) { code in
                let isSelected = code == selection
                Button {
                    selection = code
                } label: {
                    Text(verbatim: code.localizedName())
                }
                .buttonStyle(.bordered)
                .tint(isSelected ? .accentColor : .secondary)
                .overlay {
                    if isSelected {
                        Capsule().strokeBorder(Color.accentColor, lineWidth: 1.5)
                    }
                }
                .padding(.trailing, 6)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier("language-chip-\(code.rawValue)")
            }
        }
    }
}
