import Foundation
import Combine

/// WebSocket client for real-time brainstorming with Claude.
///
/// Connects to /ws/{project}/brainstorm and enables streaming chat.
/// This is the bridge between the app and the Claude CLI running on the Pi.
@MainActor
final class BrainstormClient: ObservableObject {
    // MARK: - Published State

    @Published private(set) var isConnected = false
    @Published private(set) var isTyping = false
    @Published private(set) var messages: [BrainstormMessage] = []
    @Published private(set) var currentSpec: RefinedSpec?
    @Published private(set) var lastError: Error?
    @Published private(set) var streamingText: String = ""  // Current streaming response (debounced)

    // MARK: - Types

    struct BrainstormMessage: Identifiable, Equatable {
        let id = UUID()
        let role: MessageRole
        var content: String
        let timestamp: Date

        enum MessageRole: String {
            case user
            case assistant
        }
    }

    struct RefinedSpec: Codable {
        let title: String
        let whatItDoes: String
        let howItWorks: [String]
        let filesAffected: [String]
        let estimatedScope: String
        let rawSpec: String

        enum CodingKeys: String, CodingKey {
            case title
            case whatItDoes = "what_it_does"
            case howItWorks = "how_it_works"
            case filesAffected = "files_affected"
            case estimatedScope = "estimated_scope"
            case rawSpec = "raw_spec"
        }
    }

    // MARK: - Private Properties

    private var webSocketTask: URLSessionWebSocketTask?
    private var pingTimer: Timer?
    private var currentProject: String?
    private var currentFeatureId: String?
    private var currentFeatureTitle: String?
    private let session: URLSession
    private var currentAssistantMessage: BrainstormMessage?
    private var streamingBuffer: String = ""  // Accumulates chunks before publishing
    private var lastStreamUpdate: Date = .distantPast

    // MARK: - Callbacks

    var onSpecReady: ((RefinedSpec) -> Void)?

    // MARK: - Lifecycle

    init() {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config)
    }

    // MARK: - Connection

    /// Connect to brainstorm WebSocket for a project
    /// - Parameters:
    ///   - project: Project name
    ///   - featureId: Optional feature ID for refining mode
    ///   - featureTitle: Optional feature title for refining mode
    func connect(project: String, featureId: String? = nil, featureTitle: String? = nil) {
        if currentProject != nil {
            disconnect()
        }

        currentProject = project
        currentFeatureId = featureId
        currentFeatureTitle = featureTitle
        establishConnection()
    }

    /// Disconnect from WebSocket
    func disconnect() {
        pingTimer?.invalidate()
        pingTimer = nil

        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        currentProject = nil
        isConnected = false
    }

    /// Reset the brainstorm session (start fresh)
    func reset() {
        messages = []
        currentSpec = nil
        currentAssistantMessage = nil

        let message = #"{"type": "reset"}"#
        webSocketTask?.send(.string(message)) { _ in }
    }

    // MARK: - Messaging

    /// Send a message to Claude
    func sendMessage(_ content: String) {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        // Reset streaming state
        streamingBuffer = ""
        streamingText = ""
        lastStreamUpdate = .distantPast

        // Add user message
        let userMessage = BrainstormMessage(
            role: .user,
            content: content,
            timestamp: Date()
        )
        messages.append(userMessage)

        // Prepare assistant message placeholder
        currentAssistantMessage = BrainstormMessage(
            role: .assistant,
            content: "",
            timestamp: Date()
        )
        messages.append(currentAssistantMessage!)

        isTyping = true

        // Send to server
        let payload: [String: Any] = [
            "type": "message",
            "content": content
        ]

        if let data = try? JSONSerialization.data(withJSONObject: payload),
           let jsonString = String(data: data, encoding: .utf8) {
            webSocketTask?.send(.string(jsonString)) { [weak self] error in
                if let error = error {
                    Task { @MainActor in
                        self?.lastError = error
                    }
                }
            }
        }
    }

    // MARK: - Private Methods

    private func establishConnection() {
        guard let project = currentProject else { return }

        let baseURL = PlatformConfig.defaultServerURL
        let wsURL = baseURL
            .replacingOccurrences(of: "http://", with: "ws://")
            .replacingOccurrences(of: "https://", with: "wss://")

        guard let url = URL(string: "\(wsURL)/ws/\(project)/brainstorm") else {
            lastError = URLError(.badURL)
            return
        }

        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()

        receiveMessage()
        startPingTimer()

        isConnected = true
        lastError = nil

        print("Brainstorm WebSocket connecting to: \(url)")

        // Send init message with feature context for refining mode
        sendInitMessage()
    }

    /// Send init message with feature context (for refining mode)
    private func sendInitMessage() {
        var payload: [String: Any] = ["type": "init"]

        if let featureId = currentFeatureId {
            payload["feature_id"] = featureId
        }
        if let featureTitle = currentFeatureTitle {
            payload["feature_title"] = featureTitle
        }

        if let data = try? JSONSerialization.data(withJSONObject: payload),
           let jsonString = String(data: data, encoding: .utf8) {
            webSocketTask?.send(.string(jsonString)) { _ in }
        }
    }

    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success(let message):
                    self?.handleMessage(message)
                    self?.receiveMessage()

                case .failure(let error):
                    self?.handleError(error)
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            parseMessage(text)

        case .data(let data):
            if let text = String(data: data, encoding: .utf8) {
                parseMessage(text)
            }

        @unknown default:
            break
        }
    }

    private func parseMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return
        }

        switch type {
        case "pong":
            break

        case "session_state":
            // Restore session state if reconnecting
            if let state = json["state"] as? [String: Any],
               let messageList = state["messages"] as? [[String: String]] {
                messages = messageList.compactMap { msg in
                    guard let role = msg["role"],
                          let content = msg["content"],
                          let messageRole = BrainstormMessage.MessageRole(rawValue: role) else {
                        return nil
                    }
                    return BrainstormMessage(role: messageRole, content: content, timestamp: Date())
                }
            }

        case "chunk":
            // Streaming chunk - accumulate in buffer, throttle UI updates
            if let content = json["content"] as? String {
                streamingBuffer += content

                // Only update UI every 50ms to prevent performance issues
                let now = Date()
                if now.timeIntervalSince(lastStreamUpdate) > 0.05 {
                    streamingText = streamingBuffer
                    lastStreamUpdate = now
                }
            }

        case "message_complete":
            // Full message received - finalize with complete content
            let finalContent = json["content"] as? String ?? streamingBuffer
            if !finalContent.isEmpty {
                finalizeStreamingMessage(finalContent)
            }
            streamingBuffer = ""
            streamingText = ""
            isTyping = false
            currentAssistantMessage = nil

        case "spec_ready":
            // Spec is ready!
            if let specData = json["spec"] as? [String: Any],
               let jsonData = try? JSONSerialization.data(withJSONObject: specData),
               let spec = try? JSONDecoder().decode(RefinedSpec.self, from: jsonData) {
                currentSpec = spec
                onSpecReady?(spec)
            }

        case "session_reset":
            messages = []
            currentSpec = nil
            currentAssistantMessage = nil

        case "status":
            // Processing status from server - show typing indicator immediately
            if let status = json["status"] as? String, status == "processing" {
                isTyping = true
            }

        case "error":
            if let errorMessage = json["message"] as? String {
                lastError = NSError(domain: "BrainstormClient", code: -1, userInfo: [NSLocalizedDescriptionKey: errorMessage])
            }
            isTyping = false

        default:
            print("Unknown brainstorm message type: \(type)")
        }
    }

    private func finalizeStreamingMessage(_ content: String) {
        guard var message = currentAssistantMessage else { return }
        message.content = content

        // Update the message in the array (single update, not per-chunk)
        if let index = messages.lastIndex(where: { $0.id == message.id }) {
            messages[index] = message
        }
    }

    private func handleError(_ error: Error) {
        isConnected = false
        lastError = error
        isTyping = false

        print("Brainstorm WebSocket error: \(error.localizedDescription)")

        // Try to reconnect after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard self?.currentProject != nil else { return }
            self?.establishConnection()
        }
    }

    private func startPingTimer() {
        pingTimer?.invalidate()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.sendPing()
            }
        }
    }

    private func sendPing() {
        let pingMessage = #"{"type": "ping"}"#
        webSocketTask?.send(.string(pingMessage)) { _ in }
    }
}
