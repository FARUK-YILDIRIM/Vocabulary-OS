import SwiftData
import SwiftUI
import VocabularyCore
import VocabularyData

/// Where the Library navigates besides a word.
enum LibraryRoute: Hashable {
    case lists(LanguageCode)
    case list(WordList)
}

/// A language's named lists (SPEC C4): create, open and delete them. Deleting a list keeps its words.
struct ListsView: View {
    let language: LanguageCode
    @Environment(AppModel.self) private var app
    @Query private var lists: [WordList]
    @State private var isNaming = false
    @State private var newName = ""
    @State private var pendingDeletion: WordList?

    init(language: LanguageCode) {
        self.language = language
        let code = language.rawValue
        _lists = Query(filter: #Predicate<WordList> { $0.languageCode == code }, sort: \.name)
    }

    var body: some View {
        List {
            ForEach(lists) { list in
                NavigationLink(value: LibraryRoute.list(list)) {
                    LabeledContent(list.name, value: list.entries?.count ?? 0, format: .number)
                }
                .accessibilityIdentifier("list-row-\(list.name)")
                .swipeActions {
                    deleteButton(for: list)
                }
                .contextMenu {
                    deleteButton(for: list)
                }
            }
        }
        .overlay {
            if lists.isEmpty {
                ContentUnavailableView(
                    "No Lists",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Group \(language.localizedName()) words to study or share them together.")
                )
            }
        }
        .navigationTitle("Lists")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New List", systemImage: "plus") {
                    newName = ""
                    isNaming = true
                }
                .accessibilityIdentifier("lists-new")
            }
        }
        .newListAlert(isPresented: $isNaming, name: $newName) { name in
            _ = try? app.repository.createList(named: name, language: language)
        }
        .confirmationDialog(
            pendingDeletion.map { String(localized: "Delete “\($0.name)”?") } ?? "",
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete List", role: .destructive) {
                if let list = pendingDeletion {
                    try? app.repository.delete(list)
                }
                pendingDeletion = nil
            }
        } message: {
            Text("Its words stay in your library.")
        }
    }

    private func deleteButton(for list: WordList) -> some View {
        Button(role: .destructive) {
            pendingDeletion = list
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}

/// One list's words, with sharing and CSV export (SPEC C4, C11).
struct ListDetailView: View {
    let list: WordList
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingDelete = false

    private var entries: [VocabularyEntry] {
        (list.entries ?? []).sorted { $0.term.localizedStandardCompare($1.term) == .orderedAscending }
    }

    var body: some View {
        List {
            ForEach(entries) { entry in
                NavigationLink(value: entry) {
                    WordRow(entry: entry)
                }
                .swipeActions {
                    Button("Remove", systemImage: "minus.circle", role: .destructive) {
                        app.repository.remove(entry, from: list)
                        try? app.repository.context.save()
                    }
                }
            }
        }
        .overlay {
            if entries.isEmpty {
                ContentUnavailableView(
                    "No Words",
                    systemImage: "text.badge.plus",
                    description: Text("Add a word from its page: More, then Lists.")
                )
            }
        }
        .navigationTitle(Text(verbatim: list.name))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    ShareLink(
                        item: WordListExport(contents: .list(list.id), name: list.name, container: app.container),
                        preview: SharePreview(Text(verbatim: list.name))
                    ) {
                        Label("Share List", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("list-share")
                    ShareLink(
                        item: WordListCSVExport(contents: .list(list.id), name: list.name, container: app.container),
                        preview: SharePreview(Text(verbatim: list.name))
                    ) {
                        Label("Export as CSV", systemImage: "tablecells")
                    }
                    Divider()
                    Button("Delete List", systemImage: "trash", role: .destructive) { isConfirmingDelete = true }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
                .accessibilityIdentifier("list-more")
            }
        }
        .confirmationDialog(String(localized: "Delete “\(list.name)”?"), isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete List", role: .destructive) {
                dismiss()
                try? app.repository.delete(list)
            }
        } message: {
            Text("Its words stay in your library.")
        }
    }
}

/// The lists a word is in, toggled with a tap; a new list can be made here too (SPEC C4).
struct WordListsView: View {
    let entry: VocabularyEntry
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Query private var lists: [WordList]
    @State private var isNaming = false
    @State private var newName = ""

    init(entry: VocabularyEntry) {
        self.entry = entry
        let code = entry.languageCode
        _lists = Query(filter: #Predicate<WordList> { $0.languageCode == code }, sort: \.name)
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(lists) { list in
                    let isMember = contains(list)
                    Button {
                        if isMember {
                            app.repository.remove(entry, from: list)
                        } else {
                            app.repository.add(entry, to: list)
                        }
                        try? app.repository.context.save()
                    } label: {
                        HStack {
                            Text(verbatim: list.name)
                                .foregroundStyle(Color.primary)
                            Spacer()
                            if isMember {
                                Image(systemName: "checkmark")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.tint)
                            }
                        }
                        .contentShape(.rect)
                    }
                    .accessibilityAddTraits(isMember ? .isSelected : [])
                    .accessibilityIdentifier("word-list-\(list.name)")
                }
                Button("New List…", systemImage: "plus") {
                    newName = ""
                    isNaming = true
                }
                .accessibilityIdentifier("word-lists-new")
            }
            .navigationTitle("Lists")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("word-lists-done")
                }
            }
            .newListAlert(isPresented: $isNaming, name: $newName) { name in
                guard let language = entry.language,
                      let list = try? app.repository.createList(named: name, language: language)
                else { return }
                app.repository.add(entry, to: list)
                try? app.repository.context.save()
            }
        }
        #if os(macOS)
        .frame(minWidth: 360, minHeight: 360)
        #endif
    }

    private func contains(_ list: WordList) -> Bool {
        (entry.lists ?? []).contains { $0.id == list.id }
    }
}

extension View {
    /// Asks for a new list's name; `create` gets it without surrounding spaces.
    func newListAlert(isPresented: Binding<Bool>, name: Binding<String>, create: @escaping (String) -> Void) -> some View {
        alert("New List", isPresented: isPresented) {
            TextField("Name", text: name)
                .accessibilityIdentifier("new-list-name")
            Button("Create") {
                let trimmed = name.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { create(trimmed) }
            }
            .accessibilityIdentifier("new-list-create")
            Button("Cancel", role: .cancel) {}
        }
    }
}
