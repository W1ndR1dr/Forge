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
# WorktreeManager and MergeOrchestrator run on Mac via SSH
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

    This server runs on a Raspberry Pi and is accessed by Claude Code (iOS/Mac)
    via Remote MCP Server configuration. It manages projects on a Mac via SSH.
    All git operations are executed on the Mac via SSH.
    """

    def __init__(
        self,
        projects_base: Path,
        remote_host: str,
        remote_user: str,
    ):
        """
        Initialize the MCP server.

        The server runs on Pi and connects to Mac via SSH for all git operations.

        Args:
            projects_base: Base directory containing FlowForge projects (Mac path)
            remote_host: SSH host for Mac (e.g., "brians-macbook-pro")
            remote_user: SSH username for Mac
        """
        self.projects_base = Path(projects_base)
        self.remote_host = remote_host
        self.remote_user = remote_user

        # Remote executor for Pi → Mac SSH operations
        self.remote_executor = RemoteExecutor(remote_host, remote_user)

        # Cache project configs
        self._project_cache: dict[str, tuple[FlowForgeConfig, FeatureRegistry]] = {}

    def _get_project_context(
        self, project_name: str
    ) -> tuple[Path, FlowForgeConfig, FeatureRegistry]:
        """Get or load project context via SSH from Mac."""
        project_path = self.projects_base / project_name
        flowforge_dir = project_path / ".flowforge"

        # Check project exists via SSH
        if not self.remote_executor.dir_exists(project_path):
            raise ValueError(f"Project not found: {project_name}")
        if not self.remote_executor.dir_exists(flowforge_dir):
            raise ValueError(f"Project not initialized: {project_name}")

        # Load config and registry via SSH
        return self._get_remote_project_context(project_name, project_path, flowforge_dir)

    def _invalidate_cache(self, project_name: str) -> None:
        """Invalidate cache for a project."""
        project_path = self.projects_base / project_name
        cache_key = str(project_path)
        if cache_key in self._project_cache:
            del self._project_cache[cache_key]

    def _get_remote_project_context(
        self,
        project_name: str,
        project_path: Path,
        flowforge_dir: Path,
    ) -> tuple[Path, FlowForgeConfig, FeatureRegistry]:
        """
        Load project context via SSH from remote Mac.

        Reads config.json and registry.json via SSH and constructs
        the config and registry objects from the JSON data.
        """
        from .config import ProjectConfig

        # Read config.json via SSH
        config_path = flowforge_dir / "config.json"
        config_content = self.remote_executor.read_file(config_path)
        if not config_content:
            raise ValueError(f"Could not read config for: {project_name}")

        config_data = json.loads(config_content)
        project_data = config_data.get("project", {})
        project_config = ProjectConfig(**project_data)
        config = FlowForgeConfig(
            project=project_config,
            version=config_data.get("version", "1.0.0"),
        )

        # Read registry.json via SSH
        registry_path = flowforge_dir / "registry.json"
        registry_content = self.remote_executor.read_file(registry_path)

        # Create a registry object and populate it from JSON
        # We create a "virtual" registry that operates on cached data
        registry = FeatureRegistry(project_path)

        if registry_content:
            registry_data = json.loads(registry_content)

            # Populate features
            from .registry import Feature, MergeQueueItem, ShippingStats
            for fid, fdata in registry_data.get("features", {}).items():
                registry._features[fid] = Feature.from_dict(fdata)

            # Populate merge queue
            for item in registry_data.get("merge_queue", []):
                registry._merge_queue.append(MergeQueueItem(**item))

            # Populate shipping stats
            if "shipping_stats" in registry_data:
                registry._shipping_stats = ShippingStats.from_dict(
                    registry_data["shipping_stats"]
                )

        # Cache the loaded data
        cache_key = str(project_path)
        self._project_cache[cache_key] = (config, registry)

        return project_path, config, registry

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
        """List all FlowForge-initialized projects."""
        projects = []

        # Get projects from Mac via SSH
        remote_projects = self.remote_executor.get_projects(self.projects_base)
        for p in remote_projects:
            projects.append({
                "name": p["name"],
                "path": p["path"],
            })

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

        # Save prompt via SSH
        prompt_filename = f"{feature_id}.md"
        prompt_dir = project_path / ".flowforge" / "prompts"
        prompt_path = prompt_dir / prompt_filename

        # Write prompt file on Mac
        self.remote_executor.write_file(prompt_path, prompt)

        # Update registry on Mac
        from datetime import datetime
        registry_path = project_path / ".flowforge" / "registry.json"
        registry_content = self.remote_executor.read_file(registry_path)

        if registry_content:
            import json
            registry_data = json.loads(registry_content)

            # Update the feature
            if feature_id in registry_data.get("features", {}):
                registry_data["features"][feature_id]["status"] = "in-progress"
                registry_data["features"][feature_id]["branch"] = branch_name
                registry_data["features"][feature_id]["worktree_path"] = str(worktree_path)
                registry_data["features"][feature_id]["prompt_path"] = str(prompt_path)
                registry_data["features"][feature_id]["started_at"] = datetime.now().isoformat()

                # Write updated registry
                updated_json = json.dumps(registry_data, indent=2)
                self.remote_executor.write_file(registry_path, updated_json)

        self._invalidate_cache(project)

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

        # Execute via SSH on Mac
        result = self.remote_executor.run_command(
            ["forge", "stop", feature_id],
            cwd=project_path
        )
        if result.returncode != 0:
            return MCPToolResult(
                success=False,
                message=f"Failed to stop feature: {result.stderr or result.stdout}",
            )
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
        """Check merge readiness via SSH on Mac."""
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
        """Merge a feature into main via SSH on Mac."""
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

        self._invalidate_cache(project)

        if result.returncode == 0:
            return MCPToolResult(
                success=True,
                message=f"Merged {feature.title} into {config.project.main_branch}",
                data={
                    "feature_id": feature_id,
                    "merged_into": config.project.main_branch,
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
        status: str = "idea",  # Default to idea for quick capture
    ) -> MCPToolResult:
        """Add a new feature to a project."""
        try:
            project_path, config, registry = self._get_project_context(project)
        except ValueError as e:
            return MCPToolResult(success=False, message=str(e))

        from .registry import Feature, FeatureStatus, Complexity, MAX_PLANNED_FEATURES

        # Convert status string to enum
        try:
            feature_status = FeatureStatus(status)
        except ValueError:
            feature_status = FeatureStatus.IDEA

        # =====================================================================
        # Shipping Machine Constraint: Max 3 Planned Features
        # Only applies when adding as "planned" (not "idea")
        # =====================================================================
        if feature_status == FeatureStatus.PLANNED and not registry.can_add_planned():
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

        # Create feature via SSH (forge add on Mac)
        cmd = ["forge", "add", "-C", str(project_path), title]
        if status:
            cmd.extend(["--status", status])
        if description:
            cmd.extend(["--description", description])

        result = self.remote_executor.run_command(cmd, cwd=project_path)
        if result.returncode != 0:
            return MCPToolResult(
                success=False,
                message=f"Failed to add feature: {result.stderr or result.stdout}",
            )

        # Generate ID for response (matches what forge add creates)
        feature_id = FeatureRegistry.generate_id(title)
        self._invalidate_cache(project)

        # Show remaining slots (only relevant for planned features)
        remaining = MAX_PLANNED_FEATURES - registry.count_planned()

        if feature_status == FeatureStatus.IDEA:
            message = f"Idea captured: {title}"
        else:
            message = f"Added feature: {title} ({remaining} slot{'s' if remaining != 1 else ''} remaining)"

        return MCPToolResult(
            success=True,
            message=message,
            data={
                "feature_id": feature_id,
                "title": title,
                "status": feature_status.value,
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

        # Update registry on Mac via SSH
        import json
        from datetime import datetime
        registry_path = project_path / ".flowforge" / "registry.json"
        registry_content = self.remote_executor.read_file(registry_path)

        if not registry_content:
            return MCPToolResult(success=False, message="Could not read registry")

        registry_data = json.loads(registry_content)

        if feature_id not in registry_data.get("features", {}):
            return MCPToolResult(success=False, message=f"Feature not found: {feature_id}")

        # Apply updates
        feature_data = registry_data["features"][feature_id]
        for key, value in updates.items():
            feature_data[key] = value
        feature_data["updated_at"] = datetime.now().isoformat()

        # Write updated registry
        updated_json = json.dumps(registry_data, indent=2)
        self.remote_executor.write_file(registry_path, updated_json)
        self._invalidate_cache(project)

        return MCPToolResult(
            success=True,
            message=f"Updated feature: {feature_data.get('title', feature_id)}",
            data={
                "feature_id": feature_id,
                "title": feature_data.get("title"),
                "status": feature_data.get("status"),
                "priority": feature_data.get("priority"),
                "tags": feature_data.get("tags", []),
            },
        )

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

        # Delete from registry on Mac via SSH
        import json
        registry_path = project_path / ".flowforge" / "registry.json"
        registry_content = self.remote_executor.read_file(registry_path)

        if not registry_content:
            return MCPToolResult(success=False, message="Could not read registry")

        registry_data = json.loads(registry_content)

        if feature_id not in registry_data.get("features", {}):
            return MCPToolResult(success=False, message=f"Feature not found: {feature_id}")

        feature_data = registry_data["features"][feature_id]
        feature_title = feature_data.get("title", feature_id)

        # Safety checks (unless force=True)
        if not force:
            if feature_data.get("children"):
                return MCPToolResult(
                    success=False,
                    message=f"Feature has children. Use force=True to delete.",
                )
            if feature_data.get("status") == "in-progress":
                return MCPToolResult(
                    success=False,
                    message="Feature is in-progress. Use force=True to delete.",
                )

        # Remove the feature
        del registry_data["features"][feature_id]

        # Write updated registry
        updated_json = json.dumps(registry_data, indent=2)
        self.remote_executor.write_file(registry_path, updated_json)
        self._invalidate_cache(project)

        return MCPToolResult(
            success=True,
            message=f"Deleted feature: {feature_title}",
            data={"feature_id": feature_id},
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

        For remote mode, runs forge init via SSH on the Mac.
        """
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
