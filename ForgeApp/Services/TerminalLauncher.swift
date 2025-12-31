import Foundation
#if os(macOS)
import AppKit
import ApplicationServices
#endif

/// Launches Claude Code in Warp terminal at a specific worktree path.
/// This is the bridge between Forge orchestration and actual coding.
/// macOS only - iOS doesn't have terminal access.
enum TerminalLauncher {

    /// Result of a terminal launch attempt
    struct LaunchResult {
        let success: Bool
        let message: String
    }

    #if os(macOS)
    /// Launch Claude Code in Warp at the given worktree path
    /// - Parameters:
    ///   - worktreePath: Absolute path to the worktree directory
    ///   - prompt: Optional prompt for new sessions (nil = resume existing session)
    ///   - launchCommand: Base command from server config (e.g., "claude --dangerously-skip-permissions")
    /// - Returns: LaunchResult indicating success/failure
    @MainActor
    static func launchClaudeCode(
        worktreePath: String,
        prompt: String? = nil,
        launchCommand: String? = nil
    ) async -> LaunchResult {
        let baseCommand = launchCommand ?? "claude --dangerously-skip-permissions"

        // Build the full command
        let fullCommand: String
        var promptFile: URL? = nil

        if let prompt = prompt, !prompt.isEmpty {
            // FIRST START: Save prompt to temp file, command reads it
            let tempDir = FileManager.default.temporaryDirectory
            promptFile = tempDir.appendingPathComponent("forge-prompt-\(UUID().uuidString).md")

            do {
                try prompt.write(to: promptFile!, atomically: true, encoding: .utf8)
                fullCommand = "\(baseCommand) \"$(cat '\(promptFile!.path)')\""
            } catch {
                // Fallback without temp file
                fullCommand = baseCommand
            }
        } else {
            // RESUME: Use --resume to continue previous session
            fullCommand = "claude --resume --dangerously-skip-permissions"
        }

        // Check if we have Accessibility permissions
        // Use AXIsProcessTrustedWithOptions to prompt user if needed
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        let hasAccessibility = AXIsProcessTrustedWithOptions(options)
        print("[TerminalLauncher] AXIsProcessTrusted: \(hasAccessibility)")

        // Step 1: Open Warp to the worktree path (new window, not tab)
        guard let encodedPath = worktreePath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let warpURL = URL(string: "warp://action/new_window?path=\(encodedPath)"),
              NSWorkspace.shared.open(warpURL) else {
            return LaunchResult(success: false, message: "Failed to open Warp")
        }

        // If no accessibility permissions, copy command and prompt user
        if !hasAccessibility {
            copyToClipboard(fullCommand)
            showAccessibilityPermissionsAlert()

            // Clean up temp file after delay
            if let file = promptFile {
                DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
                    try? FileManager.default.removeItem(at: file)
                }
            }

            return LaunchResult(
                success: true,
                message: "Command copied. Grant Accessibility permissions for auto-typing, then try again."
            )
        }

        // Step 2: Use AppleScript to type the command
        // Wait for Warp to open and focus
        try? await Task.sleep(nanoseconds: 800_000_000) // 0.8 seconds

        print("[TerminalLauncher] Full command: \(fullCommand)")
        print("[TerminalLauncher] Command length: \(fullCommand.count) chars")

        let escapedCommand = fullCommand.escapedForAppleScript
        let script = """
        tell application "Warp" to activate
        delay 0.3
        tell application "System Events"
            tell process "Warp"
                keystroke "\(escapedCommand)"
                delay 0.1
                keystroke return
            end tell
        end tell
        """

        print("[TerminalLauncher] Running AppleScript...")
        let result = await runAppleScript(script)
        print("[TerminalLauncher] AppleScript result: success=\(result.success), error=\(result.error ?? "none")")

        // Clean up temp file after delay
        if let file = promptFile {
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
                try? FileManager.default.removeItem(at: file)
            }
        }

        if result.success {
            return LaunchResult(success: true, message: "Claude Code launched in Warp")
        } else {
            // AppleScript failed for some other reason
            copyToClipboard(fullCommand)
            return LaunchResult(
                success: true,
                message: "Command copied - paste with ⌘V (AppleScript error: \(result.error ?? "unknown"))"
            )
        }
    }

    /// Show alert explaining how to grant Accessibility permissions
    @MainActor
    private static func showAccessibilityPermissionsAlert() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Accessibility Permission Required"
            alert.informativeText = """
            Forge needs Accessibility access to auto-type commands in Warp.

            In System Settings → Privacy & Security → Accessibility:
            1. If Forge is listed, REMOVE it first (select → click -)
            2. Click + and add Forge from /Applications
            3. Make sure the toggle is ON
            4. QUIT and relaunch Forge

            The command is on your clipboard - paste with ⌘V for now.
            """
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Open Settings")
            alert.addButton(withTitle: "OK")

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    /// Fallback to default Terminal.app
    private static func launchInDefaultTerminal(worktreePath: String) async -> LaunchResult {
        let script = """
        tell application "Terminal"
            activate
            do script "cd '\(worktreePath.escapedForAppleScript)' && claude"
        end tell
        """

        let result = await runAppleScript(script)

        if result.success {
            return LaunchResult(
                success: true,
                message: "Claude Code opened in Terminal. Prompt copied to clipboard."
            )
        } else {
            return LaunchResult(
                success: false,
                message: "Failed to open terminal: \(result.error ?? "Unknown error")"
            )
        }
    }

    /// Copy text to system clipboard
    private static func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Run AppleScript via osascript command (more reliable than NSAppleScript)
    private static func runAppleScript(_ script: String) async -> (success: Bool, error: String?) {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = ["-e", script]

                let errorPipe = Pipe()
                process.standardError = errorPipe

                do {
                    try process.run()
                    process.waitUntilExit()

                    if process.terminationStatus == 0 {
                        continuation.resume(returning: (true, nil))
                    } else {
                        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                        let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                        continuation.resume(returning: (false, errorMessage))
                    }
                } catch {
                    continuation.resume(returning: (false, error.localizedDescription))
                }
            }
        }
    }
    #endif
}

// MARK: - String Extension for AppleScript escaping

private extension String {
    /// Escape string for safe use in AppleScript keystroke
    var escapedForAppleScript: String {
        // AppleScript strings only need backslash and double quote escaped
        self.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
