import SwiftUI
import VocabularyCapture

/// A photo of a page with its recognized words as tap targets (ADR-005).
public struct WordOverlayView: View {
    private let image: CGImage
    private let page: PageText
    private let highlighted: PageText.Word?
    private let onTap: (PageText.Word) -> Void

    public init(image: CGImage, page: PageText, highlighted: PageText.Word?, onTap: @escaping (PageText.Word) -> Void) {
        self.image = image
        self.page = page
        self.highlighted = highlighted
        self.onTap = onTap
    }

    public var body: some View {
        Image(decorative: image, scale: 1)
            .resizable()
            .aspectRatio(CGFloat(image.width) / CGFloat(max(image.height, 1)), contentMode: .fit)
            .overlay {
                GeometryReader { geometry in
                    let size = geometry.size
                    ZStack(alignment: .topLeading) {
                        ForEach(page.words) { word in
                            box(for: word, in: size)
                        }
                    }
                    .frame(width: size.width, height: size.height, alignment: .topLeading)
                    .contentShape(.rect)
                    // One gesture for the whole photo, so a tap that just misses a small word still
                    // finds the nearest one.
                    .gesture(SpatialTapGesture().onEnded { value in
                        let point = CGPoint(x: value.location.x / size.width, y: value.location.y / size.height)
                        if let word = page.word(at: point) {
                            onTap(word)
                        }
                    })
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("Photo of a page", bundle: .module))
    }

    private func box(for word: PageText.Word, in size: CGSize) -> some View {
        let isHighlighted = word == highlighted
        return RoundedRectangle(cornerRadius: 3)
            .fill(Color.accentColor.opacity(isHighlighted ? 0.35 : 0.08))
            .strokeBorder(Color.accentColor.opacity(isHighlighted ? 1 : 0.3), lineWidth: isHighlighted ? 2 : 0.5)
            .frame(width: word.box.width * size.width, height: word.box.height * size.height)
            .offset(x: word.box.minX * size.width, y: word.box.minY * size.height)
            .allowsHitTesting(false)
            .accessibilityElement()
            .accessibilityLabel(Text(verbatim: word.text))
            .accessibilityAddTraits(isHighlighted ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { onTap(word) }
            .accessibilityIdentifier("page-word-\(word.id)")
    }
}
