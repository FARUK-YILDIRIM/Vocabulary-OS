import CoreTransferable
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import VocabularyCore
import VocabularyData

extension UTType {
    /// A `.vocabularyos` word list (SPEC C11), declared in Info.plist.
    nonisolated static let vocabularyOSWordList = UTType(exportedAs: "app.vocabularyos.wordlist", conformingTo: .json)
}

/// Which words a file holds: a list's, or all of a language's.
enum WordListContents: Hashable, Sendable {
    case list(UUID)
    case language(LanguageCode)

    /// The words, read when the file is written.
    @MainActor
    func document(in container: ModelContainer) throws -> WordListDocument {
        let repository = WordRepository(container: container)
        switch self {
        case .list(let id):
            var descriptor = FetchDescriptor<WordList>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            guard let list = try repository.context.fetch(descriptor).first else { throw CocoaError(.fileNoSuchFile) }
            return repository.document(for: list)
        case .language(let language):
            return try repository.document(language: language)
        }
    }
}

/// Words shared as a `.vocabularyos` file, which Vocabulary-OS opens to import them (SPEC C11).
struct WordListExport: Transferable {
    let contents: WordListContents
    /// The file name, without its extension.
    let name: String
    let container: ModelContainer

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .vocabularyOSWordList) { export in
            try await export.contents.document(in: export.container).data()
        }
        .suggestedFileName { "\($0.name).\(WordListDocument.fileExtension)" }
    }
}

/// Words exported as CSV, for spreadsheets and Anki (SPEC C11).
struct WordListCSVExport: Transferable {
    let contents: WordListContents
    let name: String
    let container: ModelContainer

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { export in
            let words = try await export.contents.document(in: export.container).words
            return Data(CSVExporter.csv(for: words).utf8)
        }
        .suggestedFileName { "\($0.name).csv" }
    }
}

/// A word list file the learner opened, waiting for them to confirm (SPEC C11).
struct PendingImport: Identifiable {
    let id = UUID()
    let document: WordListDocument
    let preview: WordListImport
}

extension AppModel {
    /// Reads a word list file the learner opened or picked, and asks them to confirm the import.
    func openWordList(at url: URL) {
        let isScoped = url.startAccessingSecurityScopedResource()
        defer {
            if isScoped { url.stopAccessingSecurityScopedResource() }
            removeInboxCopy(of: url)
        }
        do {
            let document = try WordListDocument.read(contentsOf: url)
            navigation.pendingImport = PendingImport(document: document, preview: try repository.preview(document))
        } catch WordListDocument.ReadError.newerVersion {
            navigation.importError = String(localized: "This word list was made by a newer version of Vocabulary-OS. Update the app to open it.")
        } catch WordListDocument.ReadError.notAWordList {
            navigation.importError = String(localized: "This file isn't a Vocabulary-OS word list.")
        } catch WordListDocument.ReadError.tooLarge {
            navigation.importError = String(localized: "This word list is too large to open.")
        } catch {
            navigation.importError = error.localizedDescription
        }
    }

    /// Some apps hand files over as copies in the app's Inbox; once read, a copy isn't needed.
    private func removeInboxCopy(of url: URL) {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let inbox = documents.appending(path: "Inbox", directoryHint: .isDirectory).standardizedFileURL.path
        if url.standardizedFileURL.path.hasPrefix(inbox) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

/// Confirms an import: what it adds and what it changes (SPEC C11).
struct ImportView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let pending: PendingImport
    @State private var result: WordListImport?
    @State private var errorMessage: String?

    private var language: LanguageCode { pending.document.language }
    private var profile: LearnerProfile? { app.settings.profile }
    private var isNativeLanguage: Bool { profile?.native == language }
    private var addsLanguage: Bool { profile?.learning.contains(language) == false && !isNativeLanguage }

    var body: some View {
        NavigationStack {
            Form {
                if let result {
                    Section {
                        Text("^[\(result.newWords) word](inflect: true) added.")
                            .accessibilityIdentifier("import-result")
                        if result.existingWords > 0 {
                            Text("^[\(result.existingWords) word](inflect: true) you already had stayed as they were.")
                        }
                    }
                } else {
                    Section {
                        LabeledContent("Language", value: language.localizedName())
                        LabeledContent("New words", value: pending.preview.newWords, format: .number)
                            .accessibilityIdentifier("import-new")
                        LabeledContent("Already saved", value: pending.preview.existingWords, format: .number)
                            .accessibilityIdentifier("import-existing")
                    } footer: {
                        Text("Saved words stay as they are. Review history isn't part of a word list, so every new word starts fresh.")
                    }
                    if let name = pending.document.name {
                        Section {
                            Text("The words go into your list “\(name)”, which is created if you don't have it.")
                        }
                    }
                    if isNativeLanguage {
                        Section {
                            Text("These words are in your native language, so they can't be studied here.")
                                .foregroundStyle(.red)
                        }
                    } else if addsLanguage {
                        Section {
                            Text("\(language.localizedName()) will be added to your learning languages.")
                        }
                    }
                    if let native = pending.document.words.first?.nativeLanguage, let profile, native != profile.native {
                        Section {
                            Text("Their explanations are in \(native.localizedName()).")
                        }
                    }
                }
                if let errorMessage {
                    Section {
                        Text(verbatim: errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                if result == nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Import", action: importWords)
                            .disabled(isNativeLanguage || pending.document.words.isEmpty)
                            .accessibilityIdentifier("import-confirm")
                    }
                } else {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                            .accessibilityIdentifier("import-done")
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 360)
        #endif
    }

    private var title: String {
        if let name = pending.document.name {
            return String(localized: "Import “\(name)”")
        }
        return String(localized: "Import \(language.localizedName()) Words")
    }

    private func importWords() {
        do {
            if addsLanguage, var profile {
                try profile.addLearning(language)
                app.settings.profile = profile
            }
            result = try app.repository.importWords(from: pending.document)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
