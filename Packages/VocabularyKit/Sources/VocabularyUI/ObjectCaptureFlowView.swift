import SwiftUI
import VocabularyCapture

/// The object capture flow once a photo is chosen: what it is, the language, its name, and saving
/// (SPEC C6, ADR-005).
public struct ObjectCaptureFlowView: View {
    @Bindable private var model: ObjectCaptureModel
    private let providerName: String

    public init(model: ObjectCaptureModel, providerName: String) {
        self.model = model
        self.providerName = providerName
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                photo
                if model.phase == .classifying {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Recognizing…", bundle: .module).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityIdentifier("object-classifying")
                } else {
                    labelSection
                    Divider()
                    languageSection
                    resultSection
                }
            }
            .padding()
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .animation(.default, value: model.phase)
    }

    // MARK: Photo

    @ViewBuilder
    private var photo: some View {
        if let image = model.displayImage {
            VStack(spacing: 8) {
                Image(image, scale: 1, label: Text("Photo of the object", bundle: .module))
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 280)
                    .clipShape(.rect(cornerRadius: 12))
                Button {
                    model.reset()
                } label: {
                    Label {
                        Text("New Photo", bundle: .module)
                    } icon: {
                        Image(systemName: "photo.badge.plus")
                    }
                }
                .font(.callout)
                .accessibilityIdentifier("object-new-photo")
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: What it is

    private var labelSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What is it?", bundle: .module).font(.headline)
            if model.labels.isEmpty {
                Text("Vocabulary-OS couldn't tell what this is. Type its name below, in any language.", bundle: .module)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                FlowLayout(lineSpacing: 8) {
                    ForEach(model.labels) { label in
                        let isSelected = model.label == label.name
                        Button {
                            model.label = label.name
                        } label: {
                            Text(verbatim: label.name)
                        }
                        .buttonStyle(.bordered)
                        .tint(isSelected ? .accentColor : .secondary)
                        .padding(.trailing, 6)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                        .accessibilityIdentifier("object-label-\(label.identifier)")
                    }
                }
            }
            TextField(text: $model.label) {
                Text("Or type what it is", bundle: .module)
            }
            .textFieldStyle(.roundedBorder)
            .autocorrectionDisabled()
            .accessibilityIdentifier("object-label-field")
        }
    }

    // MARK: Naming

    private var languageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Name it in", bundle: .module).font(.headline)
            LanguageChips(choices: model.languageChoices, selection: $model.language)
            switch model.phase {
            case .naming:
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Naming…", bundle: .module).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityIdentifier("object-naming")
            case .named, .saved:
                EmptyView()
            default:
                Button {
                    model.name()
                } label: {
                    Text("Name It", bundle: .module).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!model.canName)
                .accessibilityIdentifier("object-name")
            }
            if let error = model.namingError {
                Label {
                    Text(verbatim: error.localizedDescription)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                .accessibilityIdentifier("object-error")
            }
        }
    }

    // MARK: Result

    @ViewBuilder
    private var resultSection: some View {
        if let insight = model.insight {
            VStack(alignment: .leading, spacing: 16) {
                InsightCard(insight: insight, providerName: providerName)
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
                    .accessibilityIdentifier("object-saved")
                    Button {
                        model.reset()
                    } label: {
                        Text("Capture Another Object", bundle: .module)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Toggle(isOn: $model.savesPhoto) {
                        Text("Save photo with word", bundle: .module)
                    }
                    .accessibilityIdentifier("object-saves-photo")
                    Button {
                        model.save()
                    } label: {
                        Text("Save to Library", bundle: .module).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityIdentifier("object-save")
                }
            }
        }
    }
}
