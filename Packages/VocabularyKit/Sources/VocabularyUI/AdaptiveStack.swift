import SwiftUI

/// Side by side at regular text sizes, stacked at accessibility sizes, where side by side each part
/// would wrap a syllable per line.
public struct AdaptiveStack<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let alignment: VerticalAlignment
    private let spacing: CGFloat?
    private let content: Content

    /// - Parameter alignment: how the parts line up while side by side.
    public init(alignment: VerticalAlignment = .center, spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: spacing))
            : AnyLayout(HStackLayout(alignment: alignment, spacing: spacing))
        layout { content }
    }
}
