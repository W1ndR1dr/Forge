"""
FlowForge HTTP Server - FastAPI wrapper for MCP and Web UI.

This server provides:
1. MCP Protocol endpoints for Claude Code integration
2. REST API for programmatic access
3. Simple Web UI for browser-based management

Deploy on Raspberry Pi with Tailscale for secure remote access.
"""

from contextlib import asynccontextmanager
from pathlib import Path
from typing import Optional
import json
import os
import subprocess

from fastapi import FastAPI, HTTPException, Request, WebSocket, WebSocketDisconnect
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel
import asyncio

from .mcp_server import FlowForgeMCPServer, create_mcp_response
from .brainstorm import parse_proposals, Proposal, ProposalStatus, check_shippable
from .prompt_builder import PromptBuilder
from .registry import FeatureRegistry, Feature
from .intelligence import IntelligenceEngine
from .remote import RemoteExecutor
from .worktree import WorktreeManager
from .paths import PathTranslator, create_path_translator
from .pi_registry import PiRegistryManager, get_pi_registry_manager


# =============================================================================
# Configuration
# =============================================================================


def get_config() -> dict:
    """Get server configuration from environment."""
    return {
        "projects_base": Path(
            os.environ.get(
                "FLOWFORGE_PROJECTS_PATH",
                os.path.expanduser("~/Projects/Active"),
            )
        ),
        # Mac projects path for SSH commands (Pi-native architecture)
        "mac_projects_base": os.environ.get("FLOWFORGE_MAC_PROJECTS_PATH"),
        "remote_host": os.environ.get("FLOWFORGE_MAC_HOST"),
        "remote_user": os.environ.get("FLOWFORGE_MAC_USER"),
        "port": int(os.environ.get("FLOWFORGE_PORT", "8081")),
        "host": os.environ.get("FLOWFORGE_HOST", "0.0.0.0"),
    }


# =============================================================================
# WebSocket Connection Manager
# =============================================================================


class ConnectionManager:
    """Manages WebSocket connections for real-time updates."""

    def __init__(self):
        self.active_connections: dict[str, list[WebSocket]] = {}  # project -> connections

    async def connect(self, websocket: WebSocket, project: str):
        await websocket.accept()
        if project not in self.active_connections:
            self.active_connections[project] = []
        self.active_connections[project].append(websocket)

    def disconnect(self, websocket: WebSocket, project: str):
        if project in self.active_connections:
            if websocket in self.active_connections[project]:
                self.active_connections[project].remove(websocket)

    async def broadcast(self, project: str, message: dict):
        """Broadcast a message to all connections for a project."""
        if project not in self.active_connections:
            return

        dead_connections = []
        for connection in self.active_connections[project]:
            try:
                await connection.send_json(message)
            except Exception:
                dead_connections.append(connection)

        # Clean up dead connections
        for conn in dead_connections:
            self.disconnect(conn, project)

    async def broadcast_feature_update(self, project: str, feature_id: str, action: str):
        """Broadcast a feature update event."""
        await self.broadcast(project, {
            "type": "feature_update",
            "project": project,
            "feature_id": feature_id,
            "action": action,  # created, updated, deleted, started, stopped
        })


ws_manager = ConnectionManager()


# =============================================================================
# App Lifecycle
# =============================================================================

mcp_server: Optional[FlowForgeMCPServer] = None
pi_registry: Optional[PiRegistryManager] = None
remote_executor: Optional[RemoteExecutor] = None
path_translator: Optional[PathTranslator] = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Initialize MCP server on startup."""
    global mcp_server, pi_registry, remote_executor, path_translator

    config = get_config()

    # Initialize path translator for Pi→Mac path conversion
    path_translator = create_path_translator()

    # Initialize Pi-local registry manager
    pi_registry = get_pi_registry_manager()

    # Initialize remote executor if running in remote mode (Pi)
    if config["remote_host"]:
        remote_executor = RemoteExecutor(
            host=config["remote_host"],
            user=config["remote_user"],
        )

    # Initialize MCP server with Pi-local registry
    mcp_server = FlowForgeMCPServer(
        projects_base=config["projects_base"],
        remote_host=config["remote_host"],
        remote_user=config["remote_user"],
        pi_registry=pi_registry,
    )

    print(f"FlowForge MCP Server started (Pi-native architecture)")
    print(f"  Projects: {config['projects_base']}")
    print(f"  Registry: {pi_registry.base_path}")
    if config["mac_projects_base"]:
        print(f"  Mac Projects: {config['mac_projects_base']}")
    if config["remote_host"]:
        print(f"  Remote: {config['remote_user']}@{config['remote_host']}")

    yield

    print("FlowForge MCP Server stopped")


app = FastAPI(
    title="FlowForge",
    description="AI-assisted parallel development orchestrator",
    version="0.1.0",
    lifespan=lifespan,
)


# =============================================================================
# MCP Protocol Endpoints
# =============================================================================


class MCPToolCall(BaseModel):
    """MCP tool call request."""

    name: str
    arguments: dict = {}


@app.get("/mcp/tools")
async def list_mcp_tools():
    """List available MCP tools."""
    return {"tools": mcp_server.get_tool_definitions()}


@app.post("/mcp/tools/call")
async def call_mcp_tool(tool_call: MCPToolCall):
    """Execute an MCP tool call."""
    result = mcp_server.call_tool(tool_call.name, tool_call.arguments)
    return create_mcp_response(result)


# Standard MCP Server manifest endpoint
@app.get("/.well-known/mcp.json")
async def mcp_manifest():
    """MCP server manifest for discovery."""
    return {
        "name": "FlowForge",
        "version": "0.1.0",
        "description": "AI-assisted parallel development orchestrator",
        "tools": mcp_server.get_tool_definitions(),
    }


# =============================================================================
# REST API Endpoints
# =============================================================================


@app.get("/api")
async def api_discovery():
    """List all available API endpoints for discoverability."""
    return {
        "version": "1.0.0",
        "documentation": "/docs",
        "openapi": "/openapi.json",
        "endpoints": {
            "system": {
                "GET /api": "API discovery (this endpoint)",
                "GET /api/projects": "List all FlowForge projects",
                "GET /api/system/status": "System status with Mac connectivity",
            },
            "project": {
                "POST /api/{project}/init": "Initialize FlowForge in project",
                "GET /api/{project}/status": "Get project statistics",
                "GET /api/{project}/health": "Check registry vs git state",
                "GET /api/{project}/features": "List all features",
                "POST /api/{project}/features": "Create new feature",
                "GET /api/{project}/merge-check": "Check all features for merge readiness",
                "POST /api/{project}/sync": "Sync registry between Pi and Mac",
                "GET /api/{project}/sync/status": "Check if registries are in sync",
                "POST /api/{project}/cleanup": "Clean orphaned worktrees",
            },
            "feature": {
                "PATCH /api/{project}/features/{id}": "Update feature attributes",
                "DELETE /api/{project}/features/{id}": "Delete feature (cleans worktree)",
                "POST /api/{project}/features/{id}/start": "Start working on feature",
                "POST /api/{project}/features/{id}/stop": "Mark ready for review",
                "POST /api/{project}/features/{id}/merge": "Merge to main",
            },
        },
    }


@app.get("/api/projects")
async def list_projects():
    """
    List all FlowForge projects.

    Uses Pi-local storage. If Mac is online, also discovers new projects.
    """
    result = mcp_server._list_projects()
    if not result.success:
        raise HTTPException(status_code=500, detail=result.message)

    # Check Mac online status
    mac_online = mcp_server._check_mac_online()

    response = result.data
    response["mac_online"] = mac_online

    return response


# =============================================================================
# System Status Endpoints (Offline-First)
# IMPORTANT: These must come BEFORE /api/{project} routes
# =============================================================================


@app.get("/api/system/status")
async def get_system_status():
    """
    Get system status including Mac connectivity.

    Returns:
        mac_online: Whether Mac is currently reachable
        local_projects: Number of projects in Pi-local storage
    """
    mac_online = mcp_server._check_mac_online()
    local_projects = len(pi_registry.list_projects()) if pi_registry else 0

    return {
        "mac_online": mac_online,
        "local_projects": local_projects,
        "registry_path": str(pi_registry.base_path) if pi_registry else None,
    }


# =============================================================================
# Project Initialization Endpoint
# =============================================================================


class InitProjectRequest(BaseModel):
    """Request to initialize FlowForge in a project."""
    quick: bool = True
    project_name: Optional[str] = None
    description: Optional[str] = None
    vision: Optional[str] = None
    target_users: Optional[str] = None
    coding_philosophy: Optional[str] = None
    ai_guidance: Optional[str] = None
    roadmap_path: Optional[str] = None


@app.post("/api/{project}/init")
async def init_project(project: str, request: InitProjectRequest):
    """
    Initialize FlowForge in a project directory.

    Creates:
    - .flowforge/config.json
    - .flowforge/registry.json
    - .flowforge/project-context.md
    - .flowforge/prompts/ directory
    - .flowforge/research/ directory

    Optionally imports features from roadmap markdown/RTF files.
    """
    # Delegate to MCP server (always remote mode - Pi architecture)
    result = mcp_server._init_project(
        project,
        quick=request.quick,
        project_name=request.project_name,
        description=request.description,
        vision=request.vision,
        target_users=request.target_users,
        coding_philosophy=request.coding_philosophy,
        ai_guidance=request.ai_guidance,
        roadmap_path=request.roadmap_path,
    )
    if not result.success:
        raise HTTPException(status_code=400, detail=result.message)
    return result.data


def _import_features_from_roadmap(
    project_root: Path,
    roadmap_dir: Path,
    registry: FeatureRegistry,
) -> int:
    """Import features from markdown/RTF files in a roadmap directory."""
    from .registry import Feature, Complexity
    import subprocess

    count = 0

    # Support both .md and .rtf files
    for pattern in ["**/*.md", "**/*.rtf"]:
        for file_path in roadmap_dir.glob(pattern):
            # Read content (convert RTF if needed)
            if file_path.suffix == ".rtf":
                try:
                    result = subprocess.run(
                        ["textutil", "-convert", "txt", "-stdout", str(file_path)],
                        capture_output=True,
                        text=True,
                    )
                    if result.returncode == 0:
                        content = result.stdout
                    else:
                        continue
                except Exception:
                    continue
            else:
                content = file_path.read_text()

            lines = content.split("\n")

            # First heading is the title
            title = None
            for line in lines:
                if line.startswith("# "):
                    title = line[2:].strip()
                    break

            if not title:
                title = file_path.stem.replace("-", " ").replace("_", " ").title()

            feature_id = FeatureRegistry.generate_id(title)

            # Skip if exists
            if registry.get_feature(feature_id):
                continue

            # Extract description (first paragraph after title)
            description = ""
            in_description = False
            for line in lines:
                if line.startswith("# "):
                    in_description = True
                    continue
                if in_description:
                    if line.startswith("#"):
                        break
                    if line.strip():
                        description += line + " "
            description = description.strip()[:500]

            feature = Feature(
                id=feature_id,
                title=title,
                description=description,
                complexity=Complexity.MEDIUM,
                spec_path=str(file_path.relative_to(project_root)),
            )
            registry.add_feature(feature)
            count += 1

    return count


@app.get("/api/{project}/features")
async def list_features(project: str, status: Optional[str] = None):
    """
    List features in a project.

    Uses Pi-local storage. Works even when Mac is offline.
    """
    result = mcp_server._list_features(project, status)
    if not result.success:
        raise HTTPException(status_code=404, detail=result.message)

    response = result.data
    response["mac_online"] = mcp_server._check_mac_online()

    return response


@app.get("/api/{project}/status")
async def get_status(project: str):
    """Get project status."""
    result = mcp_server._get_status(project)
    if not result.success:
        raise HTTPException(status_code=404, detail=result.message)
    return result.data


# =============================================================================
# Project Health Check (Registry vs Git State)
# =============================================================================


@app.get("/api/{project}/health")
async def get_project_health(project: str):
    """
    Check project health - compare registry state to actual git state.

    Uses Pi-local registry for feature data. Git operations require Mac online.

    Detects:
    - Branches merged but feature status != completed
    - Worktree paths set but directories missing
    - Orphan worktrees (exist but not tracked in registry)

    Returns:
    - healthy: bool
    - issues: list of detected problems with suggested fixes
    """
    # Get project context from Pi-local storage
    try:
        mac_project_path, config, registry = mcp_server._get_project_context(project)
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))
    issues = []

    # Get merged branches (local or remote)
    merged_branches = set()
    try:
        if remote_executor:
            result = remote_executor.get_merged_branches(mac_project_path)
            if result.success:
                for line in result.stdout.strip().split("\n"):
                    branch = line.strip().lstrip("* ")
                    if branch and branch != "main":
                        merged_branches.add(branch)
        else:
            result = subprocess.run(
                ["git", "branch", "--merged", "main"],
                cwd=mac_project_path,
                capture_output=True,
                text=True,
            )
            if result.returncode == 0:
                for line in result.stdout.strip().split("\n"):
                    branch = line.strip().lstrip("* ")
                    if branch and branch != "main":
                        merged_branches.add(branch)
    except Exception:
        pass

    # Get all worktrees (local or remote)
    worktree_paths = set()
    try:
        if remote_executor:
            result = remote_executor.list_worktrees(mac_project_path)
            if result.success:
                # Parse porcelain format
                current_path = None
                for line in result.stdout.strip().split("\n"):
                    if line.startswith("worktree "):
                        current_path = Path(line[9:])
                    elif line == "" and current_path:
                        # Skip the main worktree
                        if ".flowforge-worktrees" in str(current_path):
                            worktree_paths.add(current_path)
                        current_path = None
        else:
            worktree_manager = WorktreeManager(mac_project_path)
            worktrees = worktree_manager.list_worktrees()
            worktree_paths = {wt.path for wt in worktrees if not wt.is_main}
    except Exception:
        pass

    # Check 1: Branches merged but status != completed
    from .registry import FeatureStatus
    for feature in registry.list_features():
        if feature.status in (FeatureStatus.IN_PROGRESS, FeatureStatus.REVIEW):
            if feature.branch and feature.branch in merged_branches:
                issues.append({
                    "feature_id": feature.id,
                    "type": "branch_merged",
                    "message": f"'{feature.title}' branch is merged to main but status is {feature.status.value}",
                    "can_auto_fix": True,
                    "fix_action": "mark_completed",
                })

    # Check 2: Worktree path set but directory missing
    for feature in registry.list_features():
        if feature.worktree_path:
            wt_path = mac_project_path / feature.worktree_path
            if remote_executor:
                exists = remote_executor.dir_exists(wt_path)
            else:
                exists = wt_path.exists()

            if not exists:
                issues.append({
                    "feature_id": feature.id,
                    "type": "missing_worktree",
                    "message": f"'{feature.title}' has worktree path set but directory doesn't exist",
                    "can_auto_fix": True,
                    "fix_action": "clear_worktree",
                })

    # Check 3: Orphan worktrees (exist but not in registry)
    registry_worktree_paths = set()
    for feature in registry.list_features():
        if feature.worktree_path:
            registry_worktree_paths.add(mac_project_path / feature.worktree_path)

    for wt_path in worktree_paths:
        if wt_path not in registry_worktree_paths:
            # Check if it's in the .flowforge-worktrees directory
            if ".flowforge-worktrees" in str(wt_path):
                issues.append({
                    "feature_id": None,
                    "type": "orphan_worktree",
                    "message": f"Orphan worktree at {wt_path.name} (not tracked by any feature)",
                    "can_auto_fix": False,  # Ambiguous - user decides
                    "fix_action": None,
                    "worktree_path": str(wt_path),
                })

    return {
        "healthy": len(issues) == 0,
        "issues": issues,
        "checked_features": len(list(registry.list_features())),
        "checked_worktrees": len(worktree_paths),
    }


class ReconcileRequest(BaseModel):
    """Request to reconcile a feature's state."""
    action: str  # "mark_completed", "clear_worktree"


@app.post("/api/{project}/features/{feature_id}/reconcile")
async def reconcile_feature(project: str, feature_id: str, request: ReconcileRequest):
    """
    Reconcile a feature's state - fix drift between registry and git.

    Actions:
    - mark_completed: Update status to completed, clear worktree/branch
    - clear_worktree: Just clear the worktree_path field

    Uses Pi-local registry for feature data.
    """
    # Get project context from Pi-local storage
    try:
        mac_path, config, registry = mcp_server._get_project_context(project)
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))

    feature = registry.get_feature(feature_id)
    if not feature:
        raise HTTPException(status_code=404, detail=f"Feature not found: {feature_id}")

    from .registry import FeatureStatus
    from datetime import datetime

    if request.action == "mark_completed":
        # Mark as completed, clear git-related fields
        registry.update_feature(
            feature_id,
            status=FeatureStatus.COMPLETED,
            worktree_path=None,
            completed_at=datetime.now().isoformat(),
        )
        # Broadcast update
        await ws_manager.broadcast_feature_update(project, feature_id, "updated")
        return {
            "success": True,
            "message": f"Marked '{feature.title}' as completed",
            "new_status": "completed",
        }

    elif request.action == "clear_worktree":
        # Just clear the worktree path
        registry.update_feature(feature_id, worktree_path=None)
        # Broadcast update
        await ws_manager.broadcast_feature_update(project, feature_id, "updated")
        return {
            "success": True,
            "message": f"Cleared worktree path for '{feature.title}'",
        }

    else:
        raise HTTPException(
            status_code=400,
            detail=f"Unknown action: {request.action}. Valid: mark_completed, clear_worktree"
        )


class StartFeatureRequest(BaseModel):
    skip_experts: bool = False


@app.post("/api/{project}/features/{feature_id}/start")
async def start_feature(
    project: str,
    feature_id: str,
    request: StartFeatureRequest = StartFeatureRequest(),
):
    """
    Start working on a feature.

    This operation REQUIRES Mac to be online (creates git worktree).
    The MCP server will return an error if Mac is offline.
    """
    result = mcp_server._start_feature(project, feature_id, request.skip_experts)
    if not result.success:
        raise HTTPException(status_code=400, detail=result.message)

    # Broadcast update
    await ws_manager.broadcast_feature_update(project, feature_id, "started")

    result.data["mac_online"] = True
    return result.data


@app.post("/api/{project}/features/{feature_id}/stop")
async def stop_feature(project: str, feature_id: str):
    """Mark feature as ready for review."""
    result = mcp_server._stop_feature(project, feature_id)
    if not result.success:
        raise HTTPException(status_code=400, detail=result.message)

    # Broadcast update
    await ws_manager.broadcast_feature_update(project, feature_id, "stopped")

    return result.data


@app.post("/api/{project}/features/{feature_id}/demote")
async def demote_feature(
    project: str, feature_id: str, to_status: str = "idea"
):
    """Demote feature back to idea/inbox status, cleaning up worktree if needed."""
    result = mcp_server._demote_feature(project, feature_id, to_status)
    if not result.success:
        raise HTTPException(status_code=400, detail=result.message)

    # Broadcast update
    await ws_manager.broadcast_feature_update(project, feature_id, "demoted")

    return result.data


@app.post("/api/{project}/features/{feature_id}/smart-done")
async def smart_done_feature(project: str, feature_id: str):
    """
    Smart mark-as-done: detects if branch is merged and acts accordingly.

    If branch is merged to main: cleans up worktree, marks as completed (shipped).
    If branch not merged: marks as ready for review.
    If Mac is offline: falls back to simple review transition.
    """
    result = mcp_server._smart_done_feature(project, feature_id)
    if not result.success:
        raise HTTPException(status_code=400, detail=result.message)

    # Broadcast update based on outcome
    outcome = result.data.get("outcome", "review")
    action = "completed" if outcome == "shipped" else "stopped"
    await ws_manager.broadcast_feature_update(project, feature_id, action)

    return result.data


@app.get("/api/{project}/merge-check")
async def merge_check_all(project: str):
    """Check all features for merge readiness."""
    result = mcp_server._merge_check(project)
    if not result.success:
        raise HTTPException(status_code=500, detail=result.message)
    return result.data


@app.get("/api/{project}/features/{feature_id}/merge-check")
async def merge_check_feature(project: str, feature_id: str):
    """Check specific feature for merge readiness."""
    result = mcp_server._merge_check(project, feature_id)
    return {
        "ready": result.success,
        "message": result.message,
        "data": result.data,
    }


class MergeRequest(BaseModel):
    skip_validation: bool = False


@app.post("/api/{project}/features/{feature_id}/merge")
async def merge_feature(
    project: str,
    feature_id: str,
    request: MergeRequest = MergeRequest(),
):
    """
    Merge a feature into main.

    This operation REQUIRES Mac to be online (performs git merge).
    The MCP server will return an error if Mac is offline.
    """
    result = mcp_server._merge_feature(project, feature_id, request.skip_validation)
    if not result.success:
        raise HTTPException(status_code=400, detail=result.message)

    result.data["mac_online"] = True
    return result.data


@app.post("/api/{project}/cleanup")
async def cleanup_orphans(project: str):
    """
    Remove worktrees for features that are completed or deleted.

    This operation requires Mac to be online.
    """
    result = mcp_server._cleanup_orphans(project)
    if not result.success:
        raise HTTPException(status_code=400, detail=result.message)
    return result.data


class SyncRequest(BaseModel):
    direction: str = "pi-to-mac"  # "pi-to-mac", "mac-to-pi", or "bidirectional"


@app.post("/api/{project}/sync")
async def sync_registries(project: str, request: SyncRequest):
    """
    Sync registries between Pi and Mac.

    Args:
        direction: One of:
            - "pi-to-mac": Write Pi's registry to Mac (default)
            - "mac-to-pi": Read Mac's registry and replace Pi's
            - "bidirectional": Merge both, most recent updated_at wins per-feature

    This operation requires Mac to be online.
    """
    result = mcp_server._sync_registry(project, request.direction)
    if not result.success:
        raise HTTPException(status_code=400, detail=result.message)
    return {"message": result.message, **result.data}


@app.get("/api/{project}/sync/status")
async def sync_status(project: str):
    """
    Check if registries are in sync, show diff if not.

    This operation requires Mac to be online.
    """
    result = mcp_server._sync_status(project)
    if not result.success:
        raise HTTPException(status_code=400, detail=result.message)
    return result.data


class AddFeatureRequest(BaseModel):
    title: str
    description: Optional[str] = None
    tags: Optional[list[str]] = None
    priority: int = 5
    status: str = "inbox"  # Default to inbox for quick capture


@app.post("/api/{project}/features")
async def add_feature(project: str, request: AddFeatureRequest):
    """
    Add a new feature.

    This is a Pi-local operation - works even when Mac is offline.
    Default status is 'inbox' for quick capture (not counted in slot limit).
    """
    result = mcp_server._add_feature(
        project,
        request.title,
        request.description,
        request.tags,
        request.priority,
        request.status,
    )
    if not result.success:
        raise HTTPException(status_code=400, detail=result.message)

    # Broadcast update
    feature_id = result.data.get("feature_id")
    if feature_id:
        await ws_manager.broadcast_feature_update(project, feature_id, "created")

    return result.data


class UpdateFeatureRequest(BaseModel):
    title: Optional[str] = None
    description: Optional[str] = None
    status: Optional[str] = None
    priority: Optional[int] = None
    complexity: Optional[str] = None
    tags: Optional[list[str]] = None
    # Fields that can be cleared (set to null)
    worktree_path: Optional[str] = None
    branch: Optional[str] = None
    completed_at: Optional[str] = None


@app.patch("/api/{project}/features/{feature_id}")
async def update_feature(
    project: str,
    feature_id: str,
    request: UpdateFeatureRequest,
):
    """Update a feature's attributes. Supports clearing fields by setting them to null."""
    # Use model_fields_set to detect which fields were explicitly provided
    # This allows distinguishing between "not provided" and "explicitly set to null"
    updates = {
        field: getattr(request, field)
        for field in request.model_fields_set
    }

    result = mcp_server._update_feature(project, feature_id, **updates)
    if not result.success:
        raise HTTPException(status_code=400, detail=result.message)

    # Broadcast update
    await ws_manager.broadcast_feature_update(project, feature_id, "updated")

    return result.data


class UpdateFeatureSpecRequest(BaseModel):
    """Request to update a feature with refined spec details."""
    title: str
    description: str
    how_it_works: list[str] = []
    files_affected: list[str] = []
    estimated_scope: str = "Medium"


@app.patch("/api/{project}/features/{feature_id}/spec")
async def update_feature_spec(
    project: str,
    feature_id: str,
    request: UpdateFeatureSpecRequest,
):
    """
    Update a feature with refined spec details.

    Used when refining an inbox item through the brainstorm chat.
    Updates title, description, and stores spec metadata.

    This is a Pi-local operation - works even when Mac is offline.
    """
    from datetime import datetime
    from .registry import FeatureStatus

    # Get project context (from Pi-local storage)
    try:
        project_path, config, registry = mcp_server._get_project_context(project)
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))

    # Get feature from Pi-local registry
    feature = registry.get_feature(feature_id)
    if not feature:
        raise HTTPException(status_code=404, detail=f"Feature not found: {feature_id}")

    old_status = feature.status

    # Build description with spec details
    full_description = request.description
    if request.how_it_works:
        full_description += "\n\nHow it works:\n" + "\n".join(f"- {item}" for item in request.how_it_works)
    if request.files_affected:
        full_description += "\n\nFiles likely affected:\n" + "\n".join(f"- {f}" for f in request.files_affected)
    if request.estimated_scope:
        full_description += f"\n\nEstimated scope: {request.estimated_scope}"

    # Build updates
    updates = {
        "title": request.title,
        "description": full_description,
    }

    # If it's an inbox item, refining promotes it to idea
    if old_status == FeatureStatus.INBOX:
        updates["status"] = FeatureStatus.IDEA.value

    # Update feature in Pi-local registry
    registry.update_feature(feature_id, **updates)

    # Save to Pi-local storage
    mcp_server._save_registry(project, registry)

    # Broadcast update
    await ws_manager.broadcast_feature_update(project, feature_id, "updated")

    status_msg = " (promoted to idea)" if old_status == FeatureStatus.INBOX else ""
    return {"success": True, "message": f"Updated feature with refined spec: {request.title}{status_msg}"}


@app.post("/api/{project}/features/{feature_id}/refine")
async def refine_feature(project: str, feature_id: str):
    """
    Refine an inbox item into an idea ready to build.

    Takes a feature from 'inbox' status to 'idea' status.
    Checks the slot constraint before refining.
    """
    from .registry import FeatureStatus, MAX_PLANNED_FEATURES

    # Get project context
    try:
        project_path, config, registry = mcp_server._get_project_context(project)
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))

    # Get the feature
    feature = registry.get_feature(feature_id)
    if not feature:
        raise HTTPException(status_code=404, detail=f"Feature not found: {feature_id}")

    # Check it's an inbox item
    if feature.status != FeatureStatus.INBOX:
        raise HTTPException(
            status_code=400,
            detail=f"Feature is not in inbox (status: {feature.status.value})"
        )

    # Check slot constraint
    if not registry.can_add_idea():
        idea_titles = registry.get_idea_titles()
        raise HTTPException(
            status_code=400,
            detail=(
                f"You have {MAX_PLANNED_FEATURES} ideas ready to build. "
                f"Finish or delete one first: {', '.join(idea_titles[:MAX_PLANNED_FEATURES])}"
            )
        )

    # Refine: inbox → idea (use MCP server's update which handles SSH)
    result = mcp_server._update_feature(project, feature_id, status="idea")
    if not result.success:
        raise HTTPException(status_code=500, detail=result.message)

    # Broadcast update
    await ws_manager.broadcast_feature_update(project, feature_id, "updated")

    remaining = MAX_PLANNED_FEATURES - registry.count_ideas()

    return {
        "feature_id": feature_id,
        "title": feature.title,
        "status": "idea",
        "idea_count": registry.count_ideas(),
        "slots_remaining": remaining,
        "message": f"Refined: {feature.title} ({remaining} slot{'s' if remaining != 1 else ''} remaining)",
    }


class DeleteFeatureRequest(BaseModel):
    force: bool = False


@app.delete("/api/{project}/features/{feature_id}")
async def delete_feature(
    project: str,
    feature_id: str,
    force: bool = False,
):
    """Delete a feature from the registry."""
    result = mcp_server._delete_feature(project, feature_id, force)
    if not result.success:
        raise HTTPException(status_code=400, detail=result.message)

    # Broadcast update
    await ws_manager.broadcast_feature_update(project, feature_id, "deleted")

    return {"success": True, "message": f"Feature {feature_id} deleted"}


# =============================================================================
# Git Status Endpoint
# =============================================================================


@app.get("/api/{project}/features/{feature_id}/git-status")
async def get_git_status(project: str, feature_id: str):
    """
    Get git status for a feature's worktree.

    Uses Pi-local registry for feature data. Git operations require Mac online.

    Returns:
    - exists: whether the worktree exists
    - has_changes: whether there are uncommitted changes
    - changes: list of changed files
    - ahead_of_main: commits ahead of main
    - behind_main: commits behind main
    """
    # Get project context from Pi-local storage
    try:
        mac_path, config, registry = mcp_server._get_project_context(project)
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))

    feature = registry.get_feature(feature_id)
    if not feature:
        raise HTTPException(status_code=404, detail=f"Feature not found: {feature_id}")

    # Check if Mac is online for git operations
    mac_online = mcp_server._check_mac_online() if mcp_server else True

    if remote_executor:
        # Remote mode - need Mac online for git status
        if not mac_online:
            return {
                "exists": False,
                "has_changes": False,
                "changes": [],
                "commit_count": 0,
                "ahead_of_main": 0,
                "behind_main": 0,
                "mac_offline": True,
            }

        # Run git status via SSH
        worktree_path = feature.worktree_path
        if not worktree_path:
            return {
                "exists": False,
                "has_changes": False,
                "changes": [],
                "commit_count": 0,
                "ahead_of_main": 0,
                "behind_main": 0,
            }

        full_worktree_path = mac_path / worktree_path

        # Check if worktree exists
        if not remote_executor.dir_exists(full_worktree_path):
            return {
                "exists": False,
                "has_changes": False,
                "changes": [],
                "commit_count": 0,
                "ahead_of_main": 0,
                "behind_main": 0,
            }

        # Get git status via SSH
        status_result = remote_executor.run_command(
            ["git", "-C", str(full_worktree_path), "status", "--porcelain"],
            timeout=10
        )
        changes = []
        if status_result.success and status_result.stdout.strip():
            changes = [line.strip() for line in status_result.stdout.strip().split("\n") if line.strip()]

        return {
            "exists": True,
            "has_changes": len(changes) > 0,
            "changes": changes,
            "commit_count": 0,  # Would need additional git commands
            "ahead_of_main": 0,
            "behind_main": 0,
        }
    else:
        # Local mode (running on Mac) - use WorktreeManager directly
        worktree_manager = WorktreeManager(mac_path)
        status = worktree_manager.get_status(feature_id)

        return {
            "exists": status.exists,
            "has_changes": status.has_changes,
            "changes": status.changes,
            "commit_count": status.commit_count,
            "ahead_of_main": status.ahead_of_main,
            "behind_main": status.behind_main,
        }


# =============================================================================
# Prompt Generation Endpoint
# =============================================================================


@app.get("/api/{project}/features/{feature_id}/prompt")
async def get_feature_prompt(project: str, feature_id: str):
    """
    Generate and return implementation prompt for a feature.

    Uses Pi-local registry for feature data. Reads Mac files via SSH
    for full prompt generation (requires Mac online).
    """
    # Get project context from Pi-local storage
    try:
        mac_path, config, registry = mcp_server._get_project_context(project)
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))

    feature = registry.get_feature(feature_id)
    if not feature:
        raise HTTPException(status_code=404, detail=f"Feature not found: {feature_id}")

    # Check if Mac is online for file reading
    mac_online = mcp_server._check_mac_online() if mcp_server else True

    if remote_executor and mac_online:
        # Remote mode with Mac online - read files via SSH
        claude_md_content = ""
        claude_md_path = mac_path / "CLAUDE.md"
        content = remote_executor.read_file(claude_md_path)
        if content:
            claude_md_content = content

        spec_content = ""
        if feature.spec_path:
            spec_path = mac_path / feature.spec_path
            content = remote_executor.read_file(spec_path)
            if content:
                spec_content = content

        # Build prompt with available content
        prompt = _build_prompt_from_parts(
            feature=feature,
            claude_md_content=claude_md_content,
            spec_content=spec_content,
            project_name=project,
        )
    elif remote_executor and not mac_online:
        # Remote mode but Mac offline - return basic prompt
        prompt = _build_prompt_from_parts(
            feature=feature,
            claude_md_content="",
            spec_content="",
            project_name=project,
            mac_offline=True,
        )
    else:
        # Local mode (running on Mac) - use PromptBuilder directly
        intelligence = IntelligenceEngine(mac_path)
        prompt_builder = PromptBuilder(mac_path, registry, intelligence)
        prompt = prompt_builder.build_for_feature(
            feature_id,
            config.project.claude_md_path,  # Was missing - caused "No CLAUDE.md found"
            include_experts=True,
            include_research=True,
        )

    return {"prompt": prompt, "feature_id": feature_id}


def _build_prompt_from_parts(
    feature: Feature,
    claude_md_content: str,
    spec_content: str,
    project_name: str,
    mac_offline: bool = False,
) -> str:
    """Build implementation prompt from parts (for remote mode)."""
    parts = []

    if mac_offline:
        parts.append(
            "⚠️ Note: Mac is offline. This is a basic prompt without project context.\n"
            "For full context, ensure your Mac is online and accessible.\n"
        )

    parts.append(f"# Implement: {feature.title}\n")

    if feature.description:
        parts.append(f"## Description\n{feature.description}\n")

    if spec_content:
        parts.append(f"## Specification\n{spec_content}\n")

    if claude_md_content:
        parts.append(f"## Project Context\n{claude_md_content}\n")

    # Check extensions for key_files (may be set during refinement)
    key_files = feature.extensions.get("key_files") if feature.extensions else None
    if key_files:
        parts.append("## Key Files\n" + "\n".join(f"- {f}" for f in key_files) + "\n")

    parts.append(
        "\n## Instructions\n"
        "1. Read and understand the existing codebase patterns\n"
        "2. Implement the feature following project conventions\n"
        "3. Test your changes thoroughly\n"
        "4. Commit with a clear message describing what was done\n"
    )

    return "\n".join(parts)


# =============================================================================
# Brainstorm / Proposal Endpoints
# =============================================================================


class BrainstormParseRequest(BaseModel):
    """Request to parse brainstorm output."""
    claude_output: str


class ProposalResponse(BaseModel):
    """A proposal from brainstorm parsing."""
    title: str
    description: str
    priority: int
    complexity: str
    tags: list[str]
    rationale: str
    status: str


@app.post("/api/{project}/brainstorm/parse")
async def parse_brainstorm_output(project: str, request: BrainstormParseRequest):
    """Parse brainstorm output into structured proposals."""
    proposals = parse_proposals(request.claude_output)

    return {
        "proposals": [
            {
                "title": p.title,
                "description": p.description,
                "priority": p.priority,
                "complexity": p.complexity,
                "tags": p.tags,
                "rationale": p.rationale,
                "status": p.status.value,
            }
            for p in proposals
        ],
        "count": len(proposals),
    }


class ApproveProposalsRequest(BaseModel):
    """Request to approve and add proposals to registry."""
    proposals: list[dict]  # List of proposal dicts to add


@app.post("/api/{project}/proposals/approve")
async def approve_proposals(project: str, request: ApproveProposalsRequest):
    """
    Add approved proposals to the feature registry.

    This is a Pi-local operation - works even when Mac is offline.
    """
    # Import Feature and Complexity here to avoid circular import at top
    from .registry import Feature, Complexity

    # Get project context (from Pi-local storage)
    try:
        project_path, config, registry = mcp_server._get_project_context(project)
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))

    added = []
    skipped = []

    for proposal_dict in request.proposals:
        proposal = Proposal.from_dict(proposal_dict)
        feature_id = FeatureRegistry.generate_id(proposal.title)

        # Skip if exists
        if registry.get_feature(feature_id):
            skipped.append(proposal.title)
            continue

        # Map complexity string to enum
        try:
            complexity_enum = Complexity(proposal.complexity)
        except ValueError:
            complexity_enum = Complexity.MEDIUM

        feature = Feature(
            id=feature_id,
            title=proposal.title,
            description=proposal.description,
            priority=proposal.priority,
            complexity=complexity_enum,
            tags=proposal.tags,
        )
        registry.add_feature(feature)
        added.append(proposal.title)

    # Save to Pi-local storage
    mcp_server._save_registry(project, registry)

    return {
        "added": added,
        "skipped": skipped,
        "added_count": len(added),
        "skipped_count": len(skipped),
    }


# =============================================================================
# Web UI
# =============================================================================


@app.get("/", response_class=HTMLResponse)
async def web_ui():
    """Simple web UI for browser access."""
    html = """
<!DOCTYPE html>
<html>
<head>
    <title>FlowForge</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        :root {
            --bg: #1a1a2e;
            --card: #16213e;
            --accent: #0f3460;
            --text: #e4e4e4;
            --muted: #888;
            --success: #4ade80;
            --warning: #facc15;
            --error: #f87171;
            --blue: #60a5fa;
        }

        * { box-sizing: border-box; margin: 0; padding: 0; }

        body {
            font-family: -apple-system, BlinkMacSystemFont, 'SF Pro', system-ui, sans-serif;
            background: var(--bg);
            color: var(--text);
            padding: 20px;
            max-width: 800px;
            margin: 0 auto;
        }

        h1 {
            font-size: 24px;
            margin-bottom: 24px;
            display: flex;
            align-items: center;
            gap: 10px;
        }

        h2 {
            font-size: 18px;
            margin: 24px 0 12px;
            color: var(--muted);
        }

        .project {
            background: var(--card);
            border-radius: 12px;
            padding: 16px;
            margin-bottom: 12px;
            cursor: pointer;
            transition: transform 0.1s;
        }

        .project:hover {
            transform: translateX(4px);
        }

        .project-name {
            font-weight: 600;
            font-size: 16px;
        }

        .project-path {
            color: var(--muted);
            font-size: 13px;
            margin-top: 4px;
        }

        .feature {
            background: var(--card);
            border-radius: 8px;
            padding: 12px 16px;
            margin-bottom: 8px;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }

        .feature-title {
            font-weight: 500;
        }

        .feature-id {
            color: var(--muted);
            font-size: 12px;
        }

        .status {
            padding: 4px 10px;
            border-radius: 12px;
            font-size: 12px;
            font-weight: 500;
        }

        .status.inbox { background: var(--accent); opacity: 0.7; }
        .status.idea { background: var(--accent); }
        .status.in-progress { background: var(--blue); color: #000; }
        .status.review { background: var(--warning); color: #000; }
        .status.completed { background: var(--success); color: #000; }
        .status.blocked { background: var(--error); }

        .stats {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(100px, 1fr));
            gap: 12px;
            margin-bottom: 24px;
        }

        .stat {
            background: var(--card);
            border-radius: 8px;
            padding: 12px;
            text-align: center;
        }

        .stat-value {
            font-size: 24px;
            font-weight: 600;
        }

        .stat-label {
            font-size: 12px;
            color: var(--muted);
        }

        .btn {
            background: var(--blue);
            color: #000;
            border: none;
            padding: 8px 16px;
            border-radius: 6px;
            font-weight: 500;
            cursor: pointer;
            font-size: 13px;
        }

        .btn:hover {
            opacity: 0.9;
        }

        .back-btn {
            background: var(--accent);
            color: var(--text);
            margin-bottom: 16px;
        }

        .loading {
            text-align: center;
            color: var(--muted);
            padding: 40px;
        }

        .error {
            background: rgba(248, 113, 113, 0.2);
            border: 1px solid var(--error);
            border-radius: 8px;
            padding: 12px;
            margin: 12px 0;
        }

        .actions {
            display: flex;
            gap: 8px;
        }
    </style>
</head>
<body>
    <div id="app">
        <div class="loading">Loading...</div>
    </div>

    <script>
        const app = document.getElementById('app');
        let currentProject = null;

        async function fetchJSON(url) {
            const res = await fetch(url);
            if (!res.ok) throw new Error(await res.text());
            return res.json();
        }

        async function postJSON(url, data = {}) {
            const res = await fetch(url, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(data),
            });
            if (!res.ok) throw new Error(await res.text());
            return res.json();
        }

        async function showProjects() {
            try {
                const data = await fetchJSON('/api/projects');
                app.innerHTML = `
                    <h1>🔨 FlowForge</h1>
                    <h2>Projects</h2>
                    ${data.projects.map(p => `
                        <div class="project" onclick="showProject('${p.name}')">
                            <div class="project-name">${p.name}</div>
                            <div class="project-path">${p.path}</div>
                        </div>
                    `).join('')}
                `;
            } catch (e) {
                app.innerHTML = `<div class="error">${e.message}</div>`;
            }
        }

        async function showProject(name) {
            currentProject = name;
            try {
                const [status, features] = await Promise.all([
                    fetchJSON(`/api/${name}/status`),
                    fetchJSON(`/api/${name}/features`),
                ]);

                const stats = status.stats.by_status || {};

                app.innerHTML = `
                    <button class="btn back-btn" onclick="showProjects()">← Back</button>
                    <h1>${status.project_name}</h1>

                    <div class="stats">
                        <div class="stat">
                            <div class="stat-value">${stats.inbox || 0}</div>
                            <div class="stat-label">Inbox</div>
                        </div>
                        <div class="stat">
                            <div class="stat-value">${stats.idea || 0}</div>
                            <div class="stat-label">Ideas</div>
                        </div>
                        <div class="stat">
                            <div class="stat-value">${stats['in-progress'] || 0}</div>
                            <div class="stat-label">Building</div>
                        </div>
                        <div class="stat">
                            <div class="stat-value">${stats.completed || 0}</div>
                            <div class="stat-label">Shipped</div>
                        </div>
                    </div>

                    <h2>Features</h2>
                    ${features.features.map(f => `
                        <div class="feature">
                            <div>
                                <div class="feature-title">${f.title}</div>
                                <div class="feature-id">${f.id}</div>
                            </div>
                            <div class="actions">
                                <span class="status ${f.status}">${f.status}</span>
                                ${f.status === 'idea' ?
                                    `<button class="btn" onclick="startFeature('${f.id}')">Start</button>` : ''}
                                ${f.status === 'in-progress' ?
                                    `<button class="btn" onclick="stopFeature('${f.id}')">Review</button>` : ''}
                                ${f.status === 'review' ?
                                    `<button class="btn" onclick="mergeFeature('${f.id}')">Ship</button>` : ''}
                            </div>
                        </div>
                    `).join('')}
                `;
            } catch (e) {
                app.innerHTML = `
                    <button class="btn back-btn" onclick="showProjects()">← Back</button>
                    <div class="error">${e.message}</div>
                `;
            }
        }

        async function startFeature(id) {
            try {
                const result = await postJSON(`/api/${currentProject}/features/${id}/start`);
                alert('Feature started! Prompt copied to clipboard (if available).');
                showProject(currentProject);
            } catch (e) {
                alert('Error: ' + e.message);
            }
        }

        async function stopFeature(id) {
            try {
                await postJSON(`/api/${currentProject}/features/${id}/stop`);
                showProject(currentProject);
            } catch (e) {
                alert('Error: ' + e.message);
            }
        }

        async function mergeFeature(id) {
            if (!confirm('Merge this feature into main?')) return;
            try {
                await postJSON(`/api/${currentProject}/features/${id}/merge`);
                alert('Feature merged successfully!');
                showProject(currentProject);
            } catch (e) {
                alert('Error: ' + e.message);
            }
        }

        showProjects();
    </script>
</body>
</html>
    """
    return HTMLResponse(content=html)


# =============================================================================
# Health Check
# =============================================================================


@app.get("/health")
async def health():
    """Health check endpoint."""
    config = get_config()
    return {
        "status": "healthy",
        "projects_base": str(config["projects_base"]),
        "remote_host": config["remote_host"],
    }


# =============================================================================
# Session Memory Endpoints (Welcome Back)
# =============================================================================


# Global session memory instance
_session_memory = None


def get_session_memory():
    """Get or create the session memory instance."""
    global _session_memory
    if _session_memory is None:
        from .session_memory import SessionMemory
        config = get_config()
        data_dir = config["projects_base"] / ".flowforge-memory"
        _session_memory = SessionMemory(data_dir)
    return _session_memory


@app.get("/api/{project}/session")
async def get_session_state(project: str):
    """
    Get session state for welcome-back experience.

    This is a Pi-local operation - works even when Mac is offline.
    """
    memory = get_session_memory()

    # Also fetch current feature status from Pi-local storage
    try:
        project_path, config, registry = mcp_server._get_project_context(project)

        # Update in-progress and ready-to-ship
        in_progress = [f.title for f in registry.list_features() if f.status.value == "in-progress"]
        ready = [f.title for f in registry.list_features() if f.status.value == "review"]

        memory.update_in_progress(project, in_progress)
        memory.update_ready_to_ship(project, ready)

        # Update streak
        stats = registry.get_shipping_stats()
        memory.update_streak(project, stats.current_streak)
    except ValueError:
        # Project not found in Pi-local storage - return empty session
        pass

    session = memory.get_session(project)
    return session.to_dict()


@app.get("/api/{project}/welcome")
async def get_welcome_message(project: str):
    """Get a welcome-back message summarizing what happened."""
    memory = get_session_memory()
    message = memory.generate_welcome_message(project)

    return {
        "message": message,
        "project": project,
    }


@app.post("/api/{project}/session/visit")
async def record_visit(project: str):
    """Record that user visited this project (clears pending changes)."""
    memory = get_session_memory()
    memory.record_visit(project)
    return {"success": True}


# =============================================================================
# Shipping Stats Endpoints (Wave 4.4)
# =============================================================================


@app.get("/api/{project}/shipping-stats")
async def get_shipping_stats(project: str):
    """
    Get shipping streak statistics for a project.

    This is a Pi-local operation - works even when Mac is offline.
    """
    # Get project context (from Pi-local storage)
    try:
        project_path, config, registry = mcp_server._get_project_context(project)
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))

    stats = registry.get_shipping_stats()

    return {
        "current_streak": stats.current_streak,
        "longest_streak": stats.longest_streak,
        "total_shipped": stats.total_shipped,
        "last_ship_date": stats.last_ship_date,
        "streak_display": registry.get_streak_display(),
    }


# =============================================================================
# WebSocket Endpoint
# =============================================================================


@app.websocket("/ws/{project}")
async def websocket_endpoint(websocket: WebSocket, project: str):
    """
    WebSocket endpoint for real-time updates.

    Clients connect to /ws/{project} to receive updates for a specific project.

    Message format (from server):
    {
        "type": "feature_update",
        "project": "ProjectName",
        "feature_id": "feature-id",
        "action": "created" | "updated" | "deleted" | "started" | "stopped"
    }

    Clients can send ping messages to keep connection alive:
    {"type": "ping"}

    Server responds with:
    {"type": "pong"}
    """
    await ws_manager.connect(websocket, project)

    try:
        while True:
            # Wait for messages from client (e.g., ping)
            data = await websocket.receive_json()

            if data.get("type") == "ping":
                await websocket.send_json({"type": "pong"})

    except WebSocketDisconnect:
        ws_manager.disconnect(websocket, project)
    except Exception:
        ws_manager.disconnect(websocket, project)


# =============================================================================
# Brainstorm WebSocket Endpoint (Chat-to-Spec)
# =============================================================================


# Store active brainstorm sessions
# Key: "project" for general brainstorm, "project:feature_id" for refinement
brainstorm_sessions: dict = {}

# Extension key migration: crystallization_history → refinement_history
_OLD_HISTORY_KEY = "crystallization_history"
_NEW_HISTORY_KEY = "refinement_history"
_SESSION_ID_KEY = "claude_code_session_id"


def _get_session_key(project: str, feature_id: Optional[str] = None) -> str:
    """Get the session key for a brainstorm session."""
    if feature_id:
        return f"{project}:{feature_id}"
    return project


def _load_feature_history(project_name: str, feature_id: str) -> list[dict]:
    """Load refinement history from a feature's extensions (Pi-local)."""
    try:
        project_path, config, registry = mcp_server._get_project_context(project_name)
        feature = registry.get_feature(feature_id)
        if feature and feature.extensions:
            # Try new key first, fall back to old key for migration
            history = feature.extensions.get(_NEW_HISTORY_KEY)
            if history is None:
                history = feature.extensions.get(_OLD_HISTORY_KEY, [])
            return history
    except Exception:
        pass
    return []


def _save_feature_history(project_name: str, feature_id: str, messages: list[dict]) -> None:
    """Save refinement history to a feature's extensions (Pi-local)."""
    try:
        project_path, config, registry = mcp_server._get_project_context(project_name)
        feature = registry.get_feature(feature_id)
        if feature:
            if feature.extensions is None:
                feature.extensions = {}
            # Always write to new key
            feature.extensions[_NEW_HISTORY_KEY] = messages
            # Remove old key if present (migration)
            feature.extensions.pop(_OLD_HISTORY_KEY, None)
            registry.update_feature(feature_id, extensions=feature.extensions)
            mcp_server._save_registry(project_name, registry)
    except Exception as e:
        print(f"Failed to save refinement history: {e}")


def _load_feature_session_id(project_name: str, feature_id: str) -> Optional[str]:
    """Load Claude Code session ID from a feature's extensions."""
    try:
        project_path, config, registry = mcp_server._get_project_context(project_name)
        feature = registry.get_feature(feature_id)
        if feature and feature.extensions:
            return feature.extensions.get(_SESSION_ID_KEY)
    except Exception:
        pass
    return None


def _save_feature_session_id(project_name: str, feature_id: str, session_id: Optional[str]) -> None:
    """Save or clear Claude Code session ID in a feature's extensions."""
    try:
        project_path, config, registry = mcp_server._get_project_context(project_name)
        feature = registry.get_feature(feature_id)
        if feature:
            if feature.extensions is None:
                feature.extensions = {}
            if session_id:
                feature.extensions[_SESSION_ID_KEY] = session_id
            else:
                # Clear session_id if None/empty
                feature.extensions.pop(_SESSION_ID_KEY, None)
            registry.update_feature(feature_id, extensions=feature.extensions)
            mcp_server._save_registry(project_name, registry)
    except Exception as e:
        print(f"Failed to save session ID: {e}")


@app.websocket("/ws/{project}/brainstorm")
async def brainstorm_websocket(websocket: WebSocket, project: str):
    """
    WebSocket endpoint for real-time brainstorming with Claude.

    This enables the Chat-to-Spec experience where users have a conversation
    with Claude to refine feature ideas into implementable specs.

    Message format (from client):
    {
        "type": "message",
        "content": "I want to add dark mode..."
    }

    Message format (from server):
    {
        "type": "chunk",           # Streaming response chunk
        "content": "text..."
    }
    {
        "type": "message_complete", # Full message done
        "content": "full response"
    }
    {
        "type": "spec_ready",       # Spec is ready
        "spec": { ... }
    }
    """
    await websocket.accept()

    try:
        # Get project context from Pi-local storage
        existing_features = []
        project_context = ""

        try:
            project_path, config, registry = mcp_server._get_project_context(project)
            existing_features = [f.title for f in registry.list_features()]

            # Try to load project context from Mac (optional, may fail if offline)
            if remote_executor:
                context_path = project_path / ".flowforge" / "project-context.md"
                context_content = remote_executor.read_file(context_path)
                if context_content:
                    project_context = context_content
        except ValueError:
            # Project not found - continue with empty context
            pass

        # Create or get existing brainstorm session
        from .agents.brainstorm import BrainstormAgent

        # Track feature being refined (set by init message)
        refining_feature_id = None
        refining_feature_title = None

        # Use project-only key for initial connection (before init message)
        session_key = _get_session_key(project)

        if session_key not in brainstorm_sessions:
            brainstorm_sessions[session_key] = BrainstormAgent(
                project_name=project,
                project_context=project_context,
                existing_features=existing_features,
            )

        agent = brainstorm_sessions[session_key]

        # Send session state on connect
        await websocket.send_json({
            "type": "session_state",
            "state": agent.get_conversation_state(),
        })

        while True:
            data = await websocket.receive_json()

            if data.get("type") == "init":
                # Client sending feature context for refinement mode
                refining_feature_id = data.get("feature_id")
                refining_feature_title = data.get("feature_title")

                # Update session key for feature-specific refinement
                session_key = _get_session_key(project, refining_feature_id)

                # Load existing history and session_id from the feature record
                existing_history = []
                existing_session_id = None
                if refining_feature_id:
                    existing_history = _load_feature_history(project, refining_feature_id)
                    existing_session_id = _load_feature_session_id(project, refining_feature_id)

                # Create session with feature context (and existing history/session)
                brainstorm_sessions[session_key] = BrainstormAgent(
                    project_name=project,
                    project_context=project_context,
                    existing_features=existing_features,
                    existing_feature_title=refining_feature_title,
                    existing_history=existing_history,  # For UI display
                    existing_session_id=existing_session_id,  # For --resume
                )
                agent = brainstorm_sessions[session_key]

                # Acknowledge init with full state (including resumed history)
                await websocket.send_json({
                    "type": "session_state",
                    "state": agent.get_conversation_state(),
                    "refining_feature_id": refining_feature_id,
                    "refining_feature_title": refining_feature_title,
                })

            elif data.get("type") == "message":
                user_message = data.get("content", "")

                # Send immediate processing status for UI feedback
                await websocket.send_json({
                    "type": "status",
                    "status": "processing",
                })

                # Stream the response
                full_response = []
                async for chunk in agent.send_message(user_message):
                    full_response.append(chunk)
                    await websocket.send_json({
                        "type": "chunk",
                        "content": chunk,
                    })

                # Send message complete
                await websocket.send_json({
                    "type": "message_complete",
                    "content": "".join(full_response),
                })

                # Persist history and session_id if refining a feature
                if refining_feature_id:
                    messages = [
                        {"role": msg.role, "content": msg.content}
                        for msg in agent.session.messages
                    ]
                    _save_feature_history(project, refining_feature_id, messages)

                    # Save Claude Code session_id for future --resume
                    if agent.session.claude_session_id:
                        _save_feature_session_id(project, refining_feature_id, agent.session.claude_session_id)

                # Check if spec is ready
                if agent.is_spec_ready():
                    spec = agent.get_spec()
                    await websocket.send_json({
                        "type": "spec_ready",
                        "spec": spec.to_dict() if spec else None,
                    })

            elif data.get("type") == "reset":
                # Reset the session
                brainstorm_sessions[session_key] = BrainstormAgent(
                    project_name=project,
                    project_context=project_context,
                    existing_features=existing_features,
                    existing_feature_title=refining_feature_title if refining_feature_id else None,
                )
                agent = brainstorm_sessions[session_key]

                # Clear persisted history and session_id if refining
                if refining_feature_id:
                    _save_feature_history(project, refining_feature_id, [])
                    _save_feature_session_id(project, refining_feature_id, None)

                await websocket.send_json({
                    "type": "session_reset",
                    "state": agent.get_conversation_state(),
                })

            elif data.get("type") == "ping":
                await websocket.send_json({"type": "pong"})

    except WebSocketDisconnect:
        pass
    except Exception as e:
        try:
            await websocket.send_json({
                "type": "error",
                "message": str(e),
            })
        except Exception:
            pass


# =============================================================================
# CLI Entry Point
# =============================================================================


def main():
    """Run the FlowForge server."""
    import uvicorn

    config = get_config()
    uvicorn.run(
        "flowforge.server:app",
        host=config["host"],
        port=config["port"],
        reload=True,
    )


if __name__ == "__main__":
    main()
