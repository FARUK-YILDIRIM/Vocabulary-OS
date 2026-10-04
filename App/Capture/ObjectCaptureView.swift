import SwiftUI
import VocabularyUI

/// Capture → Object: photograph something around you and learn its name (SPEC C6, ADR-005).
struct ObjectCaptureView: View {
    @Environment(AppModel.self) private var app
    let model: ObjectCaptureModel
    #if DEBUG
    @State private var didLoadSample = false
    #endif

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            #if DEBUG
            .onAppear {
                // Not a view task: SwiftUI cancels those when the view is rebuilt, as on macOS at launch.
                guard LaunchOptions().usesSampleObject, !didLoadSample, model.phase == .empty else { return }
                didLoadSample = true
                load(SampleObject.jpegData())
            }
            #endif
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .empty:
            ContentUnavailableView {
                Label("Capture an Object", systemImage: "cube")
            } description: {
                Text("Photograph something around you or choose a photo, and learn its name in the language you're studying.")
            } actions: {
                PhotoSourceButtons(onImage: load)
            }
        case .failed(let error):
            ContentUnavailableView {
                Label("Couldn't Read the Photo", systemImage: "exclamationmark.triangle")
            } description: {
                Text(verbatim: error.localizedDescription)
            } actions: {
                PhotoSourceButtons(onImage: load)
            }
        default:
            ObjectCaptureFlowView(model: model, providerName: app.providerDisplayName)
        }
    }

    private func load(_ data: Data) {
        Task { await model.load(data) }
    }
}
