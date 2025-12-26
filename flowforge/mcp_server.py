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
"""

from dataclasses import dataclass
from pathlib import Path
from typing import Any, Optional
import json
import os

from .config import FlowForgeConfig, find_project_root
from .registry import FeatureRegistry, FeatureStatus
from .worktree import WorktreeManager
from .merge import MergeOrchestrator
from .prompt_builder import PromptBuilder
from .intelligence import IntelligenceEngine
from .remote import RemoteExecutor


@dataclass
class MCPToolResult:
    """Result from an MCP tool call."""

    success: bool
    message: str
    data: Optional[dict] = None


class FlowForgeMCPServer:
    """
    MCP Server implementation for FlowForge.

    This server can run on a Raspberry Pi and be accessed by Claude Code
    via Remote MCP Server configuration. It manages projects on a remote
    Mac via SSH, or locally if running on the same machine.
    """

    def __init__(
        self,
        projects_base: Path,
        remote_host: Optional[str] = None,
        remote_user: Optional[str] = None,
    ):
        """
        Initialize the MCP server.

        Args:
            projects_base: Base directory containing FlowForge projects
            remote_host: SSH host for remote Mac (e.g., "mac.tailnet")
            remote_user: SSH username for remote Mac
        """
        self.projects_base = Path(projects_base)
        self.remote_host = remote_host
        self.remote_user = remote_user

        # Set up remote executor if running on Pi
        if remote_host and remote_user:
            self.remote_executor = RemoteExecutor(remote_host, remote_user)
            self.is_remote = True
        else:
            self.remote_executor = None
            self.is_remote = False

        # Cache project configs
        self._project_cache: dict[str, tuple[FlowForgeConfig, FeatureRegistry]] = {}

    def _get_project_context(
        self, project_name: str
    ) -> tuple[Path, FlowForgeConfig, FeatureRegistry]:
        """Get or load project context."""
        project_path = self.projects_base / project_name

        if not project_path.exists():
            raise ValueError(f"Project not found: {project_name}")

        flowforge_dir = project_path / ".flowforge"
        if not flowforge_dir.exists():
            raise ValueError(f"FlowForge not initialized in: {project_name}")

        # Load or get from cache
        cache_key = str(project_path)
        if cache_key not in self._project_cache:
            config = FlowForgeConfig.load(project_path)
            registry = FeatureRegistry.load(project_path)
            self._project_cache[cache_key] = (config, registry)
        else:
            config, registry = self._project_cache[cache_key]
            # Reload registry to get fresh data
            registry = FeatureRegistry.load(project_path)
            self._project_cache[cache_key] = (config, registry)

        return project_path, config, registry

    def _invalidate_cache(self, project_name: str) -> None:
        """Invalidate cache for a project."""
        project_path = self.projects_base / project_name
        cache_key = str(project_path)
        if cache_key in self._project_cache:
            del self._project_cache[cache_key]

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
                            "description": "Filter by status (planned, in-progress, review, completed, blocked)",
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
        """List all FlowForge-initialized projects."""
        projects = []

        if self.is_remote:
            # Use SSH to get projects from Mac
            remote_projects = self.remote_executor.get_projects(self.projects_base)
            for p in remote_projects:
                projects.append({
                    "name": p["name"],
                    "path": p["path"],
                })
        else:
            # Local mode - access filesystem directly
            for item in self.projects_base.iterdir():
                if item.is_dir() and (item / ".flowforge").exists():
                    try:
                        config = FlowForgeConfig.load(item)
                        projects.append({
                            "name": config.project.name,
                            "path": str(item),
                            "main_branch": config.project.main_branch,
                        })
                    except Exception:
                        # Skip projects we can't load
                        pass

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
                    message=f"Invalid status: {status}. Use: planned, in-progress, review, completed, blocked",
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
        """Start working on a feature."""
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

        # Create worktree
        worktree_mgr = WorktreeManager(project_path, config.project.worktree_base)

        worktree_path = worktree_mgr.get_worktree_path(feature_id)
        if not worktree_path:
            try:
                worktree_path = worktree_mgr.create_for_feature(
                    feature_id,
                    config.project.main_branch,
                )
            except Exception as e:
                return MCPToolResult(
                    success=False,
                    message=f"Failed to create worktree: {e}",
                )

        # Generate prompt
        intelligence = IntelligenceEngine(project_path)
        prompt_builder = PromptBuilder(project_path, registry, intelligence)

        prompt = prompt_builder.build_for_feature(
            feature_id,
            config.project.claude_md_path,
            include_experts=not skip_experts,
            include_research=True,
        )

        # Save prompt
        prompt_path = prompt_builder.save_prompt(feature_id, prompt)

        # Update registry
        registry.update_feature(
            feature_id,
            status=FeatureStatus.IN_PROGRESS,
            branch=f"feature/{feature_id}",
            worktree_path=str(worktree_path),
            prompt_path=str(prompt_path),
        )

        self._invalidate_cache(project)

        return MCPToolResult(
            success=True,
            message=f"Started feature: {feature.title}",
            data={
                "feature_id": feature_id,
                "worktree_path": str(worktree_path),
                "prompt_path": str(prompt_path),
                "prompt": prompt,  # Include full prompt for Claude Code to display
                "launch_command": f"cd {worktree_path} && {config.project.claude_command} {' '.join(config.project.claude_flags)}",
            },
        )

    def _stop_feature(self, project: str, feature_id: str) -> MCPToolResult:
        """Mark a feature as ready for review."""
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

        registry.update_feature(feature_id, status=FeatureStatus.REVIEW)
        self._invalidate_cache(project)

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

    def _merge_check(
        self,
        project: str,
        feature_id: Optional[str] = None,
    ) -> MCPToolResult:
        """Check merge readiness."""
        try:
            project_path, config, registry = self._get_project_context(project)
        except ValueError as e:
            return MCPToolResult(success=False, message=str(e))

        orchestrator = MergeOrchestrator(
            project_path,
            registry,
            config.project.main_branch,
            config.project.build_command,
        )

        if feature_id:
            # Check specific feature
            feature = registry.get_feature(feature_id)
            if not feature:
                return MCPToolResult(
                    success=False,
                    message=f"Feature not found: {feature_id}",
                )

            result = orchestrator.check_conflicts(feature_id)

            return MCPToolResult(
                success=result.success,
                message=result.message,
                data={
                    "feature_id": feature_id,
                    "ready": result.success,
                    "conflict_files": result.conflict_files,
                },
            )
        else:
            # Check all features in review
            merge_order = orchestrator.compute_merge_order()

            checks = []
            for fid in merge_order:
                feature = registry.get_feature(fid)
                result = orchestrator.check_conflicts(fid)
                checks.append({
                    "feature_id": fid,
                    "title": feature.title,
                    "ready": result.success,
                    "conflict_files": result.conflict_files,
                })

            ready_count = sum(1 for c in checks if c["ready"])

            return MCPToolResult(
                success=True,
                message=f"{ready_count}/{len(checks)} features ready to merge",
                data={
                    "merge_order": merge_order,
                    "checks": checks,
                },
            )

    def _merge_feature(
        self,
        project: str,
        feature_id: str,
        skip_validation: bool = False,
    ) -> MCPToolResult:
        """Merge a feature into main."""
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

        orchestrator = MergeOrchestrator(
            project_path,
            registry,
            config.project.main_branch,
            config.project.build_command,
        )

        result = orchestrator.merge_feature(
            feature_id,
            validate=not skip_validation,
            auto_cleanup=True,
        )

        self._invalidate_cache(project)

        if result.success:
            return MCPToolResult(
                success=True,
                message=result.message,
                data={
                    "feature_id": feature_id,
                    "merged_into": config.project.main_branch,
                },
            )
        else:
            data = {
                "feature_id": feature_id,
                "conflict_files": result.conflict_files,
            }

            if result.needs_resolution:
                # Generate conflict resolution prompt
                resolution_prompt = orchestrator.generate_conflict_prompt(feature_id)
                data["resolution_prompt"] = resolution_prompt

            if result.validation_output:
                data["validation_output"] = result.validation_output

            return MCPToolResult(
                success=False,
                message=result.message,
                data=data,
            )

    def _add_feature(
        self,
        project: str,
        title: str,
        description: Optional[str] = None,
        tags: Optional[list[str]] = None,
        priority: int = 5,
    ) -> MCPToolResult:
        """Add a new feature to a project."""
        try:
            project_path, config, registry = self._get_project_context(project)
        except ValueError as e:
            return MCPToolResult(success=False, message=str(e))

        from .registry import Feature, Complexity, MAX_PLANNED_FEATURES

        # =====================================================================
        # Shipping Machine Constraint: Max 3 Planned Features
        # =====================================================================
        if not registry.can_add_planned():
            planned_titles = registry.get_planned_feature_titles()
            return MCPToolResult(
                success=False,
                message=(
                    f"You have {MAX_PLANNED_FEATURES} planned features. "
                    f"Finish or delete one first to stay focused!\n\n"
                    f"Currently planned:\n"
                    + "\n".join(f"  • {t}" for t in planned_titles[:MAX_PLANNED_FEATURES])
                ),
                data={
                    "constraint": "max_planned_features",
                    "limit": MAX_PLANNED_FEATURES,
                    "current": registry.count_planned(),
                    "planned_titles": planned_titles,
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

        # Create feature
        feature = Feature(
            id=feature_id,
            title=title,
            description=description or "",
            tags=tags or [],
            priority=priority,
            complexity=Complexity.MEDIUM,
        )

        registry.add_feature(feature)
        self._invalidate_cache(project)

        # Show remaining slots
        remaining = MAX_PLANNED_FEATURES - registry.count_planned()

        return MCPToolResult(
            success=True,
            message=f"Added feature: {title} ({remaining} slot{'s' if remaining != 1 else ''} remaining)",
            data={
                "feature_id": feature_id,
                "title": title,
                "status": "planned",
                "planned_count": registry.count_planned(),
                "slots_remaining": remaining,
            },
        )

    def _update_feature(
        self,
        project: str,
        feature_id: str,
        title: Optional[str] = None,
        description: Optional[str] = None,
        status: Optional[str] = None,
        priority: Optional[int] = None,
        complexity: Optional[str] = None,
        tags: Optional[list[str]] = None,
    ) -> MCPToolResult:
        """Update a feature's attributes."""
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

        # Build updates dict from non-None values
        updates = {}
        if title is not None:
            updates["title"] = title
        if description is not None:
            updates["description"] = description
        if status is not None:
            updates["status"] = status
        if priority is not None:
            updates["priority"] = priority
        if complexity is not None:
            updates["complexity"] = complexity
        if tags is not None:
            updates["tags"] = tags

        if not updates:
            return MCPToolResult(
                success=False,
                message="No updates provided",
            )

        try:
            updated_feature = registry.update_feature(feature_id, **updates)
            self._invalidate_cache(project)

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
        except ValueError as e:
            return MCPToolResult(success=False, message=str(e))

    def _delete_feature(
        self,
        project: str,
        feature_id: str,
        force: bool = False,
    ) -> MCPToolResult:
        """Delete a feature from the registry."""
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

        try:
            registry.remove_feature(feature_id, force=force)
            self._invalidate_cache(project)

            return MCPToolResult(
                success=True,
                message=f"Deleted feature: {feature.title}",
                data={"feature_id": feature_id},
            )
        except ValueError as e:
            return MCPToolResult(success=False, message=str(e))


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
