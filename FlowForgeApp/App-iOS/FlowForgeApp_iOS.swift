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

/// iOS Roadmap view - aligned with macOS MissionControlV2 workflow
struct iOSRoadmapView: View {
    @Environment(AppState.self) private var appState
    @State private var showingQuickCapture = false
    @State private var quickCaptureText = ""
    @State private var showingBrainstorm = false
    @State private var brainstormFeature: Feature?

    // Computed properties matching macOS
    private var ideaInboxFeatures: [Feature] {
        appState.features.filter { $0.status == .planned || $0.status == .idea }
    }

    private var inProgressFeatures: [Feature] {
        appState.features.filter { $0.status == .inProgress || $0.status == .review }
    }

    private var shippedFeatures: [Feature] {
        appState.features.filter { $0.status == .completed }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            List {
                // IDEA INBOX - the queue of ideas waiting to be started
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
                                onRefine: { refineFeature(feature) },
                                onCopyPrompt: { copyPrompt(for: feature) }
                            )
                        }
                    }
                } header: {
                    HStack {
                        Image(systemName: "lightbulb.fill")
                            .foregroundColor(.yellow)
                        Text("IDEA INBOX")
                    }
                }

                // IN PROGRESS - active work
                if !inProgressFeatures.isEmpty {
                    Section("IN PROGRESS") {
                        ForEach(inProgressFeatures) { feature in
                            iOSFeatureRow(feature: feature)
                        }
                    }
                }

                // SHIPPED - completed features
                if !shippedFeatures.isEmpty {
                    Section("SHIPPED") {
                        ForEach(shippedFeatures.prefix(5)) { feature in
                            iOSFeatureRow(feature: feature)
                        }
                        if shippedFeatures.count > 5 {
                            Text("+ \(shippedFeatures.count - 5) more")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
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

    private func copyPrompt(for feature: Feature) {
        guard let projectName = appState.selectedProject?.name else { return }

        Task {
            do {
                let apiClient = APIClient()
                let prompt = try await apiClient.getPrompt(
                    project: projectName,
                    featureId: feature.id
                )
                await MainActor.run {
                    UIPasteboard.general.string = prompt
                }
            } catch {
                print("Failed to copy prompt: \(error)")
            }
        }
    }
}

/// Card for ideas in the IDEA INBOX
struct iOSIdeaCard: View {
    let feature: Feature
    var onRefine: () -> Void
    var onCopyPrompt: () -> Void

    @State private var showCopiedToast = false

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

            // Action buttons
            HStack(spacing: 12) {
                Button {
                    onRefine()
                } label: {
                    Label("Refine", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button {
                    onCopyPrompt()
                    showCopiedToast = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        showCopiedToast = false
                    }
                } label: {
                    Label(showCopiedToast ? "Copied!" : "Copy Prompt", systemImage: showCopiedToast ? "checkmark" : "doc.on.clipboard")
                }
                .buttonStyle(.bordered)
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

/// iOS Feature row for list view
struct iOSFeatureRow: View {
    @Environment(AppState.self) private var appState
    let feature: Feature

    @State private var showingDetail = false
    @State private var isCopying = false
    @State private var showCopiedAlert = false

    var body: some View {
        Button {
            showingDetail = true
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(feature.title)
                        .font(.headline)
                        .foregroundColor(.primary)

                    Spacer()

                    if let complexity = feature.complexity {
                        Text(complexity.displayName)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(complexityColor(complexity).opacity(0.2))
                            .foregroundColor(complexityColor(complexity))
                            .clipShape(Capsule())
                    }
                }

                if let description = feature.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                if !feature.tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(feature.tags, id: \.self) { tag in
                                Text(tag)
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.2))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button {
                copyPrompt()
            } label: {
                Label("Copy Prompt", systemImage: "doc.on.clipboard")
            }
            .tint(.blue)
        }
        .sheet(isPresented: $showingDetail) {
            iOSFeatureDetailView(feature: feature)
        }
        .alert("Copied!", isPresented: $showCopiedAlert) {
            Button("OK") {}
        } message: {
            Text("Implementation prompt copied to clipboard")
        }
    }

    private func complexityColor(_ complexity: Complexity) -> Color {
        switch complexity {
        case .small: return .green
        case .medium: return .orange
        case .large: return .red
        case .epic: return .purple
        }
    }

    private func copyPrompt() {
        guard let projectName = appState.selectedProject?.name else { return }
        isCopying = true

        Task {
            do {
                let apiClient = APIClient()
                let prompt = try await apiClient.getPrompt(
                    project: projectName,
                    featureId: feature.id
                )

                await MainActor.run {
                    PlatformPasteboard.copy(prompt)
                    isCopying = false
                    showCopiedAlert = true
                }
            } catch {
                await MainActor.run {
                    isCopying = false
                    print("Failed to copy prompt: \(error)")
                }
            }
        }
    }
}

/// iOS Feature detail view
struct iOSFeatureDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let feature: Feature

    @State private var showCopiedAlert = false

    var body: some View {
        NavigationStack {
            List {
                Section("Details") {
                    LabeledContent("ID", value: feature.id)
                    LabeledContent("Status", value: feature.status.displayName)
                    if let complexity = feature.complexity {
                        LabeledContent("Complexity", value: complexity.displayName)
                    }
                    if let branch = feature.branch {
                        LabeledContent("Branch", value: branch)
                    }
                }

                if let description = feature.description, !description.isEmpty {
                    Section("Description") {
                        Text(description)
                    }
                }

                if !feature.tags.isEmpty {
                    Section("Tags") {
                        FlowLayout(spacing: 8) {
                            ForEach(feature.tags, id: \.self) { tag in
                                Text(tag)
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.accentColor.opacity(0.2))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }

                Section("Actions") {
                    Button {
                        copyPrompt()
                    } label: {
                        Label("Copy Implementation Prompt", systemImage: "doc.on.clipboard")
                    }

                    Button {
                        Task {
                            await appState.updateFeatureStatus(feature, to: .inProgress)
                            dismiss()
                        }
                    } label: {
                        Label("Start Feature", systemImage: "play.fill")
                    }
                    .disabled(feature.status == .inProgress)
                }
            }
            .navigationTitle(feature.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .alert("Copied!", isPresented: $showCopiedAlert) {
            Button("OK") {}
        } message: {
            Text("Implementation prompt copied to clipboard")
        }
    }

    private func copyPrompt() {
        guard let projectName = appState.selectedProject?.name else { return }

        Task {
            do {
                let apiClient = APIClient()
                let prompt = try await apiClient.getPrompt(
                    project: projectName,
                    featureId: feature.id
                )

                await MainActor.run {
                    PlatformPasteboard.copy(prompt)
                    showCopiedAlert = true
                }
            } catch {
                print("Failed to copy prompt: \(error)")
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

/// iOS-adapted proposal review sheet
struct iOSProposalReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var proposals: [Proposal]
    let projectName: String
    let onComplete: ([Proposal]) -> Void

    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach($proposals) { $proposal in
                        iOSProposalRow(proposal: $proposal)
                    }
                } header: {
                    Text("\(proposals.count) proposal(s)")
                } footer: {
                    HStack {
                        Text("\(approvedCount) approved")
                            .foregroundColor(.green)
                        Text("•")
                        Text("\(declinedCount) declined")
                            .foregroundColor(.red)
                        Text("•")
                        Text("\(pendingCount) pending")
                            .foregroundColor(.secondary)
                    }
                    .font(.caption)
                }
            }
            .navigationTitle("Review Proposals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        submitApproved()
                    } label: {
                        if isSubmitting {
                            ProgressView()
                        } else {
                            Text("Add \(approvedCount)")
                        }
                    }
                    .disabled(approvedCount == 0 || isSubmitting)
                }
            }
        }
    }

    private var approvedCount: Int {
        proposals.filter { $0.status == .approved }.count
    }

    private var declinedCount: Int {
        proposals.filter { $0.status == .declined }.count
    }

    private var pendingCount: Int {
        proposals.filter { $0.status == .pending }.count
    }

    private func submitApproved() {
        isSubmitting = true
        onComplete(proposals)
        dismiss()
    }
}

/// Single proposal row for iOS
struct iOSProposalRow: View {
    @Binding var proposal: Proposal

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(proposal.title)
                    .font(.headline)
                    .strikethrough(proposal.status == .declined)

                Spacer()

                StatusPill(status: proposal.status)
            }

            Text(proposal.description)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)

            HStack(spacing: 8) {
                Text("P\(proposal.priority)")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(priorityColor.opacity(0.2))
                    .foregroundColor(priorityColor)
                    .clipShape(Capsule())

                Text(proposal.complexity.capitalized)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Action buttons
            if proposal.status == .pending {
                HStack(spacing: 12) {
                    Button("Approve") {
                        proposal.status = .approved
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .controlSize(.small)

                    Button("Decline") {
                        proposal.status = .declined
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .controlSize(.small)

                    Button("Defer") {
                        proposal.status = .deferred
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                    .controlSize(.small)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var priorityColor: Color {
        switch proposal.priority {
        case 1: return .red
        case 2: return .orange
        case 3: return .yellow
        default: return .blue
        }
    }
}

/// Status pill for proposals
struct StatusPill: View {
    let status: ProposalStatus

    var body: some View {
        Text(status.displayName)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(statusColor.opacity(0.2))
            .foregroundColor(statusColor)
            .clipShape(Capsule())
    }

    private var statusColor: Color {
        switch status {
        case .pending: return .gray
        case .approved: return .green
        case .declined: return .red
        case .deferred: return .orange
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
