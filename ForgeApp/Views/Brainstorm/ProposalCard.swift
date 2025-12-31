import SwiftUI

#if os(macOS)
import AppKit
#endif

struct ProposalCard: View {
    @Binding var proposal: Proposal
    let onApprove: () -> Void
    let onDecline: () -> Void
    let onDefer: () -> Void

    @State private var isExpanded = false
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with title and priority
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(proposal.title)
                        .font(.headline)
                        .strikethrough(proposal.status == .declined)
                        .foregroundColor(proposal.status == .declined ? Linear.textSecondary : Linear.textPrimary)

                    // Priority badge
                    HStack(spacing: 8) {
                        PriorityBadge(priority: proposal.priority)
                        ComplexityLabel(complexity: proposal.complexity)
                    }
                }

                Spacer()

                // Status indicator
                StatusIndicator(status: proposal.status)
            }

            // Description
            Text(proposal.description)
                .font(.subheadline)
                .foregroundColor(Linear.textSecondary)
                .lineLimit(isExpanded ? nil : 3)

            // Rationale (expandable)
            if !proposal.rationale.isEmpty {
                DisclosureGroup(isExpanded: $isExpanded) {
                    Text(proposal.rationale)
                        .font(.caption)
                        .foregroundColor(Linear.textSecondary)
                        .padding(.top, 4)
                } label: {
                    Text("Rationale")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(Linear.textTertiary)
                }
            }

            // Tags
            if !proposal.tags.isEmpty {
                FlowLayout(spacing: 4) {
                    ForEach(proposal.tags, id: \.self) { tag in
                        Text(tag)
                            .font(Typography.badge)
                            .padding(.horizontal, Spacing.small)
                            .padding(.vertical, Spacing.micro)
                            .background(Accent.primary.opacity(0.15))
                            .foregroundColor(Accent.primary)
                            .cornerRadius(CornerRadius.small)
                    }
                }
            }

            // Action buttons
            if proposal.status == .pending {
                HStack(spacing: Spacing.medium) {
                    Button(action: onApprove) {
                        Label("Approve", systemImage: "checkmark.circle.fill")
                    }
                    .buttonStyle(.linearPrimary(color: Accent.success))

                    Button(action: onDecline) {
                        Label("Decline", systemImage: "xmark.circle.fill")
                    }
                    .buttonStyle(.linearSecondary(color: Accent.danger))

                    Button(action: onDefer) {
                        Label("Defer", systemImage: "clock.fill")
                    }
                    .buttonStyle(.linearSecondary(color: Accent.warning))

                    Spacer()
                }
                .padding(.top, Spacing.micro)
            }
        }
        .padding(Spacing.standard)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.large)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.large)
                .stroke(borderColor, lineWidth: 1)
        )
        .opacity(proposal.status == .declined ? 0.6 : 1.0)
        .animation(LinearEasing.fast, value: proposal.status)
        .animation(LinearEasing.fast, value: isHovering)
        .onHover { isHovering = $0 }
    }

    private var backgroundColor: Color {
        switch proposal.status {
        case .approved:
            return Accent.success.opacity(0.1)
        case .declined:
            return Accent.danger.opacity(0.05)
        case .deferred:
            return Accent.warning.opacity(0.1)
        case .pending:
            return Linear.card
        }
    }

    private var borderColor: Color {
        switch proposal.status {
        case .approved:
            return Accent.success.opacity(0.3)
        case .declined:
            return Accent.danger.opacity(0.2)
        case .deferred:
            return Accent.warning.opacity(0.3)
        case .pending:
            return isHovering ? Linear.borderVisible : Linear.borderSubtle
        }
    }
}

// MARK: - Supporting Views

struct PriorityBadge: View {
    let priority: Int

    var body: some View {
        Text("P\(priority)")
            .font(Typography.badge)
            .fontWeight(.semibold)
            .padding(.horizontal, Spacing.small)
            .padding(.vertical, Spacing.micro)
            .background(priorityColor.opacity(0.15))
            .foregroundColor(priorityColor)
            .cornerRadius(CornerRadius.small)
    }

    private var priorityColor: Color {
        switch priority {
        case 1: return Accent.danger
        case 2: return Accent.warning
        case 3: return Accent.attention
        case 4: return Accent.primary
        default: return Linear.textTertiary
        }
    }
}

struct ComplexityLabel: View {
    let complexity: String

    var body: some View {
        Text(complexity.capitalized)
            .font(Typography.badge)
            .foregroundColor(Linear.textSecondary)
    }
}

struct StatusIndicator: View {
    let status: ProposalStatus

    var body: some View {
        HStack(spacing: Spacing.micro) {
            Image(systemName: iconName)
                .font(.caption)
            Text(status.displayName)
                .font(Typography.caption)
        }
        .foregroundColor(statusColor)
    }

    private var iconName: String {
        switch status {
        case .pending: return "circle"
        case .approved: return "checkmark.circle.fill"
        case .declined: return "xmark.circle.fill"
        case .deferred: return "clock.fill"
        }
    }

    private var statusColor: Color {
        switch status {
        case .pending: return Linear.textSecondary
        case .approved: return Accent.success
        case .declined: return Accent.danger
        case .deferred: return Accent.warning
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        ProposalCard(
            proposal: .constant(Proposal(
                title: "Add Dark Mode Support",
                description: "Implement a system-wide dark mode toggle that respects system preferences and allows manual override.",
                priority: 1,
                complexity: "medium",
                tags: ["ui", "settings"],
                rationale: "Dark mode is now a standard expectation for modern apps. It improves accessibility and reduces eye strain.",
                status: .pending
            )),
            onApprove: {},
            onDecline: {},
            onDefer: {}
        )

        ProposalCard(
            proposal: .constant(Proposal(
                title: "Approved Feature",
                description: "This feature has been approved.",
                priority: 2,
                complexity: "simple",
                tags: ["backend"],
                status: .approved
            )),
            onApprove: {},
            onDecline: {},
            onDefer: {}
        )

        ProposalCard(
            proposal: .constant(Proposal(
                title: "Declined Feature",
                description: "This feature was declined.",
                priority: 4,
                complexity: "epic",
                tags: [],
                status: .declined
            )),
            onApprove: {},
            onDecline: {},
            onDefer: {}
        )
    }
    .padding()
    .frame(width: 500)
}
