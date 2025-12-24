import Foundation

enum FeatureStatus: String, Codable, CaseIterable {
    case planned = "planned"
    case inProgress = "in-progress"
    case review = "review"
    case completed = "completed"
    case blocked = "blocked"

    var displayName: String {
        switch self {
        case .planned: return "Planned"
        case .inProgress: return "In Progress"
        case .review: return "Review"
        case .completed: return "Completed"
        case .blocked: return "Blocked"
        }
    }

    var color: String {
        switch self {
        case .planned: return "gray"
        case .inProgress: return "blue"
        case .review: return "orange"
        case .completed: return "green"
        case .blocked: return "red"
        }
    }
}

enum Complexity: String, Codable {
    case small = "small"
    case medium = "medium"
    case large = "large"
    case epic = "epic"

    var displayName: String {
        rawValue.capitalized
    }
}

struct Feature: Identifiable, Codable, Hashable {
    let id: String
    var title: String
    var description: String?
    var status: FeatureStatus
    var complexity: Complexity?
    var parentId: String?
    var dependencies: [String]
    var branch: String?
    var worktreePath: String?
    var promptPath: String?
    var createdAt: Date
    var startedAt: Date?
    var completedAt: Date?
    var tags: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case status
        case complexity
        case parentId = "parent_id"
        case dependencies
        case branch
        case worktreePath = "worktree_path"
        case promptPath = "prompt_path"
        case createdAt = "created_at"
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case tags
    }

    init(
        id: String,
        title: String,
        description: String? = nil,
        status: FeatureStatus = .planned,
        complexity: Complexity? = nil,
        parentId: String? = nil,
        dependencies: [String] = [],
        branch: String? = nil,
        worktreePath: String? = nil,
        promptPath: String? = nil,
        createdAt: Date = Date(),
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        tags: [String] = []
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.status = status
        self.complexity = complexity
        self.parentId = parentId
        self.dependencies = dependencies
        self.branch = branch
        self.worktreePath = worktreePath
        self.promptPath = promptPath
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.tags = tags
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        status = try container.decode(FeatureStatus.self, forKey: .status)
        complexity = try container.decodeIfPresent(Complexity.self, forKey: .complexity)
        parentId = try container.decodeIfPresent(String.self, forKey: .parentId)
        dependencies = try container.decodeIfPresent([String].self, forKey: .dependencies) ?? []
        branch = try container.decodeIfPresent(String.self, forKey: .branch)
        worktreePath = try container.decodeIfPresent(String.self, forKey: .worktreePath)
        promptPath = try container.decodeIfPresent(String.self, forKey: .promptPath)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []

        // Handle date decoding - support both ISO8601 strings and timestamps
        let createdAtString = try container.decode(String.self, forKey: .createdAt)
        if let date = ISO8601DateFormatter().date(from: createdAtString) {
            createdAt = date
        } else {
            createdAt = Date()
        }

        if let startedAtString = try container.decodeIfPresent(String.self, forKey: .startedAt),
           let date = ISO8601DateFormatter().date(from: startedAtString) {
            startedAt = date
        } else {
            startedAt = nil
        }

        if let completedAtString = try container.decodeIfPresent(String.self, forKey: .completedAt),
           let date = ISO8601DateFormatter().date(from: completedAtString) {
            completedAt = date
        } else {
            completedAt = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(complexity, forKey: .complexity)
        try container.encodeIfPresent(parentId, forKey: .parentId)
        try container.encode(dependencies, forKey: .dependencies)
        try container.encodeIfPresent(branch, forKey: .branch)
        try container.encodeIfPresent(worktreePath, forKey: .worktreePath)
        try container.encodeIfPresent(promptPath, forKey: .promptPath)
        try container.encode(tags, forKey: .tags)

        let formatter = ISO8601DateFormatter()
        try container.encode(formatter.string(from: createdAt), forKey: .createdAt)
        if let startedAt = startedAt {
            try container.encode(formatter.string(from: startedAt), forKey: .startedAt)
        }
        if let completedAt = completedAt {
            try container.encode(formatter.string(from: completedAt), forKey: .completedAt)
        }
    }
}

// Registry structure matching Python backend
struct FeatureRegistry: Codable {
    var features: [String: Feature]
    var metadata: RegistryMetadata?

    struct RegistryMetadata: Codable {
        var version: String?
        var lastModified: String?

        enum CodingKeys: String, CodingKey {
            case version
            case lastModified = "last_modified"
        }
    }
}
