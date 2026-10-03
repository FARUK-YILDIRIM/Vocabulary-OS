import SwiftUI
import VocabularyCore

/// Settings → Languages: change the native language, add, remove and reorder learning languages.
struct LanguageSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var isAddingLanguage = false

    var body: some View {
        if let profile = model.settings.profile {
            Form {
                Section("Native language") {
                    NavigationLink {
                        NativeLanguagePicker(profile: profile, onSelect: update)
                    } label: {
                        LanguageRow(code: profile.native)
                    }
                }

                Section {
                    ForEach(profile.learning, id: \.self) { code in
                        LanguageRow(code: code)
                    }
                    .onDelete { offsets in
                        var updated = profile
                        offsets.map { profile.learning[$0] }.forEach { updated.removeLearning($0) }
                        update(updated)
                    }
                    .onMove { source, destination in
                        var updated = profile
                        updated.moveLearning(fromOffsets: source, toOffset: destination)
                        update(updated)
                    }
                    .deleteDisabled(profile.learning.count == 1)

                    Button("Add Language", systemImage: "plus") {
                        isAddingLanguage = true
                    }
                } header: {
                    Text("Learning")
                } footer: {
                    Text("Removing a language hides its words. They come back when you add the language again.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Languages")
            #if os(iOS)
            .toolbar { EditButton() }
            #endif
            .sheet(isPresented: $isAddingLanguage) {
                AddLanguageSheet(profile: profile) { code in
                    var updated = profile
                    try? updated.addLearning(code)
                    update(updated)
                    isAddingLanguage = false
                }
            }
        }
    }

    private func update(_ profile: LearnerProfile) {
        model.settings.profile = profile
    }
}

private struct NativeLanguagePicker: View {
    let profile: LearnerProfile
    let onSelect: (LearnerProfile) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        LanguageList(
            languages: LanguageCatalog.all,
            isSelected: { $0 == profile.native },
            // Making the only learning language native would leave nothing to learn.
            isDisabled: { profile.learning == [$0] },
            onSelect: { code in
                var updated = profile
                try? updated.setNative(code)
                onSelect(updated)
                dismiss()
            }
        )
        .navigationTitle("Native language")
    }
}

private struct AddLanguageSheet: View {
    let profile: LearnerProfile
    let onAdd: (LanguageCode) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            LanguageList(
                languages: LanguageCatalog.all.filter { $0 != profile.native && !profile.learning.contains($0) },
                isSelected: { _ in false },
                onSelect: onAdd
            )
            .navigationTitle("Add Language")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .frame(minWidth: 360, minHeight: 420)
    }
}

#Preview {
    NavigationStack {
        LanguageSettingsView().environment(AppModel.preview())
    }
}
