import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - Workspace View
// The main shipping-focused dashboard
//
// Influenced by: The Legendary Design Panel
// - Jony Ive: Every pixel feels considered
// - Dieter Rams: Less, but better
// - Bret Victor: Immediate feedback, see the work
// - Edward Tufte: Show the data, eliminate chartjunk
// - Mike Matas: Physics-based, magical moments

struct WorkspaceView: View {
    @Environment(AppState.self) private var appState

    @State private var vibeText = ""
    @State private var isSubmitting = false
    @State private var brainstormFeature: Feature?  // Set to show brainstorm sheet

    // MARK: - Computed Properties

    private var activeFeature: Feature? {
        appState.features.first { $0.status == .inProgress }
            ?? appState.features.first { $0.status == .review }
    }

    private var inboxFeatures: [Feature] {
        // Raw captures that need refining (sorted)
        appState.sortedInboxItems
    }

    private var ideaFeatures: [Feature] {
        // Refined ideas ready to build (sorted)
        appState.sortedIdeas
    }

    private var slotsRemaining: Int {
        // Ideas are unlimited - always allow adding
        99
    }

    private var shippedThisWeek: [Feature] {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return appState.features.filter { feature in
            feature.status == .completed &&
            (feature.completedAt ?? Date.distantPast) > weekAgo
        }
    }

    private var blockedFeatures: [Feature] {
        appState.features.filter { $0.status == .blocked }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // Main content
            ScrollView {
                VStack(spacing: Spacing.xl) {
                    // Offline mode banner
                    if !appState.isConnectedToServer {
                        OfflineBanner(
                            connectionState: appState.connectionState,
                            onRetry: {
                                Task { await appState.refreshSystemStatus() }
                            }
                        )
                    }

                    // Level 0: Capture - The Vibe Input
                    vibeInputSection

                    // Level 1: Raw captures - need refining
                    inboxSection

                    // Level 2: Ready to Build - refined, pick one to start
                    if !ideaFeatures.isEmpty {
                        ideasSection
                    }

                    // Level 3: Building - what you're actively working on
                    ActiveWorkspacesSection()

                    // Level 4: Done - shipped features
                    shippedSection
                }
                .padding(Spacing.large)
            }
            .background(Linear.background)
        }
    }

    // MARK: - Vibe Input Section

    private var vibeInputSection: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            // The iconic vibe input - submit adds directly to queue
            // Project name is now in the unified toolbar
            VibeInputWithScope(
                text: $vibeText,
                onSubmit: { idea in
                    submitFeatureDirectly(idea)
                },
                isAnalyzing: isSubmitting,
                slotsRemaining: slotsRemaining
            )
        }
        .sheet(item: $brainstormFeature) { feature in
            if let project = appState.selectedProject {
                BrainstormChatView(
                    project: project.name,
                    existingFeature: feature  // Feature being refined
                )
                .environment(appState)
            }
        }
    }

    // MARK: - Ideas Section (Refined, Ready to Build)

    private var ideasSection: some View {
        @Bindable var state = appState

        return VStack(alignment: .leading, spacing: Spacing.medium) {
            // Header
            HStack {
                HStack(spacing: Spacing.small) {
                    Image(systemName: "lightbulb.max.fill")
                        .foregroundColor(Accent.success)
                    Text("IDEAS IN PROGRESS")
                        .sectionHeaderStyle()
                }

                Text("\(ideaFeatures.count)")
                    .badgeStyle(color: Accent.success)

                Spacer()

                SortPicker(selection: $state.ideaSortOrder)
            }

            // Ideas (refined, ready to build)
            ScrollView {
                VStack(spacing: Spacing.small) {
                    ForEach(ideaFeatures) { feature in
                        IdeaFeatureCard(
                            feature: feature,
                            onStart: {
                                Task { await appState.startFeature(feature) }
                            },
                            onRefine: { refineFeature(feature) },
                            onDelete: { archiveIdea(feature) },
                            onDemote: { demoteToInbox(feature) }
                        )
                    }
                }
            }
            .frame(maxHeight: 250)
        }
        .linearSection()
    }

    // MARK: - Inbox Section (Raw Captures)

    private var inboxSection: some View {
        @Bindable var state = appState

        return VStack(alignment: .leading, spacing: Spacing.medium) {
            // Header
            HStack {
                HStack(spacing: Spacing.small) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundColor(Accent.warning)
                    Text("IDEA INBOX")
                        .sectionHeaderStyle()
                }

                if !inboxFeatures.isEmpty {
                    Text("\(inboxFeatures.count)")
                        .badgeStyle(color: Accent.warning)
                }

                Spacer()

                SortPicker(selection: $state.inboxSortOrder)
            }

            // Inbox items
            if inboxFeatures.isEmpty {
                VStack(spacing: Spacing.medium) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No raw captures")
                        .font(Typography.body)
                        .foregroundColor(.secondary)
                    Text("Type above to capture an idea, then refine it")
                        .font(Typography.caption)
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .frame(maxWidth: .infinity)
                .padding(Spacing.xl)
            } else {
                ScrollView {
                    VStack(spacing: Spacing.small) {
                        ForEach(inboxFeatures) { feature in
                            InboxCard(
                                feature: feature,
                                onRefine: { refineFeature(feature) },
                                onMarkReady: { promoteToIdea(feature) },
                                onDelete: { archiveIdea(feature) }
                            )
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
        }
        .linearSection()
    }

    private var blockedCard: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            HStack {
                Text("BLOCKED")
                    .sectionHeaderStyle()
                    .foregroundColor(Accent.danger)

                Text("\(blockedFeatures.count)")
                    .font(Typography.badge)
                    .foregroundColor(.white)
                    .padding(.horizontal, Spacing.small)
                    .padding(.vertical, Spacing.micro)
                    .background(Accent.danger)
                    .cornerRadius(CornerRadius.small)
            }

            ForEach(blockedFeatures) { feature in
                BlockedCard(feature: feature)
            }
        }
        .padding(Spacing.standard)
        .background(Linear.elevated)
        .cornerRadius(CornerRadius.large)
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.large)
                .stroke(Accent.danger.opacity(0.3), lineWidth: 1)
        )
        .frame(width: 200)
    }

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            Text("THIS WEEK")
                .sectionHeaderStyle()

            HStack(spacing: Spacing.large) {
                VStack(spacing: Spacing.micro) {
                    Text("\(shippedThisWeek.count)")
                        .font(Typography.streakNumber)
                        .foregroundColor(Accent.success)
                    Text("shipped")
                        .font(Typography.caption)
                        .foregroundColor(.secondary)
                }

                VStack(spacing: Spacing.micro) {
                    Text("\(ideaFeatures.count + inboxFeatures.count)")
                        .font(Typography.streakNumber)
                        .foregroundColor(StatusColor.inProgressFallback)
                    Text("queued")
                        .font(Typography.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .linearSection()
    }

    // MARK: - Shipped Section

    private var shippedSection: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            HStack {
                Text("SHIPPED THIS WEEK")
                    .sectionHeaderStyle()

                if !shippedThisWeek.isEmpty {
                    Text("\(shippedThisWeek.count)")
                        .badgeStyle(color: Accent.success)
                }

                Spacer()
            }

            if shippedThisWeek.isEmpty {
                EmptyShippedView()
                    .frame(height: 120)
            } else {
                // Small multiples (Tufte)
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: Spacing.small) {
                    ForEach(shippedThisWeek) { feature in
                        ShippedCard(feature: feature)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    /// Direct submit - add to queue immediately (no fake AI gate)
    private func submitFeatureDirectly(_ idea: String) {
        vibeText = ""  // Clear input immediately for responsiveness
        isSubmitting = true

        Task {
            await appState.addFeatureToQueue(title: idea)
            await appState.loadFeatures()

            await MainActor.run {
                isSubmitting = false
            }
        }
    }

    /// Open brainstorm chat to refine a feature
    private func refineFeature(_ feature: Feature) {
        brainstormFeature = feature  // Setting this shows the sheet
    }

    private func shipFeature(_ feature: Feature) {
        Task {
            let success = await appState.shipFeature(feature)
            // Success/failure handled via appState.successMessage/errorMessage
            _ = success
        }
    }

    private func promoteToIdea(_ feature: Feature) {
        Task {
            await appState.refineFeature(feature)
        }
    }

    private func demoteToInbox(_ feature: Feature) {
        Task {
            await appState.demoteFeature(feature)
        }
    }

    private func archiveIdea(_ feature: Feature) {
        Task {
            await appState.deleteFeature(feature)
        }
    }
}

// MARK: - Active Work Card

struct ActiveWorkCard: View {
    @Environment(AppState.self) private var appState
    let feature: Feature
    let onShip: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false
    @State private var isVisible = false
    @State private var isLaunchingTerminal = false
    @State private var gitStatus: GitStatus?
    @State private var isLoadingGitStatus = false
    @State private var showingDeleteConfirmation = false

    private let apiClient = APIClient()

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.standard) {
            // Status and title
            HStack {
                // Pulsing status indicator
                Circle()
                    .fill(feature.status == .review ? StatusColor.reviewFallback : StatusColor.inProgressFallback)
                    .frame(width: 12, height: 12)
                    .pulse(isActive: feature.status == .inProgress)

                Text(feature.title)
                    .font(Typography.featureTitle)

                Spacer()

                // Delete button (show on hover)
                if isHovered {
                    Button(action: { showingDeleteConfirmation = true }) {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundColor(Accent.danger)
                    }
                    .buttonStyle(.plain)
                    .help("Delete feature")
                    .transition(.opacity)
                }

                Text(feature.status.displayName)
                    .badgeStyle(color: feature.status == .review ? StatusColor.reviewFallback : StatusColor.inProgressFallback)
            }

            // Description
            if let description = feature.description, !description.isEmpty {
                Text(description)
                    .font(Typography.body)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            // Worktree indicator (shows feature is actively being built)
            if feature.status == .inProgress, let worktreePath = feature.worktreePath {
                VStack(spacing: Spacing.small) {
                    HStack(spacing: Spacing.small) {
                        Image(systemName: "folder.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 12))

                        Text("Working in worktree")
                            .font(Typography.caption)
                            .foregroundColor(.secondary)

                        Spacer()

                        // Clickable path to open in Finder
                        #if os(macOS)
                        Button(action: { openInFinder(worktreePath) }) {
                            Text(URL(fileURLWithPath: worktreePath).lastPathComponent)
                                .font(Typography.caption)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Open in Finder")
                        #else
                        Text(URL(fileURLWithPath: worktreePath).lastPathComponent)
                            .font(Typography.caption)
                            .foregroundColor(.secondary)
                        #endif
                    }

                    // Git status badges
                    if let status = gitStatus {
                        HStack(spacing: Spacing.small) {
                            if status.hasChanges {
                                GitStatusBadge(
                                    icon: "pencil.circle.fill",
                                    text: "\(status.changes.count) uncommitted",
                                    color: Accent.warning
                                )
                            }
                            if status.aheadOfMain > 0 {
                                GitStatusBadge(
                                    icon: "arrow.up.circle.fill",
                                    text: "\(status.aheadOfMain) ahead",
                                    color: Accent.success
                                )
                            }
                            if status.behindMain > 0 {
                                GitStatusBadge(
                                    icon: "arrow.down.circle.fill",
                                    text: "\(status.behindMain) behind",
                                    color: Accent.warning
                                )
                            }
                            if !status.hasChanges && status.aheadOfMain == 0 && status.behindMain == 0 {
                                GitStatusBadge(
                                    icon: "checkmark.circle.fill",
                                    text: "Clean",
                                    color: .secondary
                                )
                            }

                            Spacer()

                            // Refresh button
                            Button(action: { Task { await loadGitStatus() } }) {
                                Image(systemName: isLoadingGitStatus ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .disabled(isLoadingGitStatus)
                        }
                    } else if isLoadingGitStatus {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.6)
                            Text("Loading git status...")
                                .font(Typography.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    // Open in Terminal button
                    #if os(macOS)
                    Button(action: { Task { await openInTerminal(worktreePath, promptPath: feature.promptPath) } }) {
                        HStack {
                            Image(systemName: "terminal")
                            Text(isLaunchingTerminal ? "Opening..." : "Open in Claude Code")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(Spacing.small)
                        .background(Accent.primary.opacity(0.1))
                        .foregroundColor(Accent.primary)
                        .cornerRadius(CornerRadius.small)
                    }
                    .buttonStyle(.plain)
                    .disabled(isLaunchingTerminal)
                    #endif
                }
                .padding(Spacing.small)
                .background(Linear.hover)
                .cornerRadius(CornerRadius.medium)
                .onAppear {
                    Task { await loadGitStatus() }
                }
            }

            // Drift warning banner (if health issue detected)
            if let issue = appState.healthIssue(for: feature.id) {
                DriftWarningBanner(
                    issue: issue,
                    featureTitle: feature.title,
                    isReconciling: appState.isReconciling,
                    onFix: { action in
                        Task {
                            await appState.reconcileFeature(featureId: feature.id, action: action)
                        }
                    }
                )
            }

            // SHIP IT button (Julie Zhuo - obvious next action)
            if feature.status == .review {
                Button(action: onShip) {
                    HStack {
                        Image(systemName: "paperplane.fill")
                        Text("SHIP IT")
                            .fontWeight(.bold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(Spacing.medium)
                    .background(Accent.success)
                    .foregroundColor(.white)
                    .cornerRadius(CornerRadius.medium)
                }
                .buttonStyle(.plain)
                .pressable(isPressed: false)
            }
        }
        .padding(Spacing.standard)
        .background(Linear.card)
        .cornerRadius(CornerRadius.large)
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.large)
                .stroke(StatusColor.inProgressFallback.opacity(isHovered ? 0.5 : 0.3), lineWidth: 1)
        )
        .animation(LinearEasing.fast, value: isHovered)
        .onHover { isHovered = $0 }
        .scaleEffect(isVisible ? 1.0 : 0.95)
        .opacity(isVisible ? 1 : 0)
        .onAppear {
            withAnimation(SpringPreset.gentle) {
                isVisible = true
            }
        }
        .confirmationDialog(
            "Delete Feature?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { onDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Delete \"\(feature.title)\"? This will remove the feature and any worktree.")
        }
    }

    // MARK: - Actions

    #if os(macOS)
    /// Open Claude Code in the worktree directory
    @MainActor
    private func openInTerminal(_ worktreePath: String, promptPath: String? = nil) async {
        isLaunchingTerminal = true
        defer { isLaunchingTerminal = false }

        // Try to read saved prompt for first-time launch
        var promptContent: String? = nil
        var promptURL: URL? = nil
        if let promptPath = promptPath, !promptPath.isEmpty {
            if promptPath.hasPrefix("/") {
                // Absolute path - use directly
                promptURL = URL(fileURLWithPath: promptPath)
            } else {
                // Relative path - construct from project root
                let worktreeURL = URL(fileURLWithPath: worktreePath)
                let projectRoot = worktreeURL.deletingLastPathComponent().deletingLastPathComponent()
                promptURL = projectRoot.appendingPathComponent(promptPath)
            }

            if let url = promptURL, FileManager.default.fileExists(atPath: url.path) {
                promptContent = try? String(contentsOf: url, encoding: .utf8)
            }
        }

        // Launch Claude Code - with prompt for first start, or --resume to continue
        let result = await TerminalLauncher.launchClaudeCode(
            worktreePath: worktreePath,
            prompt: promptContent,
            launchCommand: nil
        )

        // After successful launch with prompt, rename file so next click uses --resume
        if result.success, promptContent != nil, let url = promptURL {
            let usedURL = url.deletingPathExtension().appendingPathExtension("used.md")
            try? FileManager.default.moveItem(at: url, to: usedURL)
        }
    }

    /// Open the worktree folder in Finder
    private func openInFinder(_ path: String) {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
    }
    #endif

    /// Load git status for this feature's worktree
    @MainActor
    private func loadGitStatus() async {
        guard let project = appState.selectedProject else { return }

        isLoadingGitStatus = true
        defer { isLoadingGitStatus = false }

        do {
            gitStatus = try await apiClient.getGitStatus(
                project: project.name,
                featureId: feature.id
            )
        } catch {
            // Silently fail - git status is optional info
            print("Failed to load git status: \(error)")
        }
    }
}

// MARK: - Git Status Badge

struct GitStatusBadge: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(text)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundColor(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(color.opacity(0.15))
        .cornerRadius(CornerRadius.small)
    }
}

// MARK: - Drift Warning Banner

/// Banner shown when registry state doesn't match git state
struct DriftWarningBanner: View {
    let issue: HealthIssue
    let featureTitle: String
    let isReconciling: Bool
    let onFix: (String) -> Void

    @State private var showingConfirmation = false

    var body: some View {
        HStack(spacing: Spacing.medium) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(Accent.warning)
                .font(.system(size: 16))

            VStack(alignment: .leading, spacing: 2) {
                Text(issueMessage)
                    .font(Typography.caption)
                    .foregroundColor(.primary)

                if issue.type == "branch_merged" {
                    Text("Branch was merged outside Forge")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if issue.canAutoFix, let action = issue.fixAction {
                Button(action: { showingConfirmation = true }) {
                    if isReconciling {
                        ProgressView()
                            .scaleEffect(0.6)
                    } else {
                        Text("Fix")
                            .font(Typography.caption)
                            .fontWeight(.medium)
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, Spacing.medium)
                .padding(.vertical, Spacing.small)
                .background(Accent.warning.opacity(0.2))
                .foregroundColor(Accent.warning)
                .cornerRadius(CornerRadius.small)
                .disabled(isReconciling)
                .confirmationDialog(
                    confirmationTitle,
                    isPresented: $showingConfirmation,
                    titleVisibility: .visible
                ) {
                    Button(confirmationButtonText) {
                        onFix(action)
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text(confirmationMessage)
                }
            }
        }
        .padding(Spacing.medium)
        .background(Accent.warning.opacity(0.1))
        .cornerRadius(CornerRadius.medium)
    }

    private var issueMessage: String {
        switch issue.type {
        case "branch_merged":
            return "Already shipped!"
        case "missing_worktree":
            return "Worktree missing"
        case "orphan_worktree":
            return "Orphan worktree"
        default:
            return issue.message
        }
    }

    private var confirmationTitle: String {
        switch issue.type {
        case "branch_merged":
            return "Mark as Completed?"
        case "missing_worktree":
            return "Clear Worktree Path?"
        default:
            return "Fix Issue?"
        }
    }

    private var confirmationMessage: String {
        switch issue.type {
        case "branch_merged":
            return "This will mark '\(featureTitle)' as completed since the branch is already merged."
        case "missing_worktree":
            return "This will clear the stale worktree path from '\(featureTitle)'."
        default:
            return "This will reconcile the registry with git state."
        }
    }

    private var confirmationButtonText: String {
        switch issue.type {
        case "branch_merged":
            return "Mark Completed"
        case "missing_worktree":
            return "Clear Path"
        default:
            return "Fix"
        }
    }
}

// MARK: - Start Work Card

struct StartWorkCard: View {
    @Environment(AppState.self) private var appState
    let feature: Feature
    let onStart: () -> Void

    @State private var isHovered = false
    @State private var showingPromptPreview = false
    @State private var isLoadingPrompt = false
    @State private var promptText: String?
    @State private var promptError: String?

    private let apiClient = APIClient()

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.standard) {
            Text("Ready to build?")
                .font(Typography.body)
                .foregroundColor(.secondary)

            Text(feature.title)
                .font(Typography.featureTitle)

            // Tags
            if !feature.tags.isEmpty {
                HStack(spacing: Spacing.small) {
                    ForEach(feature.tags, id: \.self) { tag in
                        Text(tag)
                            .badgeStyle(color: .secondary)
                    }
                }
            }

            // Preview prompt button (secondary action)
            Button(action: { Task { await loadPromptPreview() } }) {
                HStack {
                    Image(systemName: "doc.text.magnifyingglass")
                    Text(isLoadingPrompt ? "Loading..." : "Preview Prompt")
                }
                .font(Typography.caption)
                .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(isLoadingPrompt)

            Button(action: onStart) {
                HStack {
                    Image(systemName: "hammer.fill")
                    Text("START BUILDING")
                        .fontWeight(.bold)
                }
                .frame(maxWidth: .infinity)
                .padding(Spacing.medium)
                .background(Accent.primary)
                .foregroundColor(.white)
                .cornerRadius(CornerRadius.medium)
            }
            .buttonStyle(.plain)
            .pressable(isPressed: false)
        }
        .padding(Spacing.standard)
        .background(Linear.card)
        .cornerRadius(CornerRadius.large)
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.large)
                .stroke(Accent.primary.opacity(isHovered ? 0.4 : 0.2), lineWidth: 1)
        )
        .animation(LinearEasing.fast, value: isHovered)
        .onHover { isHovered = $0 }
        .sheet(isPresented: $showingPromptPreview) {
            PromptPreviewSheet(
                featureTitle: feature.title,
                prompt: promptText ?? "Failed to load prompt",
                error: promptError,
                onDismiss: { showingPromptPreview = false }
            )
        }
    }

    @MainActor
    private func loadPromptPreview() async {
        guard let project = appState.selectedProject else { return }

        isLoadingPrompt = true
        promptError = nil

        do {
            promptText = try await apiClient.getPrompt(
                project: project.name,
                featureId: feature.id
            )
            showingPromptPreview = true
        } catch {
            promptError = error.localizedDescription
            showingPromptPreview = true
        }

        isLoadingPrompt = false
    }
}

// MARK: - Prompt Preview Sheet

struct PromptPreviewSheet: View {
    let featureTitle: String
    let prompt: String
    let error: String?
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: Spacing.micro) {
                    Text("Prompt Preview")
                        .font(Typography.sectionHeader)
                    Text(featureTitle)
                        .font(Typography.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button("Done") {
                    onDismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            // Content
            if let error = error {
                VStack(spacing: Spacing.medium) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundColor(Accent.danger)
                    Text("Failed to load prompt")
                        .font(Typography.body)
                    Text(error)
                        .font(Typography.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                ScrollView {
                    Text(prompt)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
            }

            Divider()

            // Footer
            HStack {
                Text("This is the prompt Claude Code will receive")
                    .font(Typography.caption)
                    .foregroundColor(.secondary)

                Spacer()

                #if os(macOS)
                Button(action: copyToClipboard) {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                #endif
            }
            .padding()
        }
        .frame(width: 600, height: 500)
    }

    #if os(macOS)
    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)
    }
    #endif
}

// MARK: - Blocked Card

struct BlockedCard: View {
    let feature: Feature

    var body: some View {
        HStack(spacing: Spacing.small) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(Accent.danger)
                .font(.system(size: 12))

            Text(feature.title)
                .font(Typography.caption)
                .lineLimit(1)
        }
        .padding(Spacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Accent.danger.opacity(0.1))
        .cornerRadius(CornerRadius.small)
    }
}

// MARK: - Shipped Card

struct ShippedCard: View {
    let feature: Feature

    @State private var isVisible = false

    var body: some View {
        HStack(spacing: Spacing.small) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(Accent.success)
                .font(.system(size: 14))

            Text(feature.title)
                .font(Typography.caption)
                .lineLimit(1)

            Spacer()
        }
        .padding(Spacing.small)
        .background(Accent.success.opacity(0.1))
        .cornerRadius(CornerRadius.small)
        .bounceIn(isVisible: isVisible)
        .onAppear {
            isVisible = true
        }
    }
}

// MARK: - Idea Feature Card (Ready to Build)

struct IdeaFeatureCard: View {
    @Environment(AppState.self) private var appState
    let feature: Feature
    let onStart: () -> Void
    let onRefine: () -> Void
    let onDelete: () -> Void
    let onDemote: () -> Void

    @State private var isHovered = false
    @State private var showingDeleteConfirmation = false
    @State private var showingPromptPreview = false
    @State private var isLoadingPrompt = false
    @State private var promptText: String?
    @State private var promptError: String?

    private let apiClient = APIClient()

    var body: some View {
        HStack(spacing: Spacing.medium) {
            // Checkmark icon (refined)
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(Accent.success)
                .font(.system(size: 16))

            // Title and description
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Spacing.micro) {
                    Text(feature.title)
                        .font(Typography.body)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    // Prompt indicator - subtle doc icon when prompt exists
                    if feature.promptPath != nil {
                        Image(systemName: "doc.text.fill")
                            .font(.system(size: 10))
                            .foregroundColor(Accent.primary.opacity(0.6))
                            .help("Implementation prompt ready")
                    }
                }

                if let desc = feature.description, !desc.isEmpty {
                    Text(desc.components(separatedBy: "\n").first ?? "")
                        .font(Typography.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Actions
            if isHovered {
                HStack(spacing: Spacing.small) {
                    // Demote back to inbox
                    Button(action: onDemote) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(Typography.caption)
                            .foregroundColor(.orange)
                    }
                    .buttonStyle(.plain)
                    .help("Send back to inbox")

                    Button(action: { showingDeleteConfirmation = true }) {
                        Image(systemName: "trash")
                            .font(Typography.caption)
                            .foregroundColor(Accent.danger)
                    }
                    .buttonStyle(.plain)
                    .help("Delete feature")

                    // Preview prompt
                    Button(action: { Task { await loadPromptPreview() } }) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(Typography.caption)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Preview implementation prompt")
                    .disabled(isLoadingPrompt)

                    Button(action: onRefine) {
                        HStack(spacing: 4) {
                            Image(systemName: "pencil")
                            Text("Edit")
                        }
                        .font(Typography.caption)
                        .padding(.horizontal, Spacing.small)
                        .padding(.vertical, Spacing.micro)
                        .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)

                    Button(action: onStart) {
                        HStack(spacing: 4) {
                            Image(systemName: "play.fill")
                            Text("Start")
                        }
                        .font(Typography.caption)
                        .padding(.horizontal, Spacing.medium)
                        .padding(.vertical, Spacing.small)
                        .background(Accent.success)
                        .foregroundColor(.white)
                        .cornerRadius(CornerRadius.small)
                    }
                    .buttonStyle(.plain)
                }
                .transition(.opacity)
            }
        }
        .padding(Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())  // Full row hover area
        .background(isHovered ? Linear.hover : Color.clear)
        .cornerRadius(CornerRadius.medium)
        .confirmationDialog(
            "Delete Feature?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { onDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Delete \"\(feature.title)\"? This cannot be undone.")
        }
        .sheet(isPresented: $showingPromptPreview) {
            PromptPreviewSheet(
                featureTitle: feature.title,
                prompt: promptText ?? "Failed to load prompt",
                error: promptError,
                onDismiss: { showingPromptPreview = false }
            )
        }
        .onHover { isHovered = $0 }
        .animation(LinearEasing.fast, value: isHovered)
    }

    @MainActor
    private func loadPromptPreview() async {
        guard let project = appState.selectedProject else { return }

        isLoadingPrompt = true
        promptError = nil

        do {
            promptText = try await apiClient.getPrompt(
                project: project.name,
                featureId: feature.id
            )
            showingPromptPreview = true
        } catch {
            promptError = error.localizedDescription
            showingPromptPreview = true
        }

        isLoadingPrompt = false
    }
}

// MARK: - Inbox Card

struct InboxCard: View {
    let feature: Feature
    let onRefine: () -> Void
    let onMarkReady: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false
    @State private var showingDeleteConfirmation = false

    /// Has this idea been refined (has description from chat)?
    private var isRefined: Bool {
        guard let desc = feature.description else { return false }
        return !desc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(spacing: Spacing.medium) {
            // Icon - different for refined vs raw
            Image(systemName: isRefined ? "checkmark.circle" : "lightbulb")
                .foregroundColor(isRefined ? Accent.success : Accent.brainstorm)
                .font(.system(size: 14))

            // Title and refinement status
            VStack(alignment: .leading, spacing: 2) {
                Text(feature.title)
                    .font(Typography.body)
                    .lineLimit(1)

                if isRefined {
                    Text("Refined — ready to promote")
                        .font(.system(size: 10))
                        .foregroundColor(Accent.success)
                }
            }

            Spacer()

            // Actions (show on hover)
            if isHovered {
                HStack(spacing: Spacing.small) {
                    if isRefined {
                        // Refined: can promote to Ready to Build
                        Button(action: onMarkReady) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.right.circle.fill")
                                Text("Ready")
                            }
                            .font(Typography.caption)
                            .padding(.horizontal, Spacing.small)
                            .padding(.vertical, Spacing.micro)
                            .background(Accent.success.opacity(0.2))
                            .foregroundColor(Accent.success)
                            .cornerRadius(CornerRadius.small)
                        }
                        .buttonStyle(.plain)
                        .help("Move to Ready to Build")

                        Button(action: onRefine) {
                            Image(systemName: "pencil")
                                .font(Typography.caption)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Edit spec")
                    } else {
                        // Raw: needs refinement
                        Button(action: onRefine) {
                            HStack(spacing: 4) {
                                Image(systemName: "sparkles")
                                Text("Refine")
                            }
                            .font(Typography.caption)
                            .padding(.horizontal, Spacing.small)
                            .padding(.vertical, Spacing.micro)
                            .background(Accent.brainstorm.opacity(0.15))
                            .foregroundColor(Accent.brainstorm)
                            .cornerRadius(CornerRadius.small)
                        }
                        .buttonStyle(.plain)
                        .help("Refine this idea with Claude")
                    }

                    Button(action: { showingDeleteConfirmation = true }) {
                        Image(systemName: "trash")
                            .font(Typography.caption)
                            .padding(Spacing.micro)
                            .foregroundColor(Accent.danger)
                    }
                    .buttonStyle(.plain)
                    .help("Delete this idea")
                }
                .transition(.opacity)
            }
        }
        .padding(Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())  // Full row hover area
        .background(isHovered ? Linear.hover : Color.clear)
        .cornerRadius(CornerRadius.medium)
        .onHover { isHovered = $0 }
        .animation(LinearEasing.fast, value: isHovered)
        .confirmationDialog(
            "Delete Idea?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                onDelete()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Delete \"\(feature.title)\"? This cannot be undone.")
        }
    }
}

// MARK: - Offline Banner

struct OfflineBanner: View {
    let connectionState: ConnectionState
    let onRetry: () -> Void

    @State private var isRetrying = false

    var body: some View {
        HStack(spacing: Spacing.medium) {
            // Icon
            Image(systemName: iconName)
                .font(.system(size: 16))
                .foregroundColor(iconColor)

            // Message
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Typography.body)
                    .fontWeight(.medium)
                Text(subtitle)
                    .font(Typography.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Retry button
            Button(action: retry) {
                if isRetrying {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .font(Typography.caption)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isRetrying)
        }
        .padding(Spacing.medium)
        .background(backgroundColor)
        .cornerRadius(CornerRadius.medium)
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.medium)
                .stroke(borderColor, lineWidth: 1)
        )
    }

    private var iconName: String {
        switch connectionState {
        case .connected:
            return "checkmark.circle.fill"
        case .piOnlyMode:
            return "exclamationmark.triangle.fill"
        case .offline:
            return "wifi.slash"
        }
    }

    private var iconColor: Color {
        switch connectionState {
        case .connected:
            return Accent.success
        case .piOnlyMode:
            return Accent.warning
        case .offline:
            return .secondary
        }
    }

    private var title: String {
        switch connectionState {
        case .connected:
            return "Connected"
        case .piOnlyMode:
            return "Limited Mode"
        case .offline:
            return "Offline"
        }
    }

    private var subtitle: String {
        switch connectionState {
        case .connected:
            return "All features available"
        case .piOnlyMode(let pending):
            if pending > 0 {
                return "Mac offline • \(pending) pending operation(s)"
            }
            return "Mac offline • Can view and add features"
        case .offline:
            return "Can't reach server • Showing cached data"
        }
    }

    private var backgroundColor: Color {
        switch connectionState {
        case .connected:
            return Accent.success.opacity(0.1)
        case .piOnlyMode:
            return Accent.warning.opacity(0.1)
        case .offline:
            return Color.secondary.opacity(0.1)
        }
    }

    private var borderColor: Color {
        switch connectionState {
        case .connected:
            return Accent.success.opacity(0.3)
        case .piOnlyMode:
            return Accent.warning.opacity(0.3)
        case .offline:
            return Color.secondary.opacity(0.3)
        }
    }

    private func retry() {
        isRetrying = true
        onRetry()
        // Reset after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isRetrying = false
        }
    }
}

// MARK: - Preview

#if DEBUG
struct WorkspaceViewPreview: View {
    var body: some View {
        WorkspaceView()
            .environment(AppState.preview)
            .frame(width: 800, height: 900)
    }
}

#Preview {
    WorkspaceViewPreview()
}

extension AppState {
    static var preview: AppState {
        let state = AppState()
        // Add sample data for preview
        return state
    }
}
#endif
