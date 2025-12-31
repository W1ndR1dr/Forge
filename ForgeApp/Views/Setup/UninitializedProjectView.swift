import SwiftUI

/// View shown when an uninitialized project is selected
struct UninitializedProjectView: View {
    @Environment(AppState.self) private var appState
    let project: Project

    var body: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()

            // Icon
            Image(systemName: "bolt.badge.clock")
                .font(.system(size: 48))
                .foregroundColor(Accent.primary.opacity(0.7))
                .symbolRenderingMode(.hierarchical)

            // Title and description
            VStack(spacing: Spacing.small) {
                Text("Set Up Forge")
                    .font(Typography.body)
                    .fontWeight(.semibold)
                    .foregroundColor(Linear.textPrimary)

                Text("**\(project.name)** is a Git repository but hasn't been set up with Forge yet.")
                    .font(Typography.caption)
                    .foregroundColor(Linear.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }

            // Features list
            VStack(alignment: .leading, spacing: Spacing.small) {
                featureRow(icon: "list.bullet.clipboard", text: "Track features in a visual kanban board")
                featureRow(icon: "arrow.triangle.branch", text: "Work on multiple features in parallel")
                featureRow(icon: "doc.text.magnifyingglass", text: "Generate AI prompts with full context")
                featureRow(icon: "arrow.triangle.merge", text: "Merge with confidence")
            }
            .padding(Spacing.standard)
            .background(Linear.elevated)
            .cornerRadius(CornerRadius.large)
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.large)
                    .stroke(Linear.borderSubtle, lineWidth: 1)
            )

            // Initialize button
            Button {
                appState.projectToInitialize = project
                appState.showingProjectSetup = true
            } label: {
                HStack(spacing: Spacing.small) {
                    Image(systemName: "bolt.fill")
                    Text("Initialize Forge")
                }
            }
            .buttonStyle(.linearPrimary)
            .controlSize(.large)

            Spacer()
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Linear.base)
        .environment(\.colorScheme, .dark)
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: Spacing.medium) {
            Image(systemName: icon)
                .foregroundColor(Accent.primary)
                .frame(width: 24)
            Text(text)
                .font(Typography.caption)
                .foregroundColor(Linear.textSecondary)
        }
    }
}
