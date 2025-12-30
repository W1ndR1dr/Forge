import SwiftUI

/// The Chat-to-Spec experience.
///
/// A conversational interface where users brainstorm with Claude until
/// a feature spec is refined. This is the heart of the vibecoder experience.
///
/// "Talk to Claude until your idea becomes buildable."
struct BrainstormChatView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @StateObject private var client = BrainstormClient()

    @State private var inputText = ""
    @State private var showingSpec = false
    @State private var isGeneratingSpec = false
    @FocusState private var isInputFocused: Bool

    let project: String
    var existingFeature: Feature?  // Feature being refined (nil = new brainstorm)

    /// Whether we're refining an existing feature vs brainstorming new ideas
    private var isRefiningFeature: Bool {
        existingFeature != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Spacing.medium) {
                        if client.messages.isEmpty {
                            emptyStateView
                        } else {
                            ForEach(Array(client.messages.enumerated()), id: \.element.id) { index, message in
                                // Show streaming text for the last assistant message while typing
                                let isLastAssistant = index == client.messages.count - 1 && message.role == .assistant
                                let displayText = isLastAssistant && client.isTyping ? client.streamingText : message.content
                                MessageBubble(message: message, displayText: displayText)
                                    .id(message.id)
                            }
                        }

                        // Scroll anchor
                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                    .padding(Spacing.standard)
                }
                .onChange(of: client.messages.count) { _, _ in
                    withAnimation(.spring(response: 0.3)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }

            Divider()

            // Long conversation warning (like Claude Code's compaction warning)
            if client.messages.count >= 8 && client.currentSpec == nil && !client.isTyping {
                longConversationBanner
            }

            // Spec ready indicator
            if client.currentSpec != nil {
                specReadyBanner
            }

            // Input area
            inputView
        }
        .frame(minWidth: 600, idealWidth: 750, minHeight: 550, idealHeight: 700)
        .onAppear {
            client.connect(
                project: project,
                featureId: existingFeature?.id,
                featureTitle: existingFeature?.title
            )
            client.onSpecReady = { spec in
                showingSpec = true
            }
            isInputFocused = true
        }
        .onDisappear {
            client.disconnect()
        }
        .sheet(isPresented: $showingSpec) {
            if let spec = client.currentSpec {
                SpecPreviewSheet(
                    spec: spec,
                    project: project,
                    existingFeature: existingFeature  // Pass for update vs create logic
                )
                .environment(appState)
            }
        }
        .onChange(of: client.isTyping) { _, isTyping in
            // Reset spec generation state when typing completes
            if !isTyping && isGeneratingSpec {
                isGeneratingSpec = false
            }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: Spacing.micro) {
                // Show context when refining an existing feature
                if let feature = existingFeature {
                    Text("Refining")
                        .font(Typography.caption)
                        .foregroundColor(Accent.primary)
                    Text(feature.title)
                        .font(Typography.featureTitle)
                        .lineLimit(1)
                } else {
                    Text("Brainstorm")
                        .font(Typography.featureTitle)
                }

                HStack(spacing: Spacing.small) {
                    Circle()
                        .fill(client.isConnected ? Color.green : Color.red)
                        .frame(width: 8, height: 8)

                    Text(client.isConnected ? "Connected to Claude" : "Connecting...")
                        .font(Typography.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Button(action: { client.reset() }) {
                Image(systemName: "arrow.counterclockwise")
            }
            .buttonStyle(.bordered)
            .help("Start fresh")

            // Generate Spec button - only show after some conversation
            if client.messages.count >= 2 && !client.isTyping && client.currentSpec == nil {
                Button(action: generateSpec) {
                    HStack(spacing: Spacing.micro) {
                        if isGeneratingSpec {
                            ProgressView()
                                .scaleEffect(0.6)
                        } else {
                            Image(systemName: "sparkles")
                        }
                        Text("Generate Spec")
                    }
                }
                .buttonStyle(.bordered)
                .tint(Accent.primary)
                .help("Generate spec from current conversation")
                .disabled(isGeneratingSpec)
            }

            Button("Done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.escape)
        }
        .padding(Spacing.standard)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: Spacing.large) {
            Image(systemName: isRefiningFeature ? "sparkles" : "lightbulb.fill")
                .font(.system(size: 48))
                .foregroundColor(isRefiningFeature ? Accent.primary.opacity(0.6) : Accent.warning.opacity(0.6))

            VStack(spacing: Spacing.small) {
                if existingFeature != nil {
                    Text("Let's make this idea buildable")
                        .font(Typography.sectionHeader)

                    Text("I'll ask clarifying questions until we have a clear, implementable spec.")
                        .font(Typography.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    Text("What would you like to build?")
                        .font(Typography.sectionHeader)

                    Text("Describe your idea and I'll help turn it into a spec.")
                        .font(Typography.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }

            // Only show suggestion chips for new brainstorms
            if !isRefiningFeature {
                VStack(alignment: .leading, spacing: Spacing.small) {
                    suggestionChip("Add dark mode to the app")
                    suggestionChip("Show heart rate during workouts")
                    suggestionChip("Let users export their data")
                }
            } else {
                // For refinement, show a "Start" button to kick things off
                Button(action: { startRefinement() }) {
                    HStack {
                        Image(systemName: "sparkles")
                        Text("Start")
                    }
                    .padding(.horizontal, Spacing.large)
                    .padding(.vertical, Spacing.medium)
                    .background(Accent.primary)
                    .foregroundColor(.white)
                    .cornerRadius(CornerRadius.large)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, Spacing.xl)
        .frame(maxWidth: .infinity)
    }

    /// Auto-start refinement with the feature title as context
    private func startRefinement() {
        guard let feature = existingFeature else { return }
        // Send the feature title to Claude to start the refinement process
        client.sendMessage("Help me refine this idea: \(feature.title)")
    }

    private func suggestionChip(_ text: String) -> some View {
        Button(action: {
            inputText = text
            sendMessage()
        }) {
            HStack {
                Image(systemName: "sparkle")
                    .font(.caption)
                Text(text)
                    .font(Typography.body)
            }
            .padding(.horizontal, Spacing.medium)
            .padding(.vertical, Spacing.small)
            .background(Surface.elevated)
            .cornerRadius(CornerRadius.large)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Spec Ready Banner

    private var specReadyBanner: some View {
        Button(action: { showingSpec = true }) {
            HStack(spacing: Spacing.small) {
                Image(systemName: "sparkles")
                    .foregroundColor(Accent.success)
                Text(isRefiningFeature ? "Ready to promote!" : "Spec ready!")
                    .font(Typography.caption)
                    .fontWeight(.medium)
                Spacer()
                Text("Review")
                    .font(Typography.caption)
                    .foregroundColor(Accent.primary)
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(Accent.primary)
            }
            .padding(.horizontal, Spacing.standard)
            .padding(.vertical, Spacing.small)
            .background(Accent.success.opacity(0.1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Long Conversation Warning

    private var longConversationBanner: some View {
        VStack(spacing: Spacing.small) {
            HStack(spacing: Spacing.small) {
                Image(systemName: "clock.badge.exclamationmark")
                    .foregroundColor(Accent.warning)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Long conversation (\(client.messages.count) messages)")
                        .font(Typography.caption)
                        .fontWeight(.medium)
                    Text("Responses may be slower. Consider generating a spec.")
                        .font(Typography.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            HStack(spacing: Spacing.medium) {
                Button(action: generateSpecAndReset) {
                    HStack(spacing: Spacing.micro) {
                        Image(systemName: "sparkles")
                        Text("Generate Spec")
                    }
                    .font(Typography.caption)
                    .fontWeight(.medium)
                }
                .buttonStyle(.borderedProminent)
                .tint(Accent.primary)

                Button(action: { /* Just dismiss by doing nothing - banner won't show during typing */ }) {
                    Text("Continue Anyway")
                        .font(Typography.caption)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(Spacing.standard)
        .background(Accent.warning.opacity(0.1))
    }

    /// Generate spec and offer to reset conversation for fresh iteration
    private func generateSpecAndReset() {
        isGeneratingSpec = true
        client.sendMessage("""
            Based on our discussion, please generate a SPEC_READY summary.
            Format it with the standard SPEC_READY format including:
            FEATURE, WHAT IT DOES, HOW IT WORKS, FILES LIKELY AFFECTED, and ESTIMATED SCOPE.
            """)
    }

    // MARK: - Input Area

    private var inputView: some View {
        HStack(spacing: Spacing.medium) {
            TextField("Type your idea...", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(Typography.body)
                .lineLimit(1...5)
                .focused($isInputFocused)
                .onSubmit {
                    if !inputText.isEmpty {
                        sendMessage()
                    }
                }

            Button(action: sendMessage) {
                Group {
                    if client.isTyping {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                    }
                }
                .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .foregroundColor(inputText.isEmpty ? .secondary : Accent.primary)
            .disabled(inputText.isEmpty || client.isTyping)
        }
        .padding(Spacing.standard)
        .background(Surface.elevated)
    }

    // MARK: - Actions

    private func sendMessage() {
        let message = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }

        client.sendMessage(message)
        inputText = ""
    }

    private func generateSpec() {
        isGeneratingSpec = true

        // Send a message that triggers spec generation
        let specRequest = """
        Please generate the spec now based on our conversation so far. \
        Even if we haven't covered every detail, create the best spec you can \
        with the information we have discussed. Use the SPEC_READY format.
        """

        client.sendMessage(specRequest)
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: BrainstormClient.BrainstormMessage
    var displayText: String? = nil  // Override text (for streaming)

    private var textToShow: String {
        let text = displayText ?? message.content
        return text.isEmpty ? "..." : text
    }

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.medium) {
            if message.role == .user {
                Spacer(minLength: 60)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: Spacing.micro) {
                // Role indicator
                HStack(spacing: Spacing.micro) {
                    if message.role == .assistant {
                        Image(systemName: "brain.head.profile")
                            .font(.caption)
                            .foregroundColor(Accent.primary)
                    }
                    Text(message.role == .user ? "You" : "Claude")
                        .font(Typography.caption)
                        .foregroundColor(.secondary)
                }

                // Message content
                Text(textToShow)
                    .font(Typography.body)
                    .padding(Spacing.medium)
                    .background(message.role == .user ? Accent.primary : Surface.elevated)
                    .foregroundColor(message.role == .user ? .white : .primary)
                    .cornerRadius(CornerRadius.large)
                    .textSelection(.enabled)
            }

            if message.role == .assistant {
                Spacer(minLength: 60)
            }
        }
    }
}

// MARK: - Spec Preview Sheet

struct SpecPreviewSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let spec: BrainstormClient.RefinedSpec
    let project: String
    var existingFeature: Feature?  // Feature being refined (nil = create new)

    @State private var isCreating = false

    /// Whether we're updating an existing feature vs creating new
    private var isUpdating: Bool {
        existingFeature != nil
    }

    var body: some View {
        VStack(spacing: Spacing.large) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: Spacing.micro) {
                    if isUpdating {
                        Label("Refined", systemImage: "sparkles")
                            .font(Typography.caption)
                            .foregroundColor(Accent.primary)
                    } else {
                        Label("Spec Ready", systemImage: "checkmark.seal.fill")
                            .font(Typography.caption)
                            .foregroundColor(Accent.success)
                    }

                    Text(spec.title)
                        .font(Typography.sectionHeader)
                }

                Spacer()

                Button("Dismiss") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.large) {
                    // What it does
                    specSection("What it does", content: spec.whatItDoes)

                    // How it works
                    VStack(alignment: .leading, spacing: Spacing.small) {
                        Text("How it works")
                            .sectionHeaderStyle()

                        ForEach(spec.howItWorks, id: \.self) { item in
                            HStack(alignment: .top, spacing: Spacing.small) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(Accent.success)
                                    .font(.caption)
                                Text(item)
                                    .font(Typography.body)
                            }
                        }
                    }

                    // Files affected
                    if !spec.filesAffected.isEmpty {
                        VStack(alignment: .leading, spacing: Spacing.small) {
                            Text("Files likely affected")
                                .sectionHeaderStyle()

                            ForEach(spec.filesAffected, id: \.self) { file in
                                Text(file)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    // Scope
                    HStack {
                        Text("Estimated scope:")
                            .font(Typography.caption)
                            .foregroundColor(.secondary)
                        Text(spec.estimatedScope)
                            .font(Typography.caption)
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            // Actions
            HStack {
                Button("Refine More") {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(action: applySpec) {
                    if isCreating {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Label(isUpdating ? "Save" : "Add to Backlog",
                              systemImage: isUpdating ? "checkmark.circle.fill" : "plus.circle.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isCreating)
            }
        }
        .padding(Spacing.large)
        .frame(minWidth: 500, idealWidth: 600, minHeight: 450, idealHeight: 550)
    }

    private func specSection(_ title: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            Text(title)
                .sectionHeaderStyle()
            Text(content)
                .font(Typography.body)
        }
    }

    private func applySpec() {
        isCreating = true

        Task {
            if let feature = existingFeature {
                // UPDATE existing feature with refined spec
                await appState.updateFeatureWithSpec(
                    featureId: feature.id,
                    title: spec.title,
                    description: spec.whatItDoes,
                    howItWorks: spec.howItWorks,
                    filesAffected: spec.filesAffected,
                    estimatedScope: spec.estimatedScope
                )
            } else {
                // CREATE new feature from spec
                await appState.addFeature(title: spec.title)
            }

            await MainActor.run {
                isCreating = false
                dismiss()
            }
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Chat View") {
    BrainstormChatView(project: "FlowForge")
        .environment(AppState())
        .frame(width: 600, height: 700)
}
#endif
