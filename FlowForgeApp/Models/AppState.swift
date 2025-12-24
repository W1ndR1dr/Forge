import Foundation
import Observation

@Observable
class AppState {
    var projects: [Project] = []
    var selectedProject: Project?
    var features: [Feature] = []
    var isLoading = false
    var errorMessage: String?

    private let cliBridge = CLIBridge()
    private var fileWatcher: FileWatcher?

    init() {
        Task {
            await loadProjects()
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
        await loadFeatures()
    }

    private func discoverProjects() async -> [Project] {
        // Run synchronous file operations on background queue
        return await Task.detached {
            // Check common project locations
            let homeDir = FileManager.default.homeDirectoryForCurrentUser
            let projectsPaths = [
                homeDir.appendingPathComponent("Projects/Active"),
                homeDir.appendingPathComponent("Projects"),
                homeDir.appendingPathComponent("Developer"),
            ]

            var discoveredProjects: [Project] = []

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
                        let project = Project(
                            name: url.lastPathComponent,
                            path: url.path,
                            isActive: true
                        )
                        discoveredProjects.append(project)

                        // Don't recurse into project directories
                        enumerator.skipDescendants()
                    }
                }
            }

            return discoveredProjects
        }.value
    }

    // MARK: - Feature Management

    func loadFeatures() async {
        guard let project = selectedProject else { return }

        isLoading = true
        errorMessage = nil

        // Stop watching previous project
        fileWatcher?.stop()

        do {
            let registryPath = project.registryPath
            let features = try await cliBridge.loadRegistry(at: registryPath)

            await MainActor.run {
                self.features = features
                self.isLoading = false
            }

            // Start watching new project
            fileWatcher = FileWatcher(path: registryPath) { [weak self] in
                Task { [weak self] in
                    await self?.reloadFeatures()
                }
            }
            fileWatcher?.start()

        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to load features: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }

    private func reloadFeatures() async {
        guard let project = selectedProject else { return }

        do {
            let registryPath = project.registryPath
            let features = try await cliBridge.loadRegistry(at: registryPath)

            await MainActor.run {
                self.features = features
            }
        } catch {
            // Silent fail on reload - don't show error to user
            print("Failed to reload features: \(error)")
        }
    }

    func updateFeatureStatus(_ feature: Feature, to newStatus: FeatureStatus) async {
        guard let project = selectedProject else { return }

        do {
            try await cliBridge.updateFeatureStatus(
                featureId: feature.id,
                status: newStatus,
                projectPath: project.path
            )
            // Features will be reloaded by file watcher
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to update feature: \(error.localizedDescription)"
            }
        }
    }

    func addFeature(title: String) async {
        guard let project = selectedProject else { return }

        do {
            try await cliBridge.addFeature(title: title, projectPath: project.path)
            // Features will be reloaded by file watcher
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to add feature: \(error.localizedDescription)"
            }
        }
    }

    func startFeature(_ feature: Feature) async {
        guard let project = selectedProject else { return }

        do {
            try await cliBridge.startFeature(featureId: feature.id, projectPath: project.path)
            // Features will be reloaded by file watcher
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to start feature: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Helpers

    func features(for status: FeatureStatus) -> [Feature] {
        features.filter { $0.status == status }
    }

    func clearError() {
        errorMessage = nil
    }
}
