import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - Mission Control V2
// The redesigned shipping-focused dashboard
//
// Influenced by: The Legendary Design Panel
// - Jony Ive: Every pixel feels considered
// - Dieter Rams: Less, but better
// - Bret Victor: Immediate feedback, see the work
// - Edward Tufte: Show the data, eliminate chartjunk
// - Mike Matas: Physics-based, magical moments

struct MissionControlV2: View {
    @Environment(AppState.self) private var appState

    @State private var vibeText = ""
    @State private var isAnalyzing = false

    // MARK: - Computed Properties

    private var activeFeature: Feature? {
        appState.features.first { $0.status == .inProgress }
            ?? appState.features.first { $0.status == .review }
    }

    private var upNextFeatures: [Feature] {
        Array(appState.features.filter { $0.status == .planned }.prefix(3))
    }

    private var slotsRemaining: Int {
        max(0, 3 - upNextFeatures.count)
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

    private var ideaFeatures: [Feature] {
        appState.features.filter { $0.status == .idea }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // Main content
            ScrollView {
                VStack(spacing: Spacing.xl) {
                    // Level 0: The Vibe Input
                    vibeInputSection

                    // Level 1: Today's Mission (single focus)
                    todaysMissionSection

                    // Active Workspaces (parallel development)
                    ActiveWorkspacesSection()

                    // Level 2: The Pipeline (peripheral awareness)
                    pipelineSection

                    // Level 2.5: Idea Inbox (quick captures)
                    if !ideaFeatures.isEmpty {
                        ideaInboxSection
                    }

                    // Level 3: Shipped This Week
                    shippedSection
                }
                .padding(Spacing.large)
            }
            .background(Surface.window)
        }
    }

    // MARK: - Vibe Input Section

    private var vibeInputSection: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            // Header with streak
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: Spacing.micro) {
                    if let project = appState.selectedProject {
                        Text(project.name)
                            .font(Typography.largeTitle)
                    }
                    Text("What do you want to ship?")
                        .font(Typography.body)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Streak badge
                StreakBadge(
                    currentStreak: appState.shippingStats.currentStreak,
                    longestStreak: appState.shippingStats.longestStreak,
                    totalShipped: appState.shippingStats.totalShipped
                )
            }

            // The iconic vibe input
            VibeInputWithScope(
                text: $vibeText,
                onSubmit: { idea in
                    analyzeFeature(idea)
                },
                isAnalyzing: isAnalyzing || appState.isAnalyzingFeature,
                slotsRemaining: slotsRemaining
            )

            // Show analysis loading state
            if appState.isAnalyzingFeature {
                FeatureAnalysisLoading(title: appState.pendingFeatureTitle)
                    .transition(.scaleAndFade)
            }

            // Show analysis results (inline preview)
            if let analysis = appState.pendingAnalysis {
                FeatureAnalysisPreview(
                    title: appState.pendingFeatureTitle,
                    analysis: analysis,
                    onConfirm: {
                        confirmFeature()
                    },
                    onCancel: {
                        cancelAnalysis()
                    }
                )
                .transition(.scaleAndFade)
            }
        }
        .animation(SpringPreset.smooth, value: appState.pendingAnalysis != nil)
        .animation(SpringPreset.smooth, value: appState.isAnalyzingFeature)
    }

    // MARK: - Today's Mission Section

    private var todaysMissionSection: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            Text("TODAY'S MISSION")
                .sectionHeaderStyle()

            if let feature = activeFeature {
                ActiveMissionCardV2(
                    feature: feature,
                    onShip: {
                        shipFeature(feature)
                    }
                )
            } else if let nextFeature = upNextFeatures.first {
                StartMissionCardV2(
                    feature: nextFeature,
                    onStart: {
                        Task {
                            await appState.startFeature(nextFeature)
                        }
                    }
                )
            } else {
                EmptyFeaturesView(onAddFeature: {
                    // Focus the vibe input
                })
            }
        }
    }

    // MARK: - Pipeline Section

    private var pipelineSection: some View {
        HStack(alignment: .top, spacing: Spacing.medium) {
            // Up Next Queue
            upNextCard

            // Blocked indicator
            if !blockedFeatures.isEmpty {
                blockedCard
            }

            // Quick stats
            statsCard
        }
    }

    private var upNextCard: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            HStack {
                Text("UP NEXT")
                    .sectionHeaderStyle()

                Spacer()

                // Slot indicators
                HStack(spacing: Spacing.micro) {
                    ForEach(0..<3) { index in
                        Circle()
                            .fill(index < upNextFeatures.count ? StatusColor.inProgressFallback : Color.secondary.opacity(0.3))
                            .frame(width: 6, height: 6)
                    }
                }
            }

            if upNextFeatures.isEmpty {
                EmptyBlockedView()
                    .frame(height: 80)
            } else {
                VStack(spacing: Spacing.small) {
                    ForEach(Array(upNextFeatures.enumerated()), id: \.element.id) { index, feature in
                        UpNextCardV2(feature: feature, position: index + 1)
                    }
                }
            }
        }
        .padding(Spacing.standard)
        .background(Surface.elevated)
        .cornerRadius(CornerRadius.large)
        .frame(maxWidth: .infinity)
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
                BlockedCardV2(feature: feature)
            }
        }
        .padding(Spacing.standard)
        .background(Accent.danger.opacity(0.1))
        .cornerRadius(CornerRadius.large)
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
                    Text("\(upNextFeatures.count)")
                        .font(Typography.streakNumber)
                        .foregroundColor(StatusColor.inProgressFallback)
                    Text("queued")
                        .font(Typography.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(Spacing.standard)
        .background(Surface.elevated)
        .cornerRadius(CornerRadius.large)
    }

    // MARK: - Idea Inbox Section

    private var ideaInboxSection: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            HStack {
                HStack(spacing: Spacing.small) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundColor(.purple)
                    Text("IDEA INBOX")
                        .sectionHeaderStyle()
                }

                Text("\(ideaFeatures.count)")
                    .badgeStyle(color: .purple)

                Spacer()
            }

            VStack(spacing: Spacing.small) {
                ForEach(ideaFeatures) { feature in
                    IdeaCardV2(
                        feature: feature,
                        onCrystallize: {
                            crystallizeIdea(feature)
                        },
                        onArchive: {
                            archiveIdea(feature)
                        }
                    )
                }
            }
        }
        .padding(Spacing.standard)
        .background(Color.purple.opacity(0.05))
        .cornerRadius(CornerRadius.large)
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
                        ShippedCardV2(feature: feature)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    /// Step 1: Analyze the feature (show AI insights before adding)
    private func analyzeFeature(_ idea: String) {
        vibeText = ""  // Clear input immediately for responsiveness

        Task {
            await appState.analyzeFeature(title: idea)
        }
    }

    /// Step 2: User confirmed - add the feature
    private func confirmFeature() {
        Task {
            await appState.confirmAnalyzedFeature()
        }
    }

    /// User cancelled - clear analysis
    private func cancelAnalysis() {
        appState.clearPendingAnalysis()
    }

    /// Legacy direct submit (bypasses analysis - kept for compatibility)
    private func submitFeature(_ idea: String) {
        isAnalyzing = true

        Task {
            // Add the feature via API
            await appState.addFeature(title: idea)

            // Reload features to show the new one
            await appState.loadFeatures()

            await MainActor.run {
                isAnalyzing = false
                vibeText = ""
            }
        }
    }

    private func shipFeature(_ feature: Feature) {
        Task {
            let success = await appState.shipFeature(feature)
            // Success/failure handled via appState.successMessage/errorMessage
            _ = success
        }
    }

    private func crystallizeIdea(_ feature: Feature) {
        Task {
            await appState.crystallizeFeature(feature)
        }
    }

    private func archiveIdea(_ feature: Feature) {
        Task {
            await appState.deleteFeature(feature)
        }
    }
}

// MARK: - Active Mission Card V2

struct ActiveMissionCardV2: View {
    @Environment(AppState.self) private var appState
    let feature: Feature
    let onShip: () -> Void

    @State private var isHovered = false
    @State private var isVisible = false
    @State private var isLaunchingTerminal = false
    @State private var gitStatus: GitStatus?
    @State private var isLoadingGitStatus = false

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
                    Button(action: { Task { await openInTerminal(worktreePath) } }) {
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
                .background(Surface.highlighted)
                .cornerRadius(CornerRadius.medium)
                .onAppear {
                    Task { await loadGitStatus() }
                }
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
        .background(Surface.elevated)
        .cornerRadius(CornerRadius.large)
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.large)
                .stroke(StatusColor.inProgressFallback.opacity(0.3), lineWidth: 2)
        )
        .hoverable(isHovered: isHovered)
        .onHover { isHovered = $0 }
        .scaleEffect(isVisible ? 1.0 : 0.95)
        .opacity(isVisible ? 1 : 0)
        .onAppear {
            withAnimation(SpringPreset.gentle) {
                isVisible = true
            }
        }
    }

    // MARK: - Actions

    #if os(macOS)
    /// Open Claude Code in the worktree directory
    @MainActor
    private func openInTerminal(_ worktreePath: String) async {
        isLaunchingTerminal = true
        defer { isLaunchingTerminal = false }

        let _ = await TerminalLauncher.launchClaudeCode(
            worktreePath: worktreePath,
            prompt: nil,  // No auto-paste on resume
            launchCommand: "claude --dangerously-skip-permissions"
        )
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
        .cornerRadius(4)
    }
}

// MARK: - Start Mission Card V2

struct StartMissionCardV2: View {
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
        .background(Surface.elevated)
        .cornerRadius(CornerRadius.large)
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.large)
                .stroke(Accent.primary.opacity(0.2), lineWidth: 1)
        )
        .hoverable(isHovered: isHovered)
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

// MARK: - Up Next Card V2

struct UpNextCardV2: View {
    let feature: Feature
    let position: Int
    var isSafeToParallelize: Bool = true  // Default to safe for vibecoders

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: Spacing.medium) {
            // Position indicator
            Text("\(position)")
                .font(Typography.caption)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: Spacing.micro) {
                HStack(spacing: Spacing.small) {
                    Text(feature.title)
                        .font(Typography.body)
                        .lineLimit(1)

                    // Safe to parallelize badge
                    if isSafeToParallelize {
                        ParallelSafeBadge()
                    }
                }

                if !feature.tags.isEmpty {
                    Text(feature.tags.joined(separator: " · "))
                        .font(Typography.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Complexity indicator (Tufte - the color IS the information)
            if let complexity = feature.complexity {
                Circle()
                    .fill(complexityColor(complexity))
                    .frame(width: 8, height: 8)
            }
        }
        .padding(Spacing.medium)
        .background(isHovered ? Surface.highlighted : Color.clear)
        .cornerRadius(CornerRadius.medium)
        .onHover { isHovered = $0 }
    }

    private func complexityColor(_ complexity: Complexity) -> Color {
        switch complexity {
        case .small: return ComplexityColor.small
        case .medium: return ComplexityColor.medium
        case .large: return ComplexityColor.large
        case .epic: return ComplexityColor.epic
        }
    }
}

// MARK: - Parallel Safe Badge
// Shows when a feature can be worked on alongside others

struct ParallelSafeBadge: View {
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 8))
            Text("parallel ok")
                .font(.system(size: 9, weight: .medium))
        }
        .foregroundColor(Accent.success)
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(Accent.success.opacity(0.15))
        .cornerRadius(4)
        .help("Safe to work on this while other features are in progress")
        .onHover { isHovered = $0 }
    }
}

// MARK: - Blocked Card V2

struct BlockedCardV2: View {
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

// MARK: - Shipped Card V2

struct ShippedCardV2: View {
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

// MARK: - Idea Card V2

struct IdeaCardV2: View {
    let feature: Feature
    let onCrystallize: () -> Void
    let onArchive: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: Spacing.medium) {
            // Lightbulb icon
            Image(systemName: "lightbulb")
                .foregroundColor(.purple)
                .font(.system(size: 14))

            // Title
            Text(feature.title)
                .font(Typography.body)
                .lineLimit(1)

            Spacer()

            // Actions (show on hover)
            if isHovered {
                HStack(spacing: Spacing.small) {
                    Button(action: onCrystallize) {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                            Text("Crystallize")
                        }
                        .font(Typography.caption)
                        .padding(.horizontal, Spacing.small)
                        .padding(.vertical, Spacing.micro)
                        .background(Color.purple.opacity(0.2))
                        .foregroundColor(.purple)
                        .cornerRadius(CornerRadius.small)
                    }
                    .buttonStyle(.plain)
                    .help("Refine this idea into a shippable feature")

                    Button(action: onArchive) {
                        Image(systemName: "archivebox")
                            .font(Typography.caption)
                            .padding(Spacing.micro)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Archive this idea")
                }
                .transition(.opacity)
            }
        }
        .padding(Spacing.medium)
        .background(isHovered ? Color.purple.opacity(0.1) : Color.clear)
        .cornerRadius(CornerRadius.medium)
        .onHover { isHovered = $0 }
        .animation(SpringPreset.snappy, value: isHovered)
    }
}

// MARK: - Preview

#if DEBUG
struct MissionControlV2Preview: View {
    var body: some View {
        MissionControlV2()
            .environment(AppState.preview)
            .frame(width: 800, height: 900)
    }
}

#Preview {
    MissionControlV2Preview()
}

extension AppState {
    static var preview: AppState {
        let state = AppState()
        // Add sample data for preview
        return state
    }
}
#endif
