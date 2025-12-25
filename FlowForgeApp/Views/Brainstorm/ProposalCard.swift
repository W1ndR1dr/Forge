import SwiftUI

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
                        .foregroundColor(proposal.status == .declined ? .secondary : .primary)

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
                .foregroundColor(.secondary)
                .lineLimit(isExpanded ? nil : 3)

            // Rationale (expandable)
            if !proposal.rationale.isEmpty {
                DisclosureGroup(isExpanded: $isExpanded) {
                    Text(proposal.rationale)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                } label: {
                    Text("Rationale")
                        .font(.caption)
                        .fontWeight(.medium)
                }
            }

            // Tags
            if !proposal.tags.isEmpty {
                FlowLayout(spacing: 4) {
                    ForEach(proposal.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.2))
                            .clipShape(Capsule())
                    }
                }
            }

            // Action buttons
            if proposal.status == .pending {
                HStack(spacing: 12) {
                    Button(action: onApprove) {
                        Label("Approve", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)

                    Button(action: onDecline) {
                        Label("Decline", systemImage: "xmark.circle.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)

                    Button(action: onDefer) {
                        Label("Defer", systemImage: "clock.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)

                    Spacer()
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: 1)
        )
        .opacity(proposal.status == .declined ? 0.6 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: proposal.status)
        .onHover { isHovering = $0 }
    }

    private var backgroundColor: Color {
        switch proposal.status {
        case .approved:
            return Color.green.opacity(0.1)
        case .declined:
            return Color.red.opacity(0.05)
        case .deferred:
            return Color.orange.opacity(0.1)
        case .pending:
            return Color(NSColor.textBackgroundColor)
        }
    }

    private var borderColor: Color {
        switch proposal.status {
        case .approved:
            return Color.green.opacity(0.3)
        case .declined:
            return Color.red.opacity(0.2)
        case .deferred:
            return Color.orange.opacity(0.3)
        case .pending:
            return Color.secondary.opacity(isHovering ? 0.3 : 0.1)
        }
    }
}

// MARK: - Supporting Views

struct PriorityBadge: View {
    let priority: Int

    var body: some View {
        Text("P\(priority)")
            .font(.caption2)
            .fontWeight(.bold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(priorityColor.opacity(0.2))
            .foregroundColor(priorityColor)
            .clipShape(Capsule())
    }

    private var priorityColor: Color {
        switch priority {
        case 1: return .red
        case 2: return .orange
        case 3: return .yellow
        case 4: return .blue
        default: return .gray
        }
    }
}

struct ComplexityLabel: View {
    let complexity: String

    var body: some View {
        Text(complexity.capitalized)
            .font(.caption2)
            .foregroundColor(.secondary)
    }
}

struct StatusIndicator: View {
    let status: ProposalStatus

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .font(.caption)
            Text(status.displayName)
                .font(.caption)
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
        case .pending: return .secondary
        case .approved: return .green
        case .declined: return .red
        case .deferred: return .orange
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
