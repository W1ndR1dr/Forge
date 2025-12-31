# Forge Architecture Fixes

**Purpose:** Guide for Claude Code agents to fix remaining pain points in Forge.
**Status:** Some issues already solved, others need work.

## Current Architecture (Correct Understanding)

```
┌─────────────────┐     ┌──────────────────────────────────────────────┐
│   iOS App       │────▶│  Raspberry Pi (raspberrypi:8081)             │
│   (Ideas only)  │     │                                              │
└─────────────────┘     │  Forge Server                                │
                        │  ├── Pi-local registry:                      │
                        │  │   /var/forge/registries/{project}/        │
┌─────────────────┐     │  │                                           │
│  Mac (Laptop)   │◀───▶│  └── Accesses Mac via Tailscale mount       │
│  Claude Code    │     │      for git operations                      │
│  .forge/        │     └──────────────────────────────────────────────┘
└─────────────────┘

Mac: /Users/Brian/Projects/Active/{project}/.forge/registry.json
Pi:  /var/forge/registries/{project}/registry.json
```

**Design intent:**
- Pi stores its own copy for offline access (view/add features when Mac asleep)
- Mac's `.forge/registry.json` is for local Claude Code sessions
- Git operations (start/merge) require Mac to be online

## What's Already Working

### ✅ PATCH endpoint exists (Pain Point #2 - SOLVED)

```python
# server.py:755
@app.patch("/api/{project}/features/{feature_id}")
async def update_feature(project, feature_id, request: UpdateFeatureRequest)

# Supports: title, description, status, priority, complexity, tags,
#           worktree_path, branch, completed_at
```

**Usage:**
```bash
# Mark a feature as shipped
curl -X PATCH "http://raspberrypi:8081/api/AirFit/features/my-feature" \
  -H "Content-Type: application/json" \
  -d '{"status": "completed"}'
```

### ✅ DELETE endpoint exists

```python
# server.py:913
@app.delete("/api/{project}/features/{feature_id}")
```

---

## Remaining Pain Points

### 1. Dual State Sync (CRITICAL)

**Problem:** Pi and Mac registries drift. Today when I created a feature via the API, it was on the Pi but not in the Mac's local `.forge/registry.json`. Had to add it twice.

**Current behavior:**
- Pi has `/var/forge/registries/AirFit/registry.json`
- Mac has `/Users/Brian/Projects/Active/AirFit/.forge/registry.json`
- No automatic sync between them

**What's needed:**

Option A: **Bidirectional sync on demand**
```python
@app.post("/api/{project}/sync")
async def sync_registries(project: str, direction: str = "pi-to-mac"):
    """
    Sync registries between Pi and Mac.

    direction:
    - "pi-to-mac": Write Pi's registry to Mac's .forge/registry.json
    - "mac-to-pi": Read Mac's registry and merge into Pi
    - "bidirectional": Merge both, most recent wins per-feature
    """
    pass

@app.get("/api/{project}/sync/status")
async def sync_status(project: str):
    """Check if registries are in sync, show diff if not."""
    pass
```

Option B: **Pi is always authoritative**
```python
# When Claude Code starts on Mac, it should:
# 1. Fetch current registry from Pi
# 2. Write to local .forge/registry.json
# 3. Work locally
# 4. Push changes back to Pi when done

# Could add a CLI command:
# forge sync pull  → fetch from Pi
# forge sync push  → push to Pi
```

**Recommendation:** Option B is cleaner. The local file becomes a cache, Pi is truth.

**Implementation location:** `forge/remote.py` or new `forge/sync.py`

---

### 2. Worktree Cleanup (Pain Point #3)

**Problem:** Worktrees linger after features are completed or deleted.

**Current DELETE behavior:** (server.py:913)
- Deletes from registry ✓
- Does NOT clean up `.forge-worktrees/{id}/` directory
- Does NOT remove git worktree reference

**Fix needed:**

```python
# In mcp_server.py or wherever _delete_feature lives:
def _delete_feature(self, project: str, feature_id: str, force: bool = False):
    # ... existing deletion logic ...

    # ADD: Cleanup worktree if exists
    project_path = self._get_project_path(project)
    if project_path:
        worktree_dir = project_path / ".forge-worktrees" / feature_id
        if worktree_dir.exists():
            # Remove git worktree reference
            subprocess.run(
                ["git", "worktree", "remove", str(worktree_dir), "--force"],
                cwd=project_path,
                capture_output=True
            )
            # Remove directory if still exists
            shutil.rmtree(worktree_dir, ignore_errors=True)

        # Also remove prompt file
        prompt_file = project_path / ".forge" / "prompts" / f"{feature_id}.md"
        prompt_file.unlink(missing_ok=True)
```

**Also add a cleanup sweep:**
```python
@app.post("/api/{project}/cleanup")
async def cleanup_orphans(project: str):
    """Remove worktrees for features that are completed/deleted."""
    # Scan .forge-worktrees/
    # Compare against registry
    # Remove anything not in active (in-progress/review) features
```

**Implementation location:** `forge/worktree.py` (already exists)

---

### 3. API Discoverability (Pain Point #4)

**Problem:** No root endpoint listing available routes. Claude has to guess.

**Current:** No `/api` root endpoint.

**Fix:**

```python
@app.get("/api")
async def api_discovery():
    """List all available API endpoints for discoverability."""
    return {
        "version": "1.0.0",
        "documentation": "/api/docs",  # FastAPI auto-generates this
        "endpoints": {
            "projects": {
                "GET /api/projects": "List all registered projects",
            },
            "project": {
                "GET /api/{project}/status": "Get project stats",
                "GET /api/{project}/features": "List all features",
                "POST /api/{project}/features": "Create feature",
                "POST /api/{project}/sync": "Sync with Mac registry",
                "POST /api/{project}/cleanup": "Clean orphaned worktrees",
            },
            "feature": {
                "PATCH /api/{project}/features/{id}": "Update feature (including status)",
                "DELETE /api/{project}/features/{id}": "Delete feature",
                "POST /api/{project}/features/{id}/start": "Start work",
                "POST /api/{project}/features/{id}/stop": "Move to review",
                "POST /api/{project}/features/{id}/merge": "Merge to main",
            }
        }
    }
```

**Or just enable FastAPI's built-in docs:**
```python
# In server.py, ensure these are set:
app = FastAPI(
    title="Forge API",
    docs_url="/api/docs",      # Swagger UI at http://raspberrypi:8081/api/docs
    openapi_url="/api/openapi.json"
)
```

---

## Implementation Order

| Priority | Fix | Effort | Files |
|----------|-----|--------|-------|
| 1 | API discoverability | 10 min | `server.py` |
| 2 | Worktree cleanup on delete | 30 min | `mcp_server.py`, `worktree.py` |
| 3 | Cleanup sweep endpoint | 30 min | `server.py`, `worktree.py` |
| 4 | Registry sync | 2 hrs | New `sync.py` or extend `remote.py` |

---

## Testing Checklist

```bash
# 1. API discovery
curl "http://raspberrypi:8081/api" | jq

# 2. PATCH already works (verify)
curl -X PATCH "http://raspberrypi:8081/api/AirFit/features/test" \
  -H "Content-Type: application/json" \
  -d '{"status": "completed"}'

# 3. Worktree cleanup (after implementing)
curl -X DELETE "http://raspberrypi:8081/api/AirFit/features/old-feature"
ls /Users/Brian/Projects/Active/AirFit/.forge-worktrees/
# Should NOT contain old-feature

# 4. Cleanup sweep (after implementing)
curl -X POST "http://raspberrypi:8081/api/AirFit/cleanup"

# 5. Registry sync (after implementing)
curl -X POST "http://raspberrypi:8081/api/AirFit/sync" \
  -H "Content-Type: application/json" \
  -d '{"direction": "pi-to-mac"}'
```

---

## Key Files

```
forge/
├── server.py         # FastAPI app, all HTTP endpoints
├── mcp_server.py     # MCP tools, core logic like _update_feature, _delete_feature
├── registry.py       # Feature/Registry data models
├── pi_registry.py    # Pi-local storage at /var/forge/registries/
├── worktree.py       # Git worktree operations
├── remote.py         # Mac connectivity via Tailscale
└── config.py         # Configuration management
```

---

## For the Claude Agent

When asked to fix Forge:

1. **Read this file first** for context
2. **Read CLAUDE.md** in the Forge repo for project conventions
3. **SSH to Pi** if needed: The server runs on the Pi at port 8081
4. **Test changes** by restarting the server and hitting endpoints

The Pi accesses Mac projects via Tailscale filesystem mount. Git operations run on the Mac side.
