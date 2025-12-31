import Foundation
import Combine

/// WebSocket client for real-time feature updates from Forge server
@MainActor
final class WebSocketClient: ObservableObject {
    @Published private(set) var isConnected = false
    @Published private(set) var lastError: Error?

    private var webSocketTask: URLSessionWebSocketTask?
    private var pingTimer: Timer?
    private var reconnectTimer: Timer?
    private var currentProject: String?
    private let session: URLSession

    /// Callback for feature updates
    var onFeatureUpdate: ((FeatureUpdate) -> Void)?

    /// Callback for full sync requests
    var onSyncRequest: (() -> Void)?

    struct FeatureUpdate {
        let project: String
        let featureId: String
        let action: String  // created, updated, deleted, started, stopped
    }

    init() {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config)
    }

    /// Connect to WebSocket for a specific project
    func connect(project: String) {
        // Disconnect from any existing connection
        if currentProject != nil {
            disconnect()
        }

        currentProject = project
        establishConnection()
    }

    /// Disconnect from WebSocket
    func disconnect() {
        pingTimer?.invalidate()
        pingTimer = nil
        reconnectTimer?.invalidate()
        reconnectTimer = nil

        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        currentProject = nil
        isConnected = false
    }

    private func establishConnection() {
        guard let project = currentProject else { return }

        let baseURL = PlatformConfig.defaultServerURL
        let wsURL = baseURL
            .replacingOccurrences(of: "http://", with: "ws://")
            .replacingOccurrences(of: "https://", with: "wss://")

        guard let url = URL(string: "\(wsURL)/ws/\(project)") else {
            lastError = URLError(.badURL)
            return
        }

        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()

        // Start receiving messages
        receiveMessage()

        // Start ping timer to keep connection alive
        startPingTimer()

        isConnected = true
        lastError = nil

        print("WebSocket connecting to: \(url)")
    }

    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success(let message):
                    self?.handleMessage(message)
                    // Continue receiving
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
            // Ping response, connection is alive
            break

        case "feature_update":
            if let project = json["project"] as? String,
               let featureId = json["feature_id"] as? String,
               let action = json["action"] as? String {
                let update = FeatureUpdate(project: project, featureId: featureId, action: action)
                onFeatureUpdate?(update)
            }

        case "sync":
            // Server requesting full sync
            onSyncRequest?()

        default:
            print("Unknown WebSocket message type: \(type)")
        }
    }

    private func handleError(_ error: Error) {
        isConnected = false
        lastError = error

        // Check if this is a normal closure
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cancelled, .userCancelledAuthentication:
                // Normal disconnection, don't reconnect
                return
            default:
                break
            }
        }

        print("WebSocket error: \(error.localizedDescription)")

        // Schedule reconnection
        scheduleReconnect()
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
        webSocketTask?.send(.string(pingMessage)) { [weak self] error in
            if let error = error {
                Task { @MainActor in
                    self?.handleError(error)
                }
            }
        }
    }

    private func scheduleReconnect() {
        reconnectTimer?.invalidate()

        // Exponential backoff: try again in 2 seconds, then 4, 8, etc.
        let delay: TimeInterval = 2.0

        reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard self?.currentProject != nil else { return }
                print("WebSocket reconnecting...")
                self?.establishConnection()
            }
        }
    }
}
