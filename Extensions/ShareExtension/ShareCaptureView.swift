import SwiftUI
import VocabularyUI

/// The Share extension's screen: the app's capture flow with Cancel and Done (SPEC C5).
struct ShareCaptureView: View {
    enum Outcome {
        case done, cancelled
    }

    let session: ShareSession
    let finish: (Outcome) -> Void
    @State private var didSave = false

    var body: some View {
        #if os(iOS)
        NavigationStack {
            content
                .navigationTitle("Vocabulary-OS")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if didSave {
                        ToolbarItem(placement: .confirmationAction) { doneButton }
                    } else {
                        ToolbarItem(placement: .cancellationAction) { cancelButton }
                    }
                }
        }
        #else
        // The Mac share sheet has no toolbar for the extension, so the buttons sit in a header.
        VStack(spacing: 0) {
            HStack {
                Text("Vocabulary-OS").font(.headline)
                Spacer()
                if didSave {
                    doneButton.keyboardShortcut(.defaultAction)
                } else {
                    cancelButton.keyboardShortcut(.cancelAction)
                }
            }
            .padding(12)
            Divider()
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 440, minHeight: 480)
        #endif
    }

    private var doneButton: some View {
        Button("Done") { finish(.done) }
            .accessibilityIdentifier("share-done")
    }

    private var cancelButton: some View {
        Button("Cancel") { finish(.cancelled) }
            .accessibilityIdentifier("share-cancel")
    }

    @ViewBuilder
    private var content: some View {
        switch session.state {
        case .loading:
            ProgressView()
        case .capturing(let model):
            CaptureFlowView(model: model, providerName: session.providerName, host: .shareExtension)
                .onChange(of: model.phase) { _, phase in
                    if phase == .saved {
                        didSave = true
                    }
                }
        case .needsOnboarding:
            ContentUnavailableView {
                Label("Choose Your Languages First", systemImage: "globe")
            } description: {
                Text("Open Vocabulary-OS and choose your native and learning languages. Then you can save words from any app.")
            }
        case .unavailable:
            ContentUnavailableView {
                Label("Can't Save from Here", systemImage: "exclamationmark.triangle")
            } description: {
                Text("This build of Vocabulary-OS has no App Group, so the Share extension can't pass words to the app.")
            }
        }
    }
}
