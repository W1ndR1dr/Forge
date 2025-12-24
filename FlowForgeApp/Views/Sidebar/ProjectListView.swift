import SwiftUI

struct ProjectListView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        List(appState.projects, selection: Binding(
            get: { appState.selectedProject },
            set: { newProject in
                if let project = newProject {
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
        VStack(alignment: .leading, spacing: 4) {
            Text(project.name)
                .font(.headline)
            Text(project.path)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    ProjectListView()
        .environment(AppState())
        .frame(width: 250, height: 600)
}
