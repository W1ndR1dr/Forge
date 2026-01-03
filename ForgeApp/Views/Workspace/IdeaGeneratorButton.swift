import SwiftUI

// MARK: - Idea Generator Button

/// Button that triggers AI idea generation for the current project
struct IdeaGeneratorButton: View {
    @Environment(AppState.self) private var appState

    @State private var isGenerating = false
    @State private var showingPopover = false
    @State private var generatedIdeas: [GeneratedIdea] = []
    @State private var errorMessage: String?

    var body: some View {
        Button(action: generateIdeas) {
            if isGenerating {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.8)
            } else {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 14))
            }
        }
        .buttonStyle(.plain)
        .foregroundColor(Accent.brainstorm)
        .help("Generate AI feature ideas")
        .disabled(isGenerating || appState.selectedProject == nil)
        .popover(isPresented: $showingPopover, arrowEdge: .bottom) {
            GeneratedIdeasPopover(
                ideas: $generatedIdeas,
                errorMessage: errorMessage,
                onAddToInbox: addIdeaToInbox,
                onDismiss: { showingPopover = false },
                onRetry: generateIdeas
            )
        }
    }

    private func generateIdeas() {
        guard appState.selectedProject != nil else { return }

        isGenerating = true
        errorMessage = nil

        Task {
            do {
                let ideas = try await appState.generateIdeas(count: 5)

                await MainActor.run {
                    generatedIdeas = ideas
                    isGenerating = false
                    showingPopover = true
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    generatedIdeas = []
                    isGenerating = false
                    showingPopover = true
                }
            }
        }
    }

    private func addIdeaToInbox(_ idea: GeneratedIdea) {
        Task {
            do {
                try await appState.addIdeaToInbox(idea)

                // Remove from list
                await MainActor.run {
                    generatedIdeas.removeAll { $0.id == idea.id }
                }

                // Refresh feature list
                await appState.loadFeatures()

                // Close popover if no more ideas
                if generatedIdeas.isEmpty {
                    await MainActor.run {
                        showingPopover = false
                    }
                }
            } catch {
                await MainActor.run {
                    appState.errorMessage = "Failed to add idea: \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - Generated Ideas Popover

struct GeneratedIdeasPopover: View {
    @Binding var ideas: [GeneratedIdea]
    let errorMessage: String?
    let onAddToInbox: (GeneratedIdea) -> Void
    let onDismiss: () -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            // Header
            HStack {
                Image(systemName: "wand.and.stars")
                    .foregroundColor(Accent.brainstorm)
                Text("AI-Generated Ideas")
                    .font(Typography.featureTitle)
                    .foregroundColor(Linear.textPrimary)

                Spacer()

                Button("Done") {
                    onDismiss()
                }
                .buttonStyle(.plain)
                .foregroundColor(Linear.textSecondary)
            }

            Divider()
                .background(Linear.border)

            // Content
            if let error = errorMessage {
                // Error state
                VStack(spacing: Spacing.medium) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 32))
                        .foregroundColor(Accent.warning)

                    Text("Failed to generate ideas")
                        .font(Typography.body)
                        .foregroundColor(Linear.textPrimary)

                    Text(error)
                        .font(Typography.caption)
                        .foregroundColor(Linear.textSecondary)
                        .multilineTextAlignment(.center)

                    Button(action: onRetry) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                            Text("Try Again")
                        }
                        .font(Typography.body)
                        .padding(.horizontal, Spacing.standard)
                        .padding(.vertical, Spacing.small)
                        .background(Accent.brainstorm.opacity(0.15))
                        .foregroundColor(Accent.brainstorm)
                        .cornerRadius(CornerRadius.medium)
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity)
                .padding(Spacing.large)
            } else if ideas.isEmpty {
                // Empty state (shouldn't happen, but just in case)
                VStack(spacing: Spacing.medium) {
                    Image(systemName: "lightbulb.slash")
                        .font(.system(size: 32))
                        .foregroundColor(Linear.textSecondary)

                    Text("No ideas generated")
                        .font(Typography.body)
                        .foregroundColor(Linear.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(Spacing.large)
            } else {
                // Ideas list
                ScrollView {
                    VStack(spacing: Spacing.small) {
                        ForEach(ideas) { idea in
                            GeneratedIdeaCard(
                                idea: idea,
                                onAdd: { onAddToInbox(idea) }
                            )
                        }
                    }
                }
                .frame(maxHeight: 350)
            }
        }
        .padding(Spacing.large)
        .frame(width: 400)
        .background(Linear.surfaceElevated)
        .cornerRadius(CornerRadius.xxl)
    }
}

// MARK: - Generated Idea Card

struct GeneratedIdeaCard: View {
    let idea: GeneratedIdea
    let onAdd: () -> Void

    @State private var isHovered = false
    @State private var isAdding = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            // Title
            Text(idea.title)
                .font(Typography.featureTitle)
                .foregroundColor(Linear.textPrimary)
                .lineLimit(2)

            // Description
            if !idea.description.isEmpty {
                Text(idea.description)
                    .font(Typography.caption)
                    .foregroundColor(Linear.textSecondary)
                    .lineLimit(3)
            }

            // Rationale
            if !idea.rationale.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "lightbulb.min")
                        .font(.system(size: 10))
                    Text(idea.rationale)
                        .font(.system(size: 11))
                }
                .foregroundColor(Accent.brainstorm.opacity(0.8))
                .lineLimit(2)
            }

            // Add button
            HStack {
                Spacer()

                Button(action: {
                    isAdding = true
                    onAdd()
                }) {
                    HStack(spacing: 4) {
                        if isAdding {
                            ProgressView()
                                .controlSize(.mini)
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "plus.circle.fill")
                        }
                        Text("Add to Inbox")
                    }
                    .font(Typography.caption)
                    .padding(.horizontal, Spacing.small)
                    .padding(.vertical, Spacing.micro)
                    .background(isHovered ? Accent.success.opacity(0.3) : Accent.success.opacity(0.15))
                    .foregroundColor(Accent.success)
                    .cornerRadius(CornerRadius.small)
                }
                .buttonStyle(.plain)
                .disabled(isAdding)
            }
        }
        .padding(Spacing.standard)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.medium, style: .continuous)
                .fill(isHovered ? Linear.hoverBackground : Linear.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.medium, style: .continuous)
                        .strokeBorder(Linear.border, lineWidth: 1)
                )
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Preview

#Preview {
    IdeaGeneratorButton()
        .environment(AppState())
        .padding()
        .background(Linear.background)
}
