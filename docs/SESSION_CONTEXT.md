# Forge Development Context

This file captures the full context from the initial development session so future Claude sessions can continue seamlessly.

## What Forge Is

An AI-assisted parallel development orchestrator for "vibecoders" - developers who work with AI assistance but aren't Git experts. Forge handles:

1. **Feature Registry** - Hierarchical feature tracking with dependencies
2. **Git Worktrees** - Parallel development via isolated directories
3. **Smart Prompts** - AI-generated implementation prompts with expert consultation
4. **Merge Orchestration** - Safe, validated merging with conflict detection
5. **MCP Server** - Native Claude Code integration on iPhone/web via Raspberry Pi

## User Context

- **Primary projects**: AirFit (iOS + Python), Forge itself
- **Hardware**: Mac + Raspberry Pi (brand new, not set up yet) + iPhone
- **Network**: Tailscale for secure connectivity
- **Workflow**: Uses Claude Code extensively, wants full iPhone integration
- **Git expertise**: Self-described "vibecoder" - wants full automation

## Key Decisions Made

1. **Dynamic personas over hardcoded** - AI suggests relevant experts per feature, not fixed personas
2. **Tiered intelligence** - Tier 1 (quick experts), Tier 2 (deep research), Tier 3 (multi-model)
3. **MCP over SSH for iPhone** - Claude Code iOS uses Remote MCP Server, not SSH commands
4. **Pi as always-on hub** - Forge server on Pi, worktrees created on Mac via SSH
5. **Tailscale for networking** - Secure VPN, no port forwarding needed

## What's Been Built (Phases 1 & 2)

### CLI Commands
```bash
forge init                    # Initialize in current directory
forge add "Feature Title"     # Add new feature
forge list                    # Tree view of features
forge show <id>               # Feature details
forge start <id>              # Create worktree + generate prompt
forge stop <id>               # Mark ready for review
forge status                  # Show active worktrees
forge sync <id>               # Rebase onto main
forge merge-check             # Dry-run conflict detection
forge merge <id>              # Execute merge with validation
forge merge --auto            # Merge all safe features
```

### Server (for Pi deployment)
```bash
pip install -e ".[server]"    # Install with server deps
forge-server                  # Run on http://0.0.0.0:8081

# Environment variables:
FORGE_PROJECTS_PATH=/Users/Brian/Projects/Active
FORGE_MAC_HOST=macs-tailscale-hostname
FORGE_MAC_USER=Brian
FORGE_PORT=8081
```

### MCP Tools Available
- `forge_list_projects` - List all projects
- `forge_list_features` - List features in project
- `forge_status` - Project status overview
- `forge_start_feature` - Start feature (creates worktree)
- `forge_stop_feature` - Mark for review
- `forge_merge_check` - Check merge readiness
- `forge_merge` - Execute merge
- `forge_add_feature` - Add new feature

### Files Created
```
forge/
├── __init__.py
├── __main__.py
├── cli.py              # All CLI commands
├── config.py           # Project configuration
├── registry.py         # Feature CRUD + queries
├── worktree.py         # Git worktree management
├── intelligence.py     # Tiered AI intelligence
├── prompt_builder.py   # Prompt generation
├── merge.py            # Merge orchestration      [Phase 2]
├── mcp_server.py       # Remote MCP server        [Phase 2]
├── server.py           # FastAPI wrapper          [Phase 2]
└── remote.py           # SSH execution            [Phase 2]

docs/
├── PLAN.md                   # Full development plan
├── RASPBERRY_PI_SETUP.md     # Beginner Pi setup guide
└── SESSION_CONTEXT.md        # This file
```

## Verified Working

- ✅ `forge --help` shows all commands
- ✅ `forge init` on AirFit - detected settings automatically
- ✅ `forge start zone-2-weekly-summary` - created worktree, generated prompt
- ✅ `forge-server` - runs on port 8081
- ✅ `GET /health` - returns healthy status
- ✅ `GET /api/projects` - lists AirFit
- ✅ `GET /mcp/tools` - lists all 8 MCP tools
- ✅ `POST /mcp/tools/call` - executes tools correctly
- ✅ Web UI at `http://localhost:8081/` - shows projects and features
- ✅ Forge initialized on itself (meta-bootstrap)

## What's Next (Phase 3)

Features tracked in Forge's own registry:

1. **macOS App - Kanban Roadmap** (priority 1)
   - SwiftUI Kanban board for visual feature management
   - Tags: ui, swiftui, design

2. **macOS App - Feature Detail Views** (priority 2)
   - Feature detail and merge queue views
   - Tags: ui, swiftui

3. **Pi Deployment Script** (priority 3)
   - Systemd service and deployment automation
   - Tags: deploy, pi

## Raspberry Pi Status

User has a new Pi kit, hasn't assembled it yet. Created comprehensive setup guide at `docs/RASPBERRY_PI_SETUP.md` covering:
- SD card flashing with Raspberry Pi Imager
- First boot and SSH access
- Tailscale installation
- Forge installation
- SSH key setup for Pi→Mac
- Systemd service creation
- Claude Code iOS configuration

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                     Raspberry Pi (Tailscale)                     │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  Forge Server (:8081)                                      │ │
│  │  • MCP endpoints for Claude Code iOS                       │ │
│  │  • REST API for programmatic access                        │ │
│  │  • Web UI for browser                                      │ │
│  └────────────────────────────────────────────────────────────┘ │
│                          │ SSH                                   │
│                          ▼                                       │
│                   Mac (worktrees here)                           │
└─────────────────────────────────────────────────────────────────┘
         ▲ Tailscale VPN
         │
┌────────┴────────┬─────────────────┐
│ iPhone Claude   │ Mac CLI/App     │
│ Code (MCP)      │ (direct forge)  │
└─────────────────┴─────────────────┘
```

## To Continue Development

Start a new Claude Code session:
```bash
cd ~/Projects/Active/Forge
claude
```

Then say:
> "Read docs/SESSION_CONTEXT.md, docs/PLAN.md, and CLAUDE.md for full context on this project."

Or for specific tasks:
> "Help me set up the Raspberry Pi using docs/RASPBERRY_PI_SETUP.md"
> "Let's build the SwiftUI macOS app - start the macos-app-kanban-roadmap feature"
