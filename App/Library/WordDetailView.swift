import SwiftUI
import VocabularyAI
import VocabularyCore
import VocabularyData
import VocabularyUI

/// Everything about one saved word, with edit, favorite, regenerate and delete (SPEC C4).
struct WordDetailView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Bindable var entry: VocabularyEntry
    @State private var isEditing = false
    @State private var isChoosingLists = false
    @State private var isConfirmingDelete = false
    @State private var isRegenerating = false
    @State private var regenerateError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let imageData = entry.imageData, let image = Image(imageData: imageData) {
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 240)
                        .clipShape(.rect(cornerRadius: 12))
                        .accessibilityLabel(Text("Captured photo"))
                }

                InsightCard(insight: entry.insight, providerName: app.providerName(for: entry.insightProviderID)) {
                    if let language = entry.language {
                        app.speech.speak(entry.term, language: language)
                    }
                }

                if isRegenerating {
                    ProgressView { Text("Explaining again…") }
                }
                if let regenerateError {
                    Label(regenerateError, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }

                ReviewSummary(entry: entry)
            }
            .padding()
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(entry.term)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    entry.isFavorite.toggle()
                } label: {
                    Label(entry.isFavorite ? "Remove Favorite" : "Favorite", systemImage: entry.isFavorite ? "star.fill" : "star")
                }
                .accessibilityIdentifier("detail-favorite")
                Menu {
                    Button("Edit", systemImage: "pencil") { isEditing = true }
                    Button("Explain Again", systemImage: "arrow.clockwise") {
                        Task { await regenerate() }
                    }
                    .disabled(isRegenerating)
                    Button("Lists…", systemImage: "list.bullet") { isChoosingLists = true }
                    Divider()
                    Button("Delete", systemImage: "trash", role: .destructive) { isConfirmingDelete = true }
                        .disabled(isRegenerating)
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
                .accessibilityIdentifier("detail-more")
            }
        }
        .sheet(isPresented: $isEditing) {
            WordEditView(entry: entry)
        }
        .sheet(isPresented: $isChoosingLists) {
            WordListsView(entry: entry)
        }
        .confirmationDialog(
            String(localized: "Delete “\(entry.term)”?"),
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                try? app.repository.delete(entry)
                dismiss()
            }
        } message: {
            Text("Its review history is deleted too.")
        }
    }

    private func regenerate() async {
        guard let native = app.settings.profile?.native, let language = entry.language else { return }
        isRegenerating = true
        regenerateError = nil
        defer { isRegenerating = false }
        let id = entry.id
        let service = app.makeInsightService()
        do throws(AIError) {
            // An object's word is named again, keeping its article and dictionary form apart.
            let insight = entry.captureSource == .object
                ? try await ObjectNamingService(service).name(ObjectNamingRequest(label: entry.lemma, language: language, nativeLanguage: native))
                : try await service.insight(for: InsightRequest(term: entry.term, sentence: entry.context, language: language, nativeLanguage: native))
            // The word may have been deleted meanwhile, here or on another device.
            guard let current = try? app.repository.entry(id: id) else { return }
            try? app.repository.update(current, with: insight)
        } catch {
            regenerateError = error.localizedDescription
        }
    }
}

private struct ReviewSummary: View {
    let entry: VocabularyEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Review").font(.headline)
            if entry.isNew {
                Text("Not reviewed yet. It will appear in today's reviews.")
            } else {
                Text("Next review \(entry.dueAt.formatted(date: .abbreviated, time: .omitted)) · every \(entry.intervalDays) days")
                if entry.lapses > 0 {
                    Text("Forgotten \(entry.lapses) times").foregroundStyle(.secondary)
                }
            }
            Text("Saved \(entry.createdAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
