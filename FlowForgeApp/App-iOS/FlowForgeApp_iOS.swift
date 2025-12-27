import SwiftUI

@main
struct FlowForgeApp_iOS: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            iOSContentView()
                .environment(appState)
        }
    }
}

/// iOS-specific root view with tab navigation
struct iOSContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        TabView {
            // Roadmap Tab
            NavigationStack {
                iOSRoadmapView()
                    .navigationTitle(appState.selectedProject?.name ?? "FlowForge")
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            iOSStreakBadge(streak: appState.shippingStats.currentStreak)
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            ConnectionStatusBadge()
                        }
                    }
            }
            .tabItem {
                Label("Roadmap", systemImage: "list.bullet.rectangle")
            }

            // Brainstorm Tab
            NavigationStack {
                BrainstormInputView()
                    .navigationTitle("Brainstorm")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            ConnectionStatusBadge()
                        }
                    }
            }
            .tabItem {
                Label("Brainstorm", systemImage: "lightbulb")
            }

            // Settings Tab
            NavigationStack {
                iOSSettingsView()
                    .navigationTitle("Settings")
            }
            .tabItem {
                Label("Settings", systemImage: "gear")
            }
        }
        .task {
            // Auto-connect on launch
            await appState.loadProjects()
        }
    }
}

/// Connection status indicator for toolbar
struct ConnectionStatusBadge: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(appState.isConnectedToServer ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            Text(appState.isConnectedToServer ? "Connected" : "Offline")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

/// iOS Roadmap view - Idea capture and crystallization only
struct iOSRoadmapView: View {
    @Environment(AppState.self) private var appState
    @State private var showingQuickCapture = false
    @State private var quickCaptureText = ""
    @State private var showingBrainstorm = false
    @State private var brainstormFeature: Feature?

    // Ideas and planned features only - implementation happens on Mac
    private var ideaInboxFeatures: [Feature] {
        appState.features.filter { $0.status == .planned || $0.status == .idea }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            List {
                // IDEA INBOX - capture and refine ideas here
                Section {
                    if ideaInboxFeatures.isEmpty {
                        HStack {
                            Image(systemName: "lightbulb")
                                .foregroundColor(.secondary)
                            Text("No ideas yet. Tap + to capture one!")
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 8)
                    } else {
                        ForEach(ideaInboxFeatures) { feature in
                            iOSIdeaCard(
                                feature: feature,
                                onRefine: { refineFeature(feature) }
                            )
                        }
                    }
                } header: {
                    HStack {
                        Image(systemName: "lightbulb.fill")
                            .foregroundColor(.yellow)
                        Text("IDEA INBOX")
                    }
                } footer: {
                    Text("Capture ideas here, refine with Claude, then build on Mac.")
                        .font(.caption)
                }
            }
            .listStyle(.insetGrouped)
            .refreshable {
                await appState.loadFeatures()
            }
            .overlay {
                if appState.isLoading {
                    ProgressView()
                }
            }

            // Quick Capture FAB
            Button {
                showingQuickCapture = true
            } label: {
                Image(systemName: "plus")
                    .font(.title2.bold())
                    .foregroundColor(.white)
                    .frame(width: 56, height: 56)
                    .background(Color.accentColor)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
            }
            .padding(.trailing, 20)
            .padding(.bottom, 20)
        }
        .sheet(isPresented: $showingQuickCapture) {
            QuickCaptureSheet(
                text: $quickCaptureText,
                isPresented: $showingQuickCapture
            )
        }
        .sheet(isPresented: $showingBrainstorm) {
            if let feature = brainstormFeature, let project = appState.selectedProject {
                NavigationStack {
                    BrainstormChatView(
                        project: project.name,
                        existingFeature: feature
                    )
                    .environment(appState)
                    .navigationTitle("Refine Idea")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showingBrainstorm = false }
                        }
                    }
                }
            }
        }
    }

    private func refineFeature(_ feature: Feature) {
        brainstormFeature = feature
        showingBrainstorm = true
    }
}

/// Card for ideas in the IDEA INBOX
struct iOSIdeaCard: View {
    let feature: Feature
    var onRefine: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title
            Text(feature.title)
                .font(.headline)

            // Description if present
            if let description = feature.description, !description.isEmpty {
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            // Status badge
            HStack {
                Text(feature.status == .idea ? "Needs refinement" : "Ready to build")
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(feature.status == .idea ? Color.orange.opacity(0.2) : Color.green.opacity(0.2))
                    .foregroundColor(feature.status == .idea ? .orange : .green)
                    .clipShape(Capsule())

                Spacer()

                // Refine button
                Button {
                    onRefine()
                } label: {
                    Label("Refine", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Quick Capture sheet for fast idea entry
struct QuickCaptureSheet: View {
    @Environment(AppState.self) private var appState
    @Binding var text: String
    @Binding var isPresented: Bool
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                TextField("What's the feature idea?", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($isFocused)
                    .lineLimit(3...6)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)

                Text("Quick capture adds the idea immediately. You can refine details later on Mac.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                Spacer()
            }
            .padding()
            .navigationTitle("Quick Capture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        text = ""
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addFeature()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear {
            isFocused = true
        }
    }

    private func addFeature() {
        let title = text.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }

        Task {
            await appState.addFeature(title: title)
            await appState.loadFeatures()
            await MainActor.run {
                text = ""
                isPresented = false
            }
        }
    }
}



/// Brainstorm view - real-time chat with Claude (aligned with macOS)
struct BrainstormInputView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if let project = appState.selectedProject {
            // Real-time brainstorm chat (new ideas, no existing feature)
            BrainstormChatView(
                project: project.name,
                existingFeature: nil  // New brainstorm, not refining
            )
            .environment(appState)
        } else {
            ContentUnavailableView(
                "No Project Selected",
                systemImage: "folder.badge.questionmark",
                description: Text("Select a project in Settings first.")
            )
        }
    }
}

/// iOS Settings view - simplified, auto-connects via Tailscale
struct iOSSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var showAdvanced = false

    var body: some View {
        Form {
            // Connection status - the main thing that matters
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(appState.isConnectedToServer ? Color.green : Color.red)
                                .frame(width: 12, height: 12)
                            Text(appState.isConnectedToServer ? "Connected" : "Connecting...")
                                .font(.headline)
                        }
                        Text(PlatformConfig.defaultServerURL)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if !appState.isConnectedToServer {
                        Button("Retry") {
                            Task { await appState.loadProjects() }
                        }
                        .buttonStyle(.bordered)
                    }
                }

                if let error = appState.connectionError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            } header: {
                Text("Server")
            } footer: {
                Text("Connects to your Pi via Tailscale automatically.")
            }

            // Projects - simple list
            Section("Projects") {
                if appState.projects.isEmpty && !appState.isConnectedToServer {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Loading projects...")
                            .foregroundColor(.secondary)
                    }
                } else if appState.projects.isEmpty {
                    Text("No projects found on server")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(appState.projects) { project in
                        Button {
                            Task { await appState.selectProject(project) }
                        } label: {
                            HStack {
                                Text(project.name)
                                    .foregroundColor(.primary)
                                Spacer()
                                if appState.selectedProject?.id == project.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }
                    }
                }
            }

            // About
            Section("About") {
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
            }

            // Advanced - hidden by default
            Section {
                DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Server: \(PlatformConfig.tailscaleHostname):\(PlatformConfig.serverPort)")
                            .font(.caption.monospaced())
                        Text("To change, edit PlatformConfig.swift")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .refreshable {
            await appState.loadProjects()
        }
    }
}

/// Stat badge for brainstorm context
struct StatBadge: View {
    let count: Int
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.title3.bold())
                .foregroundColor(color)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

/// Streak badge for iOS toolbar
struct iOSStreakBadge: View {
    let streak: Int

    var body: some View {
        if streak > 0 {
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .foregroundColor(.orange)
                Text("\(streak)")
                    .fontWeight(.bold)
            }
            .font(.subheadline)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.orange.opacity(0.15))
            .cornerRadius(8)
        }
    }
}

#Preview {
    iOSContentView()
        .environment(AppState())
}
