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

from fastapi import FastAPI, HTTPException, Request, WebSocket, WebSocketDisconnect
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel
import asyncio

from .mcp_server import FlowForgeMCPServer, create_mcp_response
from .brainstorm import parse_proposals, Proposal, ProposalStatus, check_shippable
from .prompt_builder import PromptBuilder
from .registry import FeatureRegistry
from .intelligence import IntelligenceEngine
from .feature_analyzer import FeatureAnalyzer, Complexity as AnalyzerComplexity, ExpertDomain as AnalyzerDomain
from .expert_router import ExpertRouter, ExpertDomain as RouterDomain
from .cache import CacheManager, get_cache_manager
from .sync import SyncManager, get_sync_manager
from .remote import RemoteExecutor
from .worktree import WorktreeManager


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
sync_manager: Optional[SyncManager] = None
cache_manager: Optional[CacheManager] = None
remote_executor: Optional[RemoteExecutor] = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Initialize MCP server, cache, and sync on startup."""
    global mcp_server, sync_manager, cache_manager, remote_executor

    config = get_config()
    mcp_server = FlowForgeMCPServer(
        projects_base=config["projects_base"],
        remote_host=config["remote_host"],
        remote_user=config["remote_user"],
    )

    # Initialize cache manager
    cache_manager = get_cache_manager()

    # Initialize sync manager if running in remote mode (Pi)
    if config["remote_host"]:
        remote_executor = RemoteExecutor(
            host=config["remote_host"],
            user=config["remote_user"],
        )
        sync_manager = SyncManager(remote_executor, cache_manager)

        # Register callback for status changes
        def on_mac_status_change(online: bool):
            status = "online" if online else "offline"
            print(f"  Mac status: {status}")

        sync_manager.on_status_change(on_mac_status_change)

        # Start background sync tasks
        await sync_manager.start_background_tasks()
        print(f"  Sync: Background tasks started")

    print(f"FlowForge MCP Server started")
    print(f"  Projects: {config['projects_base']}")
    if config["remote_host"]:
        print(f"  Remote: {config['remote_user']}@{config['remote_host']}")
    print(f"  Cache: {cache_manager.db_path}")

    yield

    # Stop background tasks
    if sync_manager:
        await sync_manager.stop_background_tasks()

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


@app.get("/api/projects")
async def list_projects():
    """
    List all FlowForge projects.

    If Mac is offline, returns cached project list.
    Response includes `from_cache` and `mac_online` flags.
    """
    # Check if we should use cache (Mac offline in remote mode)
    mac_online = True
    from_cache = False

    if sync_manager and not sync_manager.mac_online:
        # Mac is offline - use cache
        mac_online = False
        from_cache = True
        cached_projects = cache_manager.get_all_cached_projects()

        if cached_projects:
            return {
                "projects": cached_projects,
                "from_cache": True,
                "mac_online": False,
                "pending_sync": cache_manager.get_pending_count(),
            }
        else:
            # No cache available
            raise HTTPException(
                status_code=503,
                detail="Mac is offline and no cached data available"
            )

    # Mac is online (or running locally) - fetch fresh data
    result = mcp_server._list_projects()
    if not result.success:
        # Try cache as fallback
        if cache_manager:
            cached_projects = cache_manager.get_all_cached_projects()
            if cached_projects:
                return {
                    "projects": cached_projects,
                    "from_cache": True,
                    "mac_online": False,
                    "pending_sync": cache_manager.get_pending_count(),
                }
        raise HTTPException(status_code=500, detail=result.message)

    # Update cache with fresh data
    if cache_manager and result.data and "projects" in result.data:
        for project in result.data["projects"]:
            cache_manager.cache_project(
                name=project["name"],
                path=project["path"],
            )

    # Add metadata to response
    response = result.data
    response["from_cache"] = False
    response["mac_online"] = True
    response["pending_sync"] = cache_manager.get_pending_count() if cache_manager else 0

    return response


# =============================================================================
# System Status Endpoints (Offline-First)
# IMPORTANT: These must come BEFORE /api/{project} routes
# =============================================================================


@app.get("/api/system/status")
async def get_system_status():
    """
    Get system status including Mac connectivity and pending operations.

    Returns:
        mac_online: Whether Mac is currently reachable
        last_check: Timestamp of last health check
        last_sync: Timestamp of last successful sync
        pending_operations: Number of queued operations
        cache_stats: Cache database statistics
    """
    if sync_manager:
        mac_status = sync_manager.get_status()
        return {
            "mac_online": mac_status.online,
            "last_check": mac_status.last_check,
            "last_sync": mac_status.last_successful_sync,
            "pending_operations": mac_status.pending_operations,
            "cache_stats": cache_manager.get_cache_stats() if cache_manager else None,
        }
    else:
        # Running in local mode (on Mac directly)
        return {
            "mac_online": True,
            "last_check": None,
            "last_sync": None,
            "pending_operations": 0,
            "cache_stats": cache_manager.get_cache_stats() if cache_manager else None,
        }


@app.post("/api/system/sync")
async def force_sync():
    """Force an immediate sync with Mac."""
    if not sync_manager:
        return {"success": True, "message": "Running in local mode, no sync needed"}

    if not sync_manager.mac_online:
        raise HTTPException(status_code=503, detail="Mac is offline")

    result = await sync_manager.sync_all_projects()
    return {
        "success": result.success,
        "message": result.message,
        "synced_projects": result.synced_projects,
        "failed_operations": result.failed_operations,
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
    config = get_config()
    project_path = config["projects_base"] / project
    flowforge_dir = project_path / ".flowforge"

    # Handle remote mode - delegate to MCP server
    if mcp_server.is_remote:
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

    # Local mode - initialize directly
    if not project_path.exists():
        raise HTTPException(status_code=404, detail=f"Project directory not found: {project}")

    # Check if already initialized
    if flowforge_dir.exists():
        raise HTTPException(
            status_code=400,
            detail=f"Project already initialized. Delete .flowforge to reinitialize."
        )

    # Use the init module
    from .init import EnhancedInitializer, ProjectContext
    from .config import FlowForgeConfig, ProjectConfig, detect_project_settings
    from .registry import FeatureRegistry, Feature, Complexity

    initializer = EnhancedInitializer(project_path)

    # Detect tech stack and settings
    tech_stack = initializer.detect_tech_stack()
    detected = detect_project_settings(project_path)

    # Apply overrides
    if request.project_name:
        detected.name = request.project_name

    # Create config
    forge_config = FlowForgeConfig(project=detected)
    forge_config.save(project_path)

    # Create registry
    registry = FeatureRegistry.create_new(project_path)

    # Create directories
    (project_path / ".flowforge" / "prompts").mkdir(parents=True, exist_ok=True)
    (project_path / ".flowforge" / "research").mkdir(parents=True, exist_ok=True)

    # Create project context
    context = ProjectContext(
        name=request.project_name or detected.name,
        description=request.description or "",
        vision=request.vision or "",
        target_users=request.target_users or "",
        tech_stack=tech_stack,
        coding_philosophy=request.coding_philosophy or "",
        ai_guidance=request.ai_guidance or "Engage plan mode and ultrathink before implementing.",
    )
    context_path = context.save(project_path)

    # Import features from roadmap if specified
    features_imported = 0
    if request.roadmap_path:
        roadmap_full_path = project_path / request.roadmap_path
        if roadmap_full_path.exists():
            features_imported = _import_features_from_roadmap(
                project_path,
                roadmap_full_path,
                registry,
            )

    return {
        "success": True,
        "project_name": detected.name,
        "main_branch": detected.main_branch,
        "tech_stack": tech_stack,
        "features_imported": features_imported,
        "config_path": str(project_path / ".flowforge" / "config.json"),
        "registry_path": str(project_path / ".flowforge" / "registry.json"),
        "context_path": str(context_path),
    }


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

    If Mac is offline, returns cached features.
    Response includes `from_cache` and `mac_online` flags.
    """
    # Check if we should use cache (Mac offline in remote mode)
    if sync_manager and not sync_manager.mac_online:
        # Mac is offline - use cache
        cached_features = cache_manager.get_cached_features(project)

        if cached_features:
            # Filter by status if requested
            if status:
                cached_features = [f for f in cached_features if f.get("status") == status]

            return {
                "features": cached_features,
                "from_cache": True,
                "mac_online": False,
                "pending_sync": cache_manager.get_pending_count(project),
            }
        else:
            raise HTTPException(
                status_code=503,
                detail=f"Mac is offline and no cached data for {project}"
            )

    # Mac is online - fetch fresh data
    result = mcp_server._list_features(project, status)
    if not result.success:
        # Try cache as fallback
        if cache_manager:
            cached_features = cache_manager.get_cached_features(project)
            if cached_features:
                if status:
                    cached_features = [f for f in cached_features if f.get("status") == status]
                return {
                    "features": cached_features,
                    "from_cache": True,
                    "mac_online": False,
                    "pending_sync": cache_manager.get_pending_count(project),
                }
        raise HTTPException(status_code=404, detail=result.message)

    # Update cache with fresh data (need to get full registry)
    if cache_manager and sync_manager:
        # The MCP server should have cached the registry - we can update our cache
        cached_project = cache_manager.get_cached_project(project)
        if cached_project:
            # Registry already cached via project endpoint
            pass

    # Add metadata to response
    response = result.data
    response["from_cache"] = False
    response["mac_online"] = True
    response["pending_sync"] = cache_manager.get_pending_count(project) if cache_manager else 0

    return response


@app.get("/api/{project}/status")
async def get_status(project: str):
    """Get project status."""
    result = mcp_server._get_status(project)
    if not result.success:
        raise HTTPException(status_code=404, detail=result.message)
    return result.data


@app.get("/api/{project}/github-health")
async def get_github_health(project: str):
    """
    Get GitHub health check for a project.

    Checks:
    - Git repository exists
    - Origin remote configured
    - SSH authentication works
    - Main branch exists
    - Similar repos on GitHub
    """
    from .github_health import GitHubHealthChecker

    project_path = mcp_server.projects_base / project
    if not project_path.exists():
        raise HTTPException(status_code=404, detail=f"Project not found: {project}")

    checker = GitHubHealthChecker(project_path)
    report = checker.run_all_checks()
    similar = checker.find_similar_repos()
    report.similar_repos = similar

    return report.to_dict()


class FixGitHubRequest(BaseModel):
    issues: list[str] = []


@app.post("/api/{project}/github-health/fix")
async def fix_github_issues(project: str, request: FixGitHubRequest):
    """Auto-fix GitHub issues for a project."""
    from .github_health import GitHubHealthChecker

    project_path = mcp_server.projects_base / project
    if not project_path.exists():
        raise HTTPException(status_code=404, detail=f"Project not found: {project}")

    checker = GitHubHealthChecker(project_path)
    results = checker.auto_fix(request.issues)

    return {
        "fixed": [k for k, v in results.items() if v],
        "failed": [k for k, v in results.items() if not v],
    }


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
    """
    # Check if Mac is offline
    if sync_manager and not sync_manager.mac_online:
        raise HTTPException(
            status_code=503,
            detail="Mac is offline. Starting a feature requires creating a git worktree on your Mac. Please open your MacBook to continue."
        )

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
    """
    # Check if Mac is offline
    if sync_manager and not sync_manager.mac_online:
        raise HTTPException(
            status_code=503,
            detail="Mac is offline. Merging requires git access on your Mac. Please open your MacBook to continue."
        )

    result = mcp_server._merge_feature(project, feature_id, request.skip_validation)
    if not result.success:
        raise HTTPException(status_code=400, detail=result.message)

    result.data["mac_online"] = True
    return result.data


class AddFeatureRequest(BaseModel):
    title: str
    description: Optional[str] = None
    tags: Optional[list[str]] = None
    priority: int = 5
    status: str = "idea"  # Default to idea for quick capture


@app.post("/api/{project}/features")
async def add_feature(project: str, request: AddFeatureRequest):
    """
    Add a new feature.

    If Mac is offline, queues the operation for later sync.
    Default status is 'idea' for quick capture (not counted in 3-slot limit).
    """
    # Check if Mac is offline
    if sync_manager and not sync_manager.mac_online:
        # Queue the operation for later
        op_id = cache_manager.queue_operation(
            project_name=project,
            operation="add_feature",
            payload={
                "title": request.title,
                "description": request.description,
                "tags": request.tags,
                "priority": request.priority,
                "status": request.status,
            }
        )

        # Generate a temporary ID for UI feedback
        from .registry import FeatureRegistry
        temp_id = FeatureRegistry.generate_id(request.title)

        return {
            "id": temp_id,
            "title": request.title,
            "status": request.status,
            "queued": True,
            "operation_id": op_id,
            "message": "Feature queued - will be created when Mac comes online",
            "mac_online": False,
        }

    # Mac is online - proceed
    # If running in remote mode (Pi), execute via SSH to Mac
    if remote_executor:
        # Build forge add command using venv's forge
        config = get_config()
        project_path = Path(config["projects_base"]) / project
        forge_bin = project_path / ".venv" / "bin" / "forge"
        cmd = [str(forge_bin), "add", request.title]
        if request.status:
            cmd.extend(["--status", request.status])
        if request.description:
            cmd.extend(["--description", request.description])

        result = remote_executor.run_command(cmd, cwd=str(project_path))
        if not result.success:
            raise HTTPException(status_code=400, detail=result.stderr or "Failed to add feature")

        # Parse feature ID from output
        from .registry import FeatureRegistry
        feature_id = FeatureRegistry.generate_id(request.title)

        # Broadcast update
        await ws_manager.broadcast_feature_update(project, feature_id, "created")

        return {
            "feature_id": feature_id,
            "title": request.title,
            "status": request.status or "idea",
            "mac_online": True,
            "queued": False,
        }

    # Local mode - proceed directly
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
    feature_id = result.data.get("id") if isinstance(result.data, dict) else None
    if feature_id:
        await ws_manager.broadcast_feature_update(project, feature_id, "created")

    result.data["mac_online"] = True
    result.data["queued"] = False
    return result.data


class UpdateFeatureRequest(BaseModel):
    title: Optional[str] = None
    description: Optional[str] = None
    status: Optional[str] = None
    priority: Optional[int] = None
    complexity: Optional[str] = None
    tags: Optional[list[str]] = None


@app.patch("/api/{project}/features/{feature_id}")
async def update_feature(
    project: str,
    feature_id: str,
    request: UpdateFeatureRequest,
):
    """Update a feature's attributes."""
    result = mcp_server._update_feature(
        project,
        feature_id,
        title=request.title,
        description=request.description,
        status=request.status,
        priority=request.priority,
        complexity=request.complexity,
        tags=request.tags,
    )
    if not result.success:
        raise HTTPException(status_code=400, detail=result.message)

    # Broadcast update
    await ws_manager.broadcast_feature_update(project, feature_id, "updated")

    return result.data


@app.post("/api/{project}/features/{feature_id}/crystallize")
async def crystallize_feature(project: str, feature_id: str):
    """
    Crystallize an idea into a planned feature.

    Takes a feature from 'idea' status to 'planned' status.
    Checks the 3-slot constraint before crystallizing.
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

    # Check it's an idea
    if feature.status != FeatureStatus.IDEA:
        raise HTTPException(
            status_code=400,
            detail=f"Feature is not an idea (status: {feature.status.value})"
        )

    # Check 3-slot constraint
    if not registry.can_add_planned():
        planned_titles = registry.get_planned_feature_titles()
        raise HTTPException(
            status_code=400,
            detail=(
                f"You have {MAX_PLANNED_FEATURES} planned features. "
                f"Finish or delete one first: {', '.join(planned_titles[:MAX_PLANNED_FEATURES])}"
            )
        )

    # Crystallize: idea → planned
    registry.update_feature(feature_id, status=FeatureStatus.PLANNED)

    # Broadcast update
    await ws_manager.broadcast_feature_update(project, feature_id, "updated")

    remaining = MAX_PLANNED_FEATURES - registry.count_planned()

    return {
        "feature_id": feature_id,
        "title": feature.title,
        "status": "planned",
        "planned_count": registry.count_planned(),
        "slots_remaining": remaining,
        "message": f"Crystallized: {feature.title} ({remaining} slot{'s' if remaining != 1 else ''} remaining)",
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

    Returns:
    - exists: whether the worktree exists
    - has_changes: whether there are uncommitted changes
    - changes: list of changed files
    - ahead_of_main: commits ahead of main
    - behind_main: commits behind main
    """
    config = get_config()
    project_path = config["projects_base"] / project

    if not (project_path / ".flowforge").exists():
        raise HTTPException(status_code=404, detail=f"Project not found: {project}")

    registry = FeatureRegistry.load(project_path)
    feature = registry.get_feature(feature_id)

    if not feature:
        raise HTTPException(status_code=404, detail=f"Feature not found: {feature_id}")

    # Get worktree status
    worktree_manager = WorktreeManager(project_path)
    status = worktree_manager.get_worktree_status(feature_id)

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
    """Generate and return implementation prompt for a feature."""
    config = get_config()
    project_path = config["projects_base"] / project

    if not (project_path / ".flowforge").exists():
        raise HTTPException(status_code=404, detail=f"Project not found: {project}")

    registry = FeatureRegistry.load(project_path)
    feature = registry.get_feature(feature_id)

    if not feature:
        raise HTTPException(status_code=404, detail=f"Feature not found: {feature_id}")

    intelligence = IntelligenceEngine(project_path)
    prompt_builder = PromptBuilder(project_path, registry, intelligence)

    prompt = prompt_builder.build_for_feature(
        feature_id,
        include_experts=True,
        include_research=True,
    )

    return {"prompt": prompt, "feature_id": feature_id}


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


class ScopeCheckRequest(BaseModel):
    """Request to check if a feature is shippable (scope creep detection)."""
    title: str
    description: str = ""
    complexity: str = "medium"


@app.post("/api/scope-check")
async def scope_check(request: ScopeCheckRequest):
    """
    Check if a feature is shippable (no scope creep).

    Returns warnings and suggestions if the feature is too broad.
    """
    result = check_shippable(
        title=request.title,
        description=request.description,
        complexity=request.complexity,
    )
    return result


# =============================================================================
# Feature Intelligence Endpoints (AGI-pilled analysis)
# =============================================================================


class AnalyzeFeatureRequest(BaseModel):
    """Request to analyze a feature with AI."""
    title: str
    description: str = ""


@app.post("/api/{project}/analyze-feature")
async def analyze_feature(project: str, request: AnalyzeFeatureRequest):
    """
    Analyze a feature using the AGI-pilled feature analyzer.

    Returns complete intelligence about scope, complexity, expert needs,
    and shippability.
    """
    config = get_config()
    project_path = config["projects_base"] / project

    if not (project_path / ".flowforge").exists():
        raise HTTPException(status_code=404, detail=f"Project not found: {project}")

    # Get existing features for context
    registry = FeatureRegistry.load(project_path)
    existing = [f.title for f in registry.list_features() if f.status.value == "in-progress"]

    # Run the analyzer
    analyzer = FeatureAnalyzer(project_path)
    intelligence = analyzer.analyze_feature(
        title=request.title,
        description=request.description,
        existing_features=existing,
    )

    return {
        "title": intelligence.title,
        "description": intelligence.description,
        "complexity": intelligence.complexity.value,
        "estimated_hours": intelligence.estimated_hours,
        "confidence": intelligence.confidence,
        "files_affected": intelligence.files_affected,
        "foundation_score": intelligence.foundation_score,
        "foundation_reasoning": intelligence.foundation_reasoning,
        "parallelizable": intelligence.parallelizable,
        "parallel_conflicts": intelligence.parallel_conflicts,
        "needs_expert": intelligence.needs_expert,
        "expert_domain": intelligence.expert_domain.value,
        "expert_reasoning": intelligence.expert_reasoning,
        "shippable_today": intelligence.shippable_today,
        "scope_creep_detected": intelligence.scope_creep_detected,
        "scope_creep_warning": intelligence.scope_creep_warning,
        "suggested_breakdown": intelligence.suggested_breakdown,
        "suggested_tags": intelligence.suggested_tags,
    }


class QuickScopeRequest(BaseModel):
    """Request for quick (local) scope check."""
    text: str


@app.post("/api/quick-scope")
async def quick_scope_check(request: QuickScopeRequest):
    """
    Quick, local-only scope check for as-you-type feedback.

    This runs instantly without calling Claude, for the VibeInput component.
    """
    # Use a dummy analyzer (doesn't need project context for quick check)
    analyzer = FeatureAnalyzer(Path("."))
    result = analyzer.quick_scope_check(request.text)
    return result


@app.get("/api/experts")
async def list_experts():
    """List all available expert personas."""
    return {
        "experts": ExpertRouter.list_all_experts()
    }


@app.get("/api/experts/{domain}")
async def get_experts_for_domain(domain: str):
    """Get expert personas for a specific domain."""
    try:
        domain_enum = RouterDomain(domain)
    except ValueError:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid domain. Valid domains: {[d.value for d in RouterDomain]}"
        )

    experts = ExpertRouter.get_experts_for_domain(domain_enum)
    return {
        "domain": domain,
        "experts": [
            {
                "name": e.name,
                "title": e.title,
                "philosophy": e.philosophy,
                "key_principles": e.key_principles,
            }
            for e in experts
        ]
    }


@app.get("/api/experts/panel/design")
async def get_design_panel():
    """Get the legendary design panel from the UI/UX consultation."""
    panel = ExpertRouter.get_design_panel()
    return {
        "panel_name": "The Legendary Design Panel",
        "experts": [
            {
                "name": e.name,
                "title": e.title,
                "philosophy": e.philosophy,
                "key_principles": e.key_principles,
            }
            for e in panel
        ]
    }


class ApproveProposalsRequest(BaseModel):
    """Request to approve and add proposals to registry."""
    proposals: list[dict]  # List of proposal dicts to add


@app.post("/api/{project}/proposals/approve")
async def approve_proposals(project: str, request: ApproveProposalsRequest):
    """Add approved proposals to the feature registry."""
    config = get_config()
    project_path = config["projects_base"] / project

    if not (project_path / ".flowforge").exists():
        raise HTTPException(status_code=404, detail=f"Project not found: {project}")

    registry = FeatureRegistry.load(project_path)

    added = []
    skipped = []

    for proposal_dict in request.proposals:
        proposal = Proposal.from_dict(proposal_dict)
        feature_id = FeatureRegistry.generate_id(proposal.title)

        # Skip if exists
        if registry.get_feature(feature_id):
            skipped.append(proposal.title)
            continue

        # Import Feature and Complexity here to avoid circular import at top
        from .registry import Feature, Complexity

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

        .status.planned { background: var(--accent); }
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
                            <div class="stat-value">${stats.planned || 0}</div>
                            <div class="stat-label">Planned</div>
                        </div>
                        <div class="stat">
                            <div class="stat-value">${stats['in-progress'] || 0}</div>
                            <div class="stat-label">In Progress</div>
                        </div>
                        <div class="stat">
                            <div class="stat-value">${stats.review || 0}</div>
                            <div class="stat-label">Review</div>
                        </div>
                        <div class="stat">
                            <div class="stat-value">${stats.completed || 0}</div>
                            <div class="stat-label">Completed</div>
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
                                ${f.status === 'planned' ?
                                    `<button class="btn" onclick="startFeature('${f.id}')">Start</button>` : ''}
                                ${f.status === 'in-progress' ?
                                    `<button class="btn" onclick="stopFeature('${f.id}')">Review</button>` : ''}
                                ${f.status === 'review' ?
                                    `<button class="btn" onclick="mergeFeature('${f.id}')">Merge</button>` : ''}
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


@app.get("/api/{project}/pending")
async def get_pending_operations(project: str):
    """Get pending operations for a project (queued while Mac was offline)."""
    if not cache_manager:
        return {"pending": [], "count": 0}

    pending = cache_manager.get_pending_operations(project)
    return {
        "pending": [
            {
                "id": op.id,
                "operation": op.operation,
                "payload": json.loads(op.payload_json),
                "created_at": op.created_at,
                "status": op.status,
                "error": op.error_message,
            }
            for op in pending
        ],
        "count": len(pending),
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
    """Get session state for welcome-back experience."""
    memory = get_session_memory()

    # Also fetch current feature status
    config = get_config()
    project_path = config["projects_base"] / project

    if (project_path / ".flowforge").exists():
        registry = FeatureRegistry.load(project_path)

        # Update in-progress and ready-to-ship
        in_progress = [f.title for f in registry.list_features() if f.status.value == "in-progress"]
        ready = [f.title for f in registry.list_features() if f.status.value == "review"]

        memory.update_in_progress(project, in_progress)
        memory.update_ready_to_ship(project, ready)

        # Update streak
        stats = registry.get_shipping_stats()
        memory.update_streak(project, stats.current_streak)

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
    """Get shipping streak statistics for a project."""
    config = get_config()
    project_path = config["projects_base"] / project

    if not (project_path / ".flowforge").exists():
        raise HTTPException(status_code=404, detail=f"Project not found: {project}")

    registry = FeatureRegistry.load(project_path)
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


# Store active brainstorm sessions (project -> BrainstormAgent)
brainstorm_sessions: dict = {}


@app.websocket("/ws/{project}/brainstorm")
async def brainstorm_websocket(websocket: WebSocket, project: str):
    """
    WebSocket endpoint for real-time brainstorming with Claude.

    This enables the Chat-to-Spec experience where users have a conversation
    with Claude to crystallize feature ideas into implementable specs.

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
        "type": "spec_ready",       # Spec has crystallized
        "spec": { ... }
    }
    """
    await websocket.accept()

    try:
        # Get project context
        config = get_config()
        project_path = config["projects_base"] / project

        project_context = ""
        context_path = project_path / ".flowforge" / "project-context.md"
        if context_path.exists():
            project_context = context_path.read_text()

        existing_features = []
        if (project_path / ".flowforge").exists():
            registry = FeatureRegistry.load(project_path)
            existing_features = [f.title for f in registry.list_features()]

        # Create or get existing brainstorm session
        from .agents.brainstorm import BrainstormAgent

        if project not in brainstorm_sessions:
            brainstorm_sessions[project] = BrainstormAgent(
                project_name=project,
                project_context=project_context,
                existing_features=existing_features,
            )

        agent = brainstorm_sessions[project]

        # Send session state on connect
        await websocket.send_json({
            "type": "session_state",
            "state": agent.get_conversation_state(),
        })

        while True:
            data = await websocket.receive_json()

            if data.get("type") == "message":
                user_message = data.get("content", "")

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

                # Check if spec is ready
                if agent.is_spec_ready():
                    spec = agent.get_spec()
                    await websocket.send_json({
                        "type": "spec_ready",
                        "spec": spec.to_dict() if spec else None,
                    })

            elif data.get("type") == "reset":
                # Reset the session
                brainstorm_sessions[project] = BrainstormAgent(
                    project_name=project,
                    project_context=project_context,
                    existing_features=existing_features,
                )
                agent = brainstorm_sessions[project]
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
