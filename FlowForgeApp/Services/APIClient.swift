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
    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL = URL(string: "http://localhost:8081")!) {
        self.baseURL = baseURL
        self.session = URLSession.shared
    }

    // MARK: - Prompt Generation

    /// Get the implementation prompt for a feature
    func getPrompt(project: String, featureId: String) async throws -> String {
        let url = baseURL.appendingPathComponent("api/\(project)/features/\(featureId)/prompt")
        let response: PromptResponse = try await get(url: url)
        return response.prompt
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

    /// Delete a feature
    func deleteFeature(project: String, featureId: String, force: Bool = false) async throws {
        var url = baseURL.appendingPathComponent("api/\(project)/features/\(featureId)")
        if force {
            url = url.appending(queryItems: [URLQueryItem(name: "force", value: "true")])
        }
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
