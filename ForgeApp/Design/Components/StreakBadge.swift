import SwiftUI

// MARK: - Streak Badge
// Minimal, tasteful shipping streak indicator
// Shows the number, animates on change, no noise

struct StreakBadge: View {
    let currentStreak: Int
    let longestStreak: Int
    let totalShipped: Int
    let showDetails: Bool
    let compact: Bool

    @State private var displayedStreak: Int = 0
    @State private var didJustIncrement = false

    init(
        currentStreak: Int,
        longestStreak: Int = 0,
        totalShipped: Int = 0,
        showDetails: Bool = true,
        compact: Bool = false
    ) {
        self.currentStreak = currentStreak
        self.longestStreak = longestStreak
        self.totalShipped = totalShipped
        self.showDetails = showDetails
        self.compact = compact
    }

    var body: some View {
        if compact {
            compactBadge
        } else {
            fullBadge
        }
    }

    // MARK: - Compact Badge (for toolbar)

    private var compactBadge: some View {
        HStack(spacing: 4) {
            if currentStreak > 0 {
                Text("🔥")
                    .font(.system(size: 14))
                    .scaleEffect(didJustIncrement ? 1.15 : 1.0)
            }
            Text("\(displayedStreak)")
                .font(.inter(13, weight: .semibold))
                .foregroundColor(currentStreak > 0 ? Accent.streak : .secondary)
                .contentTransition(.numericText(value: Double(displayedStreak)))
        }
        .padding(.horizontal, Spacing.small)
        .padding(.vertical, Spacing.micro)
        .background(Accent.streak.opacity(currentStreak > 0 ? 0.1 : 0.05))
        .cornerRadius(CornerRadius.small)
        .onAppear { displayedStreak = currentStreak }
        .onChange(of: currentStreak) { oldValue, newValue in
            animateStreakChange(from: oldValue, to: newValue)
        }
    }

    // MARK: - Full Badge

    private var fullBadge: some View {
        HStack(spacing: Spacing.small) {
            // Fire emoji - static, no animation
            if currentStreak > 0 {
                Text("🔥")
                    .font(.system(size: 20))
                    .scaleEffect(didJustIncrement ? 1.15 : 1.0)
            }

            // Streak number with spring animation on change
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.micro) {
                    Text("\(displayedStreak)")
                        .font(Typography.streakNumber)
                        .foregroundColor(currentStreak > 0 ? Accent.streak : .secondary)
                        .contentTransition(.numericText(value: Double(displayedStreak)))

                    Text(currentStreak == 1 ? "day" : "days")
                        .font(Typography.caption)
                        .foregroundColor(.secondary)
                }

                if showDetails && totalShipped > 0 {
                    Text("\(totalShipped) shipped")
                        .font(Typography.caption)
                        .foregroundColor(.secondary.opacity(0.8))
                }
            }

            // Best streak indicator
            if showDetails && longestStreak > currentStreak {
                Divider()
                    .frame(height: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Best")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.6))

                    Text("\(longestStreak)")
                        .font(Typography.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, Spacing.standard)
        .padding(.vertical, Spacing.medium)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.large)
                .fill(Accent.streak.opacity(currentStreak > 0 ? 0.1 : 0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.large)
                .stroke(Accent.streak.opacity(currentStreak > 0 ? 0.2 : 0), lineWidth: 1)
        )
        .onAppear { displayedStreak = currentStreak }
        .onChange(of: currentStreak) { oldValue, newValue in
            animateStreakChange(from: oldValue, to: newValue)
        }
    }

    // MARK: - Animation Helper

    private func animateStreakChange(from oldValue: Int, to newValue: Int) {
        // Animate the number change
        withAnimation(SpringPreset.snappy) {
            displayedStreak = newValue
        }

        // Single pulse on increment
        if newValue > oldValue {
            withAnimation(SpringPreset.snappy) {
                didJustIncrement = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(SpringPreset.smooth) {
                    didJustIncrement = false
                }
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
struct StreakBadgePreview: View {
    @State private var streak = 7

    var body: some View {
        VStack(spacing: Spacing.xl) {
            Text("STREAK BADGES")
                .sectionHeaderStyle()

            // Various streak states
            HStack(spacing: Spacing.large) {
                StreakBadge(currentStreak: 0, totalShipped: 0)
                StreakBadge(currentStreak: 3, longestStreak: 7, totalShipped: 15)
                StreakBadge(currentStreak: 7, longestStreak: 7, totalShipped: 42)
            }

            Divider()

            // Interactive
            VStack {
                StreakBadge(currentStreak: streak, longestStreak: 14, totalShipped: 100)

                HStack {
                    Button("- Day") { streak = max(0, streak - 1) }
                    Button("+ Day") { streak += 1 }
                    Button("Reset") { streak = 0 }
                }
            }
        }
        .padding(Spacing.large)
        .frame(width: 600, height: 400)
        .background(Surface.window)
    }
}

#Preview {
    StreakBadgePreview()
}
#endif
