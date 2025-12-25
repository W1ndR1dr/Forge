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

            // Proposals list
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach($proposals) { $proposal in
                        ProposalCard(
                            proposal: $proposal,
                            onApprove: { proposal.status = .approved },
                            onDecline: { proposal.status = .declined },
                            onDefer: { proposal.status = .deferred }
                        )
                    }
                }
                .padding()
            }

            Divider()

            // Footer with summary and actions
            footerView
        }
        .frame(minWidth: 600, minHeight: 500)
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
            VStack(alignment: .leading, spacing: 4) {
                Text("Review Proposals")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("\(proposals.count) proposal\(proposals.count == 1 ? "" : "s") from brainstorm session")
                    .font(.caption)
                    .foregroundColor(.secondary)
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
        }
        .padding()
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            // Summary
            HStack(spacing: 16) {
                SummaryBadge(count: approvedCount, label: "Approved", color: .green)
                SummaryBadge(count: declinedCount, label: "Declined", color: .red)
                SummaryBadge(count: deferredCount, label: "Deferred", color: .orange)
                SummaryBadge(count: pendingCount, label: "Pending", color: .gray)
            }

            Spacer()

            // Actions
            if deferredCount > 0 {
                Button("Save Session") {
                    // Save deferred for later
                    onComplete(proposals)
                    dismiss()
                }
                .buttonStyle(.bordered)
            }

            Button("Add Approved to Registry") {
                showConfirmation = true
            }
            .buttonStyle(.borderedProminent)
            .disabled(approvedCount == 0 || isSubmitting)
        }
        .padding()
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
                let response = try await apiClient.approveProposals(
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
        HStack(spacing: 4) {
            Text("\(count)")
                .font(.headline)
                .foregroundColor(color)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
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
        projectName: "FlowForge",
        onComplete: { _ in }
    )
    .environment(AppState())
}
