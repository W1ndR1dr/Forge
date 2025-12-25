import Foundation

/// Status of a proposal in the review process
enum ProposalStatus: String, Codable, CaseIterable {
    case pending = "pending"
    case approved = "approved"
    case declined = "declined"
    case deferred = "deferred"

    var displayName: String {
        rawValue.capitalized
    }

    var color: String {
        switch self {
        case .pending: return "gray"
        case .approved: return "green"
        case .declined: return "red"
        case .deferred: return "orange"
        }
    }
}

/// A feature proposal from a brainstorm session
struct Proposal: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var description: String
    var priority: Int
    var complexity: String
    var tags: [String]
    var rationale: String
    var status: ProposalStatus

    init(
        id: UUID = UUID(),
        title: String,
        description: String = "",
        priority: Int = 3,
        complexity: String = "medium",
        tags: [String] = [],
        rationale: String = "",
        status: ProposalStatus = .pending
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.priority = priority
        self.complexity = complexity
        self.tags = tags
        self.rationale = rationale
        self.status = status
    }

    /// Priority color for display
    var priorityColor: String {
        switch priority {
        case 1: return "red"
        case 2: return "orange"
        case 3: return "yellow"
        case 4: return "blue"
        default: return "gray"
        }
    }

    /// Priority label for display
    var priorityLabel: String {
        "P\(priority)"
    }
}

// MARK: - API Response Models

/// Response from parsing brainstorm output
struct BrainstormParseResponse: Codable {
    let proposals: [Proposal]
    let count: Int
}

/// Response from approving proposals
struct ApproveProposalsResponse: Codable {
    let added: [String]
    let skipped: [String]
    let addedCount: Int
    let skippedCount: Int

    enum CodingKeys: String, CodingKey {
        case added
        case skipped
        case addedCount = "added_count"
        case skippedCount = "skipped_count"
    }
}

/// Response from getting a feature prompt
struct PromptResponse: Codable {
    let prompt: String
    let featureId: String

    enum CodingKeys: String, CodingKey {
        case prompt
        case featureId = "feature_id"
    }
}
