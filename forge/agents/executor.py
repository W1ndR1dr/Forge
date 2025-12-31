"""
AutoExecutor - Spawns and manages Claude Code sessions for implementation.

This agent handles the parallel execution of features, creating worktrees,
spawning Claude Code sessions, and monitoring their progress.
"""

import asyncio
import json
import os
import subprocess
from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from pathlib import Path
from typing import AsyncGenerator, Callable, Optional

from .prompts import EXECUTOR_SYSTEM_PROMPT


class ExecutionStatus(Enum):
    PENDING = "pending"
    CREATING_WORKTREE = "creating_worktree"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"


@dataclass
class ExecutionProgress:
    """Progress update from an execution."""
    feature_id: str
    status: ExecutionStatus
    message: str
    output_chunk: Optional[str] = None
    timestamp: datetime = field(default_factory=datetime.now)

    def to_dict(self) -> dict:
        return {
            "feature_id": self.feature_id,
            "status": self.status.value,
            "message": self.message,
            "output_chunk": self.output_chunk,
            "timestamp": self.timestamp.isoformat(),
        }


@dataclass
class ExecutionResult:
    """Final result of a feature execution."""
    feature_id: str
    success: bool
    files_changed: list[str]
    summary: str
    error: Optional[str] = None

    def to_dict(self) -> dict:
        return {
            "feature_id": self.feature_id,
            "success": self.success,
            "files_changed": self.files_changed,
            "summary": self.summary,
            "error": self.error,
        }


@dataclass
class ActiveExecution:
    """An actively running execution."""
    feature_id: str
    process: asyncio.subprocess.Process
    worktree_path: Path
    started_at: datetime = field(default_factory=datetime.now)
    output_buffer: list[str] = field(default_factory=list)


class ParallelExecutionManager:
    """
    Manages multiple parallel Claude Code executions.

    Limits concurrent executions (default 5) and queues additional requests.
    """

    def __init__(self, max_concurrent: int = 5):
        self.max_concurrent = max_concurrent
        self.active_executions: dict[str, ActiveExecution] = {}
        self.pending_queue: list[tuple[str, str, Path]] = []  # (feature_id, spec, project_path)
        self._lock = asyncio.Lock()

    @property
    def running_count(self) -> int:
        return len(self.active_executions)

    @property
    def queue_length(self) -> int:
        return len(self.pending_queue)

    def can_start(self) -> bool:
        return self.running_count < self.max_concurrent

    async def enqueue(
        self,
        feature_id: str,
        spec: str,
        project_path: Path,
    ) -> bool:
        """Add a feature to the execution queue."""
        async with self._lock:
            if feature_id in self.active_executions:
                return False  # Already running

            self.pending_queue.append((feature_id, spec, project_path))
            return True

    async def get_next(self) -> Optional[tuple[str, str, Path]]:
        """Get the next pending execution if slots available."""
        async with self._lock:
            if not self.can_start() or not self.pending_queue:
                return None
            return self.pending_queue.pop(0)

    async def register_active(
        self,
        feature_id: str,
        process: asyncio.subprocess.Process,
        worktree_path: Path,
    ):
        """Register an execution as active."""
        async with self._lock:
            self.active_executions[feature_id] = ActiveExecution(
                feature_id=feature_id,
                process=process,
                worktree_path=worktree_path,
            )

    async def unregister(self, feature_id: str):
        """Remove an execution from active list."""
        async with self._lock:
            if feature_id in self.active_executions:
                del self.active_executions[feature_id]

    def get_status(self) -> dict:
        """Get current execution manager status."""
        return {
            "active_count": self.running_count,
            "max_concurrent": self.max_concurrent,
            "queue_length": self.queue_length,
            "active_features": list(self.active_executions.keys()),
        }


class AutoExecutor:
    """
    Executes feature implementations using Claude Code.

    For each feature:
    1. Creates a git worktree (via SSH to Mac if remote)
    2. Spawns Claude Code with the spec
    3. Streams output back
    4. Detects completion
    5. Notifies Git Overlord
    """

    def __init__(
        self,
        project_path: Path,
        main_branch: str = "main",
        ssh_host: Optional[str] = None,
        ssh_user: Optional[str] = None,
        max_parallel: int = 5,
    ):
        self.project_path = project_path
        self.main_branch = main_branch
        self.ssh_host = ssh_host
        self.ssh_user = ssh_user
        self.manager = ParallelExecutionManager(max_parallel)
        self.on_progress: Optional[Callable[[ExecutionProgress], None]] = None
        self.on_complete: Optional[Callable[[ExecutionResult], None]] = None

    async def execute_feature(
        self,
        feature_id: str,
        spec: str,
        project_name: str,
    ) -> AsyncGenerator[ExecutionProgress, None]:
        """
        Execute a feature and stream progress.

        Yields ExecutionProgress updates as the execution proceeds.
        """
        # Check if we can start
        if not self.manager.can_start():
            await self.manager.enqueue(feature_id, spec, self.project_path)
            yield ExecutionProgress(
                feature_id=feature_id,
                status=ExecutionStatus.PENDING,
                message=f"Queued (position {self.manager.queue_length})",
            )
            return

        # Step 1: Create worktree
        yield ExecutionProgress(
            feature_id=feature_id,
            status=ExecutionStatus.CREATING_WORKTREE,
            message="Creating isolated workspace...",
        )

        worktree_path = await self._create_worktree(feature_id)

        # Step 2: Build the implementation prompt
        prompt = self._build_prompt(spec, project_name)

        # Step 3: Launch Claude Code
        yield ExecutionProgress(
            feature_id=feature_id,
            status=ExecutionStatus.RUNNING,
            message="Claude is implementing the feature...",
        )

        # Build command
        cmd = [
            "claude",
            "--dangerously-skip-permissions",
            "-p", prompt,
        ]

        # If remote, wrap in SSH
        if self.ssh_host and self.ssh_user:
            cmd = [
                "ssh",
                f"{self.ssh_user}@{self.ssh_host}",
                f"cd {worktree_path} && {' '.join(cmd)}",
            ]
            cwd = None
        else:
            cwd = worktree_path

        # Launch process
        process = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.STDOUT,
            cwd=cwd,
        )

        await self.manager.register_active(feature_id, process, worktree_path)

        # Stream output
        output_buffer = []
        try:
            while True:
                line = await process.stdout.readline()
                if not line:
                    break

                text = line.decode("utf-8", errors="replace")
                output_buffer.append(text)

                yield ExecutionProgress(
                    feature_id=feature_id,
                    status=ExecutionStatus.RUNNING,
                    message="Implementing...",
                    output_chunk=text,
                )

                # Check for completion marker
                if "IMPLEMENTATION_COMPLETE" in text:
                    break

            await process.wait()

        finally:
            await self.manager.unregister(feature_id)

        # Parse result
        full_output = "".join(output_buffer)
        result = self._parse_completion(feature_id, full_output, process.returncode == 0)

        if result.success:
            yield ExecutionProgress(
                feature_id=feature_id,
                status=ExecutionStatus.COMPLETED,
                message=f"Implementation complete! {len(result.files_changed)} files changed.",
            )
        else:
            yield ExecutionProgress(
                feature_id=feature_id,
                status=ExecutionStatus.FAILED,
                message=result.error or "Implementation failed",
            )

        # Notify callbacks
        if self.on_complete:
            self.on_complete(result)

    async def _create_worktree(self, feature_id: str) -> Path:
        """Create a git worktree for the feature."""
        worktree_base = self.project_path / ".forge-worktrees"
        worktree_path = worktree_base / feature_id
        branch_name = f"feature/{feature_id}"

        if worktree_path.exists():
            return worktree_path

        # Build git commands
        cmds = [
            ["git", "worktree", "add", "-b", branch_name, str(worktree_path), self.main_branch],
        ]

        for cmd in cmds:
            if self.ssh_host and self.ssh_user:
                cmd = [
                    "ssh",
                    f"{self.ssh_user}@{self.ssh_host}",
                    f"cd {self.project_path} && {' '.join(cmd)}",
                ]

            process = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                cwd=self.project_path if not self.ssh_host else None,
            )
            await process.communicate()

        return worktree_path

    def _build_prompt(self, spec: str, project_name: str) -> str:
        """Build the full implementation prompt."""
        return EXECUTOR_SYSTEM_PROMPT.format(
            project_name=project_name,
            spec=spec,
        )

    def _parse_completion(
        self,
        feature_id: str,
        output: str,
        success: bool,
    ) -> ExecutionResult:
        """Parse the completion output to extract results."""
        files_changed = []
        summary = ""

        if "IMPLEMENTATION_COMPLETE" in output:
            # Parse files changed
            import re
            files_match = re.search(
                r"Files changed:\s*\n((?:- .+\n?)+)",
                output,
                re.MULTILINE,
            )
            if files_match:
                files_text = files_match.group(1)
                files_changed = [
                    line.strip().lstrip("- ")
                    for line in files_text.split("\n")
                    if line.strip()
                ]

            # Parse summary
            summary_match = re.search(
                r"What was built:\s*\n(.+?)(?=\n\n|How to verify:|$)",
                output,
                re.DOTALL,
            )
            if summary_match:
                summary = summary_match.group(1).strip()

        return ExecutionResult(
            feature_id=feature_id,
            success=success and "IMPLEMENTATION_COMPLETE" in output,
            files_changed=files_changed,
            summary=summary or "Feature implemented",
            error=None if success else "Execution failed or incomplete",
        )

    def get_status(self) -> dict:
        """Get current executor status."""
        return self.manager.get_status()


async def test_executor():
    """Quick test of the executor."""
    executor = AutoExecutor(
        project_path=Path("/tmp/test-project"),
        main_branch="main",
    )

    test_spec = """
FEATURE: Test Feature

WHAT IT DOES:
Creates a simple test file.

HOW IT WORKS:
- Creates test.txt with "Hello, World!"
"""

    print("Testing executor...")
    async for progress in executor.execute_feature("test-feature", test_spec, "TestProject"):
        print(f"[{progress.status.value}] {progress.message}")
        if progress.output_chunk:
            print(f"  > {progress.output_chunk.strip()}")


if __name__ == "__main__":
    asyncio.run(test_executor())
