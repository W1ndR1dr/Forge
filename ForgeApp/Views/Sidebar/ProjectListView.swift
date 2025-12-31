import SwiftUI

struct ProjectListView: View {
    @Environment(AppState.self) private var appState
    @State private var hiddenSectionExpanded = false

    var body: some View {
        @Bindable var state = appState

        List(selection: Binding(
            get: { appState.selectedProject },
            set: { newProject in
                if let project = newProject {
                    appState.markProjectAccessed(project)
                    Task {
                        await appState.selectProject(project)
                    }
                }
            }
        )) {
            // Visible projects
            ForEach(appState.visibleSortedProjects) { project in
                ProjectRow(project: project)
                    .tag(project)
                    .listRowBackground(Color.clear)
                    .contextMenu {
                        Button("Hide Project") {
                            appState.hideProject(project)
                        }
                    }
            }

            // Hidden section (only if there are hidden projects)
            if !appState.hiddenProjects.isEmpty {
                Section {
                    if hiddenSectionExpanded {
                        ForEach(appState.hiddenProjects) { project in
                            ProjectRow(project: project)
                                .tag(project)
                                .opacity(0.6)
                                .listRowBackground(Color.clear)
                                .contextMenu {
                                    Button("Show Project") {
                                        appState.showProject(project)
                                    }
                                }
                        }
                    }
                } header: {
                    Button {
                        withAnimation(.snappy) {
                            hiddenSectionExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: Spacing.micro) {
                            Image(systemName: hiddenSectionExpanded ? "chevron.down" : "chevron.right")
                                .font(.caption2)
                                .foregroundColor(Linear.textMuted)
                            Text("Hidden (\(appState.hiddenProjects.count))")
                                .font(Typography.caption)
                                .foregroundColor(Linear.textMuted)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Linear.background)
        .environment(\.defaultMinListRowHeight, 36)
    }
}

struct ProjectRow: View {
    let project: Project
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            // Project icon
            Image(systemName: project.needsInitialization ? "folder.badge.gearshape" : "folder.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(project.needsInitialization ? Linear.warning : Linear.textSecondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(project.name)
                        .font(.inter(14, weight: .medium))
                        .foregroundColor(Linear.textPrimary)

                    if project.needsInitialization {
                        Text("Setup")
                            .font(.inter(10, weight: .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Linear.warning.opacity(0.15))
                            .foregroundColor(Linear.warning)
                            .cornerRadius(CornerRadius.small)
                    }
                }
                Text(project.path)
                    .font(.inter(11))
                    .foregroundColor(Linear.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.medium, style: .continuous)
                .fill(isHovered ? Linear.hoverBackground : Color.clear)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .opacity(project.needsInitialization ? 0.8 : 1.0)
    }
}

#Preview {
    ProjectListView()
        .environment(AppState())
        .frame(width: 250, height: 600)
}
