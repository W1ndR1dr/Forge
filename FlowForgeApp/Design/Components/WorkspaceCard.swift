import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - Workspace Card
// Shows an active workspace (feature being worked on)
// For vibecoders: "Each workspace is isolated — changes can't interfere!"

struct WorkspaceCard: View {
    @Environment(AppState.self) private var appState
    let feature: Feature
    let onResume: () -> Void
    let onStop: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false
    @State private var isLaunching = false
    @State private var hasConflicts = false
    @State private var conflictFiles: [String] = []
    @State private var isCheckingConflicts = false
    @State private var showingDeleteConfirmation = false

    // Smart mark-done state
    @State private var isMarkingDone = false
    @State private var showDoneToast = false
    @State private var doneToastMessage = ""
    @State private var doneToastIsSuccess = true

    private let apiClient = APIClient()

    /// Status indicator color
    private var statusColor: Color {
        switch feature.status {
        case .inProgress:
            return StatusColor.inProgressFallback
        case .review:
            return StatusColor.reviewFallback
        default:
            return .secondary
        }
    }

    /// Friendly status message
    private var statusMessage: String {
        switch feature.status {
        case .inProgress:
            if let path = feature.worktreePath {
                let folder = URL(fileURLWithPath: path).lastPathComponent
                return "Worktree: \(folder)"
            }
            return "In worktree"
        case .review:
            return "Ready for review"
        default:
            return feature.status.displayName
        }
    }

    /// Time since started
    private var timeWorking: String {
        guard let started = feature.startedAt else { return "" }
        let elapsed = Date().timeIntervalSince(started)

        if elapsed < 60 {
            return "Just started"
        } else if elapsed < 3600 {
            let minutes = Int(elapsed / 60)
            return "\(minutes)m"
        } else {
            let hours = Int(elapsed / 3600)
            return "\(hours)h"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            // Header with status
            HStack {
                // Pulsing status indicator
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                    .pulse(isActive: feature.status == .inProgress)

                Text(feature.title)
                    .font(Typography.body)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Spacer()

                // Delete button (show on hover)
                if isHovered {
                    Button(action: { showingDeleteConfirmation = true }) {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                            .foregroundColor(Accent.danger)
                    }
                    .buttonStyle(.plain)
                    .help("Delete feature")
                    .transition(.opacity)
                }

                if !timeWorking.isEmpty {
                    Text(timeWorking)
                        .font(Typography.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Status message and worktree path
            VStack(alignment: .leading, spacing: Spacing.micro) {
                Text(statusMessage)
                    .font(Typography.caption)
                    .foregroundColor(.secondary)

                // Clickable worktree path
                #if os(macOS)
                if let path = feature.worktreePath {
                    Button(action: { openInFinder(path) }) {
                        HStack(spacing: 4) {
                            Image(systemName: "folder")
                                .font(.system(size: 10))
                            Text(path)
                                .font(.system(size: 10, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .foregroundColor(.secondary.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .help("Open in Finder")
                }
                #endif
            }

            // Conflict warning
            if hasConflicts {
                HStack(spacing: Spacing.small) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(Accent.warning)
                        .font(.system(size: 12))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Conflicts with main")
                            .font(Typography.caption)
                            .fontWeight(.medium)
                            .foregroundColor(Accent.warning)
                        Text("\(conflictFiles.count) file(s) - sync before shipping")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(Spacing.small)
                .background(Accent.warning.opacity(0.1))
                .cornerRadius(CornerRadius.small)
            }

            // Actions
            HStack(spacing: Spacing.small) {
                #if os(macOS)
                Button(action: { Task { await openInTerminal() } }) {
                    Label(isLaunching ? "Opening..." : "Open in Terminal", systemImage: "terminal")
                        .font(Typography.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isLaunching || feature.worktreePath == nil)
                #endif

                #if os(macOS)
                if feature.status == .inProgress {
                    Button(action: { Task { await markAsDone() } }) {
                        Label(
                            isMarkingDone ? "Processing..." : "Mark Done",
                            systemImage: isMarkingDone ? "hourglass" : "checkmark.circle"
                        )
                        .font(Typography.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(Accent.success)
                    .disabled(isMarkingDone)
                }
                #endif
            }
        }
        .padding(Spacing.medium)
        .background(Surface.elevated)
        .cornerRadius(CornerRadius.medium)
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.medium)
                .stroke(hasConflicts ? Accent.warning.opacity(0.5) : statusColor.opacity(isHovered ? 0.5 : 0.2), lineWidth: hasConflicts ? 2 : 1)
        )
        // Toast overlay for mark-done feedback
        .overlay(alignment: .bottom) {
            if showDoneToast {
                HStack(spacing: Spacing.small) {
                    Image(systemName: doneToastIsSuccess ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    Text(doneToastMessage)
                }
                .font(Typography.caption)
                .padding(.horizontal, Spacing.medium)
                .padding(.vertical, Spacing.small)
                .background(doneToastIsSuccess ? Accent.success.opacity(0.95) : Accent.danger.opacity(0.95))
                .foregroundColor(.white)
                .clipShape(Capsule())
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .padding(.bottom, Spacing.small)
            }
        }
        .hoverable(isHovered: isHovered)
        .onHover { isHovered = $0 }
        .onAppear {
            Task { await checkConflicts() }
        }
        .confirmationDialog(
            "Delete Feature?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { onDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Delete \"\(feature.title)\"? This will remove the feature and clean up the worktree.")
        }
    }

    // MARK: - Actions

    #if os(macOS)
    /// Smart mark-as-done: detects if merged and shows appropriate feedback
    @MainActor
    private func markAsDone() async {
        isMarkingDone = true
        defer { isMarkingDone = false }

        guard let outcome = await appState.smartDoneFeature(feature) else {
            // Error case - show error toast
            showToast(message: "Failed to mark done", isSuccess: false)
            return
        }

        // Success - show appropriate toast based on outcome
        if outcome == "shipped" {
            showToast(message: "Shipped!", isSuccess: true)
        } else {
            showToast(message: "Marked for review", isSuccess: true)
        }
    }

    /// Show a toast notification with auto-dismiss
    private func showToast(message: String, isSuccess: Bool) {
        doneToastMessage = message
        doneToastIsSuccess = isSuccess

        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            showDoneToast = true
        }

        // Auto-dismiss after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showDoneToast = false
            }
        }
    }

    /// Open Claude Code in the worktree directory
    @MainActor
    private func openInTerminal() async {
        print("[WorkspaceCard] openInTerminal called for feature: \(feature.title)")
        print("[WorkspaceCard] worktreePath: \(feature.worktreePath ?? "nil")")
        print("[WorkspaceCard] promptPath: \(feature.promptPath ?? "nil")")

        guard let worktreePath = feature.worktreePath else {
            print("[WorkspaceCard] No worktreePath, returning early")
            return
        }

        isLaunching = true
        defer { isLaunching = false }

        // Try to read saved prompt for first-time launch
        // prompt_path from registry can be absolute or relative
        var promptContent: String? = nil
        var promptURL: URL? = nil
        if let promptPath = feature.promptPath, !promptPath.isEmpty {
            if promptPath.hasPrefix("/") {
                // Absolute path - use directly
                promptURL = URL(fileURLWithPath: promptPath)
            } else {
                // Relative path - construct from project root (worktree parent's parent)
                let worktreeURL = URL(fileURLWithPath: worktreePath)
                let projectRoot = worktreeURL.deletingLastPathComponent().deletingLastPathComponent()
                promptURL = projectRoot.appendingPathComponent(promptPath)
            }

            print("[WorkspaceCard] Checking for prompt at: \(promptURL?.path ?? "nil")")

            if let url = promptURL, FileManager.default.fileExists(atPath: url.path) {
                do {
                    promptContent = try String(contentsOf: url, encoding: .utf8)
                    print("[WorkspaceCard] Loaded prompt (\(promptContent?.count ?? 0) chars)")
                } catch {
                    print("[WorkspaceCard] Failed to read prompt: \(error)")
                }
            } else {
                print("[WorkspaceCard] No prompt file found, will use --resume")
            }
        }

        // Launch Claude Code - with prompt for first start, or --resume to continue
        let result = await TerminalLauncher.launchClaudeCode(
            worktreePath: worktreePath,
            prompt: promptContent,
            launchCommand: nil  // Let TerminalLauncher decide based on prompt presence
        )
        print("[WorkspaceCard] TerminalLauncher result: \(result.success) - \(result.message)")

        // After successful launch with prompt, rename file so next click uses --resume
        if result.success, promptContent != nil, let url = promptURL {
            let usedURL = url.deletingPathExtension().appendingPathExtension("used.md")
            try? FileManager.default.moveItem(at: url, to: usedURL)
            print("[WorkspaceCard] Renamed prompt to .used.md for future --resume")
        }
    }

    /// Open the worktree folder in Finder
    private func openInFinder(_ path: String) {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
    }
    #endif

    /// Check if this feature has conflicts with main
    @MainActor
    private func checkConflicts() async {
        guard let project = appState.selectedProject,
              feature.worktreePath != nil else { return }

        isCheckingConflicts = true
        defer { isCheckingConflicts = false }

        do {
            let result = try await apiClient.checkMergeConflicts(
                project: project.name,
                featureId: feature.id
            )
            hasConflicts = result.hasConflicts
            conflictFiles = result.conflictFiles
        } catch {
            // Silently fail - conflict check is optional
            print("Failed to check conflicts: \(error)")
        }
    }
}

// MARK: - Building Section
// Shows all features currently being worked on

struct ActiveWorkspacesSection: View {
    @Environment(AppState.self) private var appState

    /// Features that are currently being worked on (in-progress or review)
    private var activeFeatures: [Feature] {
        appState.features.filter { $0.status == .inProgress || $0.status == .review }
    }

    /// Next idea ready to start
    private var nextIdea: Feature? {
        appState.features.first { $0.status == .idea }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            // Header
            HStack {
                HStack(spacing: Spacing.small) {
                    Image(systemName: "hammer.fill")
                        .foregroundColor(Accent.primary)
                    Text("BUILDING")
                        .sectionHeaderStyle()
                }

                if !activeFeatures.isEmpty {
                    Text("\(activeFeatures.count)")
                        .badgeStyle(color: Accent.primary)
                }

                Spacer()

                // Helpful tip
                if activeFeatures.count > 1 {
                    Text("Each isolated — no conflicts!")
                        .font(Typography.caption)
                        .foregroundColor(.secondary)
                }
            }

            if activeFeatures.isEmpty {
                // Empty state - show "Start next" if we have ideas ready
                if let nextFeature = nextIdea {
                    StartNextCard(feature: nextFeature)
                } else {
                    VStack(spacing: Spacing.small) {
                        Image(systemName: "laptopcomputer")
                            .font(.system(size: 24))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("Nothing in progress")
                            .font(Typography.body)
                            .foregroundColor(.secondary)
                        Text("Add ideas above, then start one")
                            .font(Typography.caption)
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(Spacing.large)
                    .background(Surface.elevated)
                    .cornerRadius(CornerRadius.medium)
                }
            } else {
                // Workspace cards grid
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: Spacing.small) {
                    ForEach(activeFeatures) { feature in
                        WorkspaceCard(
                            feature: feature,
                            onResume: {
                                Task {
                                    await resumeWorkspace(feature)
                                }
                            },
                            onStop: {
                                Task {
                                    await appState.stopFeature(feature)
                                }
                            },
                            onDelete: {
                                Task {
                                    await appState.deleteFeature(feature)
                                }
                            }
                        )
                    }
                }
            }
        }
    }

    @MainActor
    private func resumeWorkspace(_ feature: Feature) async {
        #if os(macOS)
        guard let worktreePath = feature.worktreePath else { return }

        // Try to read saved prompt for first-time launch
        var promptContent: String? = nil
        var promptURL: URL? = nil
        if let promptPath = feature.promptPath, !promptPath.isEmpty {
            if promptPath.hasPrefix("/") {
                promptURL = URL(fileURLWithPath: promptPath)
            } else {
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
        #endif
    }
}

// MARK: - Start Next Card

/// Card shown when no active work - prompts to start the next planned feature
struct StartNextCard: View {
    @Environment(AppState.self) private var appState
    let feature: Feature

    @State private var isStarting = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            HStack {
                VStack(alignment: .leading, spacing: Spacing.micro) {
                    Text("Ready to build")
                        .font(Typography.caption)
                        .foregroundColor(.secondary)
                    Text(feature.title)
                        .font(Typography.featureTitle)
                        .lineLimit(2)
                }

                Spacer()
            }

            if let desc = feature.description, !desc.isEmpty {
                Text(desc)
                    .font(Typography.body)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Button(action: startFeature) {
                HStack {
                    if isStarting {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "play.fill")
                    }
                    Text(isStarting ? "Starting..." : "Start Building")
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity)
                .padding(Spacing.medium)
                .background(Accent.primary)
                .foregroundColor(.white)
                .cornerRadius(CornerRadius.medium)
            }
            .buttonStyle(.plain)
            .disabled(isStarting)
        }
        .padding(Spacing.standard)
        .background(Surface.elevated)
        .cornerRadius(CornerRadius.large)
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.large)
                .stroke(Accent.primary.opacity(0.3), lineWidth: 1)
        )
    }

    private func startFeature() {
        isStarting = true
        Task {
            await appState.startFeature(feature)
            isStarting = false
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    VStack(spacing: Spacing.large) {
        // Single workspace card
        WorkspaceCard(
            feature: Feature(
                id: "dark-mode",
                title: "Add dark mode toggle",
                status: .inProgress,
                startedAt: Date().addingTimeInterval(-3600)
            ),
            onResume: {},
            onStop: {},
            onDelete: {}
        )
        .frame(width: 250)

        // Section with multiple workspaces
        ActiveWorkspacesSection()
            .environment(AppState())
    }
    .padding()
    .frame(width: 600)
    .background(Surface.window)
}
#endif
