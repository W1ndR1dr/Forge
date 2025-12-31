import SwiftUI
import Sparkle

/// Sparkle updater controller for auto-updates
final class UpdaterController: ObservableObject {
    let updater: SPUUpdater

    init() {
        // Create the standard Sparkle updater
        updater = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        ).updater
    }

    func checkForUpdates() {
        updater.checkForUpdates()
    }
}

@main
struct ForgeApp: App {
    @StateObject private var updaterController = UpdaterController()
    @State private var appState = AppState()
    @State private var showingAddFeature = false
    @State private var newFeatureTitle = ""

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .frame(minWidth: 1200, minHeight: 800)
                .sheet(isPresented: $showingAddFeature) {
                    QuickAddFeatureSheet(
                        isPresented: $showingAddFeature,
                        featureTitle: $newFeatureTitle
                    )
                    .environment(appState)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .commands {
            // App menu - Check for Updates
            CommandGroup(after: .appInfo) {
                Button("Check for Updates...") {
                    updaterController.checkForUpdates()
                }
            }

            // Help menu
            CommandGroup(replacing: .help) {
                Button("Forge Help") {
                    if let url = URL(string: "https://github.com/W1ndR1dr/Forge") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            // File menu - New Feature
            CommandGroup(replacing: .newItem) {
                Button("New Feature") {
                    showingAddFeature = true
                }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(appState.selectedProject == nil)
            }

            // View menu - Refresh
            CommandGroup(after: .toolbar) {
                Button("Refresh") {
                    Task {
                        await appState.loadFeatures()
                    }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(appState.selectedProject == nil)

                Divider()

                // Quick jump to status columns
                Text("Jump to Column")
                    .foregroundColor(.secondary)

                Button("Planned") {
                    // Focus will be handled by the KanbanView
                }
                .keyboardShortcut("1", modifiers: .command)
                .disabled(appState.selectedProject == nil)

                Button("In Progress") {
                }
                .keyboardShortcut("2", modifiers: .command)
                .disabled(appState.selectedProject == nil)

                Button("Review") {
                }
                .keyboardShortcut("3", modifiers: .command)
                .disabled(appState.selectedProject == nil)

                Button("Completed") {
                }
                .keyboardShortcut("4", modifiers: .command)
                .disabled(appState.selectedProject == nil)

                Button("Blocked") {
                }
                .keyboardShortcut("5", modifiers: .command)
                .disabled(appState.selectedProject == nil)
            }
        }

        // Settings window (⌘,)
        Settings {
            SettingsView()
                .environment(appState)
        }
    }
}
