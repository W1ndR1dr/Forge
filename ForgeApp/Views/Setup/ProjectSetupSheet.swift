import SwiftUI

/// Sheet for initializing a new project with Forge
struct ProjectSetupSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let project: Project

    @State private var isInitializing = false
    @State private var useQuickMode = true
    @State private var projectDescription = ""
    @State private var projectVision = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()
                .background(Linear.borderSubtle)

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.large) {
                    projectInfo
                    modeSelector
                    if !useQuickMode {
                        guidedFields
                    }
                    whatGetsCreated
                }
                .padding(Spacing.large)
            }

            Divider()
                .background(Linear.borderSubtle)

            // Footer with actions
            footer
        }
        .frame(width: 480, height: useQuickMode ? 420 : 560)
        .background(Linear.base)
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: Spacing.micro) {
                Text("Initialize Forge")
                    .font(Typography.body)
                    .fontWeight(.semibold)
                    .foregroundColor(Linear.textPrimary)
                Text(project.name)
                    .font(Typography.caption)
                    .foregroundColor(Linear.textSecondary)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(Linear.textMuted)
                    .font(.title3)
            }
            .buttonStyle(.plain)
        }
        .padding(Spacing.standard)
    }

    private var projectInfo: some View {
        HStack(spacing: Spacing.medium) {
            Image(systemName: "folder.badge.gearshape")
                .font(.title2)
                .foregroundColor(Accent.primary)

            VStack(alignment: .leading, spacing: Spacing.micro) {
                Text(project.name)
                    .font(Typography.body)
                    .fontWeight(.medium)
                    .foregroundColor(Linear.textPrimary)
                Text(project.path)
                    .font(Typography.caption)
                    .foregroundColor(Linear.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()
        }
        .padding(Spacing.medium)
        .background(Linear.elevated)
        .cornerRadius(CornerRadius.medium)
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.medium)
                .stroke(Linear.borderSubtle, lineWidth: 1)
        )
    }

    private var modeSelector: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            Text("SETUP MODE")
                .sectionHeaderStyle()

            HStack(spacing: Spacing.small) {
                modeButton(
                    title: "Quick",
                    subtitle: "Just the essentials",
                    icon: "bolt.fill",
                    isSelected: useQuickMode
                ) {
                    withAnimation(LinearEasing.fast) {
                        useQuickMode = true
                    }
                }

                modeButton(
                    title: "Guided",
                    subtitle: "Add project context",
                    icon: "slider.horizontal.3",
                    isSelected: !useQuickMode
                ) {
                    withAnimation(LinearEasing.fast) {
                        useQuickMode = false
                    }
                }
            }
        }
    }

    private func modeButton(
        title: String,
        subtitle: String,
        icon: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: Spacing.small) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(isSelected ? Accent.primary : Linear.textSecondary)
                Text(title)
                    .font(Typography.caption)
                    .fontWeight(.medium)
                    .foregroundColor(isSelected ? Linear.textPrimary : Linear.textSecondary)
                Text(subtitle)
                    .font(Typography.badge)
                    .foregroundColor(Linear.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(Spacing.medium)
            .background(isSelected ? Accent.primary.opacity(0.1) : Linear.card)
            .cornerRadius(CornerRadius.medium)
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.medium)
                    .stroke(isSelected ? Accent.primary.opacity(0.5) : Linear.borderSubtle, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var guidedFields: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            VStack(alignment: .leading, spacing: Spacing.small) {
                Text("Project Description")
                    .font(Typography.caption)
                    .fontWeight(.medium)
                    .foregroundColor(Linear.textSecondary)
                TextField("What does this project do?", text: $projectDescription, axis: .vertical)
                    .textFieldStyle(.linear)
                    .lineLimit(2...4)
            }

            VStack(alignment: .leading, spacing: Spacing.small) {
                Text("Vision")
                    .font(Typography.caption)
                    .fontWeight(.medium)
                    .foregroundColor(Linear.textSecondary)
                TextField("Where is this project headed?", text: $projectVision, axis: .vertical)
                    .textFieldStyle(.linear)
                    .lineLimit(2...4)
            }
        }
    }

    private var whatGetsCreated: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            Text("WHAT GETS CREATED")
                .sectionHeaderStyle()

            VStack(alignment: .leading, spacing: Spacing.small) {
                fileItem(".flowforge/", "Forge configuration directory")
                fileItem("config.json", "Project settings")
                fileItem("registry.json", "Feature database")
                fileItem("project-context.md", "AI context for prompts")
            }
            .padding(Spacing.medium)
            .background(Linear.elevated)
            .cornerRadius(CornerRadius.medium)
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.medium)
                    .stroke(Linear.borderSubtle, lineWidth: 1)
            )
        }
    }

    private func fileItem(_ name: String, _ description: String) -> some View {
        HStack(spacing: Spacing.small) {
            Image(systemName: name.hasSuffix("/") ? "folder.fill" : "doc.fill")
                .foregroundColor(Linear.textMuted)
                .frame(width: 16)
            Text(name)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Linear.textSecondary)
            Text("-")
                .foregroundColor(Linear.textMuted)
            Text(description)
                .font(Typography.badge)
                .foregroundColor(Linear.textTertiary)
            Spacer()
        }
    }

    private var footer: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(.linearSecondary)
            .keyboardShortcut(.escape)

            Spacer()

            Button {
                Task {
                    await initializeProject()
                }
            } label: {
                HStack(spacing: Spacing.small) {
                    if isInitializing {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(isInitializing ? "Initializing..." : "Initialize")
                }
            }
            .buttonStyle(.linearPrimary)
            .disabled(isInitializing)
            .keyboardShortcut(.return)
        }
        .padding(Spacing.standard)
    }

    private func initializeProject() async {
        isInitializing = true

        do {
            try await appState.initializeProject(project, quick: useQuickMode)
            dismiss()
        } catch {
            appState.errorMessage = error.localizedDescription
        }

        isInitializing = false
    }
}
