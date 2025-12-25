import SwiftUI

// MARK: - Workspace Card
// Shows an active workspace (feature being worked on)
// For vibecoders: "Each workspace is isolated — changes can't interfere!"

struct WorkspaceCard: View {
    let feature: Feature
    let onResume: () -> Void
    let onStop: () -> Void

    @State private var isHovered = false

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
            return "Claude is working"
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

                if !timeWorking.isEmpty {
                    Text(timeWorking)
                        .font(Typography.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Status message
            HStack(spacing: Spacing.small) {
                if feature.status == .inProgress {
                    InlineLoader(message: statusMessage)
                } else {
                    Text(statusMessage)
                        .font(Typography.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Actions
            HStack(spacing: Spacing.small) {
                Button(action: onResume) {
                    Label("Resume", systemImage: "arrow.right.circle")
                        .font(Typography.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                if feature.status == .inProgress {
                    Button(action: onStop) {
                        Label("Mark Done", systemImage: "checkmark.circle")
                            .font(Typography.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(Accent.success)
                }
            }
        }
        .padding(Spacing.medium)
        .background(Surface.elevated)
        .cornerRadius(CornerRadius.medium)
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.medium)
                .stroke(statusColor.opacity(isHovered ? 0.5 : 0.2), lineWidth: 1)
        )
        .hoverable(isHovered: isHovered)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Active Workspaces Section
// Shows all features currently being worked on

struct ActiveWorkspacesSection: View {
    @Environment(AppState.self) private var appState

    /// Features that are currently being worked on (in-progress or review)
    private var activeFeatures: [Feature] {
        appState.features.filter { $0.status == .inProgress || $0.status == .review }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            // Header
            HStack {
                HStack(spacing: Spacing.small) {
                    Image(systemName: "hammer.fill")
                        .foregroundColor(Accent.primary)
                    Text("ACTIVE WORKSPACES")
                        .sectionHeaderStyle()
                }

                if !activeFeatures.isEmpty {
                    Text("\(activeFeatures.count)")
                        .badgeStyle(color: Accent.primary)
                }

                Spacer()

                // Helpful tip
                if !activeFeatures.isEmpty {
                    Text("Each isolated — no conflicts!")
                        .font(Typography.caption)
                        .foregroundColor(.secondary)
                }
            }

            if activeFeatures.isEmpty {
                // Empty state
                VStack(spacing: Spacing.small) {
                    Image(systemName: "laptopcomputer")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No active workspaces")
                        .font(Typography.body)
                        .foregroundColor(.secondary)
                    Text("Start a feature to create a workspace")
                        .font(Typography.caption)
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .frame(maxWidth: .infinity)
                .padding(Spacing.large)
                .background(Surface.elevated)
                .cornerRadius(CornerRadius.medium)
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
                                resumeWorkspace(feature)
                            },
                            onStop: {
                                Task {
                                    await appState.stopFeature(feature)
                                }
                            }
                        )
                    }
                }
            }
        }
    }

    private func resumeWorkspace(_ feature: Feature) {
        // For now, copy the prompt to clipboard if available
        if let promptPath = feature.promptPath {
            #if os(macOS)
            // Try to open the worktree in Claude Code
            if let worktreePath = feature.worktreePath {
                let url = URL(fileURLWithPath: worktreePath)
                NSWorkspace.shared.open(url)
            }
            #endif
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
            onStop: {}
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
