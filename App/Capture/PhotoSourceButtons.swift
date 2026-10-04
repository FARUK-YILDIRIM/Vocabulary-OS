import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Ways to get a photo into capture: the camera (iPhone and iPad), Photos, and image files.
struct PhotoSourceButtons: View {
    /// Receives the image file data the learner chose.
    let onImage: (Data) -> Void
    @State private var photoItem: PhotosPickerItem?
    @State private var isImportingFile = false
    @State private var isShowingCamera = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            #if os(iOS)
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button {
                    isShowingCamera = true
                } label: {
                    Label("Take Photo", systemImage: "camera")
                }
                .buttonStyle(.borderedProminent)
            }
            #endif
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label("Choose Photo", systemImage: "photo.on.rectangle")
            }
            .accessibilityIdentifier("photo-choose")
            Button {
                isImportingFile = true
            } label: {
                Label("Choose File", systemImage: "folder")
            }
            .accessibilityIdentifier("photo-choose-file")
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            photoItem = nil
            Task { await loadPhoto(item) }
        }
        .fileImporter(isPresented: $isImportingFile, allowedContentTypes: [.image]) { result in
            importFile(result)
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $isShowingCamera) {
            CameraPicker(onCapture: onImage)
                .ignoresSafeArea()
        }
        #endif
        .alert("Couldn't Open the Photo", isPresented: isShowingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(verbatim: errorMessage ?? "")
        }
    }

    private var isShowingError: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func loadPhoto(_ item: PhotosPickerItem) async {
        do {
            if let data = try await item.loadTransferable(type: Data.self) {
                onImage(data)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func importFile(_ result: Result<URL, any Error>) {
        do {
            let url = try result.get()
            // Files chosen in the picker are outside the sandbox until access is started.
            let isAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if isAccessing { url.stopAccessingSecurityScopedResource() }
            }
            onImage(try Data(contentsOf: url))
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
