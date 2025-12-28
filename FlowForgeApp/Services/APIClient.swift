import Foundation

enum APIError: Error, LocalizedError {
    case invalidURL
    case requestFailed(String)
    case decodingFailed(String)
    case serverError(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .requestFailed(let message):
            return "Request failed: \(message)"
        case .decodingFailed(let message):
            return "Failed to decode response: \(message)"
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message)"
        }
    }
}

/// HTTP client for FlowForge server API
actor APIClient {
    private var baseURL: URL
    private let session: URLSession

    init(baseURL: URL? = nil) {
        self.baseURL = baseURL ?? URL(string: PlatformConfig.defaultServerURL)!
        self.session = URLSession.shared
    }

    /// Update the server URL (for settings changes)
    func setBaseURL(_ urlString: String) {
        if let url = URL(string: urlString) {
            self.baseURL = url
        }
    }

    // MARK: - Projects

    /// Get all projects from the server
    func getProjects() async throws -> [Project] {
        let url = baseURL.appendingPathComponent("api/projects")
        let response: ProjectListResponse = try await get(url: url)
        return response.projects.map { projectData in
            Project(
                name: projectData.name,
                path: projectData.path,
                isActive: true
            )
        }
    }

    // MARK: - Feature List

    /// Get all features for a project
    func getFeatures(project: String) async throws -> [Feature] {
        let url = baseURL.appendingPathComponent("api/\(project)/features")
        let response: FeatureListResponse = try await get(url: url)
        return response.features
    }

    /// Add a new feature (defaults to inbox status for quick capture)
    func addFeature(
        project: String,
        title: String,
        description: String? = nil,
        status: String = "inbox"
    ) async throws {
        let url = baseURL.appendingPathComponent("api/\(project)/features")
        var body: [String: Any] = ["title": title, "status": status]
        if let description = description {
            body["description"] = description
        }
        let _: FeatureAddResponse = try await post(url: url, body: body)
    }

    /// Refine an inbox item into an idea ready to build
    func refineFeature(project: String, featureId: String) async throws {
        let url = baseURL.appendingPathComponent("api/\(project)/features/\(featureId)/refine")
        let _: EmptyResponse = try await post(url: url, body: [:])
    }

    /// Start a feature (creates worktree, generates prompt)
    /// Returns the worktree path and prompt for launching Claude Code
    func startFeature(project: String, featureId: String) async throws -> StartFeatureResponse {
        let url = baseURL.appendingPathComponent("api/\(project)/features/\(featureId)/start")
        return try await post(url: url, body: [:])
    }

    /// Stop a feature (cleans up worktree)
    func stopFeature(project: String, featureId: String) async throws {
        let url = baseURL.appendingPathComponent("api/\(project)/features/\(featureId)/stop")
        let _: EmptyResponse = try await post(url: url, body: [:])
    }

    /// Smart mark-as-done: detects if branch is merged and acts accordingly.
    /// Returns outcome: "shipped" (merged, cleaned up) or "review" (needs merge).
    func smartDoneFeature(project: String, featureId: String) async throws -> SmartDoneResponse {
        let url = baseURL.appendingPathComponent("api/\(project)/features/\(featureId)/smart-done")
        return try await post(url: url, body: [:])
    }

    // MARK: - Prompt Generation

    /// Get the implementation prompt for a feature
    func getPrompt(project: String, featureId: String) async throws -> String {
        let url = baseURL.appendingPathComponent("api/\(project)/features/\(featureId)/prompt")
        let response: PromptResponse = try await get(url: url)
        return response.prompt
    }

    /// Get git status for a feature's worktree
    func getGitStatus(project: String, featureId: String) async throws -> GitStatus {
        let url = baseURL.appendingPathComponent("api/\(project)/features/\(featureId)/git-status")
        return try await get(url: url)
    }

    /// Check if a feature has merge conflicts with main
    func checkMergeConflicts(project: String, featureId: String) async throws -> MergeCheckResult {
        let url = baseURL.appendingPathComponent("api/\(project)/features/\(featureId)/merge-check")
        return try await get(url: url)
    }

    // MARK: - Brainstorm / Proposals

    /// Parse Claude brainstorm output into proposals
    func parseBrainstorm(project: String, claudeOutput: String) async throws -> [Proposal] {
        let url = baseURL.appendingPathComponent("api/\(project)/brainstorm/parse")
        let body = ["claude_output": claudeOutput]

        let response: BrainstormParseResponse = try await post(url: url, body: body)
        return response.proposals
    }

    /// Approve proposals and add them to the registry
    func approveProposals(project: String, proposals: [Proposal]) async throws -> ApproveProposalsResponse {
        let url = baseURL.appendingPathComponent("api/\(project)/proposals/approve")

        // Convert proposals to dictionaries for the API
        let proposalDicts = proposals.map { proposal -> [String: Any] in
            [
                "title": proposal.title,
                "description": proposal.description,
                "priority": proposal.priority,
                "complexity": proposal.complexity,
                "tags": proposal.tags,
                "rationale": proposal.rationale,
                "status": proposal.status.rawValue,
            ]
        }

        let body = ["proposals": proposalDicts]
        return try await post(url: url, body: body)
    }

    // MARK: - Feature Operations

    /// Update a feature's attributes
    func updateFeature(
        project: String,
        featureId: String,
        title: String? = nil,
        description: String? = nil,
        status: String? = nil,
        priority: Int? = nil,
        complexity: String? = nil,
        tags: [String]? = nil
    ) async throws {
        let url = baseURL.appendingPathComponent("api/\(project)/features/\(featureId)")

        var body: [String: Any] = [:]
        if let title = title { body["title"] = title }
        if let description = description { body["description"] = description }
        if let status = status { body["status"] = status }
        if let priority = priority { body["priority"] = priority }
        if let complexity = complexity { body["complexity"] = complexity }
        if let tags = tags { body["tags"] = tags }

        let _: EmptyResponse = try await patch(url: url, body: body)
    }

    /// Update a feature with refined spec details
    /// Used when refining an inbox item through brainstorm chat
    func updateFeatureWithSpec(
        project: String,
        featureId: String,
        title: String,
        description: String,
        howItWorks: [String],
        filesAffected: [String],
        estimatedScope: String
    ) async throws {
        let url = baseURL.appendingPathComponent("api/\(project)/features/\(featureId)/spec")

        let body: [String: Any] = [
            "title": title,
            "description": description,
            "how_it_works": howItWorks,
            "files_affected": filesAffected,
            "estimated_scope": estimatedScope,
        ]

        let _: EmptyResponse = try await patch(url: url, body: body)
    }

    /// Delete a feature
    func deleteFeature(project: String, featureId: String, force: Bool = false) async throws {
        var url = baseURL.appendingPathComponent("api/\(project)/features/\(featureId)")
        if force {
            url = url.appending(queryItems: [URLQueryItem(name: "force", value: "true")])
        }
        let _: EmptyResponse = try await delete(url: url)
    }

    // MARK: - Shipping Stats (Wave 4.4)

    /// Get shipping streak statistics
    func getShippingStats(project: String) async throws -> ShippingStats {
        let url = baseURL.appendingPathComponent("api/\(project)/shipping-stats")
        return try await get(url: url)
    }

    // MARK: - Health Check (Registry vs Git State)

    /// Get project health - check for drift between registry and git state
    func getProjectHealth(project: String) async throws -> ProjectHealth {
        let url = baseURL.appendingPathComponent("api/\(project)/health")
        return try await get(url: url)
    }

    /// Reconcile a feature - fix drift between registry and git
    func reconcileFeature(project: String, featureId: String, action: String) async throws {
        let url = baseURL.appendingPathComponent("api/\(project)/features/\(featureId)/reconcile")
        let body = ["action": action]
        let _: ReconcileResponse = try await post(url: url, body: body)
    }

    // MARK: - Merge Operations

    /// Check if a feature can be merged safely
    func getMergeCheck(project: String, featureId: String) async throws -> MergeCheckResponse {
        let url = baseURL.appendingPathComponent("api/\(project)/features/\(featureId)/merge-check")
        return try await get(url: url)
    }

    /// Merge a feature (ship it!)
    func mergeFeature(project: String, featureId: String) async throws -> MergeResponse {
        let url = baseURL.appendingPathComponent("api/\(project)/features/\(featureId)/merge")
        return try await post(url: url, body: [:])
    }

    // MARK: - Project Initialization

    /// Initialize FlowForge in a project directory
    func initializeProject(
        project: String,
        quick: Bool = true,
        projectName: String? = nil,
        description: String? = nil,
        vision: String? = nil
    ) async throws -> InitProjectResponse {
        let url = baseURL.appendingPathComponent("api/\(project)/init")

        var body: [String: Any] = ["quick": quick]
        if let projectName = projectName { body["project_name"] = projectName }
        if let description = description { body["description"] = description }
        if let vision = vision { body["vision"] = vision }

        return try await post(url: url, body: body)
    }

    // MARK: - System Status (Offline-First)

    /// Get system status including Mac connectivity
    func getSystemStatus() async throws -> SystemStatus {
        let url = baseURL.appendingPathComponent("api/system/status")
        return try await get(url: url)
    }

    // MARK: - Deep Research

    /// Analyze whether a feature would benefit from deep research
    func getResearchNeed(project: String, featureId: String) async throws -> ResearchNeed {
        let url = baseURL.appendingPathComponent("api/\(project)/features/\(featureId)/research-need")
        return try await get(url: url)
    }

    /// Get research prompts for various providers
    func getResearchPrompts(project: String, featureId: String) async throws -> ResearchPrompts {
        let url = baseURL.appendingPathComponent("api/\(project)/features/\(featureId)/research-prompts")
        return try await get(url: url)
    }

    /// Upload a research report from an external provider
    func uploadResearch(
        project: String,
        featureId: String,
        provider: String,
        content: String
    ) async throws {
        let url = baseURL.appendingPathComponent("api/\(project)/features/\(featureId)/research")
        let body: [String: Any] = [
            "provider": provider,
            "content": content,
        ]
        let _: ResearchUploadResponse = try await post(url: url, body: body)
    }

    /// List all research reports for a feature
    func getResearchReports(project: String, featureId: String) async throws -> ResearchReportList {
        let url = baseURL.appendingPathComponent("api/\(project)/features/\(featureId)/research")
        return try await get(url: url)
    }

    /// Synthesize all research reports into unified implementation context
    func synthesizeResearch(project: String, featureId: String) async throws -> ResearchSynthesis {
        let url = baseURL.appendingPathComponent("api/\(project)/features/\(featureId)/research/synthesize")
        return try await post(url: url, body: [:])
    }

    /// Delete a specific research report
    func deleteResearch(project: String, featureId: String, provider: String) async throws {
        let url = baseURL.appendingPathComponent("api/\(project)/features/\(featureId)/research/\(provider)")
        let _: EmptyResponse = try await delete(url: url)
    }

    // MARK: - Private HTTP Methods

    private func get<T: Decodable>(url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        return try await execute(request)
    }

    private func post<T: Decodable>(url: URL, body: [String: Any]) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await execute(request)
    }

    private func patch<T: Decodable>(url: URL, body: [String: Any]) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await execute(request)
    }

    private func delete<T: Decodable>(url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        return try await execute(request)
    }

    private func execute<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.requestFailed("Invalid response type")
        }

        if httpResponse.statusCode >= 400 {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.serverError(httpResponse.statusCode, message)
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingFailed(error.localizedDescription)
        }
    }
}

// MARK: - Helper Types

private struct EmptyResponse: Decodable {}

private struct ProjectListResponse: Decodable {
    let projects: [ProjectData]
}

private struct ProjectData: Decodable {
    let name: String
    let path: String
}

private struct FeatureListResponse: Decodable {
    let features: [Feature]
}

private struct FeatureAddResponse: Decodable {
    let feature_id: String
}

/// Response from smart mark-as-done operation
struct SmartDoneResponse: Decodable {
    let outcome: String  // "shipped" or "review"
    let newStatus: String
    let featureId: String
    let worktreeRemoved: Bool?
    let macOnline: Bool?

    enum CodingKeys: String, CodingKey {
        case outcome
        case newStatus = "new_status"
        case featureId = "feature_id"
        case worktreeRemoved = "worktree_removed"
        case macOnline = "mac_online"
    }
}

/// Response from starting a feature - contains worktree path and prompt for launching Claude Code
struct StartFeatureResponse: Decodable {
    let featureId: String
    let worktreePath: String
    let promptPath: String?
    let prompt: String?
    let launchCommand: String?

    enum CodingKeys: String, CodingKey {
        case featureId = "feature_id"
        case worktreePath = "worktree_path"
        case promptPath = "prompt_path"
        case prompt
        case launchCommand = "launch_command"
    }
}

/// Git status for a feature's worktree
struct GitStatus: Decodable {
    let exists: Bool
    let hasChanges: Bool
    let changes: [String]
    let commitCount: Int
    let aheadOfMain: Int
    let behindMain: Int

    enum CodingKeys: String, CodingKey {
        case exists
        case hasChanges = "has_changes"
        case changes
        case commitCount = "commit_count"
        case aheadOfMain = "ahead_of_main"
        case behindMain = "behind_main"
    }

    /// Summary text for display
    var summary: String? {
        guard exists else { return nil }

        var parts: [String] = []
        if hasChanges {
            parts.append("\(changes.count) uncommitted")
        }
        if aheadOfMain > 0 {
            parts.append("\(aheadOfMain) ahead")
        }
        if behindMain > 0 {
            parts.append("\(behindMain) behind")
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

// MARK: - Merge Response Types

// MARK: - Project Initialization Response

struct InitProjectResponse: Decodable {
    let success: Bool
    let projectName: String
    let mainBranch: String
    let configPath: String?
    let registryPath: String?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case success
        case projectName = "project_name"
        case mainBranch = "main_branch"
        case configPath = "config_path"
        case registryPath = "registry_path"
        case message
    }
}

struct MergeCheckResponse: Decodable {
    let canMerge: Bool
    let conflicts: [String]?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case canMerge = "can_merge"
        case conflicts
        case message
    }
}

/// Result from checking merge conflicts for a feature
struct MergeCheckResult: Decodable {
    let ready: Bool
    let message: String?
    let data: MergeCheckData?

    /// Whether there are conflicts with main
    var hasConflicts: Bool {
        !(data?.conflictFiles?.isEmpty ?? true)
    }

    /// List of conflicting files
    var conflictFiles: [String] {
        data?.conflictFiles ?? []
    }
}

struct MergeCheckData: Decodable {
    let featureId: String?
    let ready: Bool?
    let conflictFiles: [String]?

    enum CodingKeys: String, CodingKey {
        case featureId = "feature_id"
        case ready
        case conflictFiles = "conflict_files"
    }
}

struct MergeResponse: Decodable {
    let success: Bool
    let message: String?
    let commitSha: String?

    enum CodingKeys: String, CodingKey {
        case success
        case message
        case commitSha = "commit_sha"
    }
}

// MARK: - System Status Types

/// System status including Mac connectivity and cache state
struct SystemStatus: Decodable {
    let macOnline: Bool
    let lastCheck: String?
    let lastSync: String?
    let pendingOperations: Int?
    let cacheStats: CacheStats?

    enum CodingKeys: String, CodingKey {
        case macOnline = "mac_online"
        case lastCheck = "last_check"
        case lastSync = "last_sync"
        case pendingOperations = "pending_operations"
        case cacheStats = "cache_stats"
    }
}

struct CacheStats: Decodable {
    let projectsCached: Int
    let featuresCached: Int
    let pendingOperations: Int
    let dbPath: String
    let dbSizeKb: Int

    enum CodingKeys: String, CodingKey {
        case projectsCached = "projects_cached"
        case featuresCached = "features_cached"
        case pendingOperations = "pending_operations"
        case dbPath = "db_path"
        case dbSizeKb = "db_size_kb"
    }
}

// MARK: - Health Check Types

/// Project health status - compares registry to git state
struct ProjectHealth: Decodable {
    let healthy: Bool
    let issues: [HealthIssue]
    let checkedFeatures: Int
    let checkedWorktrees: Int

    enum CodingKeys: String, CodingKey {
        case healthy
        case issues
        case checkedFeatures = "checked_features"
        case checkedWorktrees = "checked_worktrees"
    }
}

/// A single health issue detected
struct HealthIssue: Decodable, Identifiable {
    var id: String { featureId ?? worktreePath ?? UUID().uuidString }

    let featureId: String?
    let type: String  // "branch_merged", "missing_worktree", "orphan_worktree"
    let message: String
    let canAutoFix: Bool
    let fixAction: String?
    let worktreePath: String?

    enum CodingKeys: String, CodingKey {
        case featureId = "feature_id"
        case type
        case message
        case canAutoFix = "can_auto_fix"
        case fixAction = "fix_action"
        case worktreePath = "worktree_path"
    }
}

/// Response from reconciling a feature
private struct ReconcileResponse: Decodable {
    let success: Bool
    let message: String?
}

// MARK: - Deep Research Types

/// Analysis of whether a feature needs deep research
struct ResearchNeed: Decodable {
    let needsResearch: Bool
    let topics: [String]
    let reasoning: String
    let suggestedProviders: [String]
    let searchQueries: [String]?
    let officialDocs: [String]?

    enum CodingKeys: String, CodingKey {
        case needsResearch = "needs_research"
        case topics
        case reasoning
        case suggestedProviders = "suggested_providers"
        case searchQueries = "search_queries"
        case officialDocs = "official_docs"
    }
}

/// Research prompts for various providers
struct ResearchPrompts: Decodable {
    let featureId: String
    let featureTitle: String
    let prompts: [String: String]  // provider -> prompt
    let topics: [String]

    enum CodingKeys: String, CodingKey {
        case featureId = "feature_id"
        case featureTitle = "feature_title"
        case prompts
        case topics
    }
}

/// Response from uploading a research report
private struct ResearchUploadResponse: Decodable {
    let success: Bool
    let message: String
    let provider: String
    let featureId: String

    enum CodingKeys: String, CodingKey {
        case success
        case message
        case provider
        case featureId = "feature_id"
    }
}

/// A single research report
struct ResearchReport: Decodable, Identifiable {
    let id: String
    let provider: String
    let filename: String
    let preview: String
    let uploadedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case provider
        case filename
        case preview
        case uploadedAt = "uploaded_at"
    }
}

/// List of research reports for a feature
struct ResearchReportList: Decodable {
    let featureId: String
    let reports: [ResearchReport]
    let reportCount: Int
    let hasSynthesis: Bool
    let synthesisPreview: String?

    enum CodingKeys: String, CodingKey {
        case featureId = "feature_id"
        case reports
        case reportCount = "report_count"
        case hasSynthesis = "has_synthesis"
        case synthesisPreview = "synthesis_preview"
    }
}

/// Result of synthesizing research reports
struct ResearchSynthesis: Decodable {
    let success: Bool
    let featureId: String
    let synthesis: String
    let reportsSynthesized: [String]

    enum CodingKeys: String, CodingKey {
        case success
        case featureId = "feature_id"
        case synthesis
        case reportsSynthesized = "reports_synthesized"
    }
}
