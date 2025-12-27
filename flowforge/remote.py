"""
Remote execution for FlowForge.

This module enables FlowForge running on a Raspberry Pi to execute
commands on a remote Mac via SSH over Tailscale.

Why this exists:
- Git worktrees need to be created on the Mac where Claude Code runs
- The FlowForge server can run on a Pi for always-on availability
- SSH over Tailscale provides secure, reliable connectivity

Usage:
    executor = RemoteExecutor("mac.tailnet", "brian")
    result = executor.run_command(["forge", "start", "feature-id"], cwd="/Users/brian/Projects/AirFit")
"""

from dataclasses import dataclass
from pathlib import Path
from typing import Optional
import subprocess
import shlex


@dataclass
class RemoteResult:
    """Result from a remote command execution."""

    returncode: int
    stdout: str
    stderr: str

    @property
    def success(self) -> bool:
        return self.returncode == 0


class RemoteExecutor:
    """
    Execute commands on a remote Mac via SSH.

    Designed for use over Tailscale - assumes SSH keys are configured
    and the remote host is reachable via Tailscale hostname.
    """

    def __init__(
        self,
        host: str,
        user: str,
        ssh_key: Optional[Path] = None,
        connect_timeout: int = 10,
    ):
        """
        Initialize the remote executor.

        Args:
            host: SSH hostname (e.g., "mac.tailnet" or Tailscale IP)
            user: SSH username
            ssh_key: Optional path to SSH private key
            connect_timeout: SSH connection timeout in seconds
        """
        self.host = host
        self.user = user
        self.ssh_key = ssh_key
        self.connect_timeout = connect_timeout

    def _build_ssh_command(self) -> list[str]:
        """Build the base SSH command with options."""
        cmd = [
            "ssh",
            "-o", f"ConnectTimeout={self.connect_timeout}",
            "-o", "BatchMode=yes",  # Fail rather than prompt for password
            "-o", "StrictHostKeyChecking=accept-new",  # Auto-accept new hosts
        ]

        if self.ssh_key:
            cmd.extend(["-i", str(self.ssh_key)])

        cmd.append(f"{self.user}@{self.host}")

        return cmd

    def run_command(
        self,
        command: list[str],
        cwd: Optional[Path] = None,
        env: Optional[dict[str, str]] = None,
        timeout: int = 120,
    ) -> RemoteResult:
        """
        Execute a command on the remote Mac.

        Args:
            command: Command and arguments to execute
            cwd: Working directory on remote machine
            env: Environment variables to set
            timeout: Command timeout in seconds

        Returns:
            RemoteResult with returncode, stdout, stderr
        """
        # Build the remote command
        # Simple case: no cwd or env - just quote and run
        if not cwd and not env:
            remote_cmd = " ".join(shlex.quote(arg) for arg in command)
        else:
            # Complex case: need cd/export - use bash -c
            remote_cmd_parts = []

            # Change directory if specified
            if cwd:
                remote_cmd_parts.append(f"cd {shlex.quote(str(cwd))}")

            # Set environment variables
            if env:
                for key, value in env.items():
                    remote_cmd_parts.append(f"export {key}={shlex.quote(value)}")

            # Add the actual command
            remote_cmd_parts.append(" ".join(shlex.quote(arg) for arg in command))

            # Combine with && and wrap in bash -c
            inner_cmd = " && ".join(remote_cmd_parts)
            remote_cmd = f"bash -c {shlex.quote(inner_cmd)}"

        # Build full SSH command
        ssh_cmd = self._build_ssh_command()
        ssh_cmd.append(remote_cmd)

        try:
            result = subprocess.run(
                ssh_cmd,
                capture_output=True,
                text=True,
                timeout=timeout,
            )

            return RemoteResult(
                returncode=result.returncode,
                stdout=result.stdout,
                stderr=result.stderr,
            )
        except subprocess.TimeoutExpired:
            return RemoteResult(
                returncode=-1,
                stdout="",
                stderr=f"Command timed out after {timeout} seconds",
            )
        except Exception as e:
            return RemoteResult(
                returncode=-1,
                stdout="",
                stderr=f"SSH execution failed: {str(e)}",
            )

    def run_forge_command(
        self,
        project_path: Path,
        args: list[str],
        timeout: int = 120,
    ) -> RemoteResult:
        """
        Run a FlowForge command on the remote Mac.

        Args:
            project_path: Path to the project on the remote Mac
            args: Arguments to pass to `forge` command
            timeout: Command timeout in seconds

        Returns:
            RemoteResult
        """
        # Activate venv and run forge
        # Assumes forge is installed in the project's venv or globally
        command = ["forge"] + args

        return self.run_command(
            command,
            cwd=project_path,
            timeout=timeout,
        )

    def test_connection(self) -> tuple[bool, str]:
        """
        Test SSH connection to remote host.

        Returns:
            (success, message)
        """
        result = self.run_command(["echo", "FlowForge connection test"], timeout=15)

        if result.success:
            return True, f"Connected to {self.user}@{self.host}"
        else:
            return False, f"Connection failed: {result.stderr}"

    def get_projects(self, projects_base: Path) -> list[dict]:
        """
        List FlowForge-initialized projects on the remote Mac.

        Args:
            projects_base: Base directory containing projects

        Returns:
            List of project info dicts
        """
        # Find directories with .flowforge
        result = self.run_command(
            ["find", str(projects_base), "-maxdepth", "2", "-name", ".flowforge", "-type", "d"],
            timeout=30,
        )

        if not result.success:
            return []

        projects = []
        for line in result.stdout.strip().split("\n"):
            if not line:
                continue

            project_path = Path(line).parent
            projects.append({
                "name": project_path.name,
                "path": str(project_path),
            })

        return projects

    def read_file(self, file_path: Path) -> Optional[str]:
        """
        Read a file from the remote Mac.

        Args:
            file_path: Path to file on remote Mac

        Returns:
            File contents or None if read fails
        """
        result = self.run_command(["cat", str(file_path)], timeout=10)
        if result.success:
            return result.stdout
        return None

    def file_exists(self, file_path: Path) -> bool:
        """Check if a file exists on the remote Mac."""
        result = self.run_command(["test", "-f", str(file_path)], timeout=5)
        return result.success

    def dir_exists(self, dir_path: Path) -> bool:
        """Check if a directory exists on the remote Mac."""
        result = self.run_command(["test", "-d", str(dir_path)], timeout=5)
        return result.success

    def write_file(self, file_path: Path, content: str) -> RemoteResult:
        """
        Write content to a file on the remote Mac.

        Uses base64 encoding to safely transfer content via SSH.

        Args:
            file_path: Path to file on remote Mac
            content: Content to write

        Returns:
            RemoteResult with success status
        """
        import base64
        import shlex

        # Base64 encode to avoid shell escaping issues
        encoded = base64.b64encode(content.encode()).decode()

        # Ensure parent directory exists
        self.run_command(["mkdir", "-p", str(file_path.parent)], timeout=10)

        # Write via base64 decode
        result = self.run_command(
            ["bash", "-c", f"echo {shlex.quote(encoded)} | base64 -d > {shlex.quote(str(file_path))}"],
            timeout=30,
        )
        return result

    # Git-specific operations for worktree management

    def run_git_command(
        self,
        project_path: Path,
        git_args: list[str],
        timeout: int = 60,
    ) -> RemoteResult:
        """
        Run a git command on the remote Mac.

        Args:
            project_path: Path to the git repository
            git_args: Arguments to pass to git (e.g., ["status", "-s"])
            timeout: Command timeout in seconds

        Returns:
            RemoteResult
        """
        command = ["git"] + git_args
        return self.run_command(command, cwd=project_path, timeout=timeout)

    def create_worktree(
        self,
        project_path: Path,
        worktree_path: Path,
        branch_name: str,
        create_branch: bool = True,
        timeout: int = 60,
    ) -> RemoteResult:
        """
        Create a git worktree on the remote Mac.

        Args:
            project_path: Path to the main git repository
            worktree_path: Path where the worktree should be created
            branch_name: Name of the branch for the worktree
            create_branch: If True, create a new branch (-b flag)
            timeout: Command timeout in seconds

        Returns:
            RemoteResult with success status
        """
        git_args = ["worktree", "add"]
        if create_branch:
            git_args.extend(["-b", branch_name])
        git_args.append(str(worktree_path))
        if not create_branch:
            git_args.append(branch_name)

        return self.run_git_command(project_path, git_args, timeout=timeout)

    def remove_worktree(
        self,
        project_path: Path,
        worktree_path: Path,
        force: bool = False,
        timeout: int = 60,
    ) -> RemoteResult:
        """
        Remove a git worktree on the remote Mac.

        Args:
            project_path: Path to the main git repository
            worktree_path: Path to the worktree to remove
            force: If True, use --force flag
            timeout: Command timeout in seconds

        Returns:
            RemoteResult with success status
        """
        git_args = ["worktree", "remove"]
        if force:
            git_args.append("--force")
        git_args.append(str(worktree_path))

        return self.run_git_command(project_path, git_args, timeout=timeout)

    def list_worktrees(self, project_path: Path, timeout: int = 30) -> RemoteResult:
        """
        List git worktrees on the remote Mac.

        Args:
            project_path: Path to the git repository

        Returns:
            RemoteResult with worktree list in stdout (porcelain format)
        """
        return self.run_git_command(
            project_path,
            ["worktree", "list", "--porcelain"],
            timeout=timeout,
        )

    def get_merged_branches(
        self,
        project_path: Path,
        main_branch: str = "main",
        timeout: int = 30,
    ) -> RemoteResult:
        """
        Get branches that have been merged into the main branch.

        Args:
            project_path: Path to the git repository
            main_branch: Name of the main branch

        Returns:
            RemoteResult with merged branch names in stdout
        """
        return self.run_git_command(
            project_path,
            ["branch", "--merged", main_branch],
            timeout=timeout,
        )

    def check_merge_conflicts(
        self,
        project_path: Path,
        branch_name: str,
        timeout: int = 60,
    ) -> RemoteResult:
        """
        Check if merging a branch would cause conflicts (dry-run).

        Args:
            project_path: Path to the git repository
            branch_name: Branch to check for conflicts

        Returns:
            RemoteResult - success means no conflicts
        """
        # Do a dry-run merge: merge --no-commit --no-ff, then abort
        # This is safer than actual merge testing
        result = self.run_git_command(
            project_path,
            ["merge", "--no-commit", "--no-ff", branch_name],
            timeout=timeout,
        )

        # Always abort the merge (whether it succeeded or failed)
        self.run_git_command(project_path, ["merge", "--abort"], timeout=10)

        return result
