import SwiftData
import SwiftUI
import VocabularyCore
import VocabularyData

/// Saved words of one learning language, with filters, search and sort (SPEC C4).
struct LibraryView: View {
    @Environment(AppModel.self) private var app
    @State private var language: LanguageCode?
    @State private var filter: LibraryFilter = .all
    @State private var sort: LibrarySort = .recent
    @State private var search = ""

    var body: some View {
        NavigationStack {
            Group {
                if let current {
                    LibraryList(language: current, filter: filter, sort: sort, search: search) {
                        LibraryHeader(languages: app.settings.profile?.learning ?? [], language: languageBinding, filter: $filter)
                    }
                } else {
                    ContentUnavailableView("No learning languages", systemImage: "globe", description: Text("Add a language in Settings."))
                }
            }
            .navigationTitle("Library")
            .navigationDestination(for: VocabularyEntry.self) { entry in
                WordDetailView(entry: entry)
            }
            .searchable(text: $search, prompt: Text("Search words or translations"))
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Picker(selection: $sort) {
                            Text("Newest First").tag(LibrarySort.recent)
                            Text("Oldest First").tag(LibrarySort.oldest)
                            Text("A to Z").tag(LibrarySort.alphabetical)
                            Text("Next Review").tag(LibrarySort.nextReview)
                        } label: {
                            Text("Sort")
                        }
                    } label: {
                        Label("Sort", systemImage: "arrow.up.arrow.down")
                    }
                    .accessibilityIdentifier("library-sort")
                }
            }
        }
    }

    private var current: LanguageCode? {
        let learning = app.settings.profile?.learning ?? []
        if let language, learning.contains(language) { return language }
        return learning.first
    }

    private var languageBinding: Binding<LanguageCode?> {
        Binding(get: { current }, set: { language = $0 })
    }
}

private struct LibraryHeader: View {
    let languages: [LanguageCode]
    @Binding var language: LanguageCode?
    @Binding var filter: LibraryFilter

    var body: some View {
        VStack(spacing: 10) {
            if languages.count > 1 {
                Picker("Language", selection: $language) {
                    ForEach(languages, id: \.self) { code in
                        Text(verbatim: code.localizedName()).tag(Optional(code))
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("library-language")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(LibraryFilter.allCases, id: \.self) { option in
                        Button {
                            filter = option
                        } label: {
                            Text(option.title)
                        }
                        .buttonStyle(.bordered)
                        .tint(filter == option ? .accentColor : .secondary)
                        .accessibilityAddTraits(filter == option ? .isSelected : [])
                        .accessibilityIdentifier("library-filter-\(option.rawValue)")
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// The list itself; a separate view so its `@Query` is rebuilt when the filters change. The header
/// scrolls with the rows so it never covers the large navigation title.
private struct LibraryList<Header: View>: View {
    @Environment(AppModel.self) private var app
    @Query private var entries: [VocabularyEntry]
    @State private var pendingDeletion: VocabularyEntry?
    private let isNarrowed: Bool
    private let header: Header

    init(language: LanguageCode, filter: LibraryFilter, sort: LibrarySort, search: String, @ViewBuilder header: () -> Header) {
        _entries = Query(WordRepository.descriptor(language: language, filter: filter, sort: sort, search: search))
        isNarrowed = filter != .all || !search.trimmingCharacters(in: .whitespaces).isEmpty
        self.header = header()
    }

    var body: some View {
        List {
            Section {
                header
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))

            if entries.isEmpty {
                Section {
                    if isNarrowed {
                        ContentUnavailableView.search
                    } else {
                        ContentUnavailableView(
                            "No words yet",
                            systemImage: "books.vertical",
                            description: Text("Words you save in Capture appear here.")
                        )
                    }
                }
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(entries) { entry in
                        NavigationLink(value: entry) {
                            WordRow(entry: entry)
                        }
                        .swipeActions(edge: .leading) {
                            favoriteButton(for: entry)
                        }
                        .swipeActions(edge: .trailing) {
                            deleteButton(for: entry)
                        }
                        .contextMenu {
                            favoriteButton(for: entry)
                            deleteButton(for: entry)
                        }
                    }
                }
            }
        }
        .confirmationDialog(
            deletionTitle,
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let entry = pendingDeletion {
                    try? app.repository.delete(entry)
                }
                pendingDeletion = nil
            }
        }
    }

    private var deletionTitle: String {
        pendingDeletion.map { String(localized: "Delete “\($0.term)”?") } ?? ""
    }

    private func favoriteButton(for entry: VocabularyEntry) -> some View {
        Button {
            entry.isFavorite.toggle()
        } label: {
            Label(entry.isFavorite ? "Remove Favorite" : "Favorite", systemImage: entry.isFavorite ? "star.slash" : "star")
        }
        .tint(.yellow)
    }

    private func deleteButton(for entry: VocabularyEntry) -> some View {
        Button(role: .destructive) {
            pendingDeletion = entry
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}

private struct WordRow: View {
    let entry: VocabularyEntry

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: entry.term).font(.headline)
                Text(verbatim: entry.translation).foregroundStyle(.secondary)
            }
            Spacer()
            if entry.isFavorite {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                    .accessibilityLabel(Text("Favorite"))
            }
            if entry.isNew {
                Text("New")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.tint.opacity(0.15), in: .capsule)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("library-row-\(entry.term)")
    }
}

extension LibraryFilter {
    var title: LocalizedStringKey {
        switch self {
        case .all: "All"
        case .new: "New"
        case .due: "Due"
        case .favorites: "Favorites"
        case .mastered: "Mastered"
        }
    }
}

#Preview {
    LibraryView().environment(AppModel.preview())
}
