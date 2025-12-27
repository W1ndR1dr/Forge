import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var showingAddFeature = false
    @State private var showingBrainstorm = false
    @State private var newFeatureTitle = ""

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
                                    .font(.system(size: 64))
                                    .foregroundColor(.secondary)
                                Text("No Project Selected")
                                    .font(.title2)
                                    .foregroundColor(.secondary)
                                Text("Select a project from the sidebar")
                                    .foregroundColor(.secondary)
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
                .animation(SpringPreset.snappy, value: appState.errorMessage)
                .animation(SpringPreset.snappy, value: appState.successMessage)
            }
        }
        .sheet(isPresented: $showingAddFeature) {
            QuickAddFeatureSheet(
                isPresented: $showingAddFeature,
                featureTitle: $newFeatureTitle
            )
        }
        .sheet(isPresented: $showingBrainstorm) {
            BrainstormSheet()
        }
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
                Button {
                    showingBrainstorm = true
                } label: {
                    Label("Brainstorm", systemImage: "brain.head.profile")
                }
                .help("Import ideas from Claude brainstorm")

                Button {
                    showingAddFeature = true
                } label: {
                    Label("Add Feature", systemImage: "plus")
                }
                .help("Quick add a feature")
                .keyboardShortcut("n", modifiers: .command)
            }
        }
    }

    // MARK: - Keyboard Shortcut Actions

    func addNewFeature() {
        guard appState.selectedProject != nil else { return }
        showingAddFeature = true
    }

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
        VStack(spacing: 20) {
            Text("Quick Add Feature")
                .font(.title2)
                .fontWeight(.bold)

            TextField("Feature title", text: $featureTitle)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit {
                    addFeature()
                }

            HStack {
                Button("Cancel") {
                    isPresented = false
                    featureTitle = ""
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Add") {
                    addFeature()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(featureTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
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
