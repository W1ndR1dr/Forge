import SwiftUI

/// The Chat-to-Spec experience.
///
/// A conversational interface where users brainstorm with Claude until
/// a feature spec crystallizes. This is the heart of the vibecoder experience.
///
/// "Talk to Claude until your idea becomes buildable."
struct BrainstormChatView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @StateObject private var client = BrainstormClient()

    @State private var inputText = ""
    @State private var showingSpec = false
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
                            ForEach(client.messages) { message in
                                MessageBubble(message: message)
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

            // Input area
            inputView
        }
        .frame(minWidth: 500, minHeight: 500)
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
                if let feature = existingFeature {
                    Text("Let's crystallize this idea")
                        .font(Typography.sectionHeader)

                    Text("I'll ask questions to help make \"\(feature.title)\" specific and implementable.")
                        .font(Typography.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    Text("What would you like to build?")
                        .font(Typography.sectionHeader)

                    Text("Describe your idea and I'll help you turn it into a spec.")
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
                        Image(systemName: "arrow.right.circle.fill")
                        Text("Start Refining")
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
        // Send the feature title to Claude to start the crystallization process
        client.sendMessage("I want to refine this idea: \(feature.title)")
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
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: BrainstormClient.BrainstormMessage

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
                Text(message.content.isEmpty ? "..." : message.content)
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

    let spec: BrainstormClient.CrystallizedSpec
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
                        Label("Crystallized", systemImage: "sparkles")
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
                        Label(isUpdating ? "Apply Changes" : "Build This",
                              systemImage: isUpdating ? "checkmark.circle.fill" : "hammer.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isCreating)
            }
        }
        .padding(Spacing.large)
        .frame(minWidth: 450, minHeight: 400)
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
                // UPDATE existing feature with crystallized spec
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
