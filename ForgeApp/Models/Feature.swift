import Foundation

enum FeatureStatus: String, Codable, CaseIterable {
    case inbox = "inbox"  // Quick captures, raw thoughts
    case idea = "idea"  // Refined, ready to build (was "planned")
    case inProgress = "in-progress"
    case review = "review"
    case completed = "completed"
    case blocked = "blocked"

    var displayName: String {
        switch self {
        case .inbox: return "Inbox"
        case .idea: return "Ready"  // Ready to build
        case .inProgress: return "Building"
        case .review: return "Review"
        case .completed: return "Shipped"
        case .blocked: return "Blocked"
        }
    }

    var color: String {
        switch self {
        case .inbox: return "purple"  // Distinct color for raw captures
        case .idea: return "gray"  // Ready to build
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
    var updatedAt: Date?
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
        case dependsOn = "depends_on"  // Python uses depends_on
        case branch
        case worktreePath = "worktree_path"
        case promptPath = "prompt_path"
        case createdAt = "created_at"
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case updatedAt = "updated_at"  // Python uses updated_at
        case tags
        case priority
    }

    init(
        id: String,
        title: String,
        description: String? = nil,
        status: FeatureStatus = .idea,
        complexity: Complexity? = nil,
        parentId: String? = nil,
        dependencies: [String] = [],
        branch: String? = nil,
        worktreePath: String? = nil,
        promptPath: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
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
        self.updatedAt = updatedAt
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

        // Support both "dependencies" and "depends_on" field names
        if let deps = try container.decodeIfPresent([String].self, forKey: .dependencies) {
            dependencies = deps
        } else if let deps = try container.decodeIfPresent([String].self, forKey: .dependsOn) {
            dependencies = deps
        } else {
            dependencies = []
        }

        branch = try container.decodeIfPresent(String.self, forKey: .branch)
        worktreePath = try container.decodeIfPresent(String.self, forKey: .worktreePath)
        promptPath = try container.decodeIfPresent(String.self, forKey: .promptPath)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []

        // Handle date decoding - support both ISO8601 strings and flexible formats
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let fallbackFormatter = ISO8601DateFormatter()
        fallbackFormatter.formatOptions = [.withInternetDateTime]

        // Python's isoformat() doesn't include timezone, so we need a DateFormatter fallback
        let pythonFormatter = DateFormatter()
        pythonFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
        pythonFormatter.locale = Locale(identifier: "en_US_POSIX")

        let pythonFormatterNoFrac = DateFormatter()
        pythonFormatterNoFrac.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        pythonFormatterNoFrac.locale = Locale(identifier: "en_US_POSIX")

        func parseDate(_ string: String) -> Date? {
            formatter.date(from: string)
                ?? fallbackFormatter.date(from: string)
                ?? pythonFormatter.date(from: string)
                ?? pythonFormatterNoFrac.date(from: string)
        }

        let createdAtString = try container.decode(String.self, forKey: .createdAt)
        createdAt = parseDate(createdAtString) ?? Date()

        if let updatedAtString = try container.decodeIfPresent(String.self, forKey: .updatedAt) {
            updatedAt = parseDate(updatedAtString)
        } else {
            updatedAt = nil
        }

        if let startedAtString = try container.decodeIfPresent(String.self, forKey: .startedAt) {
            startedAt = parseDate(startedAtString)
        } else {
            startedAt = nil
        }

        if let completedAtString = try container.decodeIfPresent(String.self, forKey: .completedAt) {
            completedAt = parseDate(completedAtString)
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


// MARK: - Shipping Stats (Wave 4.4)

/// Shipping streak statistics for gamification
struct ShippingStats: Codable {
    var currentStreak: Int
    var longestStreak: Int
    var totalShipped: Int
    var lastShipDate: String?
    var streakDisplay: String?

    enum CodingKeys: String, CodingKey {
        case currentStreak = "current_streak"
        case longestStreak = "longest_streak"
        case totalShipped = "total_shipped"
        case lastShipDate = "last_ship_date"
        case streakDisplay = "streak_display"
    }

    init(
        currentStreak: Int = 0,
        longestStreak: Int = 0,
        totalShipped: Int = 0,
        lastShipDate: String? = nil,
        streakDisplay: String? = nil
    ) {
        self.currentStreak = currentStreak
        self.longestStreak = longestStreak
        self.totalShipped = totalShipped
        self.lastShipDate = lastShipDate
        self.streakDisplay = streakDisplay
    }

    /// Formatted display string for the streak
    var displayText: String {
        if let display = streakDisplay, !display.isEmpty {
            return display
        }
        if currentStreak == 0 {
            return "No streak"
        } else if currentStreak == 1 {
            return "🔥 1 day"
        } else {
            return "🔥 \(currentStreak) days"
        }
    }
}
