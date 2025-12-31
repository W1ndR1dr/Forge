import SwiftUI

/// Welcome Back experience.
///
/// Shows users what happened since their last session:
/// - Features that changed status
/// - Pending questions from AI
/// - What's ready to ship
///
/// "Here's what happened while you were away."
struct WelcomeBackView: View {
    @Environment(AppState.self) private var appState
    let project: String
    let onDismiss: () -> Void

    @State private var sessionState: SessionState?
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: Spacing.large) {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let state = sessionState {
                contentView(state)
            } else {
                emptyStateView
            }
        }
        .padding(Spacing.large)
        .frame(minWidth: 400, minHeight: 300)
        .task {
            await loadSession()
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func contentView(_ state: SessionState) -> some View {
        VStack(alignment: .leading, spacing: Spacing.large) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: Spacing.micro) {
                    Text("Welcome back!")
                        .font(Typography.sectionHeader)

                    Text(project)
                        .font(Typography.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if state.currentStreak > 0 {
                    streakBadge(state.currentStreak)
                }
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.large) {
                    // Changes since last visit
                    if !state.changesSince.isEmpty {
                        changesSection(state.changesSince)
                    }

                    // Pending questions
                    if !state.pendingQuestions.isEmpty {
                        questionsSection(state.pendingQuestions)
                    }

                    // Ready to ship
                    if !state.featuresReadyToShip.isEmpty {
                        readyToShipSection(state.featuresReadyToShip)
                    }

                    // In progress
                    if !state.featuresInProgress.isEmpty {
                        inProgressSection(state.featuresInProgress)
                    }

                    // Nothing new
                    if state.changesSince.isEmpty &&
                       state.pendingQuestions.isEmpty &&
                       state.featuresReadyToShip.isEmpty &&
                       state.featuresInProgress.isEmpty {
                        emptyStateView
                    }
                }
            }

            Divider()

            // Actions
            HStack {
                Spacer()

                Button("Let's Build") {
                    Task {
                        await recordVisit()
                    }
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Sections

    private func changesSection(_ changes: [FeatureChange]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            Label("Since last time", systemImage: "clock.arrow.circlepath")
                .sectionHeaderStyle()

            ForEach(changes.prefix(5), id: \.featureId) { change in
                HStack(spacing: Spacing.small) {
                    changeIcon(change.changeType)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(change.featureTitle)
                            .font(Typography.body)
                        Text(change.changeType.capitalized)
                            .font(Typography.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }
                .padding(Spacing.small)
                .background(Surface.elevated)
                .cornerRadius(CornerRadius.medium)
            }
        }
    }

    private func questionsSection(_ questions: [PendingQuestion]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            Label("Needs your input", systemImage: "questionmark.circle.fill")
                .sectionHeaderStyle()
                .foregroundColor(Accent.warning)

            ForEach(questions, id: \.featureId) { question in
                VStack(alignment: .leading, spacing: Spacing.small) {
                    Text(question.featureTitle)
                        .font(Typography.featureTitle)

                    Text(question.question)
                        .font(Typography.body)
                        .foregroundColor(.secondary)
                }
                .padding(Spacing.medium)
                .background(Accent.warning.opacity(0.1))
                .cornerRadius(CornerRadius.medium)
            }
        }
    }

    private func readyToShipSection(_ features: [String]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            Label("Ready to ship", systemImage: "checkmark.circle.fill")
                .sectionHeaderStyle()
                .foregroundColor(Accent.success)

            ForEach(features, id: \.self) { title in
                HStack {
                    Text(title)
                        .font(Typography.body)

                    Spacer()

                    Image(systemName: "arrow.right.circle")
                        .foregroundColor(Accent.success)
                }
                .padding(Spacing.small)
                .background(Accent.success.opacity(0.1))
                .cornerRadius(CornerRadius.medium)
            }
        }
    }

    private func inProgressSection(_ features: [String]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            Label("In progress", systemImage: "hammer.fill")
                .sectionHeaderStyle()

            ForEach(features, id: \.self) { title in
                HStack {
                    Text(title)
                        .font(Typography.body)

                    Spacer()

                    ProgressView()
                        .scaleEffect(0.7)
                }
                .padding(Spacing.small)
                .background(Surface.elevated)
                .cornerRadius(CornerRadius.medium)
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: Spacing.medium) {
            Image(systemName: "sparkles")
                .font(.system(size: 36))
                .foregroundColor(Accent.primary.opacity(0.6))

            Text("Ready to build something?")
                .font(Typography.body)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func streakBadge(_ streak: Int) -> some View {
        HStack(spacing: Spacing.micro) {
            Image(systemName: "flame.fill")
                .foregroundColor(Accent.streak)
            Text("\(streak)")
                .font(Typography.streakNumber)
        }
        .padding(.horizontal, Spacing.medium)
        .padding(.vertical, Spacing.small)
        .background(Accent.streak.opacity(0.15))
        .cornerRadius(CornerRadius.large)
    }

    private func changeIcon(_ type: String) -> some View {
        let (icon, color): (String, Color) = switch type {
        case "created": ("plus.circle.fill", Accent.primary)
        case "started": ("play.circle.fill", StatusColor.inProgressFallback)
        case "completed": ("checkmark.circle.fill", Accent.success)
        case "merged": ("arrow.triangle.merge", Accent.success)
        case "blocked": ("exclamationmark.triangle.fill", Accent.danger)
        default: ("circle.fill", Color.secondary)
        }

        return Image(systemName: icon)
            .foregroundColor(color)
    }

    // MARK: - API

    private func loadSession() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let url = URL(string: "\(PlatformConfig.currentServerURL)/api/\(project)/session")!
            let (data, _) = try await URLSession.shared.data(from: url)
            sessionState = try JSONDecoder().decode(SessionState.self, from: data)
        } catch {
            print("Failed to load session: \(error)")
        }
    }

    private func recordVisit() async {
        do {
            var request = URLRequest(url: URL(string: "\(PlatformConfig.currentServerURL)/api/\(project)/session/visit")!)
            request.httpMethod = "POST"
            _ = try await URLSession.shared.data(for: request)
        } catch {
            print("Failed to record visit: \(error)")
        }
    }
}

// MARK: - Models

struct SessionState: Codable {
    let projectName: String
    let lastSeen: String
    let changesSince: [FeatureChange]
    let pendingQuestions: [PendingQuestion]
    let featuresInProgress: [String]
    let featuresReadyToShip: [String]
    let currentStreak: Int

    enum CodingKeys: String, CodingKey {
        case projectName = "project_name"
        case lastSeen = "last_seen"
        case changesSince = "changes_since"
        case pendingQuestions = "pending_questions"
        case featuresInProgress = "features_in_progress"
        case featuresReadyToShip = "features_ready_to_ship"
        case currentStreak = "current_streak"
    }
}

struct FeatureChange: Codable {
    let featureId: String
    let featureTitle: String
    let changeType: String
    let timestamp: String
    let details: String?

    enum CodingKeys: String, CodingKey {
        case featureId = "feature_id"
        case featureTitle = "feature_title"
        case changeType = "change_type"
        case timestamp
        case details
    }
}

struct PendingQuestion: Codable {
    let featureId: String
    let featureTitle: String
    let question: String
    let context: String?
    let askedAt: String

    enum CodingKeys: String, CodingKey {
        case featureId = "feature_id"
        case featureTitle = "feature_title"
        case question
        case context
        case askedAt = "asked_at"
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    WelcomeBackView(project: "Forge") {}
        .environment(AppState())
        .frame(width: 500, height: 600)
}
#endif
