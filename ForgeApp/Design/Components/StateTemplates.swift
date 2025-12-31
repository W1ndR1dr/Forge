import SwiftUI

// MARK: - State Templates
// Every state deserves considered design (Tufte's "honest states")
//
// Influenced by: Dieter Rams (purposeful), Edward Tufte (honest)
// "Empty states should invite, not depress. Errors should help, not alarm."

// MARK: - Empty States

/// Generic empty state with customizable message and action
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?

    @State private var isVisible = false

    init(
        icon: String = "tray",
        title: String,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: Spacing.large) {
            // Icon with subtle animation
            ZStack {
                Circle()
                    .fill(Surface.elevated)
                    .frame(width: 80, height: 80)

                Image(systemName: icon)
                    .font(.system(size: 32))
                    .foregroundColor(.secondary)
            }
            .scaleEffect(isVisible ? 1.0 : 0.8)

            // Text content
            VStack(spacing: Spacing.small) {
                Text(title)
                    .font(Typography.sectionHeader)
                    .foregroundColor(.primary)

                Text(message)
                    .font(Typography.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : 10)

            // Optional action button
            if let actionTitle = actionTitle, let action = action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(Typography.body)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .tint(Accent.primary)
                .opacity(isVisible ? 1 : 0)
            }
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(SpringPreset.gentle.delay(0.1)) {
                isVisible = true
            }
        }
    }
}

/// Empty state specifically for feature lists
struct EmptyFeaturesView: View {
    let onAddFeature: () -> Void

    var body: some View {
        EmptyStateView(
            icon: "sparkles",
            title: "Ready to Ship",
            message: "Your pipeline is clear. What do you want to build next?",
            actionTitle: "Add First Feature",
            action: onAddFeature
        )
    }
}

/// Empty state for shipped features (celebration!)
struct EmptyShippedView: View {
    var body: some View {
        EmptyStateView(
            icon: "shippingbox",
            title: "Nothing Shipped Yet",
            message: "Complete a feature to see it here. Your first ship is coming!"
        )
    }
}

/// Empty state for blocked features (encouraging)
struct EmptyBlockedView: View {
    var body: some View {
        EmptyStateView(
            icon: "checkmark.circle",
            title: "No Blockers",
            message: "All clear! Nothing is blocking your progress."
        )
    }
}

// MARK: - Loading States

/// Skeleton card for loading state (shimmer effect)
struct SkeletonCard: View {
    let height: CGFloat

    @State private var isAnimating = false

    init(height: CGFloat = 80) {
        self.height = height
    }

    var body: some View {
        RoundedRectangle(cornerRadius: CornerRadius.large)
            .fill(Surface.elevated)
            .frame(height: height)
            .overlay(
                GeometryReader { geometry in
                    LinearGradient(
                        colors: [
                            .clear,
                            .white.opacity(0.3),
                            .clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geometry.size.width * 0.6)
                    .offset(x: isAnimating ? geometry.size.width : -geometry.size.width * 0.6)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.large))
            .onAppear {
                withAnimation(
                    Animation.linear(duration: 1.5)
                        .repeatForever(autoreverses: false)
                ) {
                    isAnimating = true
                }
            }
    }
}

/// Skeleton feature card matching real FeatureCard dimensions
struct SkeletonFeatureCard: View {
    @State private var isAnimating = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            // Title skeleton
            SkeletonLine(width: 0.7)

            // Description skeleton
            VStack(alignment: .leading, spacing: Spacing.small) {
                SkeletonLine(width: 1.0)
                SkeletonLine(width: 0.5)
            }

            // Badge skeleton
            HStack(spacing: Spacing.small) {
                SkeletonPill()
                SkeletonPill()
            }
        }
        .padding(Spacing.standard)
        .background(Surface.elevated)
        .cornerRadius(CornerRadius.large)
    }
}

/// Skeleton line for text placeholders
struct SkeletonLine: View {
    let width: CGFloat // 0.0 to 1.0 relative width
    let height: CGFloat

    @State private var isAnimating = false

    init(width: CGFloat = 1.0, height: CGFloat = 14) {
        self.width = width
        self.height = height
    }

    var body: some View {
        GeometryReader { geometry in
            RoundedRectangle(cornerRadius: CornerRadius.small)
                .fill(Color.secondary.opacity(0.2))
                .frame(width: geometry.size.width * width, height: height)
                .shimmer(isActive: true)
        }
        .frame(height: height)
    }
}

/// Skeleton pill for badge placeholders
struct SkeletonPill: View {
    var body: some View {
        RoundedRectangle(cornerRadius: CornerRadius.small)
            .fill(Color.secondary.opacity(0.15))
            .frame(width: 60, height: 20)
            .shimmer(isActive: true)
    }
}

/// Loading state with multiple skeleton cards
struct LoadingFeaturesView: View {
    let cardCount: Int

    init(cardCount: Int = 3) {
        self.cardCount = cardCount
    }

    var body: some View {
        VStack(spacing: Spacing.medium) {
            ForEach(0..<cardCount, id: \.self) { index in
                SkeletonFeatureCard()
                    .opacity(1.0 - Double(index) * 0.15)
            }
        }
    }
}

/// Inline loading indicator (for buttons, etc.)
struct InlineLoader: View {
    let message: String?

    @State private var rotation: Double = 0

    init(message: String? = nil) {
        self.message = message
    }

    var body: some View {
        HStack(spacing: Spacing.small) {
            Circle()
                .trim(from: 0.2, to: 1.0)
                .stroke(Accent.primary, lineWidth: 2)
                .frame(width: 16, height: 16)
                .rotationEffect(.degrees(rotation))
                .onAppear {
                    withAnimation(
                        Animation.linear(duration: 1.0)
                            .repeatForever(autoreverses: false)
                    ) {
                        rotation = 360
                    }
                }

            if let message = message {
                Text(message)
                    .font(Typography.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Error States

/// Generic error state with retry action
struct ErrorStateView: View {
    let error: String
    let suggestion: String?
    let onRetry: (() -> Void)?

    @State private var isVisible = false

    init(
        error: String,
        suggestion: String? = nil,
        onRetry: (() -> Void)? = nil
    ) {
        self.error = error
        self.suggestion = suggestion
        self.onRetry = onRetry
    }

    var body: some View {
        VStack(spacing: Spacing.large) {
            // Error icon
            ZStack {
                Circle()
                    .fill(Accent.danger.opacity(0.1))
                    .frame(width: 80, height: 80)

                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 32))
                    .foregroundColor(Accent.danger)
            }
            .scaleEffect(isVisible ? 1.0 : 0.8)

            // Error message
            VStack(spacing: Spacing.small) {
                Text("Something went wrong")
                    .font(Typography.sectionHeader)
                    .foregroundColor(.primary)

                Text(error)
                    .font(Typography.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)

                if let suggestion = suggestion {
                    Text(suggestion)
                        .font(Typography.caption)
                        .foregroundColor(.secondary.opacity(0.8))
                        .multilineTextAlignment(.center)
                }
            }
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : 10)

            // Retry button
            if let onRetry = onRetry {
                Button(action: onRetry) {
                    HStack(spacing: Spacing.small) {
                        Image(systemName: "arrow.clockwise")
                        Text("Try Again")
                    }
                    .font(Typography.body)
                    .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .tint(Accent.primary)
                .opacity(isVisible ? 1 : 0)
            }
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(SpringPreset.gentle.delay(0.1)) {
                isVisible = true
            }
        }
    }
}

/// Connection error (specific to server issues)
struct ConnectionErrorView: View {
    let onRetry: () -> Void

    var body: some View {
        ErrorStateView(
            error: "Unable to connect to Forge server",
            suggestion: "Make sure the server is running on localhost:7749",
            onRetry: onRetry
        )
    }
}

/// Inline error banner (dismissible)
struct ErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    @State private var isVisible = false

    var body: some View {
        HStack(spacing: Spacing.medium) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundColor(Accent.danger)

            Text(message)
                .font(Typography.body)
                .foregroundColor(.primary)
                .lineLimit(2)

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(Spacing.standard)
        .background(Accent.danger.opacity(0.1))
        .cornerRadius(CornerRadius.medium)
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.medium)
                .stroke(Accent.danger.opacity(0.3), lineWidth: 1)
        )
        .scaleEffect(isVisible ? 1.0 : 0.95)
        .opacity(isVisible ? 1 : 0)
        .onAppear {
            withAnimation(SpringPreset.snappy) {
                isVisible = true
            }
        }
    }
}

// MARK: - Success States

/// Success toast/banner (auto-dismisses)
struct SuccessBanner: View {
    let message: String
    let autoDismissAfter: Double?
    let onDismiss: () -> Void

    @State private var isVisible = false

    init(
        message: String,
        autoDismissAfter: Double? = 3.0,
        onDismiss: @escaping () -> Void
    ) {
        self.message = message
        self.autoDismissAfter = autoDismissAfter
        self.onDismiss = onDismiss
    }

    var body: some View {
        HStack(spacing: Spacing.medium) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(Accent.success)

            Text(message)
                .font(Typography.body)
                .foregroundColor(.primary)

            Spacer()
        }
        .padding(Spacing.standard)
        .background(Accent.success.opacity(0.1))
        .cornerRadius(CornerRadius.medium)
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.medium)
                .stroke(Accent.success.opacity(0.3), lineWidth: 1)
        )
        .scaleEffect(isVisible ? 1.0 : 0.95)
        .opacity(isVisible ? 1 : 0)
        .onAppear {
            withAnimation(SpringPreset.snappy) {
                isVisible = true
            }

            if let delay = autoDismissAfter {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    withAnimation(SpringPreset.smooth) {
                        isVisible = false
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        onDismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Progress States

/// Determinate progress with label
struct ProgressStateView: View {
    let progress: Double // 0.0 to 1.0
    let label: String
    let detail: String?

    var body: some View {
        VStack(spacing: Spacing.medium) {
            // Circular progress
            AnimatedProgressRing(
                progress: progress,
                lineWidth: 8,
                color: Accent.primary
            )
            .frame(width: 80, height: 80)
            .overlay(
                Text("\(Int(progress * 100))%")
                    .font(Typography.featureTitle)
                    .fontWeight(.bold)
            )

            // Labels
            VStack(spacing: Spacing.small) {
                Text(label)
                    .font(Typography.body)
                    .foregroundColor(.primary)

                if let detail = detail {
                    Text(detail)
                        .font(Typography.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(Spacing.xl)
    }
}

// MARK: - Conditional State Wrapper

/// Wrapper that shows appropriate state based on conditions
struct StatefulView<Content: View, Empty: View, Loading: View, Error: View>: View {
    let isEmpty: Bool
    let isLoading: Bool
    let error: String?

    @ViewBuilder let content: () -> Content
    @ViewBuilder let empty: () -> Empty
    @ViewBuilder let loading: () -> Loading
    @ViewBuilder let errorView: (String) -> Error

    var body: some View {
        if isLoading {
            loading()
        } else if let error = error {
            errorView(error)
        } else if isEmpty {
            empty()
        } else {
            content()
        }
    }
}

// MARK: - Preview

#if DEBUG
struct StateTemplatesPreview: View {
    @State private var showError = false

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.xl) {
                // Empty states
                Text("EMPTY STATES")
                    .sectionHeaderStyle()

                EmptyFeaturesView(onAddFeature: {})
                    .frame(height: 250)
                    .background(Surface.window)
                    .cornerRadius(CornerRadius.large)

                // Loading states
                Text("LOADING STATES")
                    .sectionHeaderStyle()

                LoadingFeaturesView(cardCount: 2)
                    .padding()
                    .background(Surface.window)
                    .cornerRadius(CornerRadius.large)

                HStack {
                    InlineLoader(message: "Analyzing...")
                    Spacer()
                }
                .padding()

                // Error states
                Text("ERROR STATES")
                    .sectionHeaderStyle()

                ErrorBanner(message: "Failed to save feature", onDismiss: {})
                    .padding(.horizontal)

                // Success states
                Text("SUCCESS STATES")
                    .sectionHeaderStyle()

                SuccessBanner(message: "Feature shipped!", onDismiss: {})
                    .padding(.horizontal)

                // Progress states
                Text("PROGRESS STATES")
                    .sectionHeaderStyle()

                ProgressStateView(
                    progress: 0.65,
                    label: "Building feature...",
                    detail: "Editing 3 of 5 files"
                )
                .frame(height: 200)
                .background(Surface.elevated)
                .cornerRadius(CornerRadius.large)
            }
            .padding(Spacing.large)
        }
        .frame(width: 500, height: 800)
        .background(Surface.window)
    }
}

#Preview {
    StateTemplatesPreview()
}
#endif
