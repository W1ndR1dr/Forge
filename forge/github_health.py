"""
GitHub Health Check - Validates git/GitHub setup for Forge.

Ensures worktrees will work by checking:
- Git repository exists
- Origin remote is configured
- SSH authentication works
- Main branch exists on remote
- Similar repos on GitHub (cleanup suggestions)
"""

import json
import subprocess
from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path
from typing import Optional


class HealthStatus(str, Enum):
    OK = "ok"
    WARNING = "warning"
    ERROR = "error"


@dataclass
class HealthCheck:
    """Result of a single health check."""
    name: str
    status: HealthStatus
    message: str
    auto_fixable: bool = False
    fix_command: Optional[str] = None


@dataclass
class SimilarRepo:
    """A potentially duplicate/related repo on GitHub."""
    name: str
    full_name: str
    description: Optional[str]
    url: str
    similarity_reason: str
    pushed_at: Optional[str] = None


@dataclass
class HealthReport:
    """Complete health check report."""
    overall_status: HealthStatus
    checks: list[HealthCheck] = field(default_factory=list)
    auto_fix_available: list[str] = field(default_factory=list)
    similar_repos: list[SimilarRepo] = field(default_factory=list)

    def to_dict(self) -> dict:
        return {
            "overall_status": self.overall_status.value,
            "checks": {
                c.name: {
                    "status": c.status.value,
                    "message": c.message,
                    "auto_fixable": c.auto_fixable,
                }
                for c in self.checks
            },
            "auto_fix_available": self.auto_fix_available,
            "similar_repos": [
                {
                    "name": r.name,
                    "full_name": r.full_name,
                    "description": r.description,
                    "url": r.url,
                    "reason": r.similarity_reason,
                }
                for r in self.similar_repos
            ],
        }


class GitHubHealthChecker:
    """
    Validates git/GitHub setup and suggests fixes.

    Usage:
        checker = GitHubHealthChecker(Path("/path/to/project"))
        report = checker.run_all_checks()

        if report.auto_fix_available:
            checker.auto_fix(report.auto_fix_available)
    """

    def __init__(self, project_path: Path):
        self.project_path = project_path.resolve()
        self.project_name = self.project_path.name

    def run_all_checks(self) -> HealthReport:
        """Run all health checks and return a comprehensive report."""
        checks = []

        # 1. Check git repo exists
        git_check = self._check_git_repo()
        checks.append(git_check)

        if git_check.status == HealthStatus.ERROR:
            # Can't continue without git
            return HealthReport(
                overall_status=HealthStatus.ERROR,
                checks=checks,
            )

        # 2. Check origin remote
        origin_check = self._check_origin_remote()
        checks.append(origin_check)

        # 3. Check main branch
        main_check = self._check_main_branch()
        checks.append(main_check)

        # 4. Check remote accessibility (only if origin exists)
        if origin_check.status == HealthStatus.OK:
            remote_check = self._check_remote_accessible()
            checks.append(remote_check)

            # Only check SSH auth for SSH-based origins (not HTTPS)
            origin_url = origin_check.message.replace("Origin: ", "")
            if origin_url.startswith("git@") or "ssh://" in origin_url:
                ssh_check = self._check_ssh_auth()
                checks.append(ssh_check)

        # Determine overall status
        statuses = [c.status for c in checks]
        if HealthStatus.ERROR in statuses:
            overall = HealthStatus.ERROR
        elif HealthStatus.WARNING in statuses:
            overall = HealthStatus.WARNING
        else:
            overall = HealthStatus.OK

        # Collect auto-fixable issues
        auto_fix = [c.name for c in checks if c.auto_fixable]

        return HealthReport(
            overall_status=overall,
            checks=checks,
            auto_fix_available=auto_fix,
        )

    def _run_git(self, *args: str, check: bool = False) -> subprocess.CompletedProcess:
        """Run a git command in the project directory."""
        return subprocess.run(
            ["git", *args],
            cwd=self.project_path,
            capture_output=True,
            text=True,
            check=check,
        )

    def _run_gh(self, *args: str) -> subprocess.CompletedProcess:
        """Run a gh CLI command."""
        return subprocess.run(
            ["gh", *args],
            capture_output=True,
            text=True,
        )

    # =========================================================================
    # Individual Health Checks
    # =========================================================================

    def _check_git_repo(self) -> HealthCheck:
        """Check if this is a valid git repository."""
        git_dir = self.project_path / ".git"

        if not git_dir.exists():
            return HealthCheck(
                name="git_repo",
                status=HealthStatus.ERROR,
                message="Not a git repository. Run 'git init' first.",
                auto_fixable=True,
                fix_command="git init",
            )

        # Verify it's valid
        result = self._run_git("rev-parse", "--git-dir")
        if result.returncode != 0:
            return HealthCheck(
                name="git_repo",
                status=HealthStatus.ERROR,
                message="Invalid git repository.",
            )

        return HealthCheck(
            name="git_repo",
            status=HealthStatus.OK,
            message="Valid git repository.",
        )

    def _check_origin_remote(self) -> HealthCheck:
        """Check if origin remote is configured."""
        result = self._run_git("remote", "get-url", "origin")

        if result.returncode != 0:
            return HealthCheck(
                name="origin_remote",
                status=HealthStatus.ERROR,
                message="No 'origin' remote configured.",
                auto_fixable=True,
                fix_command=f"git remote add origin git@github.com:USER/{self.project_name}.git",
            )

        origin_url = result.stdout.strip()

        # Check if it looks like a GitHub URL
        if "github.com" not in origin_url:
            return HealthCheck(
                name="origin_remote",
                status=HealthStatus.WARNING,
                message=f"Origin points to non-GitHub remote: {origin_url}",
            )

        return HealthCheck(
            name="origin_remote",
            status=HealthStatus.OK,
            message=f"Origin: {origin_url}",
        )

    def _check_main_branch(self) -> HealthCheck:
        """Check if main/master branch exists."""
        # Try to detect the default branch
        for branch in ["main", "master"]:
            result = self._run_git("rev-parse", "--verify", branch)
            if result.returncode == 0:
                return HealthCheck(
                    name="main_branch",
                    status=HealthStatus.OK,
                    message=f"Default branch: {branch}",
                )

        # Check if there are any branches at all
        result = self._run_git("branch", "--list")
        if not result.stdout.strip():
            return HealthCheck(
                name="main_branch",
                status=HealthStatus.WARNING,
                message="No branches exist. Make an initial commit.",
                auto_fixable=False,
            )

        # There are branches, just not main/master
        branches = result.stdout.strip()
        return HealthCheck(
            name="main_branch",
            status=HealthStatus.WARNING,
            message=f"No 'main' or 'master' branch. Found: {branches}",
        )

    def _check_remote_accessible(self) -> HealthCheck:
        """Check if we can reach the remote."""
        result = self._run_git("ls-remote", "--exit-code", "origin", "HEAD")

        if result.returncode != 0:
            error = result.stderr.strip()
            if "Permission denied" in error or "publickey" in error:
                return HealthCheck(
                    name="remote_accessible",
                    status=HealthStatus.ERROR,
                    message="Cannot access remote: SSH key issue.",
                )
            elif "Repository not found" in error:
                return HealthCheck(
                    name="remote_accessible",
                    status=HealthStatus.ERROR,
                    message="Remote repository not found on GitHub.",
                    auto_fixable=True,
                    fix_command=f"gh repo create {self.project_name} --private --source=.",
                )
            else:
                return HealthCheck(
                    name="remote_accessible",
                    status=HealthStatus.ERROR,
                    message=f"Cannot access remote: {error}",
                )

        return HealthCheck(
            name="remote_accessible",
            status=HealthStatus.OK,
            message="Remote is accessible.",
        )

    def _check_ssh_auth(self) -> HealthCheck:
        """Check if SSH authentication to GitHub works."""
        result = subprocess.run(
            ["ssh", "-T", "git@github.com"],
            capture_output=True,
            text=True,
        )

        # GitHub returns exit code 1 even on success with a greeting
        output = result.stderr.strip()
        if "successfully authenticated" in output.lower():
            return HealthCheck(
                name="ssh_auth",
                status=HealthStatus.OK,
                message="SSH authentication working.",
            )
        elif "permission denied" in output.lower():
            return HealthCheck(
                name="ssh_auth",
                status=HealthStatus.ERROR,
                message="SSH key not configured for GitHub.",
            )
        else:
            # Connection issue or other problem
            return HealthCheck(
                name="ssh_auth",
                status=HealthStatus.WARNING,
                message=f"SSH status unclear: {output[:100]}",
            )

    # =========================================================================
    # Auto-Fix
    # =========================================================================

    def auto_fix(self, issues: list[str]) -> dict[str, bool]:
        """
        Attempt to automatically fix identified issues.

        Returns dict of {issue_name: success}.
        """
        results = {}

        for issue in issues:
            if issue == "git_repo":
                results[issue] = self._fix_git_init()
            elif issue == "origin_remote":
                results[issue] = self._fix_origin_remote()
            elif issue == "remote_accessible":
                results[issue] = self._fix_create_repo()
            else:
                results[issue] = False

        return results

    def _fix_git_init(self) -> bool:
        """Initialize git repository."""
        result = self._run_git("init")
        return result.returncode == 0

    def _fix_origin_remote(self) -> bool:
        """
        Add origin remote.

        Tries to detect GitHub username from gh CLI.
        """
        # Get GitHub username
        result = self._run_gh("api", "user", "--jq", ".login")
        if result.returncode != 0:
            return False

        username = result.stdout.strip()
        if not username:
            return False

        # Add origin
        origin_url = f"git@github.com:{username}/{self.project_name}.git"
        result = self._run_git("remote", "add", "origin", origin_url)

        return result.returncode == 0

    def _fix_create_repo(self) -> bool:
        """Create GitHub repository using gh CLI."""
        result = self._run_gh(
            "repo", "create", self.project_name,
            "--private",
            "--source", str(self.project_path),
            "--push",
        )
        return result.returncode == 0

    # =========================================================================
    # Similar Repo Detection
    # =========================================================================

    def find_similar_repos(self) -> list[SimilarRepo]:
        """
        Find similar/duplicate repos on GitHub.

        Uses simple name matching. For LLM-powered analysis,
        call analyze_similar_repos() with the results.
        """
        # Get user's repos via gh CLI
        result = self._run_gh(
            "repo", "list",
            "--json", "name,nameWithOwner,description,url,pushedAt",
            "--limit", "100",
        )

        if result.returncode != 0:
            return []

        try:
            repos = json.loads(result.stdout)
        except json.JSONDecodeError:
            return []

        similar = []
        project_lower = self.project_name.lower()

        for repo in repos:
            name = repo.get("name", "")
            name_lower = name.lower()

            # Skip exact match (current project)
            if name_lower == project_lower:
                continue

            # Check for similarity
            similarity_reason = None

            # Name contains project name
            if project_lower in name_lower or name_lower in project_lower:
                similarity_reason = "Name contains similar words"

            # Levenshtein-like check (simple version)
            elif self._names_similar(project_lower, name_lower):
                similarity_reason = "Similar spelling"

            # Check for common patterns (old, v2, ios, etc.)
            elif self._is_variant(project_lower, name_lower):
                similarity_reason = "Appears to be a variant/fork"

            if similarity_reason:
                similar.append(SimilarRepo(
                    name=name,
                    full_name=repo.get("nameWithOwner", name),
                    description=repo.get("description"),
                    url=repo.get("url", ""),
                    similarity_reason=similarity_reason,
                    pushed_at=repo.get("pushedAt"),
                ))

        return similar

    def _names_similar(self, name1: str, name2: str) -> bool:
        """Simple similarity check based on character overlap."""
        # If more than 70% of characters match, consider similar
        if len(name1) < 3 or len(name2) < 3:
            return False

        set1 = set(name1.replace("-", "").replace("_", ""))
        set2 = set(name2.replace("-", "").replace("_", ""))

        intersection = set1 & set2
        union = set1 | set2

        if not union:
            return False

        similarity = len(intersection) / len(union)
        return similarity > 0.7

    def _is_variant(self, project: str, other: str) -> bool:
        """Check if other is a variant of project (old, v2, ios, etc.)."""
        variants = ["-old", "-new", "-v2", "-v1", "-ios", "-macos", "-app", "-cli"]

        for variant in variants:
            if other == project + variant or other == project.replace("-", "") + variant:
                return True
            if project == other + variant or project == other.replace("-", "") + variant:
                return True

        return False


def check_github_health(project_path: Path) -> HealthReport:
    """
    Convenience function to run all health checks.

    Usage:
        from forge.github_health import check_github_health

        report = check_github_health(Path("/path/to/project"))
        if report.overall_status != HealthStatus.OK:
            print("Issues found:", report.to_dict())
    """
    checker = GitHubHealthChecker(project_path)
    report = checker.run_all_checks()

    # Also check for similar repos
    similar = checker.find_similar_repos()
    report.similar_repos = similar

    return report
