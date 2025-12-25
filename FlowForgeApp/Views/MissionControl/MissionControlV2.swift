import SwiftUI

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
    @State private var showConfetti = false
    @State private var showCelebration = false
    @State private var lastShippedTitle = ""

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

                    // Level 3: Shipped This Week
                    shippedSection
                }
                .padding(Spacing.large)
            }
            .background(Surface.window)

            // Confetti overlay
            ConfettiView(isActive: $showConfetti)
                .ignoresSafeArea()

            // Celebration modal
            if showCelebration {
                ShipCelebrationView(
                    isShowing: $showCelebration,
                    featureTitle: lastShippedTitle,
                    onDismiss: {
                        // Reset for next celebration
                    }
                )
            }
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
        lastShippedTitle = feature.title

        Task {
            let success = await appState.shipFeature(feature)

            if success {
                await MainActor.run {
                    showConfetti = true
                    showCelebration = true
                }
            }
            // If failed, appState.errorMessage is already set with friendly message
        }
    }
}

// MARK: - Active Mission Card V2

struct ActiveMissionCardV2: View {
    let feature: Feature
    let onShip: () -> Void

    @State private var isHovered = false
    @State private var isVisible = false

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

            // Claude activity indicator (Bret Victor - see the work)
            if feature.status == .inProgress {
                HStack(spacing: Spacing.small) {
                    InlineLoader(message: "Claude is working...")

                    Spacer()

                    // Would show actual file being edited
                    Text("src/components/...")
                        .font(Typography.caption)
                        .foregroundColor(.secondary)
                }
                .padding(Spacing.small)
                .background(Surface.highlighted)
                .cornerRadius(CornerRadius.medium)
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
}

// MARK: - Start Mission Card V2

struct StartMissionCardV2: View {
    let feature: Feature
    let onStart: () -> Void

    @State private var isHovered = false

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
    }
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
