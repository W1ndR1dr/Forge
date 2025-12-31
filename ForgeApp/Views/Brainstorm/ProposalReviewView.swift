import SwiftUI

/// View for reviewing brainstorm proposals before adding to registry
struct ProposalReviewView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @Binding var proposals: [Proposal]
    let projectName: String
    let onComplete: ([Proposal]) -> Void

    @State private var isSubmitting = false
    @State private var showConfirmation = false
    @State private var errorMessage: String?

    private let apiClient = APIClient()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()
                .background(Linear.borderSubtle)

            // Proposals list
            ScrollView {
                LazyVStack(spacing: Spacing.medium) {
                    ForEach($proposals) { $proposal in
                        ProposalCard(
                            proposal: $proposal,
                            onApprove: { proposal.status = .approved },
                            onDecline: { proposal.status = .declined },
                            onDefer: { proposal.status = .deferred }
                        )
                    }
                }
                .padding(Spacing.standard)
            }

            Divider()
                .background(Linear.borderSubtle)

            // Footer with summary and actions
            footerView
        }
        .frame(minWidth: 600, minHeight: 500)
        .background(Linear.base)
        .environment(\.colorScheme, .dark)
        .alert("Add Features", isPresented: $showConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Add \(approvedCount) Feature\(approvedCount == 1 ? "" : "s")") {
                submitApproved()
            }
        } message: {
            Text("Add \(approvedCount) approved proposal\(approvedCount == 1 ? "" : "s") to the registry?")
        }
        .alert("Error", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            if let error = errorMessage {
                Text(error)
            }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: Spacing.micro) {
                Text("Review Proposals")
                    .font(Typography.body)
                    .fontWeight(.semibold)
                    .foregroundColor(Linear.textPrimary)
                Text("\(proposals.count) proposal\(proposals.count == 1 ? "" : "s") from brainstorm session")
                    .font(Typography.caption)
                    .foregroundColor(Linear.textSecondary)
            }

            Spacer()

            // Batch actions
            Menu {
                Button("Approve All Pending") {
                    approveAllPending()
                }
                Button("Decline All Pending") {
                    declineAllPending()
                }
                Button("Defer All Pending") {
                    deferAllPending()
                }
                Divider()
                Button("Reset All to Pending") {
                    resetAllToPending()
                }
            } label: {
                Label("Batch Actions", systemImage: "square.stack.3d.up")
            }
            .menuStyle(.borderlessButton)

            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(.linearSecondary)
        }
        .padding(Spacing.standard)
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            // Summary
            HStack(spacing: Spacing.standard) {
                SummaryBadge(count: approvedCount, label: "Approved", color: Accent.success)
                SummaryBadge(count: declinedCount, label: "Declined", color: Accent.danger)
                SummaryBadge(count: deferredCount, label: "Deferred", color: Accent.warning)
                SummaryBadge(count: pendingCount, label: "Pending", color: Linear.textTertiary)
            }

            Spacer()

            // Actions
            if deferredCount > 0 {
                Button("Save Session") {
                    // Save deferred for later
                    onComplete(proposals)
                    dismiss()
                }
                .buttonStyle(.linearSecondary)
            }

            Button("Add Approved to Registry") {
                showConfirmation = true
            }
            .buttonStyle(.linearPrimary(color: Accent.success))
            .disabled(approvedCount == 0 || isSubmitting)
        }
        .padding(Spacing.standard)
    }

    // MARK: - Computed Properties

    private var approvedCount: Int {
        proposals.filter { $0.status == .approved }.count
    }

    private var declinedCount: Int {
        proposals.filter { $0.status == .declined }.count
    }

    private var deferredCount: Int {
        proposals.filter { $0.status == .deferred }.count
    }

    private var pendingCount: Int {
        proposals.filter { $0.status == .pending }.count
    }

    // MARK: - Actions

    private func approveAllPending() {
        for i in proposals.indices where proposals[i].status == .pending {
            proposals[i].status = .approved
        }
    }

    private func declineAllPending() {
        for i in proposals.indices where proposals[i].status == .pending {
            proposals[i].status = .declined
        }
    }

    private func deferAllPending() {
        for i in proposals.indices where proposals[i].status == .pending {
            proposals[i].status = .deferred
        }
    }

    private func resetAllToPending() {
        for i in proposals.indices {
            proposals[i].status = .pending
        }
    }

    private func submitApproved() {
        isSubmitting = true

        let approvedProposals = proposals.filter { $0.status == .approved }

        Task {
            do {
                _ = try await apiClient.approveProposals(
                    project: projectName,
                    proposals: approvedProposals
                )

                await MainActor.run {
                    isSubmitting = false
                    onComplete(proposals)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Supporting Views

struct SummaryBadge: View {
    let count: Int
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: Spacing.micro) {
            Text("\(count)")
                .font(Typography.body)
                .fontWeight(.semibold)
                .foregroundColor(color)
            Text(label)
                .font(Typography.caption)
                .foregroundColor(Linear.textSecondary)
        }
    }
}

#Preview {
    ProposalReviewView(
        proposals: .constant([
            Proposal(
                title: "Add Dark Mode",
                description: "System-wide dark mode support",
                priority: 1,
                complexity: "medium",
                tags: ["ui"],
                rationale: "User demand for dark mode"
            ),
            Proposal(
                title: "Export to PDF",
                description: "Export feature lists to PDF",
                priority: 3,
                complexity: "simple",
                tags: ["export"]
            ),
            Proposal(
                title: "Real-time Sync",
                description: "WebSocket-based real-time sync",
                priority: 2,
                complexity: "complex",
                tags: ["backend", "sync"]
            ),
        ]),
        projectName: "Forge",
        onComplete: { _ in }
    )
    .environment(AppState())
}
