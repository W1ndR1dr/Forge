import SwiftUI

/// Platform-specific configuration
///
/// Architecture: Both iOS and macOS connect to Pi for brainstorming and sync.
/// Mac additionally has native execution capabilities (Claude Code, Xcode builds).
enum PlatformConfig {
    #if os(macOS)
    static let isMac = true
    static let isIOS = false
    /// Mac can run Claude Code locally for implementation
    static let canExecuteNatively = true
    #else
    static let isMac = false
    static let isIOS = true
    /// iOS can only brainstorm and track - execution happens on Mac
    static let canExecuteNatively = false
    #endif

    /// Tailscale hostname for the server (Raspberry Pi - single source of truth)
    static let tailscaleHostname = "raspberrypi"
    static let serverPort = 8081

    /// Default server URL - BOTH platforms connect to Pi for unified sync
    /// The Pi is the single source of truth for brainstorming and feature state.
    /// Mac's native execution capability is separate from the sync layer.
    static var defaultServerURL: String {
        // Both platforms connect to Pi via Tailscale
        return "http://\(tailscaleHostname):\(serverPort)"
    }

    /// Current server URL (may be overridden by user, always normalized)
    static var currentServerURL: String {
        let stored = UserDefaults.standard.string(forKey: "serverURL") ?? defaultServerURL
        return normalizeServerURL(stored)
    }

    /// Server URL (configurable)
    static var serverURL: URL {
        return URL(string: currentServerURL)!
    }

    /// Save custom server URL (auto-normalizes)
    static func setServerURL(_ urlString: String) {
        let normalized = normalizeServerURL(urlString)
        UserDefaults.standard.set(normalized, forKey: "serverURL")
    }

    /// Normalize a server URL to ensure it's valid
    /// Handles: "raspberrypi" → "http://raspberrypi:8081"
    ///          "192.168.1.1" → "http://192.168.1.1:8081"
    ///          "http://host" → "http://host:8081"
    ///          "http://host:9000" → "http://host:9000" (keeps custom port)
    static func normalizeServerURL(_ input: String) -> String {
        var url = input.trimmingCharacters(in: .whitespacesAndNewlines)

        // Empty → default
        guard !url.isEmpty else { return defaultServerURL }

        // Add http:// if no scheme
        if !url.hasPrefix("http://") && !url.hasPrefix("https://") {
            url = "http://" + url
        }

        // Parse to check for port
        if let components = URLComponents(string: url) {
            // Add default port if missing
            if components.port == nil {
                var mutable = components
                mutable.port = serverPort
                return mutable.string ?? url
            }
        }

        return url
    }

    /// Validate a URL string (after normalization)
    static func isValidServerURL(_ input: String) -> Bool {
        let normalized = normalizeServerURL(input)
        guard let url = URL(string: normalized) else { return false }
        return url.scheme != nil && url.host != nil
    }
}

/// Platform-specific color for text background
extension Color {
    static var textBackground: Color {
        #if os(macOS)
        return Color(NSColor.textBackgroundColor)
        #else
        return Color(UIColor.secondarySystemBackground)
        #endif
    }

    static var controlBackground: Color {
        #if os(macOS)
        return Color(NSColor.controlBackgroundColor)
        #else
        return Color(UIColor.systemBackground)
        #endif
    }

    static var windowBackground: Color {
        #if os(macOS)
        return Color(NSColor.windowBackgroundColor)
        #else
        return Color(UIColor.systemBackground)
        #endif
    }
}
