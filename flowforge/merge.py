"""
Merge orchestration for FlowForge.

Handles:
- Conflict detection (dry-run merges)
- Dependency-aware merge ordering
- Post-merge validation
- Automatic rollback on failure
- Conflict resolution prompt generation
"""

from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Optional
import subprocess

from .registry import Feature, FeatureRegistry, FeatureStatus


@dataclass
class MergeResult:
    """Result of a merge operation."""

    success: bool
    message: str
    feature_id: str
    conflict_files: list[str] = field(default_factory=list)
    needs_resolution: bool = False
    validation_output: Optional[str] = None


@dataclass
class ConflictInfo:
    """Information about merge conflicts."""

    files: list[str]
    feature_id: str
    feature_title: str
    branch: str


class MergeOrchestrator:
    """
    Orchestrates merging of feature branches into main.

    Key capabilities:
    - Dry-run conflict detection before actual merge
    - Topological sort for dependency-safe merge order
    - Post-merge build validation
    - Automatic rollback on validation failure
    - Conflict resolution prompt generation for Claude Code
    """

    def __init__(
        self,
        project_root: Path,
        registry: FeatureRegistry,
        main_branch: str = "main",
        build_command: Optional[str] = None,
    ):
        self.project_root = project_root
        self.registry = registry
        self.main_branch = main_branch
        self.build_command = build_command

    def _run_git(
        self,
        args: list[str],
        cwd: Optional[Path] = None,
        check: bool = True,
    ) -> subprocess.CompletedProcess:
        """Run a git command."""
        return subprocess.run(
            ["git"] + args,
            cwd=cwd or self.project_root,
            capture_output=True,
            text=True,
            check=check,
        )

    def sync_feature(self, feature_id: str) -> tuple[bool, str]:
        """
        Sync a feature branch with latest main (rebase).

        Returns (success, message).
        """
        feature = self.registry.get_feature(feature_id)
        if not feature:
            return False, f"Feature not found: {feature_id}"

        if not feature.worktree_path:
            return False, "Feature has no worktree. Run 'forge start' first."

        worktree = Path(feature.worktree_path)
        if not worktree.exists():
            return False, f"Worktree does not exist: {worktree}"

        # Check for uncommitted changes
        status = self._run_git(["status", "--porcelain"], cwd=worktree, check=False)
        if status.stdout.strip():
            return False, (
                "Uncommitted changes exist. Commit or stash first.\n\n"
                f"cd {worktree}\n"
                "git add -A && git commit -m 'WIP: save progress'"
            )

        # Fetch latest main
        self._run_git(["fetch", "origin", self.main_branch], check=False)

        # Rebase onto origin/main
        result = self._run_git(
            ["rebase", f"origin/{self.main_branch}"],
            cwd=worktree,
            check=False,
        )

        if result.returncode != 0:
            # Abort the failed rebase
            self._run_git(["rebase", "--abort"], cwd=worktree, check=False)
            return False, (
                f"Rebase conflict detected. Aborted.\n\n"
                f"To resolve manually:\n"
                f"  cd {worktree}\n"
                f"  git rebase origin/{self.main_branch}\n"
                f"  # resolve conflicts\n"
                f"  git rebase --continue"
            )

        return True, f"Successfully rebased {feature_id} onto {self.main_branch}."

    def check_conflicts(self, feature_id: str) -> MergeResult:
        """
        Dry-run merge to detect conflicts.

        Does NOT actually merge - just checks if it would succeed.
        """
        feature = self.registry.get_feature(feature_id)
        if not feature:
            return MergeResult(False, f"Feature not found: {feature_id}", feature_id)

        if not feature.branch:
            return MergeResult(False, "Feature has no branch", feature_id)

        # Ensure we're on main and up to date
        self._run_git(["checkout", self.main_branch], check=False)
        self._run_git(["pull", "origin", self.main_branch], check=False)

        # Attempt merge with --no-commit --no-ff
        result = self._run_git(
            ["merge", "--no-commit", "--no-ff", feature.branch],
            check=False,
        )

        # Get conflict files if any
        conflict_files = []
        if result.returncode != 0:
            diff_result = self._run_git(
                ["diff", "--name-only", "--diff-filter=U"],
                check=False,
            )
            conflict_files = [
                f for f in diff_result.stdout.strip().split("\n") if f.strip()
            ]

        # Abort the merge (cleanup)
        self._run_git(["merge", "--abort"], check=False)

        if conflict_files:
            return MergeResult(
                success=False,
                message=f"Conflicts detected in {len(conflict_files)} file(s)",
                feature_id=feature_id,
                conflict_files=conflict_files,
                needs_resolution=True,
            )

        return MergeResult(
            success=True,
            message="No conflicts detected. Ready to merge.",
            feature_id=feature_id,
        )

    def compute_merge_order(self) -> list[str]:
        """
        Compute safe merge order based on dependencies.

        Uses topological sort - features with no dependencies merge first.
        Only considers features in 'review' status.
        """
        features = self.registry.list_features(status=FeatureStatus.REVIEW)

        # Build dependency graph (only for features in review)
        review_ids = {f.id for f in features}
        graph = {}
        for f in features:
            # Only count dependencies that are also in review
            deps = [d for d in f.depends_on if d in review_ids]
            graph[f.id] = set(deps)

        # Kahn's algorithm for topological sort
        in_degree = {fid: 0 for fid in graph}
        for fid, deps in graph.items():
            for dep in deps:
                if dep in in_degree:
                    in_degree[fid] += 1

        # Start with features that have no in-review dependencies
        queue = [fid for fid, deg in in_degree.items() if deg == 0]
        order = []

        while queue:
            # Sort by priority for consistent ordering
            queue.sort(key=lambda fid: self.registry.get_feature(fid).priority)
            fid = queue.pop(0)
            order.append(fid)

            # Reduce in-degree for dependents
            for other_fid, deps in graph.items():
                if fid in deps:
                    in_degree[other_fid] -= 1
                    if in_degree[other_fid] == 0:
                        queue.append(other_fid)

        return order

    def merge_feature(
        self,
        feature_id: str,
        validate: bool = True,
        auto_cleanup: bool = True,
    ) -> MergeResult:
        """
        Execute merge of a feature into main.

        Steps:
        1. Check for conflicts (dry-run)
        2. Perform actual merge
        3. Run validation (build command) if configured
        4. Rollback if validation fails
        5. Update registry
        6. Clean up worktree if auto_cleanup
        """
        feature = self.registry.get_feature(feature_id)
        if not feature:
            return MergeResult(False, f"Feature not found: {feature_id}", feature_id)

        if not feature.branch:
            return MergeResult(False, "Feature has no branch", feature_id)

        # Pre-flight conflict check
        conflict_check = self.check_conflicts(feature_id)
        if not conflict_check.success:
            return conflict_check

        # Checkout main and update
        self._run_git(["checkout", self.main_branch])
        self._run_git(["pull", "origin", self.main_branch], check=False)

        # Perform actual merge
        merge_message = (
            f"Merge feature: {feature.title}\n\n"
            f"Feature ID: {feature_id}\n"
            f"Branch: {feature.branch}"
        )

        result = self._run_git(
            ["merge", "--no-ff", feature.branch, "-m", merge_message],
            check=False,
        )

        if result.returncode != 0:
            return MergeResult(
                success=False,
                message=f"Merge failed: {result.stderr}",
                feature_id=feature_id,
            )

        # Run validation if configured
        if validate and self.build_command:
            validation = subprocess.run(
                self.build_command,
                cwd=self.project_root,
                shell=True,
                capture_output=True,
                text=True,
            )

            if validation.returncode != 0:
                # Rollback merge
                self._run_git(["reset", "--hard", "HEAD~1"])
                return MergeResult(
                    success=False,
                    message=f"Validation failed, merge rolled back",
                    feature_id=feature_id,
                    validation_output=validation.stderr or validation.stdout,
                )

        # Update registry
        self.registry.update_feature(
            feature_id,
            status=FeatureStatus.COMPLETED,
            completed_at=datetime.now().isoformat(),
        )

        # Clean up worktree and branch
        if auto_cleanup and feature.worktree_path:
            worktree_path = Path(feature.worktree_path)
            if worktree_path.exists():
                self._run_git(
                    ["worktree", "remove", str(worktree_path)],
                    check=False,
                )
            # Delete the branch
            self._run_git(["branch", "-d", feature.branch], check=False)

            # Update registry to clear worktree path
            self.registry.update_feature(
                feature_id,
                worktree_path=None,
                branch=None,
            )

        return MergeResult(
            success=True,
            message=f"Successfully merged {feature.title} into {self.main_branch}",
            feature_id=feature_id,
        )

    def merge_all_safe(self, validate: bool = True) -> list[MergeResult]:
        """
        Merge all features that are ready and have no conflicts.

        Returns list of merge results.
        """
        order = self.compute_merge_order()
        results = []

        for feature_id in order:
            # Check conflicts first
            check = self.check_conflicts(feature_id)
            if not check.success:
                results.append(check)
                continue

            # Merge
            result = self.merge_feature(feature_id, validate=validate)
            results.append(result)

            # Stop on first failure
            if not result.success:
                break

        return results

    def generate_conflict_prompt(self, feature_id: str) -> str:
        """
        Generate a prompt for Claude Code to resolve conflicts.
        """
        feature = self.registry.get_feature(feature_id)
        if not feature:
            return f"Feature not found: {feature_id}"

        # Get conflict info
        check = self.check_conflicts(feature_id)
        if check.success:
            return "No conflicts to resolve."

        conflict_list = "\n".join(f"- `{f}`" for f in check.conflict_files)

        return f"""# Merge Conflict Resolution

You are resolving merge conflicts for feature: **{feature.title}**

## Conflicting Files
{conflict_list}

## Context
- Feature branch: `{feature.branch}`
- Target branch: `{self.main_branch}`
- Description: {feature.description}

## Instructions

1. Navigate to the worktree:
   ```bash
   cd {feature.worktree_path}
   ```

2. Start the merge:
   ```bash
   git fetch origin {self.main_branch}
   git merge origin/{self.main_branch}
   ```

3. For each conflicting file, resolve the conflicts by:
   - Keeping the feature's new functionality
   - Preserving any bug fixes from main
   - When in doubt, prefer both changes if they're in different areas

4. After resolving, complete the merge:
   ```bash
   git add -A
   git commit -m "fix: Resolve merge conflicts for {feature.title}"
   ```

5. Mark the feature as ready again:
   ```bash
   forge stop {feature_id}
   ```

## Resolution Strategy

Prefer the feature branch changes unless they conflict with critical bug fixes from main.
When unsure, preserve both changes if they affect different parts of the file.
"""
