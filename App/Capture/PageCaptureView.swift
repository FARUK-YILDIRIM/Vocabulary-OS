import SwiftUI
import VocabularyCapture
import VocabularyUI

/// Capture → Page: photograph a book page or choose a photo, then tap a word (SPEC C6, ADR-005).
struct PageCaptureView: View {
    @Environment(AppModel.self) private var app
    @Bindable var model: PageCaptureModel
    #if DEBUG
    @State private var didLoadSample = false
    #endif
    @State private var zoom: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1

    private static let zoomRange: ClosedRange<CGFloat> = 1...4

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .sheet(isPresented: isCapturing) { captureSheet }
            #if DEBUG
            .onAppear {
                // Not a view task: SwiftUI cancels those when the view is rebuilt, as on macOS at launch.
                guard LaunchOptions().usesSamplePage, !didLoadSample, model.phase == .empty else { return }
                didLoadSample = true
                load(SamplePage.jpegData())
            }
            #endif
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .empty:
            ContentUnavailableView {
                Label("Capture from a Page", systemImage: "book.pages")
            } description: {
                Text("Photograph a page of a book or choose a photo. Then tap a word to see what it means in its sentence.")
            } actions: {
                sourceButtons
            }
        case .recognizing:
            VStack(spacing: 16) {
                if let image = model.displayImage {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFit()
                        .opacity(0.5)
                        .padding()
                }
                ProgressView("Finding words…")
                    .accessibilityIdentifier("page-recognizing")
            }
        case .recognized:
            if let page = model.page, !page.isEmpty, let image = model.displayImage {
                recognizedPage(image: image, page: page)
            } else {
                ContentUnavailableView {
                    Label("No Text Found", systemImage: "text.magnifyingglass")
                } description: {
                    Text("Try a sharper photo, with the page filling the frame.")
                } actions: {
                    sourceButtons
                }
            }
        case .failed(let error):
            ContentUnavailableView {
                Label("Couldn't Read the Photo", systemImage: "exclamationmark.triangle")
            } description: {
                Text(verbatim: error.localizedDescription)
            } actions: {
                sourceButtons
            }
        }
    }

    private func recognizedPage(image: CGImage, page: PageText) -> some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                ScrollView([.horizontal, .vertical]) {
                    WordOverlayView(image: image, page: page, highlighted: model.tappedWord) { word in
                        model.tap(word)
                    }
                    .frame(width: max(geometry.size.width - 32, 120) * currentZoom)
                    .padding(16)
                }
                // A page reads from the top, also when the photo is shorter than the screen.
                .defaultScrollAnchor(.top)
                .simultaneousGesture(
                    MagnifyGesture()
                        .updating($pinch) { value, state, _ in state = value.magnification }
                        .onEnded { value in zoom = clampedZoom(zoom * value.magnification) }
                )
                .overlay(alignment: .bottomTrailing) { zoomButtons }
            }
            Divider()
            HStack(spacing: 12) {
                Toggle("Save photo with words", isOn: $model.savesPhoto)
                    .fixedSize()
                    .accessibilityIdentifier("page-saves-photo")
                Spacer(minLength: 0)
                Button {
                    zoom = 1
                    model.reset()
                } label: {
                    Label("New Photo", systemImage: "photo.badge.plus")
                }
                .accessibilityIdentifier("page-new-photo")
            }
            .font(.callout)
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
    }

    private var zoomButtons: some View {
        HStack(spacing: 0) {
            Button {
                zoom = clampedZoom(zoom / 1.5)
            } label: {
                Label("Zoom Out", systemImage: "minus.magnifyingglass")
            }
            .disabled(zoom <= Self.zoomRange.lowerBound)
            Button {
                zoom = clampedZoom(zoom * 1.5)
            } label: {
                Label("Zoom In", systemImage: "plus.magnifyingglass")
            }
            .disabled(zoom >= Self.zoomRange.upperBound)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.bordered)
        .padding(12)
    }

    private var sourceButtons: some View {
        PhotoSourceButtons(onImage: load)
    }

    @ViewBuilder
    private var captureSheet: some View {
        if let capture = model.capture {
            NavigationStack {
                CaptureFlowView(model: capture, providerName: app.providerDisplayName)
                    .navigationTitle("Capture")
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { model.capture = nil }
                                .accessibilityIdentifier("page-capture-done")
                        }
                    }
            }
            #if os(macOS)
            .frame(minWidth: 480, minHeight: 560)
            #endif
        }
    }

    // MARK: State

    private var currentZoom: CGFloat { clampedZoom(zoom * pinch) }

    private func clampedZoom(_ value: CGFloat) -> CGFloat {
        min(max(value, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
    }

    private var isCapturing: Binding<Bool> {
        Binding(get: { model.capture != nil }, set: { if !$0 { model.capture = nil } })
    }

    // MARK: Loading

    private func load(_ data: Data) {
        zoom = 1
        Task { await model.load(data) }
    }
}
