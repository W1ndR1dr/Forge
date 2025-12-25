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

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

from .mcp_server import FlowForgeMCPServer, create_mcp_response
from .brainstorm import parse_proposals, Proposal, ProposalStatus
from .prompt_builder import PromptBuilder
from .registry import FeatureRegistry
from .intelligence import IntelligenceEngine


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
# App Lifecycle
# =============================================================================

mcp_server: Optional[FlowForgeMCPServer] = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Initialize MCP server on startup."""
    global mcp_server

    config = get_config()
    mcp_server = FlowForgeMCPServer(
        projects_base=config["projects_base"],
        remote_host=config["remote_host"],
        remote_user=config["remote_user"],
    )

    print(f"FlowForge MCP Server started")
    print(f"  Projects: {config['projects_base']}")
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


@app.get("/api/projects")
async def list_projects():
    """List all FlowForge projects."""
    result = mcp_server._list_projects()
    if not result.success:
        raise HTTPException(status_code=500, detail=result.message)
    return result.data


@app.get("/api/{project}/features")
async def list_features(project: str, status: Optional[str] = None):
    """List features in a project."""
    result = mcp_server._list_features(project, status)
    if not result.success:
        raise HTTPException(status_code=404, detail=result.message)
    return result.data


@app.get("/api/{project}/status")
async def get_status(project: str):
    """Get project status."""
    result = mcp_server._get_status(project)
    if not result.success:
        raise HTTPException(status_code=404, detail=result.message)
    return result.data


class StartFeatureRequest(BaseModel):
    skip_experts: bool = False


@app.post("/api/{project}/features/{feature_id}/start")
async def start_feature(
    project: str,
    feature_id: str,
    request: StartFeatureRequest = StartFeatureRequest(),
):
    """Start working on a feature."""
    result = mcp_server._start_feature(project, feature_id, request.skip_experts)
    if not result.success:
        raise HTTPException(status_code=400, detail=result.message)
    return result.data


@app.post("/api/{project}/features/{feature_id}/stop")
async def stop_feature(project: str, feature_id: str):
    """Mark feature as ready for review."""
    result = mcp_server._stop_feature(project, feature_id)
    if not result.success:
        raise HTTPException(status_code=400, detail=result.message)
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
    """Merge a feature into main."""
    result = mcp_server._merge_feature(project, feature_id, request.skip_validation)
    if not result.success:
        raise HTTPException(status_code=400, detail=result.message)
    return result.data


class AddFeatureRequest(BaseModel):
    title: str
    description: Optional[str] = None
    tags: Optional[list[str]] = None
    priority: int = 5


@app.post("/api/{project}/features")
async def add_feature(project: str, request: AddFeatureRequest):
    """Add a new feature."""
    result = mcp_server._add_feature(
        project,
        request.title,
        request.description,
        request.tags,
        request.priority,
    )
    if not result.success:
        raise HTTPException(status_code=400, detail=result.message)
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
    return result.data


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
    return {"success": True, "message": f"Feature {feature_id} deleted"}


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
