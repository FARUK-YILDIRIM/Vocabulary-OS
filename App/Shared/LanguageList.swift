import SwiftUI
import VocabularyCore

/// A searchable list of languages with checkmarks, used by onboarding and settings.
struct LanguageList: View {
    let languages: [LanguageCode]
    let isSelected: (LanguageCode) -> Bool
    var isDisabled: (LanguageCode) -> Bool = { _ in false }
    let onSelect: (LanguageCode) -> Void

    @State private var query = ""

    var body: some View {
        List(filteredLanguages, id: \.self) { code in
            Button {
                onSelect(code)
            } label: {
                LanguageRow(code: code, isSelected: isSelected(code))
            }
            .buttonStyle(.plain)
            .disabled(isDisabled(code))
            .accessibilityIdentifier("language-\(code.rawValue)")
        }
        .searchable(text: $query, prompt: Text("Search languages"))
    }

    private var filteredLanguages: [LanguageCode] {
        let sorted = languages.sorted { $0.localizedName().localizedStandardCompare($1.localizedName()) == .orderedAscending }
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return sorted }
        return sorted.filter { code in
            [code.localizedName(), code.autonym, code.englishName].contains { $0.localizedStandardContains(needle) }
        }
    }
}

/// One language: its name in itself and in the UI language, plus a checkmark when selected.
struct LanguageRow: View {
    let code: LanguageCode
    var isSelected = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(code.autonym)
                if code.autonym != code.localizedName() {
                    Text(code.localizedName())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .fontWeight(.semibold)
                    .foregroundStyle(.tint)
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    LanguageList(languages: LanguageCatalog.all, isSelected: { $0 == .german }, onSelect: { _ in })
}
