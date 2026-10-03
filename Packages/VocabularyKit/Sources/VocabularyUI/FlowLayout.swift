import SwiftUI

/// Lays subviews out left to right and wraps them like text. A subview marked with
/// `.flowLineBreak()` ends the current line.
struct FlowLayout: Layout {
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let lines = arrange(subviews, maxWidth: proposal.width ?? .infinity)
        let width = lines.map(\.width).max() ?? 0
        let height = lines.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(lines.count - 1, 0))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for line in arrange(subviews, maxWidth: bounds.width) {
            var x = bounds.minX
            for item in line.items {
                let size = subviews[item].sizeThatFits(.unspecified)
                subviews[item].place(at: CGPoint(x: x, y: y + (line.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width
            }
            y += line.height + lineSpacing
        }
    }

    private struct Line {
        var items: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, maxWidth: CGFloat) -> [Line] {
        var lines = [Line()]
        for index in subviews.indices {
            if subviews[index][FlowLineBreak.self] {
                lines.append(Line())
                continue
            }
            let size = subviews[index].sizeThatFits(.unspecified)
            if lines[lines.count - 1].width + size.width > maxWidth, !lines[lines.count - 1].items.isEmpty {
                lines.append(Line())
            }
            lines[lines.count - 1].items.append(index)
            lines[lines.count - 1].width += size.width
            lines[lines.count - 1].height = max(lines[lines.count - 1].height, size.height)
        }
        return lines.filter { !$0.items.isEmpty || $0.height > 0 }
    }
}

/// Layout values are read off the main actor, so the key is nonisolated.
private nonisolated struct FlowLineBreak: LayoutValueKey {
    static let defaultValue = false
}

extension View {
    /// Ends the current line in a `FlowLayout`.
    func flowLineBreak() -> some View {
        layoutValue(key: FlowLineBreak.self, value: true)
    }
}
