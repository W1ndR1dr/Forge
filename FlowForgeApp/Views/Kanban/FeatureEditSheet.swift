import SwiftUI

/// Sheet for editing feature attributes
struct FeatureEditSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let feature: Feature
    let projectName: String

    @State private var title: String
    @State private var description: String
    @State private var status: FeatureStatus
    @State private var complexity: Complexity
    @State private var tagsText: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let apiClient = APIClient()

    init(feature: Feature, projectName: String) {
        self.feature = feature
        self.projectName = projectName
        _title = State(initialValue: feature.title)
        _description = State(initialValue: feature.description ?? "")
        _status = State(initialValue: feature.status)
        _complexity = State(initialValue: feature.complexity ?? .medium)
        _tagsText = State(initialValue: feature.tags.joined(separator: ", "))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Edit Feature")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            // Form
            Form {
                Section("Basic Info") {
                    TextField("Title", text: $title)
                        .textFieldStyle(.roundedBorder)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Description")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextEditor(text: $description)
                            .frame(minHeight: 80)
                            .font(.body)
                    }
                }

                Section("Attributes") {
                    Picker("Status", selection: $status) {
                        ForEach(FeatureStatus.allCases, id: \.self) { status in
                            HStack {
                                Circle()
                                    .fill(statusColor(for: status))
                                    .frame(width: 8, height: 8)
                                Text(status.displayName)
                            }
                            .tag(status)
                        }
                    }

                    Picker("Complexity", selection: $complexity) {
                        ForEach(Complexity.allCases, id: \.self) { complexity in
                            Text(complexity.displayName).tag(complexity)
                        }
                    }
                }

                Section("Tags") {
                    TextField("Tags (comma-separated)", text: $tagsText)
                        .textFieldStyle(.roundedBorder)
                    Text("e.g., ui, backend, urgent")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .formStyle(.grouped)

            Divider()

            // Footer
            HStack {
                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }

                Spacer()

                Button("Save") {
                    saveChanges()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving || title.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 500, height: 500)
    }

    private func statusColor(for status: FeatureStatus) -> Color {
        switch status {
        case .planned: return .gray
        case .inProgress: return .blue
        case .review: return .orange
        case .completed: return .green
        case .blocked: return .red
        }
    }

    private func saveChanges() {
        isSaving = true
        errorMessage = nil

        let tags = tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        Task {
            do {
                try await apiClient.updateFeature(
                    project: projectName,
                    featureId: feature.id,
                    title: title != feature.title ? title : nil,
                    description: description != (feature.description ?? "") ? description : nil,
                    status: status != feature.status ? status.rawValue : nil,
                    complexity: complexity != feature.complexity ? complexity.rawValue : nil,
                    tags: tags != feature.tags ? tags : nil
                )

                await MainActor.run {
                    isSaving = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Complexity Extension

extension Complexity: CaseIterable {
    static var allCases: [Complexity] {
        [.small, .medium, .large, .epic]
    }
}

#Preview {
    FeatureEditSheet(
        feature: Feature(
            id: "test-1",
            title: "Sample Feature",
            description: "This is a test feature",
            status: .planned,
            complexity: .medium,
            tags: ["ui", "backend"]
        ),
        projectName: "TestProject"
    )
    .environment(AppState())
}
