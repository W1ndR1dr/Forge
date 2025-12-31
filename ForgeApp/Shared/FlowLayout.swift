import SwiftUI

/// A layout that arranges views in a flow pattern, wrapping to new lines
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = computeLayout(proposal: proposal, subviews: subviews)

        for (index, placement) in result.placements.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + placement.x, y: bounds.minY + placement.y),
                proposal: ProposedViewSize(placement.size)
            )
        }
    }

    private struct LayoutResult {
        var size: CGSize
        var placements: [(x: CGFloat, y: CGFloat, size: CGSize)]
    }

    private func computeLayout(proposal: ProposedViewSize, subviews: Subviews) -> LayoutResult {
        var placements: [(x: CGFloat, y: CGFloat, size: CGSize)] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxWidth: CGFloat = 0

        let availableWidth = proposal.width ?? .infinity

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            // Check if we need to wrap to a new line
            if currentX + size.width > availableWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            placements.append((x: currentX, y: currentY, size: size))

            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            maxWidth = max(maxWidth, currentX - spacing)
        }

        let totalHeight = currentY + lineHeight

        return LayoutResult(
            size: CGSize(width: maxWidth, height: totalHeight),
            placements: placements
        )
    }
}

// Extension to use FlowLayout as a ViewBuilder container
extension FlowLayout {
    struct Content<Content: View>: View {
        let spacing: CGFloat
        let content: Content

        init(spacing: CGFloat = 8, @ViewBuilder content: () -> Content) {
            self.spacing = spacing
            self.content = content()
        }

        var body: some View {
            FlowLayout(spacing: spacing) {
                content
            }
        }
    }
}
