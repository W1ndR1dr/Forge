import Foundation
#if os(macOS)
import AppKit
#endif

/// Launches Claude Code in Warp terminal at a specific worktree path.
/// This is the bridge between FlowForge orchestration and actual coding.
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
    ///   - prompt: Optional prompt to copy to clipboard (user can paste into Claude)
    /// - Returns: LaunchResult indicating success/failure
    @MainActor
    static func launchClaudeCode(
        worktreePath: String,
        prompt: String? = nil
    ) async -> LaunchResult {
        // Copy prompt to clipboard first (as backup/convenience)
        if let prompt = prompt, !prompt.isEmpty {
            copyToClipboard(prompt)
        }

        // AppleScript to open Warp, create new tab, cd to worktree, run claude
        let script = """
        tell application "Warp"
            activate
            delay 0.3
        end tell

        tell application "System Events"
            tell process "Warp"
                -- New tab
                keystroke "t" using command down
                delay 0.5

                -- cd to worktree and run claude
                keystroke "cd '\(worktreePath.escapedForAppleScript)' && claude"
                keystroke return
            end tell
        end tell
        """

        let result = await runAppleScript(script)

        if result.success {
            return LaunchResult(
                success: true,
                message: "Claude Code opened in Warp. Prompt copied to clipboard."
            )
        } else {
            // Fallback: Try opening Terminal.app if Warp isn't available
            let fallbackResult = await launchInDefaultTerminal(worktreePath: worktreePath)
            return fallbackResult
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

    /// Run AppleScript and return result
    private static func runAppleScript(_ script: String) async -> (success: Bool, error: String?) {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var error: NSDictionary?
                let appleScript = NSAppleScript(source: script)
                let _ = appleScript?.executeAndReturnError(&error)

                if let error = error {
                    let errorMessage = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
                    continuation.resume(returning: (false, errorMessage))
                } else {
                    continuation.resume(returning: (true, nil))
                }
            }
        }
    }
    #endif
}

// MARK: - String Extension for AppleScript escaping

private extension String {
    /// Escape string for safe use in AppleScript
    var escapedForAppleScript: String {
        self.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "'\\''")
    }
}
