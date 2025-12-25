import Foundation
import Observation

@MainActor
@Observable
class AppState {
    var projects: [Project] = []
    var selectedProject: Project?
    var features: [Feature] = []
    var isLoading = false
    var errorMessage: String?
    var successMessage: String?  // For toast notifications
    var isConnectedToServer = false
    var connectionError: String?

    // Brainstorm state
    var parsedProposals: [Proposal] = []
    var showingProposalReview = false

    // Feature analysis state (Wave 2)
    var pendingAnalysis: FeatureAnalysis?
    var pendingFeatureTitle: String = ""
    var isAnalyzingFeature = false

    // Shipping stats (Wave 4.4)
    var shippingStats: ShippingStats = ShippingStats()
    var showingMilestone: Int? = nil  // Track which milestone to show (7, 14, 30, etc.)

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
        setupWebSocket()
        Task {
            await loadProjects()
        }
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
    func testConnection() async -> (success: Bool, message: String) {
        do {
            let projects = try await apiClient.getProjects()
            isConnectedToServer = true
            connectionError = nil
            return (true, "Connected! Found \(projects.count) project(s)")
        } catch {
            isConnectedToServer = false
            connectionError = error.localizedDescription
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

    func loadProjects() async {
        isLoading = true
        errorMessage = nil

        // For now, we'll scan for FlowForge projects in common locations
        // In the future, this could be enhanced to remember projects
        let projects = await discoverProjects()
        await MainActor.run {
            self.projects = projects
            if let first = projects.first {
                self.selectedProject = first
                Task {
                    await self.loadFeatures()
                }
            }
            self.isLoading = false
        }
    }

    func selectProject(_ project: Project) async {
        selectedProject = project

        // Connect WebSocket for real-time updates
        if useAPIMode {
            await MainActor.run {
                webSocketClient?.connect(project: project.name)
            }
        }

        await loadFeatures()
    }

    /// Enable API mode (for connecting to remote server)
    func enableAPIMode() {
        #if os(macOS)
        useAPIMode = true
        if let project = selectedProject {
            Task { @MainActor in
                webSocketClient?.connect(project: project.name)
            }
        }
        #endif
    }

    /// Disable API mode (for local CLI usage)
    func disableAPIMode() {
        #if os(macOS)
        useAPIMode = false
        webSocketClient?.disconnect()
        #endif
    }

    private func discoverProjects() async -> [Project] {
        #if os(macOS)
        // macOS: Scan local filesystem for FlowForge projects
        return await Task.detached {
            // Check common project locations
            let homeDir = FileManager.default.homeDirectoryForCurrentUser
            let projectsPaths = [
                homeDir.appendingPathComponent("Projects/Active"),
                homeDir.appendingPathComponent("Projects"),
                homeDir.appendingPathComponent("Developer"),
            ]

            var discoveredProjects: [Project] = []
            var seenPaths: Set<String> = []  // Deduplicate by path

            for basePath in projectsPaths {
                guard let enumerator = FileManager.default.enumerator(
                    at: basePath,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                ) else { continue }

                for case let url as URL in enumerator {
                    // Check if this directory has a .flowforge folder
                    let flowforgeDir = url.appendingPathComponent(".flowforge")
                    var isDirectory: ObjCBool = false

                    if FileManager.default.fileExists(atPath: flowforgeDir.path, isDirectory: &isDirectory),
                       isDirectory.boolValue {
                        // Deduplicate - only add if we haven't seen this path
                        let resolvedPath = url.standardizedFileURL.path
                        if !seenPaths.contains(resolvedPath) {
                            seenPaths.insert(resolvedPath)
                            let project = Project(
                                name: url.lastPathComponent,
                                path: resolvedPath,
                                isActive: true
                            )
                            discoveredProjects.append(project)
                        }

                        // Don't recurse into project directories
                        enumerator.skipDescendants()
                    }
                }
            }

            return discoveredProjects
        }.value
        #else
        // iOS: Fetch projects from API
        do {
            return try await apiClient.getProjects()
        } catch {
            print("Failed to fetch projects: \(error)")
            return []
        }
        #endif
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

        do {
            let features: [Feature]

            #if os(iOS)
            // iOS always uses API mode
            features = try await apiClient.getFeatures(project: project.name)
            self.isConnectedToServer = true
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

            // Load shipping stats in background
            Task {
                await loadShippingStats()
            }

        } catch {
            self.errorMessage = "Failed to load features: \(error.localizedDescription)"
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

    // MARK: - Feature Analysis (Wave 2)

    /// Analyze a feature before adding (shows complexity, scope warnings, expert suggestions)
    func analyzeFeature(title: String, description: String? = nil) async {
        guard let project = selectedProject else { return }

        isAnalyzingFeature = true
        pendingFeatureTitle = title
        pendingAnalysis = nil

        do {
            let analysis = try await apiClient.analyzeFeature(
                project: project.name,
                title: title,
                description: description
            )
            self.pendingAnalysis = analysis
        } catch {
            // If analysis fails, we can still add the feature
            // Just log and continue - don't block the user
            print("Feature analysis unavailable: \(error)")
            // Create a minimal fallback analysis
            self.pendingAnalysis = FeatureAnalysis(
                complexity: "medium",
                estimatedHours: nil,
                confidence: nil,
                foundationScore: nil,
                expertDomain: nil,
                scopeCreepWarnings: nil,
                suggestedBreakdown: nil,
                filesAffected: nil,
                shippableToday: nil
            )
        }

        isAnalyzingFeature = false
    }

    /// Clear pending analysis (user cancelled)
    func clearPendingAnalysis() {
        pendingAnalysis = nil
        pendingFeatureTitle = ""
        isAnalyzingFeature = false
    }

    /// Confirm and add the pending analyzed feature
    func confirmAnalyzedFeature() async {
        guard !pendingFeatureTitle.isEmpty else { return }

        let title = pendingFeatureTitle

        await addFeature(title: title)
        await loadFeatures()

        // Clear the pending state
        pendingAnalysis = nil
        pendingFeatureTitle = ""

        // Show success toast
        showSuccess("Feature added to queue!")
    }

    func startFeature(_ feature: Feature) async {
        guard let project = selectedProject else { return }

        do {
            #if os(iOS)
            try await apiClient.startFeature(project: project.name, featureId: feature.id)
            #else
            if useAPIMode {
                try await apiClient.startFeature(project: project.name, featureId: feature.id)
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

    // MARK: - Ship Feature (Merge)

    /// Ship a feature - merges it and triggers celebration
    /// Returns true if successful (for celebration trigger)
    func shipFeature(_ feature: Feature) async -> Bool {
        guard let project = selectedProject else { return false }

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

    /// Maximum planned features allowed (Wave 4 constraint)
    static let maxPlannedFeatures = 3

    /// Number of currently planned features
    var plannedCount: Int {
        features.filter { $0.status == .planned }.count
    }

    /// Remaining slots for planned features
    var plannedSlotsRemaining: Int {
        max(0, Self.maxPlannedFeatures - plannedCount)
    }

    /// Whether user can add a new planned feature
    var canAddPlannedFeature: Bool {
        plannedCount < Self.maxPlannedFeatures
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
                checkForMilestone(newStreak: stats.currentStreak)
            }
        } catch {
            // Silent fail - stats are optional
            print("Failed to load shipping stats: \(error)")
        }
    }

    /// Check if we hit a milestone and show celebration
    private func checkForMilestone(newStreak: Int) {
        let milestones = [7, 14, 30, 50, 100]
        if milestones.contains(newStreak) {
            showingMilestone = newStreak
        }
    }

    /// Dismiss the milestone banner
    func dismissMilestone() {
        showingMilestone = nil
    }
}
