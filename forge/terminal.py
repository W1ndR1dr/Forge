"""
Terminal integration for Forge.

Supports opening new terminal tabs/windows in worktree directories
with Claude Code ready to go. Zero git knowledge required.

Supported terminals:
- Warp (recommended for vibecoders)
- iTerm2
- Terminal.app (macOS default)
"""

import subprocess
import shutil
import platform
from pathlib import Path
from typing import Optional
from enum import Enum


# Terminal launching only works on macOS (uses osascript)
IS_MACOS = platform.system() == "Darwin"


class Terminal(str, Enum):
    """Supported terminal applications."""
    WARP = "warp"
    ITERM = "iterm"
    TERMINAL = "terminal"
    AUTO = "auto"  # Auto-detect


def detect_terminal() -> Terminal:
    """Auto-detect the best available terminal."""
    # Check for Warp first (preferred for vibecoders)
    if Path("/Applications/Warp.app").exists():
        return Terminal.WARP
    elif Path("/Applications/iTerm.app").exists():
        return Terminal.ITERM
    else:
        return Terminal.TERMINAL


def open_terminal_in_directory(
    directory: Path,
    terminal: Terminal = Terminal.AUTO,
    command: Optional[str] = None,
    title: Optional[str] = None,
) -> bool:
    """
    Open a new terminal tab/window in the specified directory.

    Args:
        directory: Path to open the terminal in
        terminal: Which terminal to use (auto-detects if AUTO)
        command: Optional command to run after opening
        title: Optional title for the tab/window

    Returns:
        True if successful, False otherwise
    """
    if not IS_MACOS:
        # Terminal launching requires macOS osascript
        return False

    if terminal == Terminal.AUTO:
        terminal = detect_terminal()

    try:
        if terminal == Terminal.WARP:
            return _open_warp(directory, command, title)
        elif terminal == Terminal.ITERM:
            return _open_iterm(directory, command, title)
        else:
            return _open_terminal_app(directory, command, title)
    except Exception as e:
        print(f"Failed to open terminal: {e}")
        return False


def _open_warp(
    directory: Path,
    command: Optional[str] = None,
    title: Optional[str] = None,
) -> bool:
    """Open Warp in a new tab at the specified directory."""

    # Build the AppleScript for Warp
    # Warp supports opening new tabs via the warp:// URL scheme or AppleScript
    script_parts = [
        'tell application "Warp"',
        '    activate',
    ]

    # Create a new tab and cd to directory
    if command:
        # If we have a command, combine cd and command
        full_command = f'cd "{directory}" && {command}'
        script_parts.append(f'    tell application "System Events" to keystroke "t" using command down')
        script_parts.append('    delay 0.5')
        script_parts.append(f'    tell application "System Events" to keystroke "{full_command}"')
        script_parts.append('    tell application "System Events" to keystroke return')
    else:
        # Just open in the directory
        script_parts.append(f'    tell application "System Events" to keystroke "t" using command down')
        script_parts.append('    delay 0.5')
        script_parts.append(f'    tell application "System Events" to keystroke "cd \\"{directory}\\""')
        script_parts.append('    tell application "System Events" to keystroke return')

    script_parts.append('end tell')

    script = '\n'.join(script_parts)

    result = subprocess.run(
        ['osascript', '-e', script],
        capture_output=True,
        text=True
    )

    return result.returncode == 0


def _open_iterm(
    directory: Path,
    command: Optional[str] = None,
    title: Optional[str] = None,
) -> bool:
    """Open iTerm2 in a new tab at the specified directory."""

    cd_command = f'cd "{directory}"'
    if command:
        cd_command += f' && {command}'

    script = f'''
    tell application "iTerm"
        activate
        tell current window
            create tab with default profile
            tell current session
                write text "{cd_command}"
            end tell
        end tell
    end tell
    '''

    result = subprocess.run(
        ['osascript', '-e', script],
        capture_output=True,
        text=True
    )

    return result.returncode == 0


def _open_terminal_app(
    directory: Path,
    command: Optional[str] = None,
    title: Optional[str] = None,
) -> bool:
    """Open Terminal.app in a new tab at the specified directory."""

    cd_command = f'cd "{directory}"'
    if command:
        cd_command += f' && {command}'

    script = f'''
    tell application "Terminal"
        activate
        do script "{cd_command}"
    end tell
    '''

    result = subprocess.run(
        ['osascript', '-e', script],
        capture_output=True,
        text=True
    )

    return result.returncode == 0


def launch_claude_code(
    worktree_path: Path,
    prompt_path: Optional[Path] = None,
    claude_command: str = "claude",
    claude_flags: list[str] = None,
    terminal: Terminal = Terminal.AUTO,
    auto_start: bool = True,
) -> bool:
    """
    Launch Claude Code in a new terminal tab at the worktree directory.

    This is the main function vibecoders should use - it handles everything:
    1. Opens new terminal tab in the worktree
    2. Runs Claude Code with appropriate flags
    3. You just paste the prompt from clipboard

    Args:
        worktree_path: Path to the feature worktree
        prompt_path: Optional path to the saved prompt file
        claude_command: Claude CLI command (default: "claude")
        claude_flags: Extra flags for Claude (default: ["--dangerously-skip-permissions"])
        terminal: Which terminal to use (default: auto-detect)
        auto_start: If True, start Claude Code automatically

    Returns:
        True if successful
    """
    if claude_flags is None:
        claude_flags = ["--dangerously-skip-permissions"]

    if auto_start:
        # Build the full claude command
        flags_str = " ".join(claude_flags)
        command = f"{claude_command} {flags_str}"

        return open_terminal_in_directory(
            worktree_path,
            terminal=terminal,
            command=command,
            title=f"Forge: {worktree_path.name}",
        )
    else:
        # Just open in the directory
        return open_terminal_in_directory(
            worktree_path,
            terminal=terminal,
            title=f"Forge: {worktree_path.name}",
        )


# Convenience function for the CLI
def start_feature_in_terminal(
    worktree_path: Path,
    feature_title: str,
    claude_command: str = "claude",
    claude_flags: list[str] = None,
    terminal: str = "auto",
) -> tuple[bool, str]:
    """
    Start working on a feature in a new terminal tab.

    Returns (success, message) for the CLI to display.
    """
    terminal_enum = Terminal(terminal) if terminal != "auto" else Terminal.AUTO

    success = launch_claude_code(
        worktree_path=worktree_path,
        claude_command=claude_command,
        claude_flags=claude_flags,
        terminal=terminal_enum,
        auto_start=True,
    )

    if success:
        detected = detect_terminal() if terminal_enum == Terminal.AUTO else terminal_enum
        return True, f"Opened {detected.value.title()} with Claude Code in {worktree_path.name}"
    else:
        return False, "Failed to open terminal. You can manually run:\n" \
                     f"  cd {worktree_path}\n" \
                     f"  {claude_command} {' '.join(claude_flags or [])}"
