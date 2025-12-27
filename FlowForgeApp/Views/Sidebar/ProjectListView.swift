import SwiftUI

struct ProjectListView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        List(appState.sortedProjects, selection: Binding(
            get: { appState.selectedProject },
            set: { newProject in
                if let project = newProject {
                    appState.markProjectAccessed(project)
                    Task {
                        await appState.selectProject(project)
                    }
                }
            }
        )) { project in
            ProjectRow(project: project)
                .tag(project)
        }
        .navigationTitle("Projects")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                SortPicker(selection: $state.projectSortOrder)
                    .help("Sort projects")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task {
                        await appState.loadProjects()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh projects")
            }
        }
    }
}

struct ProjectRow: View {
    let project: Project

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(project.name)
                        .font(.headline)

                    if project.needsInitialization {
                        Text("Setup")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(DesignTokens.Colors.warning.opacity(0.15))
                            .foregroundStyle(DesignTokens.Colors.warning)
                            .clipShape(Capsule())
                    }
                }
                Text(project.path)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            if project.needsInitialization {
                Image(systemName: "bolt.badge.clock")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
        .opacity(project.needsInitialization ? 0.8 : 1.0)
    }
}

#Preview {
    ProjectListView()
        .environment(AppState())
        .frame(width: 250, height: 600)
}
