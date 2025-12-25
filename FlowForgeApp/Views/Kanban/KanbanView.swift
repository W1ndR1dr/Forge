import SwiftUI

struct KanbanView: View {
    @Environment(AppState.self) private var appState
    @State private var showingAddFeature = false
    @State private var newFeatureTitle = ""

    private let displayedStatuses: [FeatureStatus] = [
        .planned,
        .inProgress,
        .review,
        .completed
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                if let project = appState.selectedProject {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(project.name)
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("\(appState.features.count) features")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Button {
                    showingAddFeature = true
                } label: {
                    Label("Add Feature", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Kanban Board
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(displayedStatuses, id: \.self) { status in
                        StatusColumn(
                            status: status,
                            features: appState.features(for: status),
                            projectName: appState.selectedProject?.name ?? ""
                        )
                    }
                }
                .padding()
            }
        }
        .sheet(isPresented: $showingAddFeature) {
            AddFeatureSheet(
                isPresented: $showingAddFeature,
                featureTitle: $newFeatureTitle
            )
        }
    }
}

struct AddFeatureSheet: View {
    @Environment(AppState.self) private var appState
    @Binding var isPresented: Bool
    @Binding var featureTitle: String

    var body: some View {
        VStack(spacing: 20) {
            Text("Add New Feature")
                .font(.title2)
                .fontWeight(.bold)

            TextField("Feature title", text: $featureTitle)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    addFeature()
                }

            HStack {
                Button("Cancel") {
                    isPresented = false
                    featureTitle = ""
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Add") {
                    addFeature()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(featureTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
    }

    private func addFeature() {
        guard !featureTitle.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        Task {
            await appState.addFeature(title: featureTitle)
            await MainActor.run {
                isPresented = false
                featureTitle = ""
            }
        }
    }
}

#Preview {
    KanbanView()
        .environment(AppState())
        .frame(width: 1200, height: 800)
}
