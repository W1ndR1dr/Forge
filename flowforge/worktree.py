"""Git worktree management for FlowForge."""

from dataclasses import dataclass
from pathlib import Path
from typing import Optional
import subprocess
import shutil


@dataclass
class WorktreeInfo:
    """Information about a git worktree."""

    path: Path
    branch: str
    commit: str
    is_main: bool = False


@dataclass
class WorktreeStatus:
    """Status of a feature's worktree."""

    exists: bool
    has_changes: bool = False
    commit_count: int = 0
    changes: list[str] = None
    ahead_of_main: int = 0
    behind_main: int = 0

    def __post_init__(self):
        if self.changes is None:
            self.changes = []


class WorktreeManager:
    """
    Manages Git worktrees for parallel feature development.

    Each feature gets its own worktree in .flowforge-worktrees/{feature-id}/,
    allowing multiple Claude Code sessions to work on different features
    simultaneously without branch switching conflicts.
    """

    def __init__(self, repo_root: Path, worktree_base: str = ".flowforge-worktrees"):
        self.repo_root = repo_root
        self.worktree_base = repo_root / worktree_base

    def _run_git(
        self,
        args: list[str],
        cwd: Optional[Path] = None,
        check: bool = True,
    ) -> subprocess.CompletedProcess:
        """Run a git command."""
        return subprocess.run(
            ["git"] + args,
            cwd=cwd or self.repo_root,
            capture_output=True,
            text=True,
            check=check,
        )

    def list_worktrees(self) -> list[WorktreeInfo]:
        """List all worktrees for this repo."""
        result = self._run_git(["worktree", "list", "--porcelain"])

        worktrees = []
        current: dict = {}

        for line in result.stdout.strip().split("\n"):
            if line.startswith("worktree "):
                current["path"] = Path(line.split(" ", 1)[1])
            elif line.startswith("HEAD "):
                current["commit"] = line.split(" ", 1)[1][:8]
            elif line.startswith("branch "):
                current["branch"] = line.split(" ", 1)[1].replace("refs/heads/", "")
            elif line == "":
                if current and "path" in current:
                    worktrees.append(WorktreeInfo(
                        path=current.get("path"),
                        branch=current.get("branch", "detached"),
                        commit=current.get("commit", "unknown"),
                        is_main=current.get("path") == self.repo_root,
                    ))
                current = {}

        # Don't forget the last one
        if current and "path" in current:
            worktrees.append(WorktreeInfo(
                path=current.get("path"),
                branch=current.get("branch", "detached"),
                commit=current.get("commit", "unknown"),
                is_main=current.get("path") == self.repo_root,
            ))

        return worktrees

    def create_for_feature(
        self,
        feature_id: str,
        base_branch: str = "main",
    ) -> Path:
        """
        Create a worktree for a feature.

        1. Creates branch: feature/{feature_id}
        2. Creates worktree at: .flowforge-worktrees/{feature_id}
        3. Returns the worktree path
        """
        branch_name = f"feature/{feature_id}"
        worktree_path = self.worktree_base / feature_id

        if worktree_path.exists():
            raise ValueError(f"Worktree already exists: {worktree_path}")

        # Ensure worktree base directory exists
        self.worktree_base.mkdir(parents=True, exist_ok=True)

        # Check if branch already exists
        result = self._run_git(
            ["rev-parse", "--verify", branch_name],
            check=False,
        )

        if result.returncode != 0:
            # Branch doesn't exist, create it from base
            self._run_git(["branch", branch_name, base_branch])

        # Create worktree
        self._run_git(["worktree", "add", str(worktree_path), branch_name])

        return worktree_path

    def remove_for_feature(
        self,
        feature_id: str,
        force: bool = False,
        delete_branch: bool = True,
    ) -> None:
        """
        Remove a worktree and optionally its branch.

        Safety: Only removes if branch is merged or force=True.
        """
        worktree_path = self.worktree_base / feature_id
        branch_name = f"feature/{feature_id}"

        if not worktree_path.exists():
            return

        # Check if branch is merged (unless forcing)
        if not force:
            result = self._run_git(["branch", "--merged", "main"], check=False)
            if branch_name not in result.stdout:
                raise ValueError(
                    f"Branch {branch_name} is not merged into main.\n"
                    f"Use force=True to remove anyway (you will lose changes!)."
                )

        # Remove worktree
        self._run_git(["worktree", "remove", str(worktree_path), "--force"] if force else ["worktree", "remove", str(worktree_path)])

        # Remove branch if requested
        if delete_branch:
            self._run_git(
                ["branch", "-D" if force else "-d", branch_name],
                check=False,  # Don't fail if branch doesn't exist
            )

    def get_status(self, feature_id: str) -> WorktreeStatus:
        """Get git status for a feature's worktree."""
        worktree_path = self.worktree_base / feature_id

        if not worktree_path.exists():
            return WorktreeStatus(exists=False)

        # Get uncommitted changes
        status_result = self._run_git(
            ["status", "--porcelain"],
            cwd=worktree_path,
            check=False,
        )

        changes = [
            line for line in status_result.stdout.strip().split("\n")
            if line.strip()
        ]

        # Get commit count vs main
        log_result = self._run_git(
            ["log", "main..HEAD", "--oneline"],
            cwd=worktree_path,
            check=False,
        )

        commits = [
            line for line in log_result.stdout.strip().split("\n")
            if line.strip()
        ]

        # Get ahead/behind counts
        ahead = len(commits)
        behind = 0

        rev_list = self._run_git(
            ["rev-list", "--left-right", "--count", "main...HEAD"],
            cwd=worktree_path,
            check=False,
        )
        if rev_list.returncode == 0 and rev_list.stdout.strip():
            parts = rev_list.stdout.strip().split()
            if len(parts) == 2:
                behind, ahead = int(parts[0]), int(parts[1])

        return WorktreeStatus(
            exists=True,
            has_changes=bool(changes),
            commit_count=len(commits),
            changes=changes,
            ahead_of_main=ahead,
            behind_main=behind,
        )

    def sync_from_main(self, feature_id: str) -> tuple[bool, str]:
        """
        Rebase feature branch onto latest main.

        Returns (success, message).
        Safety: Checks for uncommitted changes first.
        """
        worktree_path = self.worktree_base / feature_id

        if not worktree_path.exists():
            return False, f"Worktree does not exist: {worktree_path}"

        # Check for uncommitted changes
        status = self._run_git(
            ["status", "--porcelain"],
            cwd=worktree_path,
        )

        if status.stdout.strip():
            return False, (
                "Uncommitted changes exist. Commit or stash first.\n\n"
                "To fix:\n"
                f"  cd {worktree_path}\n"
                "  git add -A && git commit -m 'WIP: save progress'\n"
                "  forge sync {feature_id}"
            )

        # Fetch latest main
        self._run_git(["fetch", "origin", "main"], check=False)

        # Rebase onto origin/main
        result = self._run_git(
            ["rebase", "origin/main"],
            cwd=worktree_path,
            check=False,
        )

        if result.returncode != 0:
            # Abort the failed rebase
            self._run_git(["rebase", "--abort"], cwd=worktree_path, check=False)
            return False, (
                f"Rebase conflict detected. Aborted.\n\n"
                f"Conflicts:\n{result.stderr}\n\n"
                f"You may need to manually resolve conflicts:\n"
                f"  cd {worktree_path}\n"
                f"  git rebase origin/main\n"
                f"  # resolve conflicts\n"
                f"  git rebase --continue"
            )

        return True, "Successfully rebased onto latest main."

    def get_worktree_path(self, feature_id: str) -> Optional[Path]:
        """Get the worktree path for a feature if it exists."""
        path = self.worktree_base / feature_id
        return path if path.exists() else None

    def prune(self) -> int:
        """
        Prune stale worktree references.

        Returns number of pruned entries.
        """
        before = len(self.list_worktrees())
        self._run_git(["worktree", "prune"])
        after = len(self.list_worktrees())
        return before - after


class ClaudeCodeLauncher:
    """
    Launches Claude Code CLI in a worktree with proper configuration.

    Handles:
    - Setting working directory to worktree
    - Injecting feature prompt via stdin or file
    - Using --dangerously-skip-permissions when configured
    - Session continuity via --resume
    """

    def __init__(
        self,
        claude_command: str = "claude",
        default_flags: list[str] = None,
    ):
        self.claude_command = claude_command
        self.default_flags = default_flags or ["--dangerously-skip-permissions"]

    def build_command(
        self,
        worktree_path: Path,
        prompt: Optional[str] = None,
        session_id: Optional[str] = None,
        extra_flags: list[str] = None,
    ) -> list[str]:
        """
        Build the Claude Code command.

        Returns the command as a list suitable for subprocess.
        """
        cmd = [self.claude_command]

        # Add default flags
        cmd.extend(self.default_flags)

        # Add session resume if provided
        if session_id:
            cmd.extend(["--resume", session_id])

        # Add extra flags
        if extra_flags:
            cmd.extend(extra_flags)

        # Add prompt if provided (as the final argument)
        if prompt:
            cmd.extend(["--print", "-p", prompt])

        return cmd

    def get_launch_instructions(
        self,
        worktree_path: Path,
        prompt_path: Optional[Path] = None,
        session_id: Optional[str] = None,
    ) -> str:
        """
        Get human-readable instructions for launching Claude Code.

        For manual launch (recommended for interactive use).
        """
        lines = [
            f"cd {worktree_path}",
            f"{self.claude_command} {' '.join(self.default_flags)}",
        ]

        if prompt_path:
            lines.append(f"\n# Prompt saved to: {prompt_path}")
            lines.append("# Paste the prompt from your clipboard to begin.")

        if session_id:
            lines.insert(1, f"# To resume previous session: --resume {session_id}")

        return "\n".join(lines)
