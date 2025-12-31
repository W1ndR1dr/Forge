import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        NavigationSplitView {
            ProjectListView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 300)
        } detail: {
            ZStack {
                // Main content - Workspace view
                VStack(spacing: 0) {
                    // Connection status bar at top
                    if !appState.isConnectedToServer {
                        ConnectionStatusBar(
                            state: appState.isLoading ? .connecting : .disconnected,
                            serverURL: PlatformConfig.defaultServerURL
                        )
                        .padding(.horizontal, Spacing.medium)
                        .padding(.top, Spacing.small)
                    }

                    // Content
                    Group {
                        if appState.isLoading {
                            LoadingFeaturesView(cardCount: 4)
                                .padding(Spacing.large)
                        } else if let project = appState.selectedProject {
                            if project.needsInitialization {
                                UninitializedProjectView(project: project)
                            } else {
                                WorkspaceView()
                            }
                        } else {
                            VStack(spacing: Spacing.standard) {
                                Image(systemName: "tray")
                                    .font(.system(size: 48))
                                    .foregroundColor(Linear.textMuted)
                                Text("No Project Selected")
                                    .font(Typography.body)
                                    .fontWeight(.medium)
                                    .foregroundColor(Linear.textSecondary)
                                Text("Select a project from the sidebar")
                                    .font(Typography.caption)
                                    .foregroundColor(Linear.textTertiary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }

                // Toast notifications overlay (error/success only)
                VStack {
                    Spacer()
                    VStack(spacing: Spacing.small) {
                        if let error = appState.errorMessage {
                            ErrorBanner(
                                message: error,
                                onDismiss: { appState.clearError() }
                            )
                            .padding(.horizontal, Spacing.large)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }

                        if let success = appState.successMessage {
                            SuccessBanner(
                                message: success,
                                autoDismissAfter: 3.0,
                                onDismiss: { appState.clearSuccess() }
                            )
                            .padding(.horizontal, Spacing.large)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .padding(.bottom, Spacing.large)
                }
                .animation(LinearEasing.fast, value: appState.errorMessage)
                .animation(LinearEasing.fast, value: appState.successMessage)
            }
            .background(Linear.background)
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: Binding(
            get: { appState.showingProposalReview },
            set: { appState.showingProposalReview = $0 }
        )) {
            if let project = appState.selectedProject {
                ProposalReviewView(
                    proposals: Binding(
                        get: { appState.parsedProposals },
                        set: { appState.parsedProposals = $0 }
                    ),
                    projectName: project.name,
                    onComplete: { _ in
                        appState.showingProposalReview = false
                    }
                )
            }
        }
        .sheet(isPresented: $state.showingProjectSetup) {
            if let project = appState.projectToInitialize {
                ProjectSetupSheet(project: project)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                // Refresh button (useful for checking server status)
                Button {
                    refreshFeatures()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Refresh features from server")
                .keyboardShortcut("r", modifiers: .command)
            }
        }
    }

    // MARK: - Keyboard Shortcut Actions

    func refreshFeatures() {
        Task {
            await appState.loadFeatures()
        }
    }
}

// Quick add feature sheet for keyboard shortcut
struct QuickAddFeatureSheet: View {
    @Environment(AppState.self) private var appState
    @Binding var isPresented: Bool
    @Binding var featureTitle: String
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: Spacing.large) {
            Text("Quick Add Feature")
                .font(Typography.body)
                .fontWeight(.semibold)
                .foregroundColor(Linear.textPrimary)

            TextField("Feature title", text: $featureTitle)
                .textFieldStyle(.linear)
                .focused($isFocused)
                .onSubmit {
                    addFeature()
                }

            HStack {
                Button("Cancel") {
                    isPresented = false
                    featureTitle = ""
                }
                .buttonStyle(.linearSecondary)
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Add") {
                    addFeature()
                }
                .buttonStyle(.linearPrimary)
                .keyboardShortcut(.defaultAction)
                .disabled(featureTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(Spacing.large)
        .frame(width: 400)
        .background(Linear.background)
        .onAppear {
            isFocused = true
        }
    }

    private func addFeature() {
        guard !featureTitle.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        Task {
            await appState.addFeature(title: featureTitle)
            await MainActor.run {
                isPresented = false
                featureTitle = ""
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(AppState())
        .frame(width: 1200, height: 800)
}
