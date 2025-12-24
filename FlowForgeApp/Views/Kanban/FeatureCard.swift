import SwiftUI
import UniformTypeIdentifiers

struct FeatureCard: View {
    @Environment(AppState.self) private var appState
    let feature: Feature

    @State private var isHovering = false
    @State private var showingDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title
            Text(feature.title)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(3)

            // Description (if available)
            if let description = feature.description, !description.isEmpty {
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            // Metadata
            HStack(spacing: 8) {
                // Complexity badge
                if let complexity = feature.complexity {
                    ComplexityBadge(complexity: complexity)
                }

                Spacer()

                // Status indicator
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
            }

            // Tags
            if !feature.tags.isEmpty {
                FlowLayout(spacing: 4) {
                    ForEach(feature.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.2))
                            .clipShape(Capsule())
                    }
                }
            }

            // Branch info
            if let branch = feature.branch {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.branch")
                        .font(.caption2)
                    Text(branch)
                        .font(.caption2)
                }
                .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(NSColor.textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary.opacity(isHovering ? 0.3 : 0.1), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(isHovering ? 0.1 : 0.05), radius: isHovering ? 4 : 2)
        .scaleEffect(isHovering ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
        .draggable(feature.id)
        .contextMenu {
            Button("View Details") {
                showingDetails = true
            }

            Divider()

            Button("Start Feature") {
                Task {
                    await appState.startFeature(feature)
                }
            }
            .disabled(feature.status == .inProgress)

            Divider()

            Menu("Move to") {
                ForEach(FeatureStatus.allCases, id: \.self) { status in
                    Button(status.displayName) {
                        Task {
                            await appState.updateFeatureStatus(feature, to: status)
                        }
                    }
                    .disabled(status == feature.status)
                }
            }
        }
        .sheet(isPresented: $showingDetails) {
            FeatureDetailSheet(feature: feature)
        }
    }

    private var statusColor: Color {
        switch feature.status {
        case .planned: return .gray
        case .inProgress: return .blue
        case .review: return .orange
        case .completed: return .green
        case .blocked: return .red
        }
    }
}

struct ComplexityBadge: View {
    let complexity: Complexity

    var body: some View {
        Text(complexity.displayName)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(complexityColor.opacity(0.2))
            .foregroundColor(complexityColor)
            .clipShape(Capsule())
    }

    private var complexityColor: Color {
        switch complexity {
        case .small: return .green
        case .medium: return .orange
        case .large: return .red
        case .epic: return .purple
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                     y: bounds.minY + result.positions[index].y),
                         proposal: .unspecified)
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var lineHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if currentX + size.width > maxWidth && currentX > 0 {
                    currentX = 0
                    currentY += lineHeight + spacing
                    lineHeight = 0
                }

                positions.append(CGPoint(x: currentX, y: currentY))
                currentX += size.width + spacing
                lineHeight = max(lineHeight, size.height)
            }

            self.size = CGSize(width: maxWidth, height: currentY + lineHeight)
        }
    }
}

struct FeatureDetailSheet: View {
    let feature: Feature
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("Feature Details")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button("Close") {
                    dismiss()
                }
            }

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    DetailRow(label: "ID", value: feature.id)
                    DetailRow(label: "Title", value: feature.title)

                    if let description = feature.description {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Description")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(description)
                                .font(.body)
                        }
                    }

                    DetailRow(label: "Status", value: feature.status.displayName)

                    if let complexity = feature.complexity {
                        DetailRow(label: "Complexity", value: complexity.displayName)
                    }

                    if let branch = feature.branch {
                        DetailRow(label: "Branch", value: branch)
                    }

                    if let worktreePath = feature.worktreePath {
                        DetailRow(label: "Worktree", value: worktreePath)
                    }

                    DetailRow(label: "Created", value: feature.createdAt.formatted())

                    if let startedAt = feature.startedAt {
                        DetailRow(label: "Started", value: startedAt.formatted())
                    }

                    if let completedAt = feature.completedAt {
                        DetailRow(label: "Completed", value: completedAt.formatted())
                    }

                    if !feature.tags.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Tags")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            FlowLayout(spacing: 4) {
                                ForEach(feature.tags, id: \.self) { tag in
                                    Text(tag)
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.accentColor.opacity(0.2))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .frame(width: 500, height: 600)
    }
}

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.body)
                .textSelection(.enabled)
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        FeatureCard(
            feature: Feature(
                id: "test-1",
                title: "Sample Feature with a Long Title",
                description: "This is a longer description that explains what the feature does",
                status: .inProgress,
                complexity: .medium,
                branch: "feature/sample",
                tags: ["ui", "backend", "important"]
            )
        )

        FeatureCard(
            feature: Feature(
                id: "test-2",
                title: "Simple Feature",
                status: .planned,
                complexity: .small
            )
        )
    }
    .environment(AppState())
    .padding()
    .frame(width: 300)
}
