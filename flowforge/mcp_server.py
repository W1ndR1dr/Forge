"""
FlowForge MCP Server - Remote MCP integration for Claude Code.

This module implements a Model Context Protocol (MCP) server that allows
Claude Code (on iOS, web, or anywhere) to natively control FlowForge.

The server exposes tools for:
- Listing projects and features
- Starting/stopping feature development
- Checking merge conflicts
- Executing merges

When deployed on a Raspberry Pi with Tailscale, this enables full
FlowForge functionality from Claude Code on iPhone.

Architecture (Pi-native):
- Registry operations (list, add, update, delete) run locally on Pi
- Git operations (start, stop, merge) require Mac via SSH
- This allows idea capture even when MacBook is asleep
"""

from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Optional
import json

from .config import FlowForgeConfig
from .registry import FeatureRegistry, FeatureStatus, Feature, Complexity
from .prompt_builder import PromptBuilder
from .intelligence import IntelligenceEngine
from .remote import RemoteExecutor
from .pi_registry import PiRegistryManager, get_pi_registry_manager


@dataclass
class MCPToolResult:
    """Result from an MCP tool call."""

    success: bool
    message: str
    data: Optional[dict] = None


class FlowForgeMCPServer:
    """
    MCP Server implementation for FlowForge.

    This server runs on a Raspberry Pi and is accessed by Claude Code (iOS/Mac)
    via Remote MCP Server configuration.

    Architecture:
    - Registry operations (list, add, update, delete) use Pi-local storage
    - Git operations (start, stop, merge) require Mac via SSH
    """

    def __init__(
        self,
        projects_base: Path,
        remote_host: Optional[str] = None,
        remote_user: Optional[str] = None,
        pi_registry: Optional[PiRegistryManager] = None,
    ):
        """
        Initialize the MCP server.

        Args:
            projects_base: Base directory containing FlowForge projects (Mac path)
            remote_host: SSH host for Mac (for git operations)
            remote_user: SSH username for Mac
            pi_registry: Pi-local registry manager (created if not provided)
        """
        self.projects_base = Path(projects_base)
        self.remote_host = remote_host
        self.remote_user = remote_user

        # Pi-local registry manager (for offline-capable registry operations)
        self.pi_registry = pi_registry or get_pi_registry_manager()

        # Remote executor for Pi → Mac SSH operations (git only)
        self.remote_executor = None
        if remote_host and remote_user:
            self.remote_executor = RemoteExecutor(remote_host, remote_user)

        # Track Mac online status
        self._mac_online: Optional[bool] = None

    def _check_mac_online(self) -> bool:
        """Check if Mac is reachable via SSH."""
        if not self.remote_executor:
            return False

        if self._mac_online is not None:
            return self._mac_online

        try:
            result = self.remote_executor.run_command(["echo", "ok"], timeout=5)
            self._mac_online = result.success and result.stdout.strip() == "ok"
        except Exception:
            self._mac_online = False

        return self._mac_online

    def _require_mac(self) -> None:
        """Raise an error if Mac is not available (for git operations)."""
        if not self._check_mac_online():
            raise ValueError(
                "Mac is offline. This operation requires git access on your Mac. "
                "Please open your MacBook to continue."
            )

    def _auto_migrate_project(self, project_name: str) -> bool:
        """
        Auto-migrate a project from Mac to Pi-local storage.

        Called when a project is requested but not found locally.
        Returns True if migration succeeded, False if Mac is offline.
        """
        if not self._check_mac_online():
            return False

        project_path = self.projects_base / project_name
        flowforge_dir = project_path / ".flowforge"

        # Check project exists on Mac
        if not self.remote_executor.dir_exists(flowforge_dir):
            return False

        # Read registry and config from Mac
        registry_content = self.remote_executor.read_file(flowforge_dir / "registry.json")
        config_content = self.remote_executor.read_file(flowforge_dir / "config.json")

        if not registry_content:
            return False

        # Import to Pi-local storage
        self.pi_registry.import_from_mac(
            project_name=project_name,
            registry_json=registry_content,
            config_json=config_content,
            mac_path=str(project_path),
        )

        return True

    def _get_project_context(
        self, project_name: str
    ) -> tuple[Path, FlowForgeConfig, FeatureRegistry]:
        """
        Get project context from Pi-local storage.

        If project not found locally but Mac is online, auto-migrate.
        """
        # Check Pi-local storage first
        if not self.pi_registry.registry_exists(project_name):
            # Try to auto-migrate from Mac
            if not self._auto_migrate_project(project_name):
                raise ValueError(
                    f"Project not found: {project_name}. "
                    "Mac is offline or project doesn't exist."
                )

        # Load from Pi-local storage
        registry = self.pi_registry.get_registry(project_name)
        config = self.pi_registry.get_config(project_name)

        # Get Mac path for git operations
        mac_path = Path(self.pi_registry._get_mac_path(project_name))

        # If no config stored, create a minimal one
        if config is None:
            from .config import ProjectConfig
            config = FlowForgeConfig(
                project=ProjectConfig(name=project_name),
                version="1.0.0",
            )

        return mac_path, config, registry

    def _save_registry(self, project_name: str, registry: FeatureRegistry) -> None:
        """Save registry to Pi-local storage."""
        self.pi_registry.save_registry(project_name, registry)

    # =========================================================================
    # MCP Tools
    # =========================================================================

    def get_tool_definitions(self) -> list[dict]:
        """Return MCP tool definitions for Claude Code."""
        return [
            {
                "name": "flowforge_list_projects",
                "description": "List all FlowForge-initialized projects",
                "inputSchema": {
                    "type": "object",
                    "properties": {},
                    "required": [],
                },
            },
            {
                "name": "flowforge_list_features",
                "description": "List all features in a project",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "project": {
                            "type": "string",
                            "description": "Project name (e.g., 'AirFit')",
                        },
                        "status": {
                            "type": "string",
                            "description": "Filter by status (inbox, idea, in-progress, review, completed, blocked)",
                        },
                    },
                    "required": ["project"],
                },
            },
            {
                "name": "flowforge_status",
                "description": "Get status overview for a project",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "project": {
                            "type": "string",
                            "description": "Project name",
                        },
                    },
                    "required": ["project"],
                },
            },
            {
                "name": "flowforge_start_feature",
                "description": "Start working on a feature (creates worktree, generates prompt)",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "project": {
                            "type": "string",
                            "description": "Project name",
                        },
                        "feature_id": {
                            "type": "string",
                            "description": "Feature ID to start",
                        },
                        "skip_experts": {
                            "type": "boolean",
                            "description": "Skip expert suggestion",
                            "default": False,
                        },
                    },
                    "required": ["project", "feature_id"],
                },
            },
            {
                "name": "flowforge_stop_feature",
                "description": "Mark a feature as ready for review",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "project": {
                            "type": "string",
                            "description": "Project name",
                        },
                        "feature_id": {
                            "type": "string",
                            "description": "Feature ID to stop",
                        },
                    },
                    "required": ["project", "feature_id"],
                },
            },
            {
                "name": "flowforge_merge_check",
                "description": "Check if a feature is ready to merge (dry-run conflict detection)",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "project": {
                            "type": "string",
                            "description": "Project name",
                        },
                        "feature_id": {
                            "type": "string",
                            "description": "Feature ID to check (optional, checks all if omitted)",
                        },
                    },
                    "required": ["project"],
                },
            },
            {
                "name": "flowforge_merge",
                "description": "Merge a feature into main",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "project": {
                            "type": "string",
                            "description": "Project name",
                        },
                        "feature_id": {
                            "type": "string",
                            "description": "Feature ID to merge",
                        },
                        "skip_validation": {
                            "type": "boolean",
                            "description": "Skip build validation",
                            "default": False,
                        },
                    },
                    "required": ["project", "feature_id"],
                },
            },
            {
                "name": "flowforge_add_feature",
                "description": "Add a new feature to a project",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "project": {
                            "type": "string",
                            "description": "Project name",
                        },
                        "title": {
                            "type": "string",
                            "description": "Feature title",
                        },
                        "description": {
                            "type": "string",
                            "description": "Feature description",
                        },
                        "tags": {
                            "type": "array",
                            "items": {"type": "string"},
                            "description": "Feature tags",
                        },
                        "priority": {
                            "type": "integer",
                            "description": "Priority (1=highest)",
                            "default": 5,
                        },
                    },
                    "required": ["project", "title"],
                },
            },
            {
                "name": "flowforge_init_project",
                "description": "Initialize FlowForge in a project directory. Creates .flowforge config and enables feature tracking.",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "project": {
                            "type": "string",
                            "description": "Project name (directory name in projects base)",
                        },
                        "quick": {
                            "type": "boolean",
                            "description": "Use quick initialization (skip interactive questions)",
                            "default": True,
                        },
                        "project_name": {
                            "type": "string",
                            "description": "Override project name (defaults to directory name)",
                        },
                        "description": {
                            "type": "string",
                            "description": "Brief project description",
                        },
                    },
                    "required": ["project"],
                },
            },
        ]

    def call_tool(self, tool_name: str, arguments: dict) -> MCPToolResult:
        """Execute an MCP tool call."""
        tool_handlers = {
            "flowforge_list_projects": self._list_projects,
            "flowforge_list_features": self._list_features,
            "flowforge_status": self._get_status,
            "flowforge_start_feature": self._start_feature,
            "flowforge_stop_feature": self._stop_feature,
            "flowforge_merge_check": self._merge_check,
            "flowforge_merge": self._merge_feature,
            "flowforge_add_feature": self._add_feature,
            "flowforge_init_project": self._init_project,
        }

        handler = tool_handlers.get(tool_name)
        if not handler:
            return MCPToolResult(
                success=False,
                message=f"Unknown tool: {tool_name}",
            )

        try:
            return handler(**arguments)
        except Exception as e:
            return MCPToolResult(
                success=False,
                message=f"Error executing {tool_name}: {str(e)}",
            )

    # =========================================================================
    # Tool Implementations
    # =========================================================================

    def _list_projects(self) -> MCPToolResult:
        """
        List all FlowForge-initialized projects.

        Uses Pi-local storage. If Mac is online, also discovers new projects.
        """
        # Get projects from Pi-local storage
        projects = self.pi_registry.list_projects()

        # If Mac is online, check for new projects and auto-migrate
        if self._check_mac_online():
            try:
                remote_projects = self.remote_executor.get_projects(self.projects_base)
                local_names = {p["name"] for p in projects}

                for p in remote_projects:
                    if p["name"] not in local_names:
                        # Auto-migrate new project
                        if self._auto_migrate_project(p["name"]):
                            projects.append({
                                "name": p["name"],
                                "path": p["path"],
                            })
            except Exception:
                pass  # Ignore errors, use local data

        return MCPToolResult(
            success=True,
            message=f"Found {len(projects)} project(s)",
            data={"projects": projects},
        )

    def _list_features(
        self,
        project: str,
        status: Optional[str] = None,
    ) -> MCPToolResult:
        """List features in a project."""
        try:
            project_path, config, registry = self._get_project_context(project)
        except ValueError as e:
            return MCPToolResult(success=False, message=str(e))

        # Get features
        status_filter = None
        if status:
            try:
                status_filter = FeatureStatus(status)
            except ValueError:
                return MCPToolResult(
                    success=False,
                    message=f"Invalid status: {status}. Use: inbox, idea, in-progress, review, completed, blocked",
                )

        features = registry.list_features(status=status_filter)

        # Return full feature data for GUI clients
        feature_list = [f.to_dict() for f in features]

        return MCPToolResult(
            success=True,
            message=f"Found {len(feature_list)} feature(s)",
            data={"features": feature_list},
        )

    def _get_status(self, project: str) -> MCPToolResult:
        """Get status overview for a project."""
        try:
            project_path, config, registry = self._get_project_context(project)
        except ValueError as e:
            return MCPToolResult(success=False, message=str(e))

        stats = registry.get_stats()

        return MCPToolResult(
            success=True,
            message=f"Project {config.project.name} status",
            data={
                "project_name": config.project.name,
                "main_branch": config.project.main_branch,
                "stats": stats,
            },
        )

    def _start_feature(
        self,
        project: str,
        feature_id: str,
        skip_experts: bool = False,
    ) -> MCPToolResult:
        """
        Start working on a feature.

        This operation REQUIRES Mac to be online (creates git worktree).
        Registry updates happen locally on Pi.
        """
        # Git operations require Mac
        try:
            self._require_mac()
        except ValueError as e:
            return MCPToolResult(success=False, message=str(e))

        try:
            project_path, config, registry = self._get_project_context(project)
        except ValueError as e:
            return MCPToolResult(success=False, message=str(e))

        feature = registry.get_feature(feature_id)
        if not feature:
            return MCPToolResult(
                success=False,
                message=f"Feature not found: {feature_id}",
            )

        if feature.status == FeatureStatus.COMPLETED:
            return MCPToolResult(
                success=False,
                message="Feature is already completed",
            )

        # Determine worktree paths
        worktree_base = config.project.worktree_base or ".flowforge-worktrees"
        worktree_dir = project_path / worktree_base / feature_id
        branch_name = f"feature/{feature_id}"

        # Create worktree via SSH on Mac
        # Check if worktree already exists
        if self.remote_executor.dir_exists(worktree_dir):
            worktree_path = worktree_dir
        else:
            # Create worktree on Mac via SSH
            result = self.remote_executor.create_worktree(
                project_path=project_path,
                worktree_path=worktree_dir,
                branch_name=branch_name,
                create_branch=True,
            )
            if not result.success:
                # Branch might already exist, try without -b
                result = self.remote_executor.create_worktree(
                    project_path=project_path,
                    worktree_path=worktree_dir,
                    branch_name=branch_name,
                    create_branch=False,
                )
                if not result.success:
                    return MCPToolResult(
                        success=False,
                        message=f"Failed to create worktree: {result.stderr}",
                    )
            worktree_path = worktree_dir

        # Generate prompt (runs on Pi, just needs registry data)
        intelligence = IntelligenceEngine(project_path)
        prompt_builder = PromptBuilder(project_path, registry, intelligence)

        prompt = prompt_builder.build_for_feature(
            feature_id,
            config.project.claude_md_path,
            include_experts=not skip_experts,
            include_research=True,
        )

        # Save prompt via SSH (prompts need to be on Mac for Claude Code)
        prompt_filename = f"{feature_id}.md"
        prompt_dir = project_path / ".flowforge" / "prompts"
        prompt_path = prompt_dir / prompt_filename
        self.remote_executor.write_file(prompt_path, prompt)

        # Update registry locally on Pi
        from datetime import datetime
        registry.update_feature(
            feature_id,
            status=FeatureStatus.IN_PROGRESS,
            branch=branch_name,
            worktree_path=str(worktree_path),
            prompt_path=str(prompt_path),
            started_at=datetime.now().isoformat(),
        )
        self._save_registry(project, registry)

        return MCPToolResult(
            success=True,
            message=f"Started feature: {feature.title}",
            data={
                "feature_id": feature_id,
                "worktree_path": str(worktree_path),
                "prompt_path": str(prompt_path),
                "prompt": prompt,
                "launch_command": f"cd {worktree_path} && {config.project.claude_command} {' '.join(config.project.claude_flags)}",
            },
        )

    def _stop_feature(self, project: str, feature_id: str) -> MCPToolResult:
        """
        Mark a feature as ready for review.

        This is a Pi-local operation - works even when Mac is offline.
        (Git state isn't changed, just registry status)
        """
        try:
            project_path, config, registry = self._get_project_context(project)
        except ValueError as e:
            return MCPToolResult(success=False, message=str(e))

        feature = registry.get_feature(feature_id)
        if not feature:
            return MCPToolResult(
                success=False,
                message=f"Feature not found: {feature_id}",
            )

        if feature.status != FeatureStatus.IN_PROGRESS:
            return MCPToolResult(
                success=False,
                message=f"Feature is not in-progress (status: {feature.status.value})",
            )

        # Update registry locally on Pi
        registry.update_feature(feature_id, status=FeatureStatus.REVIEW)
        self._save_registry(project, registry)

        return MCPToolResult(
            success=True,
            message=f"Feature '{feature.title}' marked as ready for review",
            data={
                "feature_id": feature_id,
                "next_steps": [
                    f"Run merge-check to verify no conflicts",
                    f"Run merge to merge into {config.project.main_branch}",
                ],
            },
        )

    def _smart_done_feature(self, project: str, feature_id: str) -> MCPToolResult:
        """
        Smart mark-as-done: detects if branch is merged and acts accordingly.

        If branch is merged to main:
          - Cleans up worktree (if exists)
          - Sets status to COMPLETED
          - Returns outcome="shipped"

        If branch is not merged:
          - Sets status to REVIEW
          - Returns outcome="review"

        If Mac is offline:
          - Falls back to simple REVIEW transition (Pi-local operation)
        """
        from datetime import datetime

        try:
            project_path, config, registry = self._get_project_context(project)
        except ValueError as e:
            return MCPToolResult(success=False, message=str(e))

        feature = registry.get_feature(feature_id)
        if not feature:
            return MCPToolResult(
                success=False,
                message=f"Feature not found: {feature_id}",
            )

        if feature.status != FeatureStatus.IN_PROGRESS:
            return MCPToolResult(
                success=False,
                message=f"Feature is not in-progress (status: {feature.status.value})",
            )

        # Check if branch is merged to main (requires Mac)
        branch_merged = False
        worktree_cleaned = False
        branch_name = feature.branch or f"feature/{feature_id}"
        main_branch = config.project.main_branch

        if self._check_mac_online():
            # Check if branch is merged
            result = self.remote_executor.get_merged_branches(project_path, main_branch)
            if result.success:
                # Parse branch list - each line is "  branch-name" or "* branch-name"
                merged_branches = [
                    b.strip().lstrip("* ") for b in result.stdout.strip().split("\n") if b.strip()
                ]
                branch_merged = branch_name in merged_branches

            if branch_merged:
                # Clean up worktree if it exists
                worktree_path = project_path / ".flowforge-worktrees" / feature_id
                if self.remote_executor.dir_exists(worktree_path):
                    cleanup_result = self.remote_executor.remove_worktree(
                        project_path, worktree_path, force=True
                    )
                    worktree_cleaned = cleanup_result.success

        if branch_merged:
            # Branch is merged - mark as completed (shipped)
            registry.update_feature(
                feature_id,
                status=FeatureStatus.COMPLETED,
                worktree_path=None,
            )
            # Set completed_at timestamp
            updated_feature = registry.get_feature(feature_id)
            if updated_feature:
                updated_feature.completed_at = datetime.now()
                registry._save()

            self._save_registry(project, registry)

            return MCPToolResult(
                success=True,
                message=f"Feature '{feature.title}' shipped!",
                data={
                    "feature_id": feature_id,
                    "outcome": "shipped",
                    "new_status": "completed",
                    "worktree_removed": worktree_cleaned,
                    "branch_name": branch_name,
                },
            )
        else:
            # Branch not merged (or Mac offline) - mark as review
            registry.update_feature(feature_id, status=FeatureStatus.REVIEW)
            self._save_registry(project, registry)

            message = f"Feature '{feature.title}' marked for review"
            if not self._check_mac_online():
                message += " (Mac offline - merge status not checked)"

            return MCPToolResult(
                success=True,
                message=message,
                data={
                    "feature_id": feature_id,
                    "outcome": "review",
                    "new_status": "review",
                    "mac_online": self._check_mac_online(),
                },
            )

    def _merge_check(
        self,
        project: str,
        feature_id: Optional[str] = None,
    ) -> MCPToolResult:
        """
        Check merge readiness.

        This operation REQUIRES Mac to be online (runs git merge dry-run).
        """
        # Git operations require Mac
        try:
            self._require_mac()
        except ValueError as e:
            return MCPToolResult(success=False, message=str(e))

        try:
            project_path, config, registry = self._get_project_context(project)
        except ValueError as e:
            return MCPToolResult(success=False, message=str(e))

        if feature_id:
            # Check specific feature
            feature = registry.get_feature(feature_id)
            if not feature:
                return MCPToolResult(
                    success=False,
                    message=f"Feature not found: {feature_id}",
                )

            # Run merge-check via SSH
            result = self.remote_executor.run_command(
                ["forge", "merge-check", feature_id],
                cwd=project_path
            )

            # Parse result - success if returncode is 0
            ready = result.returncode == 0
            message = result.stdout.strip() if result.stdout else (
                "Ready to merge" if ready else f"Not ready: {result.stderr}"
            )

            return MCPToolResult(
                success=ready,
                message=message,
                data={
                    "feature_id": feature_id,
                    "ready": ready,
                    "conflict_files": [],  # Parse from output if needed
                },
            )
        else:
            # Check all features in review
            review_features = registry.list_features(status=FeatureStatus.REVIEW)

            checks = []
            ready_count = 0
            for feature in review_features:
                result = self.remote_executor.run_command(
                    ["forge", "merge-check", feature.id],
                    cwd=project_path
                )
                ready = result.returncode == 0
                if ready:
                    ready_count += 1
                checks.append({
                    "feature_id": feature.id,
                    "title": feature.title,
                    "ready": ready,
                    "conflict_files": [],
                })

            return MCPToolResult(
                success=True,
                message=f"{ready_count}/{len(checks)} features ready to merge",
                data={
                    "merge_order": [f.id for f in review_features],
                    "checks": checks,
                },
            )

    def _merge_feature(
        self,
        project: str,
        feature_id: str,
        skip_validation: bool = False,
    ) -> MCPToolResult:
        """
        Merge a feature into main.

        This operation REQUIRES Mac to be online (runs git merge).
        Registry is updated locally on Pi after successful merge.
        """
        # Git operations require Mac
        try:
            self._require_mac()
        except ValueError as e:
            return MCPToolResult(success=False, message=str(e))

        try:
            project_path, config, registry = self._get_project_context(project)
        except ValueError as e:
            return MCPToolResult(success=False, message=str(e))

        feature = registry.get_feature(feature_id)
        if not feature:
            return MCPToolResult(
                success=False,
                message=f"Feature not found: {feature_id}",
            )

        # Build merge command
        cmd = ["forge", "merge", feature_id]
        if skip_validation:
            cmd.append("--skip-validation")

        # Run merge via SSH
        result = self.remote_executor.run_command(cmd, cwd=project_path)

        if result.returncode == 0:
            # Update registry locally on Pi
            from datetime import datetime
            registry.update_feature(
                feature_id,
                status=FeatureStatus.COMPLETED,
                completed_at=datetime.now().isoformat(),
            )
            # Record the ship for streak tracking
            registry.record_ship()
            self._save_registry(project, registry)

            return MCPToolResult(
                success=True,
                message=f"Merged {feature.title} into {config.project.main_branch}",
                data={
                    "feature_id": feature_id,
                    "merged_into": config.project.main_branch,
                    "shipping_stats": registry.get_shipping_stats().to_dict(),
                },
            )
        else:
            return MCPToolResult(
                success=False,
                message=result.stderr or result.stdout or "Merge failed",
                data={
                    "feature_id": feature_id,
                    "output": result.stdout,
                    "error": result.stderr,
                },
            )

    def _add_feature(
        self,
        project: str,
        title: str,
        description: Optional[str] = None,
        tags: Optional[list[str]] = None,
        priority: int = 5,
        status: str = "inbox",  # Default to inbox for quick capture
    ) -> MCPToolResult:
        """
        Add a new feature to a project.

        This is a Pi-local operation - works even when Mac is offline.
        """
        try:
            project_path, config, registry = self._get_project_context(project)
        except ValueError as e:
            return MCPToolResult(success=False, message=str(e))

        from .registry import MAX_PLANNED_FEATURES

        # Convert status string to enum
        try:
            feature_status = FeatureStatus(status)
        except ValueError:
            feature_status = FeatureStatus.INBOX

        # =====================================================================
        # Shipping Machine Constraint: Max Ideas Ready to Build
        # Only applies when adding as "idea" (not "inbox")
        # =====================================================================
        if feature_status == FeatureStatus.IDEA and not registry.can_add_idea():
            idea_titles = registry.get_idea_titles()
            return MCPToolResult(
                success=False,
                message=(
                    f"You have {MAX_PLANNED_FEATURES} ideas ready to build. "
                    f"Finish or delete one first to stay focused!\n\n"
                    f"Currently ready to build:\n"
                    + "\n".join(f"  • {t}" for t in idea_titles[:MAX_PLANNED_FEATURES])
                ),
                data={
                    "constraint": "max_ideas",
                    "limit": MAX_PLANNED_FEATURES,
                    "current": registry.count_ideas(),
                    "idea_titles": idea_titles,
                },
            )

        # Generate ID
        feature_id = FeatureRegistry.generate_id(title)

        # Check if exists
        if registry.get_feature(feature_id):
            return MCPToolResult(
                success=False,
                message=f"Feature already exists: {feature_id}",
            )

        # Create feature locally (Pi-local write - works offline!)
        feature = Feature(
            id=feature_id,
            title=title,
            description=description or "",
            status=feature_status,
            priority=priority,
            complexity=Complexity.MEDIUM,
            tags=tags or [],
        )
        registry.add_feature(feature)

        # Save to Pi-local storage
        self._save_registry(project, registry)

        # Show remaining slots (only relevant for idea features)
        remaining = MAX_PLANNED_FEATURES - registry.count_ideas()

        if feature_status == FeatureStatus.INBOX:
            message = f"Captured to inbox: {title}"
        else:
            message = f"Added idea: {title} ({remaining} slot{'s' if remaining != 1 else ''} remaining)"

        return MCPToolResult(
            success=True,
            message=message,
            data={
                "feature_id": feature_id,
                "title": title,
                "status": feature_status.value,
                "idea_count": registry.count_ideas(),
                "slots_remaining": remaining,
            },
        )

    def _update_feature(
        self,
        project: str,
        feature_id: str,
        **updates,
    ) -> MCPToolResult:
        """
        Update a feature's attributes.

        This is a Pi-local operation - works even when Mac is offline.
        Supports clearing fields by explicitly passing None values.
        """
        try:
            project_path, config, registry = self._get_project_context(project)
        except ValueError as e:
            return MCPToolResult(success=False, message=str(e))

        feature = registry.get_feature(feature_id)
        if not feature:
            return MCPToolResult(
                success=False,
                message=f"Feature not found: {feature_id}",
            )

        if not updates:
            return MCPToolResult(
                success=False,
                message="No updates provided",
            )

        # Update registry locally (Pi-local write - works offline!)
        # Pass all updates including None values to allow clearing fields
        registry.update_feature(feature_id, **updates)

        # Save to Pi-local storage
        self._save_registry(project, registry)

        # Get updated feature
        updated_feature = registry.get_feature(feature_id)

        return MCPToolResult(
            success=True,
            message=f"Updated feature: {updated_feature.title}",
            data={
                "feature_id": feature_id,
                "title": updated_feature.title,
                "status": updated_feature.status.value,
                "priority": updated_feature.priority,
                "tags": updated_feature.tags,
            },
        )

    def _delete_feature(
        self,
        project: str,
        feature_id: str,
        force: bool = False,
    ) -> MCPToolResult:
        """
        Delete a feature from the registry.

        Registry deletion is a Pi-local operation (works offline).
        Worktree cleanup requires Mac to be online.
        """
        try:
            project_path, config, registry = self._get_project_context(project)
        except ValueError as e:
            return MCPToolResult(success=False, message=str(e))

        feature = registry.get_feature(feature_id)
        if not feature:
            return MCPToolResult(success=False, message=f"Feature not found: {feature_id}")

        feature_title = feature.title
        had_worktree = bool(feature.worktree_path)

        # Clean up worktree if exists and Mac is online
        worktree_cleaned = False
        if had_worktree and self._check_mac_online() and self.remote_executor:
            worktree_path = project_path / ".flowforge-worktrees" / feature_id
            if self.remote_executor.dir_exists(worktree_path):
                cleanup_result = self.remote_executor.remove_worktree(
                    project_path, worktree_path, force=True
                )
                worktree_cleaned = cleanup_result.success

            # Also remove prompt file
            prompt_file = project_path / ".flowforge" / "prompts" / f"{feature_id}.md"
            if self.remote_executor.file_exists(prompt_file):
                self.remote_executor.run_command(["rm", "-f", str(prompt_file)])

        # Delete from registry locally (Pi-local write - works offline!)
        try:
            registry.remove_feature(feature_id, force=force)
        except ValueError as e:
            return MCPToolResult(success=False, message=str(e))

        # Save to Pi-local storage
        self._save_registry(project, registry)

        message = f"Deleted feature: {feature_title}"
        if had_worktree:
            message += f" (worktree cleaned: {worktree_cleaned})"

        return MCPToolResult(
            success=True,
            message=message,
            data={"feature_id": feature_id, "worktree_cleaned": worktree_cleaned},
        )

    def _cleanup_orphans(self, project: str) -> MCPToolResult:
        """
        Remove worktrees for features that are completed or deleted.

        This operation requires Mac to be online.
        """
        if not self._check_mac_online() or not self.remote_executor:
            return MCPToolResult(
                success=False, message="Mac offline - cannot clean worktrees"
            )

        try:
            project_path, config, registry = self._get_project_context(project)
        except ValueError as e:
            return MCPToolResult(success=False, message=str(e))

        worktree_base = project_path / ".flowforge-worktrees"

        # Get active feature IDs (in-progress or review)
        active_ids = {
            f.id
            for f in registry.list_features()
            if f.status in (FeatureStatus.IN_PROGRESS, FeatureStatus.REVIEW)
        }

        # List worktree directories on Mac
        result = self.remote_executor.run_command(["ls", str(worktree_base)])
        if not result.success:
            return MCPToolResult(
                success=True,
                message="No worktrees directory found",
                data={"cleaned": 0, "orphans": []},
            )

        orphans_cleaned = []
        for dirname in result.stdout.strip().split("\n"):
            if dirname and dirname not in active_ids:
                worktree_path = worktree_base / dirname
                cleanup_result = self.remote_executor.remove_worktree(
                    project_path, worktree_path, force=True
                )
                if cleanup_result.success:
                    orphans_cleaned.append(dirname)

        return MCPToolResult(
            success=True,
            message=f"Cleaned {len(orphans_cleaned)} orphaned worktrees",
            data={"cleaned": len(orphans_cleaned), "orphans": orphans_cleaned},
        )

    def _sync_registry(self, project: str, direction: str = "pi-to-mac") -> MCPToolResult:
        """
        Sync registries between Pi and Mac.

        Args:
            project: Project name
            direction: One of:
                - "pi-to-mac": Write Pi's registry to Mac's .flowforge/registry.json
                - "mac-to-pi": Read Mac's registry and replace Pi's
                - "bidirectional": Merge both, most recent updated_at wins per-feature
        """
        if not self._check_mac_online() or not self.remote_executor:
            return MCPToolResult(success=False, message="Mac offline - cannot sync")

        try:
            project_path, config, pi_registry = self._get_project_context(project)
        except ValueError as e:
            return MCPToolResult(success=False, message=str(e))

        mac_registry_path = project_path / ".flowforge" / "registry.json"

        if direction == "pi-to-mac":
            # Write Pi registry to Mac
            registry_data = {
                "version": "1.0.0",
                "features": {f.id: f.to_dict() for f in pi_registry.list_features()},
                "merge_queue": [asdict(item) for item in pi_registry._merge_queue],
                "shipping_stats": pi_registry._shipping_stats.to_dict(),
            }
            registry_json = json.dumps(registry_data, indent=2, default=str)
            result = self.remote_executor.write_file(mac_registry_path, registry_json)
            if result.success:
                return MCPToolResult(
                    success=True,
                    message="Synced Pi registry to Mac",
                    data={"direction": direction, "feature_count": len(pi_registry.list_features())},
                )
            return MCPToolResult(success=False, message=f"Failed to write Mac registry: {result.stderr}")

        elif direction == "mac-to-pi":
            # Read Mac registry and import to Pi
            mac_content = self.remote_executor.read_file(mac_registry_path)
            if not mac_content:
                return MCPToolResult(success=False, message="Could not read Mac registry")
            self.pi_registry.import_from_mac(project, mac_content, mac_path=str(project_path))
            return MCPToolResult(
                success=True,
                message="Synced Mac registry to Pi",
                data={"direction": direction},
            )

        elif direction == "bidirectional":
            # Read Mac registry
            mac_content = self.remote_executor.read_file(mac_registry_path)
            mac_data = json.loads(mac_content) if mac_content else {"features": {}}

            # Get Pi registry data as list
            pi_features_list = [f.to_dict() for f in pi_registry.list_features()]
            pi_data = {
                "version": "1.0.0",
                "features": pi_features_list,
                "merge_queue": [asdict(item) for item in pi_registry._merge_queue],
                "shipping_stats": pi_registry._shipping_stats.to_dict(),
            }

            # Handle both dict and list format for Mac features
            mac_features = mac_data.get("features", {})
            if isinstance(mac_features, dict):
                mac_features_list = list(mac_features.values())
            else:
                mac_features_list = mac_features

            # Build merged feature list (most recent updated_at wins)
            merged = {}
            for f in mac_features_list + pi_features_list:
                fid = f["id"]
                if fid not in merged or f.get("updated_at", "") > merged[fid].get("updated_at", ""):
                    merged[fid] = f

            # Save merged to both (Mac uses dict format {id: data})
            merged_data = {**pi_data, "features": merged}
            merged_json = json.dumps(merged_data, indent=2, default=str)

            # Write to Mac
            self.remote_executor.write_file(mac_registry_path, merged_json)
            # Re-import to Pi
            self.pi_registry.import_from_mac(project, merged_json, mac_path=str(project_path))

            return MCPToolResult(
                success=True,
                message=f"Bidirectional sync complete ({len(merged)} features)",
                data={"direction": direction, "feature_count": len(merged)},
            )

        return MCPToolResult(
            success=False,
            message=f"Invalid direction: {direction}. Use 'pi-to-mac', 'mac-to-pi', or 'bidirectional'",
        )

    def _sync_status(self, project: str) -> MCPToolResult:
        """Check if registries are in sync, show diff if not."""
        if not self._check_mac_online() or not self.remote_executor:
            return MCPToolResult(success=False, message="Mac offline - cannot check sync status")

        try:
            project_path, config, pi_registry = self._get_project_context(project)
        except ValueError as e:
            return MCPToolResult(success=False, message=str(e))

        mac_registry_path = project_path / ".flowforge" / "registry.json"

        mac_content = self.remote_executor.read_file(mac_registry_path)
        mac_data = json.loads(mac_content) if mac_content else {"features": {}}

        # Handle both dict and list format for features
        mac_features = mac_data.get("features", {})
        if isinstance(mac_features, dict):
            mac_ids = set(mac_features.keys())
        else:
            mac_ids = {f["id"] for f in mac_features}
        pi_ids = {f.id for f in pi_registry.list_features()}

        only_mac = mac_ids - pi_ids
        only_pi = pi_ids - mac_ids
        in_both = mac_ids & pi_ids

        return MCPToolResult(
            success=True,
            message="Sync status retrieved",
            data={
                "in_sync": not only_mac and not only_pi,
                "mac_count": len(mac_ids),
                "pi_count": len(pi_ids),
                "only_on_mac": list(only_mac),
                "only_on_pi": list(only_pi),
                "in_both": len(in_both),
            },
        )

    def _init_project(
        self,
        project: str,
        quick: bool = True,
        project_name: Optional[str] = None,
        description: Optional[str] = None,
        vision: Optional[str] = None,
        target_users: Optional[str] = None,
        coding_philosophy: Optional[str] = None,
        ai_guidance: Optional[str] = None,
        roadmap_path: Optional[str] = None,
    ) -> MCPToolResult:
        """
        Initialize FlowForge in a project directory.

        This operation REQUIRES Mac to be online (creates .flowforge on Mac).
        After initialization, registry is auto-migrated to Pi.
        """
        # Git operations require Mac
        try:
            self._require_mac()
        except ValueError as e:
            return MCPToolResult(success=False, message=str(e))

        project_path = self.projects_base / project
        flowforge_dir = project_path / ".flowforge"

        # Check if project exists on Mac
        if not self.remote_executor.dir_exists(project_path):
            return MCPToolResult(
                success=False,
                message=f"Project directory not found on Mac: {project}",
            )

        # Check if already initialized
        if self.remote_executor.dir_exists(flowforge_dir):
            return MCPToolResult(
                success=False,
                message=f"Project already initialized: {project}",
            )

        # Run forge init via SSH
        args = ["init"]
        if quick:
            args.append("--quick")
        if project_name:
            args.extend(["--name", project_name])

        result = self.remote_executor.run_forge_command(
            project_path,
            args,
            timeout=60,
        )

        if not result.success:
            return MCPToolResult(
                success=False,
                message=f"Remote initialization failed: {result.stderr}",
            )

        # Verify initialization
        if not self.remote_executor.dir_exists(flowforge_dir):
            return MCPToolResult(
                success=False,
                message="Initialization command succeeded but .flowforge not created",
            )

        # Auto-migrate to Pi-local storage
        self._auto_migrate_project(project)

        return MCPToolResult(
            success=True,
            message=f"Initialized FlowForge in {project}",
            data={
                "project": project,
                "path": str(project_path),
            },
        )


# =============================================================================
# MCP Protocol Handler
# =============================================================================


def create_mcp_response(result: MCPToolResult) -> dict:
    """Create an MCP-compatible response from a tool result."""
    content = [
        {
            "type": "text",
            "text": result.message,
        }
    ]

    if result.data:
        content.append({
            "type": "text",
            "text": json.dumps(result.data, indent=2),
        })

    return {
        "content": content,
        "isError": not result.success,
    }
