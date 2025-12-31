import Foundation
import Observation
#if os(iOS)
import UIKit
#endif

/// Sorting options for lists
enum SortOrder: String, CaseIterable, Codable {
    case recentlyUsed = "recently_used"
    case alphabetical = "alphabetical"
    case manual = "manual"

    var displayName: String {
        switch self {
        case .recentlyUsed: return "Recent"
        case .alphabetical: return "A-Z"
        case .manual: return "Manual"
        }
    }

    var icon: String {
        switch self {
        case .recentlyUsed: return "clock"
        case .alphabetical: return "textformat.abc"
        case .manual: return "line.3.horizontal"
        }
    }
}

/// Connection state for offline-first architecture
enum ConnectionState: Equatable {
    case connected              // Pi reachable, Mac online
    case piOnlyMode(pending: Int)  // Pi reachable, Mac offline (cached data)
    case offline                // Can't reach Pi at all

    var isFullyConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var macOnline: Bool {
        if case .connected = self { return true }
        return false
    }

    var displayText: String {
        switch self {
        case .connected:
            return "Connected"
        case .piOnlyMode(let pending):
            if pending > 0 {
                return "Offline Mode (\(pending) pending)"
            }
            return "Offline Mode (cached)"
        case .offline:
            return "No Connection"
        }
    }
}

@MainActor
@Observable
class AppState {
    private static let lastProjectKey = "Forge.lastSelectedProject"

    var projects: [Project] = []
    var selectedProject: Project?
    var features: [Feature] = []
    var isLoading = false
    var errorMessage: String?
    var successMessage: String?  // For toast notifications
    var isConnectedToServer = false
    var connectionError: String?

    // Offline-first state
    var connectionState: ConnectionState = .offline
    var systemStatus: SystemStatus?
    var isDataFromCache = false

    // Brainstorm state
    var parsedProposals: [Proposal] = []
    var showingProposalReview = false


    // Shipping stats (Wave 4.4)
    var shippingStats: ShippingStats = ShippingStats()

    // Health check state (registry vs git drift detection)
    var projectHealth: ProjectHealth?
    var isReconciling = false

    // Project initialization state
    var showingProjectSetup = false
    var projectToInitialize: Project?

    // Sorting preferences (persisted)
    var projectSortOrder: SortOrder {
        didSet { UserDefaults.standard.set(projectSortOrder.rawValue, forKey: "projectSortOrder") }
    }
    var inboxSortOrder: SortOrder {
        didSet { UserDefaults.standard.set(inboxSortOrder.rawValue, forKey: "inboxSortOrder") }
    }
    var ideaSortOrder: SortOrder {
        didSet { UserDefaults.standard.set(ideaSortOrder.rawValue, forKey: "ideaSortOrder") }
    }

    // Track when items were last accessed (for "recently used" sorting)
    private var projectAccessTimes: [String: Date] = [:] {
        didSet { saveAccessTimes() }
    }
    private var featureAccessTimes: [String: Date] = [:] {
        didSet { saveAccessTimes() }
    }

    // Track hidden projects (persisted)
    private var hiddenProjectIds: Set<String> = [] {
        didSet { saveHiddenProjects() }
    }

    // Offline caching
    private let featureCache = FeatureCache()

    #if os(macOS)
    private let cliBridge = CLIBridge()
    private var fileWatcher: FileWatcher?
    #endif

    private var apiClient = APIClient()
    private var webSocketClient: WebSocketClient?

    /// Whether to use API mode (server) vs CLI mode (local file only)
    /// Default to API mode when server is running - gives full features
    #if os(iOS)
    private let useAPIMode = true  // iOS always uses API
    #else
    private var useAPIMode = true  // macOS uses API when server is running
    #endif

    init() {
        // Load sorting preferences from UserDefaults
        if let raw = UserDefaults.standard.string(forKey: "projectSortOrder"),
           let order = SortOrder(rawValue: raw) {
            projectSortOrder = order
        } else {
            projectSortOrder = .recentlyUsed
        }
        if let raw = UserDefaults.standard.string(forKey: "inboxSortOrder"),
           let order = SortOrder(rawValue: raw) {
            inboxSortOrder = order
        } else {
            inboxSortOrder = .recentlyUsed
        }
        if let raw = UserDefaults.standard.string(forKey: "ideaSortOrder"),
           let order = SortOrder(rawValue: raw) {
            ideaSortOrder = order
        } else {
            ideaSortOrder = .recentlyUsed
        }

        // Load access times and hidden projects
        loadAccessTimes()
        loadHiddenProjects()

        setupWebSocket()
        Task {
            await loadProjects()
            await refreshSystemStatus()
        }
    }

    // MARK: - Access Time Tracking (for "recently used" sorting)

    private func saveAccessTimes() {
        if let data = try? JSONEncoder().encode(projectAccessTimes) {
            UserDefaults.standard.set(data, forKey: "projectAccessTimes")
        }
        if let data = try? JSONEncoder().encode(featureAccessTimes) {
            UserDefaults.standard.set(data, forKey: "featureAccessTimes")
        }
    }

    private func loadAccessTimes() {
        if let data = UserDefaults.standard.data(forKey: "projectAccessTimes"),
           let times = try? JSONDecoder().decode([String: Date].self, from: data) {
            projectAccessTimes = times
        }
        if let data = UserDefaults.standard.data(forKey: "featureAccessTimes"),
           let times = try? JSONDecoder().decode([String: Date].self, from: data) {
            featureAccessTimes = times
        }
    }

    private func saveHiddenProjects() {
        if let data = try? JSONEncoder().encode(Array(hiddenProjectIds)) {
            UserDefaults.standard.set(data, forKey: "hiddenProjectIds")
        }
    }

    private func loadHiddenProjects() {
        if let data = UserDefaults.standard.data(forKey: "hiddenProjectIds"),
           let ids = try? JSONDecoder().decode([String].self, from: data) {
            hiddenProjectIds = Set(ids)
        }
    }

    /// Mark a project as accessed (for recently used sorting)
    func markProjectAccessed(_ project: Project) {
        projectAccessTimes[project.id.uuidString] = Date()
    }

    /// Mark a feature as accessed (for recently used sorting)
    func markFeatureAccessed(_ feature: Feature) {
        featureAccessTimes[feature.id] = Date()
    }

    // MARK: - Sorted Lists

    /// Projects sorted according to current preference
    var sortedProjects: [Project] {
        switch projectSortOrder {
        case .recentlyUsed:
            return projects.sorted { a, b in
                let timeA = projectAccessTimes[a.id.uuidString] ?? .distantPast
                let timeB = projectAccessTimes[b.id.uuidString] ?? .distantPast
                return timeA > timeB
            }
        case .alphabetical:
            return projects.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .manual:
            return projects
        }
    }

    /// Visible projects (excludes hidden) sorted according to current preference
    var visibleSortedProjects: [Project] {
        sortedProjects.filter { !hiddenProjectIds.contains($0.path) }
    }

    /// Hidden projects sorted according to current preference
    var hiddenProjects: [Project] {
        sortedProjects.filter { hiddenProjectIds.contains($0.path) }
    }

    /// Inbox items (raw captures) sorted according to current preference
    var sortedInboxItems: [Feature] {
        let inbox = features.filter { $0.status == .inbox }
        return sortFeatures(inbox, by: inboxSortOrder)
    }

    /// Ideas (refined, ready to build) sorted according to current preference
    var sortedIdeas: [Feature] {
        let ideas = features.filter { $0.status == .idea }
        return sortFeatures(ideas, by: ideaSortOrder)
    }

    private func sortFeatures(_ items: [Feature], by order: SortOrder) -> [Feature] {
        switch order {
        case .recentlyUsed:
            return items.sorted { a, b in
                // Priority: local access time > updatedAt > createdAt
                let timeA = featureAccessTimes[a.id] ?? a.updatedAt ?? a.createdAt
                let timeB = featureAccessTimes[b.id] ?? b.updatedAt ?? b.createdAt
                return timeA > timeB
            }
        case .alphabetical:
            return items.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .manual:
            return items
        }
    }

    // MARK: - System Status (Offline-First)

    /// Refresh system status to determine connection state
    func refreshSystemStatus() async {
        do {
            let status = try await apiClient.getSystemStatus()
            self.systemStatus = status

            if status.macOnline {
                connectionState = .connected
                isConnectedToServer = true
            } else {
                connectionState = .piOnlyMode(pending: 0)
                isConnectedToServer = true  // Pi is reachable, just Mac is offline
            }
        } catch {
            // Can't reach Pi at all
            connectionState = .offline
            isConnectedToServer = false
            connectionError = error.localizedDescription
        }
    }

    /// Check if Mac is required for an operation (and show friendly error if offline)
    func requiresMac(for operation: String) -> Bool {
        guard connectionState.macOnline else {
            errorMessage = "Mac is offline. \(operation) requires your MacBook to be open."
            return false
        }
        return true
    }

    // MARK: - Server Configuration

    /// Update the server URL and reconnect
    func updateServerURL(_ urlString: String) {
        PlatformConfig.setServerURL(urlString)

        // Update API client
        apiClient = APIClient(baseURL: URL(string: urlString))

        // Reconnect WebSocket if connected
        if let project = selectedProject {
            webSocketClient?.disconnect()
            webSocketClient?.connect(project: project.name)
        }

        // Reload to test connection
        Task {
            await loadProjects()
        }
    }

    /// Test connection to server
    /// - Parameter url: Optional URL to test (defaults to current server URL)
    func testConnection(url: String? = nil) async -> (success: Bool, message: String) {
        do {
            // If testing a custom URL, create a temporary client
            let client: APIClient
            if let testURL = url, let baseURL = URL(string: testURL) {
                client = APIClient(baseURL: baseURL)
            } else {
                client = apiClient
            }

            let projects = try await client.getProjects()
            // Only update state if testing current URL
            if url == nil {
                isConnectedToServer = true
                connectionError = nil
            }
            return (true, "Connected! Found \(projects.count) project(s)")
        } catch {
            // Only update state if testing current URL
            if url == nil {
                isConnectedToServer = false
                connectionError = error.localizedDescription
            }
            return (false, error.localizedDescription)
        }
    }

    private func setupWebSocket() {
        webSocketClient = WebSocketClient()

        webSocketClient?.onFeatureUpdate = { [weak self] update in
            Task { @MainActor in
                await self?.handleFeatureUpdate(update)
            }
        }

        webSocketClient?.onSyncRequest = { [weak self] in
            Task { @MainActor in
                await self?.reloadFeatures()
            }
        }
    }

    private func handleFeatureUpdate(_ update: WebSocketClient.FeatureUpdate) async {
        guard update.project == selectedProject?.name else { return }

        switch update.action {
        case "deleted":
            // Remove the feature from local state
            features.removeAll { $0.id == update.featureId }
        default:
            // For created, updated, started, stopped - reload to get latest
            await reloadFeatures()
        }
    }

    // MARK: - Project Management

    /// Hide a project from the sidebar
    func hideProject(_ project: Project) {
        hiddenProjectIds.insert(project.path)  // Use path (stable) not UUID (regenerated on launch)
    }

    /// Show a hidden project in the sidebar
    func showProject(_ project: Project) {
        hiddenProjectIds.remove(project.path)
    }

    func loadProjects() async {
        isLoading = true
        errorMessage = nil

        let projects = await discoverProjects()
        await MainActor.run {
            self.projects = projects

            // Restore last selected project, or fall back to first
            let lastProjectName = UserDefaults.standard.string(forKey: Self.lastProjectKey)
            let projectToSelect = projects.first { $0.name == lastProjectName } ?? projects.first

            if let project = projectToSelect {
                self.selectedProject = project
                Task {
                    await self.loadFeatures()
                }
            }
            self.isLoading = false
        }
    }

    func selectProject(_ project: Project) async {
        selectedProject = project

        // Persist selection for next launch
        UserDefaults.standard.set(project.name, forKey: Self.lastProjectKey)

        // Connect WebSocket for real-time updates
        if useAPIMode {
            await MainActor.run {
                webSocketClient?.connect(project: project.name)
            }
        }

        await loadFeatures()
    }

    private func discoverProjects() async -> [Project] {
        #if os(macOS)
        // macOS: Scan local filesystem for Forge projects AND uninitialized Git repos
        // ONLY scans top-level directories (no recursion into subdirectories)
        return await Task.detached {
            let homeDir = FileManager.default.homeDirectoryForCurrentUser

            // Only scan the primary projects location - no nested paths
            let projectsBase = homeDir.appendingPathComponent("Projects/Active")

            var discoveredProjects: [Project] = []
            var seenPaths: Set<String> = []

            // Only scan IMMEDIATE children of projects base (no recursion)
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: projectsBase,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                return []
            }

            for url in contents {
                // Skip if not a directory
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                      isDirectory.boolValue else {
                    continue
                }

                let forgeDir = url.appendingPathComponent(".forge")
                let gitDir = url.appendingPathComponent(".git")

                var isForgeDir: ObjCBool = false
                var isGitDir: ObjCBool = false

                let hasForge = FileManager.default.fileExists(
                    atPath: forgeDir.path,
                    isDirectory: &isForgeDir
                ) && isForgeDir.boolValue

                let hasGit = FileManager.default.fileExists(
                    atPath: gitDir.path,
                    isDirectory: &isGitDir
                ) && isGitDir.boolValue

                // Must have .forge OR (.git + looks like a real project)
                let looksLikeProject = hasForge || (hasGit && Self.looksLikeRealProject(url))

                if looksLikeProject {
                    let resolvedPath = url.standardizedFileURL.path
                    if !seenPaths.contains(resolvedPath) {
                        seenPaths.insert(resolvedPath)

                        let status: ProjectInitializationStatus = hasForge
                            ? .initialized
                            : .uninitialized

                        let project = Project(
                            name: url.lastPathComponent,
                            path: resolvedPath,
                            isActive: hasForge,
                            initializationStatus: status
                        )
                        discoveredProjects.append(project)
                    }
                }
            }

            // Sort: initialized projects first, then by name
            return discoveredProjects.sorted { p1, p2 in
                if p1.isInitialized != p2.isInitialized {
                    return p1.isInitialized
                }
                return p1.name.localizedCaseInsensitiveCompare(p2.name) == .orderedAscending
            }
        }.value
        #else
        // iOS: Fetch projects from API
        do {
            let projects = try await apiClient.getProjects()
            await MainActor.run {
                isConnectedToServer = true
                connectionError = nil
            }
            return projects
        } catch {
            await MainActor.run {
                isConnectedToServer = false
                connectionError = "Cannot connect to \(PlatformConfig.defaultServerURL)"
            }
            print("Failed to fetch projects: \(error)")
            return []
        }
        #endif
    }

    /// Check if a directory looks like a real project (not a tool/dependency)
    /// Looks for common project markers like package.json, pyproject.toml, etc.
    private static nonisolated func looksLikeRealProject(_ url: URL) -> Bool {
        let projectMarkers = [
            "package.json",       // Node.js
            "pyproject.toml",     // Python (modern)
            "setup.py",           // Python (legacy)
            "Cargo.toml",         // Rust
            "go.mod",             // Go
            "build.gradle",       // Java/Kotlin
            "pom.xml",            // Java/Maven
            "Gemfile",            // Ruby
            "*.xcodeproj",        // Xcode (checked separately)
            "*.xcworkspace",      // Xcode workspace
            "project.yml",        // XcodeGen
            "Makefile",           // Make-based
            "CMakeLists.txt",     // CMake
            "CLAUDE.md",          // Claude Code project
            "README.md",          // Most real projects have this
        ]

        let fm = FileManager.default

        for marker in projectMarkers {
            if marker.contains("*") {
                // Wildcard pattern - check for any matching file
                let pattern = marker.replacingOccurrences(of: "*", with: "")
                if let contents = try? fm.contentsOfDirectory(atPath: url.path) {
                    if contents.contains(where: { $0.hasSuffix(pattern) }) {
                        return true
                    }
                }
            } else {
                // Exact file check
                if fm.fileExists(atPath: url.appendingPathComponent(marker).path) {
                    return true
                }
            }
        }

        return false
    }

    // MARK: - Project Initialization

    /// Initialize Forge in an uninitialized project
    func initializeProject(_ project: Project, quick: Bool = true) async throws {
        guard project.needsInitialization else {
            throw ForgeError.alreadyInitialized
        }

        let result = try await apiClient.initializeProject(
            project: project.name,
            quick: quick
        )

        // Update local state
        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            projects[index].initializationStatus = .initialized
            projects[index].isActive = true
        }

        successMessage = "Initialized \(result.projectName)!"

        // Reload projects to get fresh data
        await loadProjects()
    }

    // MARK: - Feature Management

    func loadFeatures() async {
        guard let project = selectedProject else { return }

        isLoading = true
        errorMessage = nil

        #if os(macOS)
        // Stop watching previous project (local mode only)
        fileWatcher?.stop()
        #endif

        // Load cached features first (instant display while fetching)
        #if os(iOS)
        if let cached = featureCache.load(for: project.name) {
            self.features = cached
        }
        #endif

        do {
            let features: [Feature]

            #if os(iOS)
            // iOS always uses API mode
            features = try await apiClient.getFeatures(project: project.name)
            self.isConnectedToServer = true

            // Cache the fresh data
            featureCache.save(features, for: project.name)
            #else
            if useAPIMode {
                // API mode: fetch from server
                features = try await apiClient.getFeatures(project: project.name)
                self.isConnectedToServer = true
            } else {
                // CLI mode: read local registry
                let registryPath = project.registryPath
                features = try await cliBridge.loadRegistry(at: registryPath)

                // Start watching for local changes
                fileWatcher = FileWatcher(path: registryPath) { [weak self] in
                    Task { [weak self] in
                        await self?.reloadFeatures()
                    }
                }
                fileWatcher?.start()
            }
            #endif

            self.features = features
            self.isLoading = false

            // Load stats and health check in background
            Task {
                await loadShippingStats()
                await checkProjectHealth()
            }

        } catch {
            #if os(iOS)
            // On iOS, if fetch fails but we have cache, show cached data
            if !self.features.isEmpty {
                self.errorMessage = "Showing cached data (offline)"
            } else {
                self.errorMessage = "Failed to load features: \(error.localizedDescription)"
            }
            #else
            self.errorMessage = "Failed to load features: \(error.localizedDescription)"
            #endif
            self.isLoading = false
            self.isConnectedToServer = false
        }
    }

    private func reloadFeatures() async {
        guard let project = selectedProject else { return }

        do {
            let features: [Feature]

            #if os(iOS)
            features = try await apiClient.getFeatures(project: project.name)
            #else
            if useAPIMode {
                features = try await apiClient.getFeatures(project: project.name)
            } else {
                let registryPath = project.registryPath
                features = try await cliBridge.loadRegistry(at: registryPath)
            }
            #endif

            self.features = features
        } catch {
            // Silent fail on reload - don't show error to user
            print("Failed to reload features: \(error)")
        }
    }

    func updateFeatureStatus(_ feature: Feature, to newStatus: FeatureStatus) async {
        guard let project = selectedProject else { return }

        do {
            #if os(iOS)
            try await apiClient.updateFeature(
                project: project.name,
                featureId: feature.id,
                status: newStatus.rawValue
            )
            #else
            if useAPIMode {
                try await apiClient.updateFeature(
                    project: project.name,
                    featureId: feature.id,
                    status: newStatus.rawValue
                )
            } else {
                try await cliBridge.updateFeatureStatus(
                    featureId: feature.id,
                    status: newStatus,
                    projectPath: project.path
                )
            }
            #endif
        } catch {
            self.errorMessage = "Failed to update feature: \(error.localizedDescription)"
        }
    }

    func addFeature(title: String) async {
        guard let project = selectedProject else { return }

        do {
            #if os(iOS)
            try await apiClient.addFeature(project: project.name, title: title)
            #else
            if useAPIMode {
                try await apiClient.addFeature(project: project.name, title: title)
            } else {
                try await cliBridge.addFeature(title: title, projectPath: project.path)
            }
            #endif
        } catch {
            self.errorMessage = "Failed to add feature: \(error.localizedDescription)"
        }
    }

    // MARK: - Add Feature to Queue

    /// Add a feature directly to the queue (no analysis gate)
    /// This is the instant capture path - ideas are cheap, discipline comes at START
    func addFeatureToQueue(title: String) async {
        guard let project = selectedProject else { return }

        do {
            try await apiClient.addFeature(project: project.name, title: title, status: "inbox")
            showSuccess("Added to inbox!")
        } catch {
            self.errorMessage = "Failed to add feature: \(error.localizedDescription)"
        }
    }

    func startFeature(_ feature: Feature) async {
        guard let project = selectedProject else { return }

        // Check if Mac is online (required for git worktree creation)
        guard requiresMac(for: "Starting a feature") else {
            return
        }

        do {
            #if os(iOS)
            // iOS: Just start the feature - user will copy prompt to Claude web
            let response = try await apiClient.startFeature(project: project.name, featureId: feature.id)
            if let prompt = response.prompt {
                // Copy prompt to clipboard for easy paste into Claude web
                UIPasteboard.general.string = prompt
                showSuccess("Ready to build! Prompt copied to clipboard.")
            }
            #else
            if useAPIMode {
                // macOS API mode: Start feature AND launch Warp terminal
                let response = try await apiClient.startFeature(project: project.name, featureId: feature.id)

                // Launch Claude Code in Warp terminal with configured command
                let launchResult = await TerminalLauncher.launchClaudeCode(
                    worktreePath: response.worktreePath,
                    prompt: response.prompt,
                    launchCommand: response.launchCommand
                )

                if launchResult.success {
                    showSuccess("Opening Claude Code...")
                } else {
                    // Still successful - worktree created, just manual terminal launch needed
                    showSuccess("Worktree ready! Prompt copied to clipboard.")
                }
            } else {
                try await cliBridge.startFeature(featureId: feature.id, projectPath: project.path)
            }
            #endif
        } catch {
            self.errorMessage = "Failed to start feature: \(error.localizedDescription)"
        }
    }

    func stopFeature(_ feature: Feature) async {
        guard let project = selectedProject else { return }

        do {
            #if os(iOS)
            try await apiClient.stopFeature(project: project.name, featureId: feature.id)
            #else
            if useAPIMode {
                try await apiClient.stopFeature(project: project.name, featureId: feature.id)
            } else {
                try await cliBridge.stopFeature(featureId: feature.id, projectPath: project.path)
            }
            #endif
        } catch {
            self.errorMessage = "Failed to stop feature: \(error.localizedDescription)"
        }
    }

    #if os(macOS)
    /// Smart mark-as-done: detects if branch is merged and acts accordingly.
    /// Returns the outcome: "shipped" (merged, cleaned up) or "review" (needs merge).
    /// Returns nil on error.
    func smartDoneFeature(_ feature: Feature) async -> String? {
        guard let project = selectedProject else { return nil }

        do {
            let response = try await apiClient.smartDoneFeature(
                project: project.name,
                featureId: feature.id
            )

            // Update local state based on outcome
            if let index = features.firstIndex(where: { $0.id == feature.id }) {
                if response.outcome == "shipped" {
                    features[index].status = .completed
                    features[index].completedAt = Date()
                    features[index].worktreePath = nil
                    features[index].branch = nil
                } else {
                    features[index].status = .review
                }
            }

            return response.outcome
        } catch {
            self.errorMessage = "Failed to mark done: \(error.localizedDescription)"
            return nil
        }
    }
    #endif

    func deleteFeature(_ feature: Feature) async {
        guard let project = selectedProject else { return }

        do {
            #if os(iOS)
            try await apiClient.deleteFeature(project: project.name, featureId: feature.id)
            self.features.removeAll { $0.id == feature.id }
            #else
            if useAPIMode {
                try await apiClient.deleteFeature(project: project.name, featureId: feature.id)
                self.features.removeAll { $0.id == feature.id }
            } else {
                try await cliBridge.deleteFeature(featureId: feature.id, projectPath: project.path)
            }
            #endif
        } catch {
            self.errorMessage = "Failed to delete feature: \(error.localizedDescription)"
        }
    }

    // MARK: - Refine Feature (Inbox → Idea)

    /// Refine an inbox item into an idea ready to build
    func refineFeature(_ feature: Feature) async {
        guard let project = selectedProject else { return }

        do {
            try await apiClient.refineFeature(project: project.name, featureId: feature.id)
            // Update local state
            if let index = features.firstIndex(where: { $0.id == feature.id }) {
                features[index].status = .idea
            }
            self.successMessage = "Refined: \(feature.title)"
        } catch {
            self.errorMessage = "Failed to refine: \(error.localizedDescription)"
        }
    }

    /// Demote a feature from idea back to inbox
    func demoteFeature(_ feature: Feature) async {
        guard let project = selectedProject else { return }

        do {
            try await apiClient.updateFeature(
                project: project.name,
                featureId: feature.id,
                status: "inbox"
            )
            // Update local state
            if let index = features.firstIndex(where: { $0.id == feature.id }) {
                features[index].status = .inbox
            }
            self.successMessage = "Back to inbox: \(feature.title)"
        } catch {
            self.errorMessage = "Failed to demote: \(error.localizedDescription)"
        }
    }

    /// Update a feature with refined spec details
    /// This is used when refining an existing inbox item through brainstorm chat
    func updateFeatureWithSpec(
        featureId: String,
        title: String,
        description: String,
        howItWorks: [String],
        complexity: String
    ) async {
        guard let project = selectedProject else { return }

        do {
            try await apiClient.updateFeatureWithSpec(
                project: project.name,
                featureId: featureId,
                title: title,
                description: description,
                howItWorks: howItWorks,
                complexity: complexity
            )

            // Update local state
            if let index = features.firstIndex(where: { $0.id == featureId }) {
                features[index].title = title
                features[index].description = description
            }

            self.successMessage = "Refined: \(title)"
            await loadFeatures()  // Reload to get full updated state
        } catch {
            self.errorMessage = "Failed to update feature: \(error.localizedDescription)"
        }
    }

    // MARK: - Ship Feature (Merge)

    /// Ship a feature - merges it and triggers celebration
    /// Returns true if successful (for celebration trigger)
    func shipFeature(_ feature: Feature) async -> Bool {
        guard let project = selectedProject else { return false }

        // Check if Mac is online (required for git merge)
        guard requiresMac(for: "Shipping a feature") else {
            return false
        }

        do {
            // First check if merge is safe
            let check = try await apiClient.getMergeCheck(project: project.name, featureId: feature.id)

            if !check.canMerge {
                // Friendly error message for vibecoders
                if let conflicts = check.conflicts, !conflicts.isEmpty {
                    self.errorMessage = "This feature changed files that were also changed elsewhere. Let me help merge them."
                } else {
                    self.errorMessage = check.message ?? "Can't ship this feature right now. Try refreshing."
                }
                return false
            }

            // Perform the merge
            let result = try await apiClient.mergeFeature(project: project.name, featureId: feature.id)

            if result.success {
                // Update local state
                if let index = features.firstIndex(where: { $0.id == feature.id }) {
                    features[index].status = .completed
                    features[index].completedAt = Date()
                }

                // Reload stats to update streak
                await loadShippingStats()

                return true
            } else {
                self.errorMessage = result.message ?? "Something went wrong. Try again?"
                return false
            }
        } catch {
            // Friendly error message
            self.errorMessage = "Can't reach the server. Check your connection."
            return false
        }
    }

    // MARK: - Brainstorm

    /// Parse brainstorm output from Claude and show review UI
    func parseBrainstorm(claudeOutput: String) async throws {
        guard let project = selectedProject else {
            throw APIError.requestFailed("No project selected")
        }

        let proposals = try await apiClient.parseBrainstorm(
            project: project.name,
            claudeOutput: claudeOutput
        )

        self.parsedProposals = proposals
        self.showingProposalReview = true
    }

    /// Approve selected proposals and add to registry
    func approveProposals(_ proposals: [Proposal]) async throws {
        guard let project = selectedProject else {
            throw APIError.requestFailed("No project selected")
        }

        let approvedProposals = proposals.filter { $0.status == .approved }
        guard !approvedProposals.isEmpty else { return }

        _ = try await apiClient.approveProposals(
            project: project.name,
            proposals: approvedProposals
        )

        // Reload features to show newly added
        await loadFeatures()
    }

    // MARK: - Helpers

    func features(for status: FeatureStatus) -> [Feature] {
        features.filter { $0.status == status }
    }

    func clearError() {
        errorMessage = nil
    }

    func clearSuccess() {
        successMessage = nil
    }

    /// Show a success toast (auto-dismisses)
    func showSuccess(_ message: String) {
        successMessage = message
    }

    // MARK: - Shipping Machine Constraints

    /// Maximum ideas allowed (effectively unlimited - ideas are cheap!)
    /// The discipline comes at START, not CAPTURE
    static let maxIdeas = 99

    /// Number of ready-to-build ideas
    var ideaCount: Int {
        features.filter { $0.status == .idea }.count
    }

    /// Remaining slots for ideas
    var ideaSlotsRemaining: Int {
        max(0, Self.maxIdeas - ideaCount)
    }

    /// Whether user can add a new idea
    var canAddIdea: Bool {
        ideaCount < Self.maxIdeas
    }

    // MARK: - Shipping Stats

    func loadShippingStats() async {
        guard let project = selectedProject else { return }

        do {
            let oldStreak = shippingStats.currentStreak
            let stats = try await apiClient.getShippingStats(project: project.name)
            self.shippingStats = stats

            // Check for milestone (only if streak increased)
            if stats.currentStreak > oldStreak {
                // Milestone celebrations removed - minimal design
            }
        } catch {
            // Silent fail - stats are optional
            print("Failed to load shipping stats: \(error)")
        }
    }

    // MARK: - Health Check (Registry vs Git Drift)

    /// Check project health - compare registry to git state
    func checkProjectHealth() async {
        guard let project = selectedProject else { return }

        do {
            let health = try await apiClient.getProjectHealth(project: project.name)
            self.projectHealth = health
        } catch {
            // Silent fail - health check is optional info
            print("Failed to check project health: \(error)")
            self.projectHealth = nil
        }
    }

    /// Get health issue for a specific feature (if any)
    func healthIssue(for featureId: String) -> HealthIssue? {
        return projectHealth?.issues.first { $0.featureId == featureId }
    }

    /// Reconcile a feature - fix drift between registry and git
    func reconcileFeature(featureId: String, action: String) async {
        guard let project = selectedProject else { return }

        isReconciling = true
        defer { isReconciling = false }

        do {
            try await apiClient.reconcileFeature(
                project: project.name,
                featureId: featureId,
                action: action
            )
            showSuccess("Feature reconciled!")

            // Refresh data
            await loadFeatures()
            await checkProjectHealth()
        } catch {
            errorMessage = "Failed to reconcile: \(error.localizedDescription)"
        }
    }

}

// MARK: - Forge Errors

enum ForgeError: LocalizedError {
    case alreadyInitialized
    case projectNotFound
    case initializationFailed(String)

    var errorDescription: String? {
        switch self {
        case .alreadyInitialized:
            return "This project is already initialized with Forge."
        case .projectNotFound:
            return "Project not found."
        case .initializationFailed(let reason):
            return "Failed to initialize project: \(reason)"
        }
    }
}

// MARK: - Offline Feature Cache

/// Simple feature cache for offline browsing on iOS
class FeatureCache {
    private let defaults = UserDefaults.standard
    private let cachePrefix = "forge.features."

    /// Save features to cache for a project
    func save(_ features: [Feature], for projectName: String) {
        let key = cachePrefix + projectName
        do {
            let data = try JSONEncoder().encode(features)
            defaults.set(data, forKey: key)
        } catch {
            print("Failed to cache features: \(error)")
        }
    }

    /// Load cached features for a project
    func load(for projectName: String) -> [Feature]? {
        let key = cachePrefix + projectName
        guard let data = defaults.data(forKey: key) else { return nil }

        do {
            return try JSONDecoder().decode([Feature].self, from: data)
        } catch {
            print("Failed to load cached features: \(error)")
            return nil
        }
    }

    /// Clear cache for a project
    func clear(for projectName: String) {
        let key = cachePrefix + projectName
        defaults.removeObject(forKey: key)
    }

    /// Clear all cached features
    func clearAll() {
        let keys = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix(cachePrefix) }
        keys.forEach { defaults.removeObject(forKey: $0) }
    }
}
