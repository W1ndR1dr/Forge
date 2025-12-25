import SwiftUI

// MARK: - Feature Analysis Preview
// Shows AI analysis results before adding a feature
// Vibecoder-friendly: "Here's what I think about this feature"

struct FeatureAnalysisPreview: View {
    let title: String
    let analysis: FeatureAnalysis
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @State private var isVisible = false

    /// Complexity color for vibecoder-friendly display
    private var complexityColor: Color {
        switch analysis.complexity.lowercased() {
        case "small", "tiny":
            return ComplexityColor.small
        case "medium":
            return ComplexityColor.medium
        case "large":
            return ComplexityColor.large
        case "epic", "huge":
            return ComplexityColor.epic
        default:
            return ComplexityColor.medium
        }
    }

    /// Friendly complexity label
    private var complexityLabel: String {
        switch analysis.complexity.lowercased() {
        case "small", "tiny":
            return "Quick win"
        case "medium":
            return "Solid feature"
        case "large":
            return "Big project"
        case "epic", "huge":
            return "Major undertaking"
        default:
            return analysis.complexity.capitalized
        }
    }

    /// Shippable today message
    private var shippableMessage: String? {
        guard let shippable = analysis.shippableToday else { return nil }
        return shippable ? "Shippable today" : "May take a few sessions"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            // Header
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(Accent.primary)
                Text("AI Analysis")
                    .font(Typography.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                Spacer()

                // Complexity badge
                Text(complexityLabel)
                    .font(Typography.badge)
                    .foregroundColor(.white)
                    .padding(.horizontal, Spacing.small)
                    .padding(.vertical, Spacing.micro)
                    .background(complexityColor)
                    .cornerRadius(CornerRadius.small)
            }

            // Feature title being analyzed
            Text(title)
                .font(Typography.body)
                .fontWeight(.medium)

            // Scope warnings (if any)
            if let warnings = analysis.scopeCreepWarnings, !warnings.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.small) {
                    ForEach(warnings, id: \.self) { warning in
                        HStack(alignment: .top, spacing: Spacing.small) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(Accent.warning)
                                .font(.system(size: 12))
                            Text(warning)
                                .font(Typography.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(Spacing.small)
                .background(Accent.warning.opacity(0.1))
                .cornerRadius(CornerRadius.small)
            }

            // Suggested breakdown (if feature is too big)
            if let breakdown = analysis.suggestedBreakdown, !breakdown.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.small) {
                    Text("Consider breaking this down:")
                        .font(Typography.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)

                    ForEach(Array(breakdown.prefix(3).enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: Spacing.small) {
                            Text("\(index + 1).")
                                .font(Typography.caption)
                                .foregroundColor(Accent.primary)
                                .frame(width: 16)
                            Text(step)
                                .font(Typography.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(Spacing.small)
                .background(Accent.primary.opacity(0.05))
                .cornerRadius(CornerRadius.small)
            }

            // Expert domain suggestion
            if let domain = analysis.expertDomain {
                HStack(spacing: Spacing.small) {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .foregroundColor(Accent.primary)
                        .font(.system(size: 14))
                    Text("Expert: \(domain)")
                        .font(Typography.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Shippable indicator
            if let message = shippableMessage {
                HStack(spacing: Spacing.small) {
                    Image(systemName: analysis.shippableToday == true ? "checkmark.circle.fill" : "clock")
                        .foregroundColor(analysis.shippableToday == true ? Accent.success : .secondary)
                        .font(.system(size: 14))
                    Text(message)
                        .font(Typography.caption)
                        .foregroundColor(analysis.shippableToday == true ? Accent.success : .secondary)
                }
            }

            // Actions
            HStack(spacing: Spacing.medium) {
                Button(action: onCancel) {
                    Text("Rethink it")
                        .font(Typography.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                Button(action: onConfirm) {
                    HStack(spacing: Spacing.small) {
                        Image(systemName: "plus.circle.fill")
                        Text("Add to Queue")
                    }
                    .font(Typography.caption)
                    .fontWeight(.medium)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(Spacing.standard)
        .background(Surface.elevated)
        .cornerRadius(CornerRadius.large)
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.large)
                .stroke(Accent.primary.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        .scaleEffect(isVisible ? 1 : 0.95)
        .opacity(isVisible ? 1 : 0)
        .onAppear {
            withAnimation(SpringPreset.gentle) {
                isVisible = true
            }
        }
    }
}

// MARK: - Loading State

struct FeatureAnalysisLoading: View {
    let title: String

    var body: some View {
        HStack(spacing: Spacing.medium) {
            ProgressView()
                .scaleEffect(0.8)

            VStack(alignment: .leading, spacing: Spacing.micro) {
                Text("Analyzing: \(title)")
                    .font(Typography.caption)
                    .fontWeight(.medium)
                Text("Checking complexity, scope, and best approach...")
                    .font(Typography.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(Spacing.medium)
        .background(Surface.elevated)
        .cornerRadius(CornerRadius.medium)
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    VStack(spacing: Spacing.large) {
        // With warnings and breakdown
        FeatureAnalysisPreview(
            title: "Add user authentication with OAuth and email verification",
            analysis: FeatureAnalysis(
                complexity: "large",
                estimatedHours: 8,
                confidence: 0.85,
                foundationScore: 70,
                expertDomain: "Security",
                scopeCreepWarnings: [
                    "This might be too big for one feature",
                    "Consider separating OAuth and email verification"
                ],
                suggestedBreakdown: [
                    "Basic email/password auth",
                    "OAuth integration (Google)",
                    "Email verification flow"
                ],
                filesAffected: ["auth.swift", "user.swift"],
                shippableToday: false
            ),
            onConfirm: {},
            onCancel: {}
        )

        // Simple feature
        FeatureAnalysisPreview(
            title: "Add dark mode toggle",
            analysis: FeatureAnalysis(
                complexity: "small",
                estimatedHours: 2,
                confidence: 0.95,
                foundationScore: 90,
                expertDomain: "UI/UX",
                scopeCreepWarnings: nil,
                suggestedBreakdown: nil,
                filesAffected: ["settings.swift"],
                shippableToday: true
            ),
            onConfirm: {},
            onCancel: {}
        )

        // Loading state
        FeatureAnalysisLoading(title: "Export to PDF")
    }
    .padding()
    .frame(width: 400)
    .background(Surface.window)
}
#endif
