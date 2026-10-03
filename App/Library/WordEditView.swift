import SwiftUI
import VocabularyCore
import VocabularyData

/// Lets the learner correct any generated field; review state is kept (SPEC C4).
struct WordEditView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let entry: VocabularyEntry

    @State private var term: String
    @State private var lemma: String
    @State private var translation: String
    @State private var meaning: String
    @State private var context: String

    init(entry: VocabularyEntry) {
        self.entry = entry
        _term = State(initialValue: entry.term)
        _lemma = State(initialValue: entry.lemma)
        _translation = State(initialValue: entry.translation)
        _meaning = State(initialValue: entry.meaning)
        _context = State(initialValue: entry.context ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Word") {
                    TextField("Word", text: $term)
                        .accessibilityIdentifier("edit-term")
                    TextField("Dictionary form", text: $lemma)
                }
                Section("Meaning") {
                    TextField("Translation", text: $translation)
                        .accessibilityIdentifier("edit-translation")
                    TextField("Definition", text: $meaning, axis: .vertical)
                }
                Section("Sentence") {
                    TextField("Sentence", text: $context, axis: .vertical)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Edit Word")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(trimmed(term).isEmpty || trimmed(translation).isEmpty)
                        .accessibilityIdentifier("edit-save")
                }
            }
        }
        .frame(minWidth: 380, minHeight: 420)
    }

    private func save() {
        var insight = entry.insight
        insight.term = trimmed(term)
        insight.lemma = trimmed(lemma).isEmpty ? insight.term : trimmed(lemma)
        insight.translation = trimmed(translation)
        insight.meaning = trimmed(meaning)
        insight.context = trimmed(context).isEmpty ? nil : trimmed(context)
        try? app.repository.update(entry, with: insight)
        dismiss()
    }

    private func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
