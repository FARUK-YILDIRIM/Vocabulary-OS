#if os(macOS)
import SwiftUI
import VocabularyUI

/// The window Services → "Capture in Vocabulary-OS" opens: the capture flow for the selected text.
struct QuickCaptureView: View {
    @Environment(AppModel.self) private var app
    let model: CaptureModel

    var body: some View {
        Group {
            if app.settings.isOnboarded {
                CaptureFlowView(model: model, providerName: app.providerName(for:))
            } else {
                ContentUnavailableView {
                    Label("Choose Your Languages First", systemImage: "globe")
                } description: {
                    Text("Finish setting up Vocabulary-OS in its main window, then capture the text again.")
                }
            }
        }
        .frame(minWidth: 440, idealWidth: 520, minHeight: 420, idealHeight: 600)
    }
}
#endif
