import SwiftUI
import UniformTypeIdentifiers

struct StatusColumn: View {
    @Environment(AppState.self) private var appState

    let status: FeatureStatus
    let features: [Feature]

    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Column Header
            HStack {
                Text(status.displayName)
                    .font(.headline)
                    .fontWeight(.semibold)

                Spacer()

                Text("\(features.count)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.2))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)

            Divider()

            // Feature Cards
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(features) { feature in
                        FeatureCard(feature: feature)
                    }

                    if features.isEmpty {
                        Text("No features")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 32)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }
        .frame(width: 280)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isTargeted ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .dropDestination(for: String.self) { droppedItems, location in
            handleDrop(droppedItems)
        } isTargeted: { targeted in
            isTargeted = targeted
        }
    }

    private func handleDrop(_ items: [String]) -> Bool {
        guard let featureId = items.first,
              let feature = appState.features.first(where: { $0.id == featureId }),
              feature.status != status else {
            return false
        }

        Task {
            await appState.updateFeatureStatus(feature, to: status)
        }

        return true
    }
}

#Preview {
    HStack(spacing: 16) {
        StatusColumn(
            status: .planned,
            features: [
                Feature(
                    id: "test-1",
                    title: "Sample Feature 1",
                    description: "This is a test feature",
                    status: .planned,
                    complexity: .medium
                ),
                Feature(
                    id: "test-2",
                    title: "Sample Feature 2",
                    status: .planned,
                    complexity: .small
                ),
            ]
        )

        StatusColumn(
            status: .inProgress,
            features: [
                Feature(
                    id: "test-3",
                    title: "In Progress Feature",
                    status: .inProgress,
                    complexity: .large
                ),
            ]
        )
    }
    .environment(AppState())
    .padding()
    .frame(height: 600)
}
