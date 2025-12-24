import Foundation

struct Project: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var path: String
    var isActive: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case path
        case isActive = "is_active"
    }

    init(id: UUID = UUID(), name: String, path: String, isActive: Bool = true) {
        self.id = id
        self.name = name
        self.path = path
        self.isActive = isActive
    }

    var configPath: String {
        "\(path)/.flowforge/config.json"
    }

    var registryPath: String {
        "\(path)/.flowforge/registry.json"
    }
}

struct ProjectConfig: Codable {
    var projectName: String
    var projectRoot: String
    var worktreeBase: String
    var defaultBranch: String
    var aiProvider: String?
    var intelligenceLevel: Int

    enum CodingKeys: String, CodingKey {
        case projectName = "project_name"
        case projectRoot = "project_root"
        case worktreeBase = "worktree_base"
        case defaultBranch = "default_branch"
        case aiProvider = "ai_provider"
        case intelligenceLevel = "intelligence_level"
    }

    init(
        projectName: String,
        projectRoot: String,
        worktreeBase: String = ".flowforge-worktrees",
        defaultBranch: String = "main",
        aiProvider: String? = nil,
        intelligenceLevel: Int = 1
    ) {
        self.projectName = projectName
        self.projectRoot = projectRoot
        self.worktreeBase = worktreeBase
        self.defaultBranch = defaultBranch
        self.aiProvider = aiProvider
        self.intelligenceLevel = intelligenceLevel
    }
}
