import SwiftUI

/// Platform-specific configuration
enum PlatformConfig {
    #if os(macOS)
    static let isMac = true
    static let isIOS = false
    #else
    static let isMac = false
    static let isIOS = true
    #endif

    /// Tailscale hostname for the server (auto-configured for private use)
    static let tailscaleHostname = "airfit-server.tail22bf1e.ts.net"
    static let serverPort = 8081

    /// Default server URL string (fallback)
    static var defaultServerURL: String {
        #if os(macOS)
        return "http://localhost:\(serverPort)"
        #else
        // Default to Tailscale for iOS (works on any network)
        return "http://\(tailscaleHostname):\(serverPort)"
        #endif
    }

    /// Current server URL (may be overridden by user)
    static var currentServerURL: String {
        UserDefaults.standard.string(forKey: "serverURL") ?? defaultServerURL
    }

    /// Server URL (configurable)
    static var serverURL: URL {
        return URL(string: currentServerURL)!
    }

    /// Save custom server URL
    static func setServerURL(_ urlString: String) {
        UserDefaults.standard.set(urlString, forKey: "serverURL")
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
