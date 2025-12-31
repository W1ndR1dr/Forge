import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        NavigationSplitView {
            // Sidebar - recessed, darker
            ProjectListView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 300)
        } detail: {
            // Main workspace - elevated, foreground
            ZStack {
                // Elevated workspace container
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
                .background(Linear.background)

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
        .toolbar {
            // Forge branding - leftmost
            ToolbarItem(placement: .navigation) {
                HStack(spacing: Spacing.medium) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 28, height: 28)
                    Text("Forge")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Linear.textPrimary)
                }
                .padding(.horizontal, -4) // Tighten around branding
            }
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
