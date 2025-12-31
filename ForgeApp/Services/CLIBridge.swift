import Foundation

#if os(macOS)
import AppKit
#endif

enum CLIError: Error, LocalizedError {
    case commandFailed(String)
    case invalidOutput(String)
    case registryNotFound(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let message):
            return "CLI command failed: \(message)"
        case .invalidOutput(let message):
            return "Invalid CLI output: \(message)"
        case .registryNotFound(let path):
            return "Registry not found at: \(path)"
        }
    }
}

actor CLIBridge {
    private let commandPath: String

    init(commandPath: String = "/usr/local/bin/forge") {
        self.commandPath = commandPath
    }

    // MARK: - Registry Operations

    func loadRegistry(at path: String) async throws -> [Feature] {
        guard FileManager.default.fileExists(atPath: path) else {
            throw CLIError.registryNotFound(path)
        }

        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let decoder = JSONDecoder()

        let registry = try decoder.decode(FeatureRegistry.self, from: data)
        return Array(registry.features.values).sorted { $0.createdAt > $1.createdAt }
    }

    func loadConfig(at path: String) async throws -> ProjectConfig {
        guard FileManager.default.fileExists(atPath: path) else {
            throw CLIError.registryNotFound(path)
        }

        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let decoder = JSONDecoder()

        return try decoder.decode(ProjectConfig.self, from: data)
    }

    // MARK: - CLI Commands (macOS only - uses Process)

    // MARK: - Local Feature Operations (no CLI needed)

    func addFeature(title: String, projectPath: String) async throws {
        let registryPath = "\(projectPath)/.flowforge/registry.json"
        let data = try Data(contentsOf: URL(fileURLWithPath: registryPath))
        let decoder = JSONDecoder()
        var registry = try decoder.decode(FeatureRegistry.self, from: data)

        // Generate a slug-based ID from the title
        let id = title.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "[^a-z0-9-]", with: "", options: .regularExpression)

        let feature = Feature(
            id: id,
            title: title,
            description: nil,
            status: .idea,
            complexity: nil,
            parentId: nil,
            dependencies: [],
            branch: nil,
            worktreePath: nil,
            promptPath: nil,
            createdAt: Date(),
            startedAt: nil,
            completedAt: nil,
            tags: []
        )

        registry.features[id] = feature

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let updatedData = try encoder.encode(registry)
        try updatedData.write(to: URL(fileURLWithPath: registryPath))
    }

    func startFeature(featureId: String, projectPath: String) async throws {
        // For local mode, just update the status to in-progress
        // The full CLI would also create worktrees, generate prompts, etc.
        try await updateFeatureStatus(
            featureId: featureId,
            status: .inProgress,
            projectPath: projectPath
        )
    }

    func stopFeature(featureId: String, projectPath: String) async throws {
        // For local mode, just update the status to review
        try await updateFeatureStatus(
            featureId: featureId,
            status: .review,
            projectPath: projectPath
        )
    }

    func updateFeatureStatus(featureId: String, status: FeatureStatus, projectPath: String) async throws {
        // Read the registry
        let registryPath = "\(projectPath)/.flowforge/registry.json"
        let data = try Data(contentsOf: URL(fileURLWithPath: registryPath))
        let decoder = JSONDecoder()
        var registry = try decoder.decode(FeatureRegistry.self, from: data)

        // Update the feature status
        guard var feature = registry.features[featureId] else {
            throw CLIError.commandFailed("Feature not found: \(featureId)")
        }

        feature.status = status

        // Update timestamps based on status
        switch status {
        case .inProgress:
            if feature.startedAt == nil {
                feature.startedAt = Date()
            }
        case .completed:
            feature.completedAt = Date()
        default:
            break
        }

        registry.features[featureId] = feature

        // Write back to registry
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let updatedData = try encoder.encode(registry)
        try updatedData.write(to: URL(fileURLWithPath: registryPath))
    }

    func deleteFeature(featureId: String, projectPath: String) async throws {
        // Read the registry
        let registryPath = "\(projectPath)/.flowforge/registry.json"
        let data = try Data(contentsOf: URL(fileURLWithPath: registryPath))
        let decoder = JSONDecoder()
        var registry = try decoder.decode(FeatureRegistry.self, from: data)

        // Remove the feature
        guard registry.features[featureId] != nil else {
            throw CLIError.commandFailed("Feature not found: \(featureId)")
        }

        registry.features.removeValue(forKey: featureId)

        // Write back to registry
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let updatedData = try encoder.encode(registry)
        try updatedData.write(to: URL(fileURLWithPath: registryPath))
    }

    #if os(macOS)
    func listFeatures(projectPath: String) async throws -> String {
        return try await runCommand(
            args: ["list"],
            workingDirectory: projectPath
        )
    }

    func getStatus(projectPath: String) async throws -> String {
        return try await runCommand(
            args: ["status"],
            workingDirectory: projectPath
        )
    }

    // MARK: - Process Execution

    private func runCommand(args: [String], workingDirectory: String) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let pipe = Pipe()
            let errorPipe = Pipe()

            process.executableURL = URL(fileURLWithPath: commandPath)
            process.arguments = args
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
            process.standardOutput = pipe
            process.standardError = errorPipe

            process.terminationHandler = { process in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

                if process.terminationStatus == 0 {
                    continuation.resume(returning: output)
                } else {
                    let combinedOutput = errorOutput.isEmpty ? output : errorOutput
                    continuation.resume(
                        throwing: CLIError.commandFailed(
                            "Exit code \(process.terminationStatus): \(combinedOutput)"
                        )
                    )
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    #endif
}
