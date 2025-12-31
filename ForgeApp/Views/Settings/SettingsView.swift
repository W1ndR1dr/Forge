import SwiftUI

// MARK: - Settings View
// macOS standard preferences window
// Vibecoder-friendly: Simple, clear options

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            ConnectionSettingsTab()
                .tabItem {
                    Label("Connection", systemImage: "network")
                }
        }
        .frame(width: 500, height: 300)
    }
}

// MARK: - General Settings Tab

struct GeneralSettingsTab: View {
    @AppStorage("showParallelBadges") private var showParallelBadges = true
    @AppStorage("playSounds") private var playSounds = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.large) {
                // Display section
                VStack(alignment: .leading, spacing: Spacing.medium) {
                    Text("DISPLAY")
                        .sectionHeaderStyle()

                    VStack(spacing: Spacing.small) {
                        SettingsToggleRow(
                            title: "Show \"parallel ok\" badges",
                            subtitle: "Show badges on features safe to work on in parallel",
                            isOn: $showParallelBadges
                        )

                        SettingsToggleRow(
                            title: "Play sounds on ship",
                            subtitle: "Play a celebration sound when you ship a feature",
                            isOn: $playSounds
                        )
                    }
                }
                .linearSection()

                // About section
                VStack(alignment: .leading, spacing: Spacing.medium) {
                    Text("ABOUT")
                        .sectionHeaderStyle()

                    Text("Forge helps you ship features faster by managing the complexity of parallel development. Just focus on what you want to build!")
                        .font(Typography.caption)
                        .foregroundColor(Linear.textSecondary)
                }
                .linearSection()
            }
            .padding(Spacing.large)
        }
        .background(Linear.base)
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - Settings Toggle Row

struct SettingsToggleRow: View {
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: Spacing.micro) {
                Text(title)
                    .font(Typography.body)
                    .foregroundColor(Linear.textPrimary)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(Typography.caption)
                        .foregroundColor(Linear.textTertiary)
                }
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(Accent.primary)
        }
        .padding(Spacing.medium)
        .background(Linear.card)
        .cornerRadius(CornerRadius.medium)
    }
}

// MARK: - Connection Settings Tab

struct ConnectionSettingsTab: View {
    @Environment(AppState.self) private var appState
    @State private var serverURL: String = PlatformConfig.defaultServerURL
    @State private var isTestingConnection = false
    @State private var connectionResult: ConnectionTestResult?

    /// Normalized URL preview (what will actually be used)
    private var normalizedURL: String {
        PlatformConfig.normalizeServerURL(serverURL)
    }

    /// Show preview if input differs from normalized
    private var showNormalizedPreview: Bool {
        !serverURL.isEmpty && serverURL != normalizedURL
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.large) {
                // Server section
                VStack(alignment: .leading, spacing: Spacing.medium) {
                    Text("FLOWFORGE SERVER")
                        .sectionHeaderStyle()

                    VStack(alignment: .leading, spacing: Spacing.small) {
                        HStack(spacing: Spacing.medium) {
                            TextField("hostname or IP", text: $serverURL)
                                .textFieldStyle(.linear)
                                .foregroundColor(Linear.textPrimary)

                            Button("Test") {
                                testConnection()
                            }
                            .buttonStyle(.linearSecondary)
                            .disabled(isTestingConnection)
                        }

                        // Show normalized URL preview if different from input
                        if showNormalizedPreview {
                            HStack(spacing: Spacing.small) {
                                Image(systemName: "arrow.right.circle")
                                    .foregroundColor(Linear.textTertiary)
                                Text(normalizedURL)
                                    .font(Typography.caption)
                                    .foregroundColor(Linear.textTertiary)
                            }
                        }

                        // Connection status
                        HStack(spacing: Spacing.small) {
                            Circle()
                                .fill(statusColor)
                                .frame(width: 8, height: 8)

                            Text(statusMessage)
                                .font(Typography.caption)
                                .foregroundColor(Linear.textSecondary)
                        }

                        // Test result
                        if let result = connectionResult {
                            HStack(spacing: Spacing.small) {
                                Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundColor(result.success ? Accent.success : Accent.danger)

                                Text(result.message)
                                    .font(Typography.caption)
                                    .foregroundColor(result.success ? Accent.success : Accent.danger)
                            }
                            .padding(.vertical, Spacing.small)
                        }

                        Text("Just enter hostname (e.g., \"raspberrypi\") — http:// and port added automatically")
                            .font(.system(size: 10))
                            .foregroundColor(Linear.textMuted)
                    }
                }
                .linearSection()

                // Apply button
                Button("Apply Changes") {
                    applyChanges()
                }
                .buttonStyle(.linearPrimary)
                .disabled(normalizedURL == PlatformConfig.currentServerURL)

                // Info section
                VStack(alignment: .leading, spacing: Spacing.medium) {
                    Text("INFO")
                        .sectionHeaderStyle()

                    VStack(alignment: .leading, spacing: Spacing.small) {
                        Text("The Forge server handles:")
                            .font(Typography.caption)
                            .fontWeight(.medium)
                            .foregroundColor(Linear.textSecondary)

                        VStack(alignment: .leading, spacing: 2) {
                            bulletPoint("Git worktree management")
                            bulletPoint("Feature analysis & intelligence")
                            bulletPoint("Merge operations")
                            bulletPoint("Real-time sync via WebSocket")
                        }
                        .foregroundColor(Linear.textTertiary)
                    }
                }
                .linearSection()
            }
            .padding(Spacing.large)
        }
        .background(Linear.base)
        .environment(\.colorScheme, .dark)
        .onAppear {
            serverURL = PlatformConfig.currentServerURL
        }
    }

    private var statusColor: Color {
        if isTestingConnection {
            return Accent.warning
        }
        return appState.isConnectedToServer ? Accent.success : Accent.danger
    }

    private var statusMessage: String {
        if isTestingConnection {
            return "Testing connection..."
        }
        return appState.isConnectedToServer ? "Connected" : "Not connected"
    }

    private func bulletPoint(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Text("•")
            Text(text)
        }
        .font(Typography.caption)
    }

    private func testConnection() {
        isTestingConnection = true
        connectionResult = nil

        Task {
            // Test using the normalized URL
            let result = await appState.testConnection(url: normalizedURL)
            await MainActor.run {
                connectionResult = ConnectionTestResult(
                    success: result.success,
                    message: result.message
                )
                isTestingConnection = false
            }
        }
    }

    private func applyChanges() {
        // Apply the normalized URL
        let normalized = normalizedURL
        appState.updateServerURL(normalized)
        PlatformConfig.setServerURL(normalized)
        // Update display to show normalized
        serverURL = normalized
    }
}

struct ConnectionTestResult {
    let success: Bool
    let message: String
}


// MARK: - Preview

#if DEBUG
#Preview {
    SettingsView()
        .environment(AppState())
}
#endif
