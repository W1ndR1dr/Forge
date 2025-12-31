"""
GitOverlord - The invisible git manager.

Manages all git operations so the user never has to think about git.
Handles worktrees, merges, conflict detection, and cleanup.
"""

import asyncio
import subprocess
from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from pathlib import Path
from typing import Optional

from .prompts import GIT_OVERLORD_PROMPT


class MergeStatus(Enum):
    READY = "ready"              # No conflicts, ready to merge
    CONFLICTS = "conflicts"      # Has conflicts that need resolution
    BUILDING = "building"        # Waiting for build validation
    MERGED = "merged"           # Successfully merged
    FAILED = "failed"           # Merge or validation failed


@dataclass
class WorktreeInfo:
    """Information about a git worktree."""
    feature_id: str
    path: Path
    branch: str
    ahead_of_main: int
    has_uncommitted: bool
    last_commit_date: Optional[datetime] = None


@dataclass
class ConflictInfo:
    """Information about merge conflicts."""
    feature_id: str
    conflicting_files: list[str]
    can_auto_resolve: bool
    resolution_hint: str


@dataclass
class MergeResult:
    """Result of a merge operation."""
    feature_id: str
    success: bool
    status: MergeStatus
    message: str
    validation_output: Optional[str] = None


class GitOverlord:
    """
    The invisible git manager.

    Responsibilities:
    - Monitor completed implementations
    - Run build validation in worktrees
    - Check for merge conflicts
    - Execute merges in safe order
    - Clean up after successful merges
    - Ask user only when ambiguity exists
    """

    def __init__(
        self,
        project_path: Path,
        main_branch: str = "main",
        build_command: Optional[str] = None,
        auto_merge: bool = False,
    ):
        self.project_path = project_path
        self.main_branch = main_branch
        self.build_command = build_command
        self.auto_merge = auto_merge
        self.worktree_base = project_path / ".forge-worktrees"

    async def get_worktrees(self) -> list[WorktreeInfo]:
        """Get all active worktrees."""
        result = await self._run_git(["worktree", "list", "--porcelain"])
        worktrees = []

        current_wt = {}
        for line in result.split("\n"):
            if line.startswith("worktree "):
                if current_wt and "path" in current_wt:
                    wt = self._parse_worktree(current_wt)
                    if wt:
                        worktrees.append(wt)
                current_wt = {"path": line.split(" ", 1)[1]}
            elif line.startswith("branch "):
                current_wt["branch"] = line.split(" ", 1)[1]

        # Parse last one
        if current_wt and "path" in current_wt:
            wt = self._parse_worktree(current_wt)
            if wt:
                worktrees.append(wt)

        return worktrees

    def _parse_worktree(self, wt_dict: dict) -> Optional[WorktreeInfo]:
        """Parse worktree info from git output."""
        path = Path(wt_dict.get("path", ""))
        branch = wt_dict.get("branch", "")

        # Skip main worktree
        if path == self.project_path:
            return None

        # Extract feature ID from path
        if not str(path).startswith(str(self.worktree_base)):
            return None

        feature_id = path.name

        return WorktreeInfo(
            feature_id=feature_id,
            path=path,
            branch=branch.replace("refs/heads/", ""),
            ahead_of_main=0,  # Will be populated separately
            has_uncommitted=False,
        )

    async def check_conflicts(self, feature_id: str) -> ConflictInfo:
        """Check if a feature has merge conflicts with main."""
        worktree_path = self.worktree_base / feature_id

        # Try a dry-run merge
        try:
            result = await self._run_git(
                ["merge", "--no-commit", "--no-ff", self.main_branch, "--quiet"],
                cwd=worktree_path,
            )

            # Abort the merge
            await self._run_git(["merge", "--abort"], cwd=worktree_path)

            return ConflictInfo(
                feature_id=feature_id,
                conflicting_files=[],
                can_auto_resolve=True,
                resolution_hint="No conflicts - ready to merge!",
            )

        except subprocess.CalledProcessError as e:
            # Parse conflict files
            status_result = await self._run_git(["status", "--porcelain"], cwd=worktree_path)
            conflicts = [
                line[3:] for line in status_result.split("\n")
                if line.startswith("UU ") or line.startswith("AA ")
            ]

            # Abort the merge
            try:
                await self._run_git(["merge", "--abort"], cwd=worktree_path)
            except Exception:
                pass

            return ConflictInfo(
                feature_id=feature_id,
                conflicting_files=conflicts,
                can_auto_resolve=len(conflicts) <= 2,  # Simple heuristic
                resolution_hint=self._get_resolution_hint(conflicts),
            )

    def _get_resolution_hint(self, conflicts: list[str]) -> str:
        """Generate a hint for resolving conflicts."""
        if not conflicts:
            return "No conflicts to resolve."

        if len(conflicts) == 1:
            return f"One file has conflicts: {conflicts[0]}. Review and choose which version to keep."

        return f"{len(conflicts)} files have conflicts. Review each and decide how to combine changes."

    async def merge_feature(
        self,
        feature_id: str,
        validate: bool = True,
        cleanup: bool = True,
    ) -> MergeResult:
        """Merge a feature into main."""
        worktree_path = self.worktree_base / feature_id

        # Step 1: Check for conflicts
        conflict_info = await self.check_conflicts(feature_id)
        if conflict_info.conflicting_files:
            return MergeResult(
                feature_id=feature_id,
                success=False,
                status=MergeStatus.CONFLICTS,
                message=f"Conflicts detected in {len(conflict_info.conflicting_files)} files",
            )

        # Step 2: Run validation if configured
        if validate and self.build_command:
            validation_output = await self._run_validation(worktree_path)
            if "FAILED" in validation_output or "error" in validation_output.lower():
                return MergeResult(
                    feature_id=feature_id,
                    success=False,
                    status=MergeStatus.FAILED,
                    message="Build validation failed",
                    validation_output=validation_output,
                )

        # Step 3: Perform the merge
        try:
            # Switch to main
            await self._run_git(["checkout", self.main_branch])

            # Merge the feature branch
            branch_name = f"feature/{feature_id}"
            await self._run_git(["merge", "--no-ff", branch_name, "-m", f"Merge {feature_id}"])

            # Step 4: Cleanup
            if cleanup:
                await self.cleanup_worktree(feature_id)

            return MergeResult(
                feature_id=feature_id,
                success=True,
                status=MergeStatus.MERGED,
                message=f"Successfully merged {feature_id} into {self.main_branch}",
            )

        except subprocess.CalledProcessError as e:
            return MergeResult(
                feature_id=feature_id,
                success=False,
                status=MergeStatus.FAILED,
                message=f"Merge failed: {str(e)}",
            )

    async def cleanup_worktree(self, feature_id: str):
        """Remove a worktree and its branch."""
        worktree_path = self.worktree_base / feature_id
        branch_name = f"feature/{feature_id}"

        # Remove worktree
        await self._run_git(["worktree", "remove", str(worktree_path), "--force"])

        # Delete branch
        try:
            await self._run_git(["branch", "-d", branch_name])
        except Exception:
            # Branch might already be deleted
            pass

    async def _run_validation(self, worktree_path: Path) -> str:
        """Run build validation in a worktree."""
        if not self.build_command:
            return "No build command configured"

        process = await asyncio.create_subprocess_shell(
            self.build_command,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.STDOUT,
            cwd=worktree_path,
        )

        stdout, _ = await process.communicate()
        return stdout.decode("utf-8", errors="replace")

    async def compute_merge_order(self, feature_ids: list[str]) -> list[str]:
        """Compute the safest order to merge features."""
        # For now, simple FIFO order
        # TODO: Analyze dependencies and potential conflicts
        return feature_ids

    async def merge_all_safe(self) -> list[MergeResult]:
        """Merge all features that are safe to merge."""
        worktrees = await self.get_worktrees()
        results = []

        for wt in worktrees:
            conflict_info = await self.check_conflicts(wt.feature_id)
            if not conflict_info.conflicting_files:
                result = await self.merge_feature(wt.feature_id)
                results.append(result)

        return results

    async def _run_git(
        self,
        args: list[str],
        cwd: Optional[Path] = None,
    ) -> str:
        """Run a git command."""
        cmd = ["git"] + args
        process = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            cwd=cwd or self.project_path,
        )

        stdout, stderr = await process.communicate()

        if process.returncode != 0:
            raise subprocess.CalledProcessError(
                process.returncode,
                cmd,
                stdout,
                stderr,
            )

        return stdout.decode("utf-8").strip()

    def get_status(self) -> dict:
        """Get overlord status synchronously."""
        return {
            "project": str(self.project_path),
            "main_branch": self.main_branch,
            "auto_merge": self.auto_merge,
            "build_command": self.build_command,
        }


class OverlordService:
    """
    Background service that monitors and manages merges.

    Runs continuously, checking for features ready to merge
    and handling them according to configuration.
    """

    def __init__(self, overlord: GitOverlord, check_interval: float = 30.0):
        self.overlord = overlord
        self.check_interval = check_interval
        self._running = False
        self._task: Optional[asyncio.Task] = None

    async def start(self):
        """Start the overlord service."""
        self._running = True
        self._task = asyncio.create_task(self._run_loop())

    async def stop(self):
        """Stop the overlord service."""
        self._running = False
        if self._task:
            self._task.cancel()
            try:
                await self._task
            except asyncio.CancelledError:
                pass

    async def _run_loop(self):
        """Main service loop."""
        while self._running:
            try:
                await self._check_and_merge()
            except Exception as e:
                print(f"GitOverlord error: {e}")

            await asyncio.sleep(self.check_interval)

    async def _check_and_merge(self):
        """Check for features ready to merge."""
        if not self.overlord.auto_merge:
            return

        worktrees = await self.overlord.get_worktrees()

        for wt in worktrees:
            conflict_info = await self.overlord.check_conflicts(wt.feature_id)

            if not conflict_info.conflicting_files:
                print(f"Auto-merging {wt.feature_id}...")
                result = await self.overlord.merge_feature(wt.feature_id)
                print(f"  {result.message}")


async def test_overlord():
    """Quick test of the Git Overlord."""
    overlord = GitOverlord(
        project_path=Path("/tmp/test-project"),
        main_branch="main",
    )

    print("Git Overlord Status:")
    print(overlord.get_status())


if __name__ == "__main__":
    asyncio.run(test_overlord())
