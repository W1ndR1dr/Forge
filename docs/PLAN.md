# Forge: AI-Assisted Parallel Development Orchestrator

## Overview

**Forge** is a development orchestration tool that enables systematic, parallel AI-assisted development. It manages feature backlogs, generates optimized Claude Code prompts, automates Git worktree workflows, and orchestrates merges—all designed for a "vibecoder" who wants full automation with human oversight at key decision points.

**Project Location**: `~/Projects/Active/Forge/`

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     Forge macOS App (SwiftUI)                   │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐        │
│  │ Roadmap  │  │ Feature  │  │  Merge   │  │ Settings │        │
│  │ (Kanban) │  │  Detail  │  │  Queue   │  │          │        │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘        │
└─────────────────────────────────────────────────────────────────┘
                              │ calls
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                     Forge CLI (Python/Typer)                    │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐        │
│  │ Registry │  │ Worktree │  │  Prompt  │  │  Merge   │        │
│  │ Manager  │  │ Manager  │  │ Builder  │  │Orchestr. │        │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘        │
└─────────────────────────────────────────────────────────────────┘
                              │ manages
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Per-Project Files                          │
│  .devflow/                    .devflow-worktrees/               │
│  ├── registry.json            ├── feature-zone2-tracking/       │
│  ├── config.json              ├── feature-morning-briefings/    │
│  ├── prompts/                 └── feature-calendar-sync/        │
│  └── personas/                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Core Features

### 1. Feature Registry
- Hierarchical feature list (features with sub-features)
- Status tracking: `planned` → `in-progress` → `review` → `completed`
- Priority, complexity, tags, dependencies
- Links to spec files and generated prompts

### 2. Git Worktree Management (Parallelization Engine)
- Each feature gets its own isolated worktree directory
- Multiple Claude Code sessions run simultaneously on different features
- Automatic branch creation: `feature/{feature-id}`
- Worktree cleanup after successful merge

### 3. Prompt Generation
- Parses project's CLAUDE.md for context
- Incorporates feature spec file
- Injects persona preambles (Jony Ive, John Carmack, etc.)
- Copies to clipboard for immediate use

### 4. Merge Orchestration
- Computes safe merge order based on dependencies
- Dry-run conflict detection before merge
- Post-merge validation (build command)
- Automatic rollback on validation failure
- Generates conflict resolution prompts for Claude Code

### 5. SwiftUI macOS App
- Visual Kanban roadmap with drag-drop
- One-click "Start Feature" (creates worktree + prompt)
- Merge queue visualization
- Real-time status updates via FileWatcher

---

## Data Model

### Feature Schema
```json
{
  "id": "zone2-tracking",
  "title": "Zone 2 Weekly Summary",
  "description": "HealthKit query for HR zones during workouts",
  "status": "planned",
  "priority": 1,
  "complexity": "small",
  "parent_id": "multi-sport-expansion",
  "children": [],
  "depends_on": [],
  "branch": null,
  "worktree_path": null,
  "spec_path": "docs/features/zone2-tracking.md",
  "tags": ["healthkit", "ui"]
}
```

### Dynamic Persona Generation (AGI-Pilled Approach)

Instead of hardcoded personas, Forge uses **tiered intelligence**:

**Tier 1: Quick Expert Suggestion**
```
forge start zone2-tracking
→ Claude suggests: Dr. Peter Attia, Dr. Iñigo San Millán, Apple HealthKit engineer
→ User picks relevant experts
→ Prompt includes their perspectives
```

**Tier 2: Deep Research Mode**
For complex/novel features, Forge detects when deep research is warranted:
```
forge start memory-system
→ Claude: "This feature warrants deep research on Anthropic's memory
   philosophy, OpenAI patterns, and academic work on episodic memory"
→ User confirms
→ Opens research threads on Claude.ai / Gemini / ChatGPT
→ Research saved to .forge/research/{feature-id}/
→ Synthesized into implementation prompt
```

**Tier 3: Multi-Model Research**
For critical architecture decisions, research across multiple providers and synthesize.

**Detection is AI-driven, not hardcoded** - Claude decides when to escalate based on:
- Feature complexity and novelty
- Existence of significant prior art
- Architecture/design implications
- User can always manually trigger: `forge start feature-id --deep-research`

---

## CLI Commands

```bash
# Project Setup
forge init                            # Initialize in current directory
forge init --from-roadmap docs/       # Import features from markdown

# Feature Management
forge add "Feature Title"             # Add new feature (interactive)
forge list                            # Tree view of all features
forge show <id>                       # Feature details

# Parallel Development
forge start <id>                      # Create worktree + generate prompt
forge start <id> --persona carmack    # With persona injection
forge status                          # Show all active worktrees
forge stop <id>                       # Mark ready for review

# Merge Operations
forge merge-check                     # Dry-run all pending merges
forge merge <id>                      # Execute merge with validation
forge merge --auto                    # Merge all safe features in order
```

---

## Directory Structure

### Forge Tool (new project)
```
~/Projects/Active/Forge/
├── forge/                      # Python CLI package
│   ├── __init__.py
│   ├── __main__.py
│   ├── cli.py                  # Typer commands
│   ├── config.py               # Configuration management
│   ├── registry.py             # Feature CRUD + queries
│   ├── worktree.py             # Git worktree operations
│   ├── prompt_builder.py       # CLAUDE.md parsing + prompts
│   ├── merge.py                # Merge orchestration
│   └── personas.py             # Persona library
├── ForgeApp/                   # SwiftUI macOS app
│   ├── App/
│   ├── Models/
│   ├── Views/
│   ├── Services/
│   └── project.yml
├── pyproject.toml
└── CLAUDE.md
```

### Per-Project (created by `forge init`)
```
your-project/
├── .forge/
│   ├── registry.json           # Feature database
│   ├── config.json             # Project settings
│   └── prompts/                # Generated prompts
├── .forge-worktrees/           # Git worktrees
│   ├── feature-a/
│   └── feature-b/
└── CLAUDE.md                   # Existing project docs
```

---

## Implementation Phases

### Phase 1: Core CLI Foundation (Week 1)
**Goal**: Working worktree management and prompt generation

| Task | Priority |
|------|----------|
| Project structure + pyproject.toml | P0 |
| Config + Registry dataclasses | P0 |
| `devflow init` command | P0 |
| WorktreeManager (create/list/remove) | P0 |
| `devflow start <id>` command | P0 |
| Basic PromptBuilder (reads CLAUDE.md) | P0 |
| `devflow list` + `devflow status` | P1 |

**Validation**: Can create worktree, generate prompt, copy to clipboard

### Phase 2: Feature Management (Week 2)
**Goal**: Full feature CRUD with hierarchy

| Task | Priority |
|------|----------|
| `devflow add` (interactive) | P0 |
| Parent/child relationships | P1 |
| Dependency tracking | P1 |
| Import from markdown | P2 |

### Phase 3: Prompts + Personas (Week 2-3)
**Goal**: Rich, context-aware prompts

| Task | Priority |
|------|----------|
| CLAUDE.md section extraction | P0 |
| Spec file integration | P0 |
| 6 built-in personas | P1 |
| Custom persona support | P2 |

### Phase 4: Merge Orchestration (Week 3)
**Goal**: Safe, validated merging

| Task | Priority |
|------|----------|
| Conflict detection (dry-run) | P0 |
| `devflow merge <id>` | P0 |
| Build validation after merge | P1 |
| Rollback on failure | P1 |
| Conflict prompt generation | P1 |

### Phase 5: SwiftUI App - Core (Week 4)
**Goal**: Visual roadmap

| Task | Priority |
|------|----------|
| XcodeGen project setup | P0 |
| CLIBridge (calls Python CLI) | P0 |
| RoadmapView (Kanban) | P0 |
| FeatureCard with drag-drop | P1 |

### Phase 6: SwiftUI App - Polish (Week 5)
**Goal**: Full-featured macOS app

| Task | Priority |
|------|----------|
| FeatureDetailView | P0 |
| MergeQueueView | P1 |
| SettingsView + PersonaEditor | P2 |

---

## Key Technical Decisions

### Why Python CLI + SwiftUI App?
- **Python**: Superior Git/subprocess integration, familiar from AirFit server
- **SwiftUI**: Native macOS feel, matches iOS expertise
- **Both share registry.json**: Single source of truth

### Why Git Worktrees?
- True parallel development (not just branch switching)
- Each Claude Code session is isolated
- No conflicts until merge time
- Clean separation of concerns

### Safety Guardrails
- Never force-push to main
- Confirmation prompts for destructive operations
- Auto-rollback on validation failure
- All prompts saved for history

---

## Files to Create

### Python Package
- `forge/__init__.py`
- `forge/__main__.py`
- `forge/cli.py`
- `forge/config.py`
- `forge/registry.py`
- `forge/worktree.py`
- `forge/prompt_builder.py`
- `forge/merge.py`
- `forge/personas.py`
- `pyproject.toml`
- `CLAUDE.md`

### SwiftUI App (Phase 5+)
- `ForgeApp/project.yml`
- `ForgeApp/App/ForgeApp.swift`
- `ForgeApp/Models/Feature.swift`
- `ForgeApp/Models/AppState.swift`
- `ForgeApp/Services/CLIBridge.swift`
- `ForgeApp/Services/FileWatcher.swift`
- `ForgeApp/Views/ContentView.swift`
- `ForgeApp/Views/Roadmap/RoadmapView.swift`
- `ForgeApp/Views/Roadmap/FeatureCard.swift`
- `ForgeApp/Views/Detail/FeatureDetailView.swift`

---

## User Decisions (Confirmed)

1. **Project Location**: `~/Projects/Active/Forge/`
2. **Name**: Forge (CLI command: `forge`)
3. **Test Data**: Import AirFit roadmap features (AGI-Proofing-Plan + MultiSportExpansion)

---

## Phase 1: COMPLETE ✅

Delivered:
- `forge init` - Auto-detects project settings
- `forge add` - Add features with hierarchy, tags, dependencies
- `forge start` - Creates worktree + generates context-rich prompt
- `forge list` / `forge status` - Visual tracking
- `intelligence.py` - Tiered expert suggestion + deep research detection
- Tested on AirFit with working worktree

---

## Phase 2: Merge + Sync + Interoperability

### 2A. Merge Orchestration (`forge/merge.py`)

```bash
forge sync <id>              # Rebase feature onto latest main
forge merge-check            # Dry-run conflict detection for all review features
forge merge-check <id>       # Check specific feature
forge merge <id>             # Execute merge with validation
forge merge --auto           # Merge all safe features in dependency order
```

**Implementation:**
- `MergeOrchestrator` class with conflict detection
- Topological sort for dependency-safe merge order
- Post-merge build validation (runs `build_command` from config)
- Auto-rollback on validation failure
- Conflict prompt generation for Claude Code resolution

### 2B. Forge MCP Server (for Raspberry Pi) - THE UNLOCK

**Why**: Claude Code on iOS supports **Remote MCP Servers**. This enables native integration!

```
┌─────────────────────────────────────────────────────────────────┐
│                     Raspberry Pi                                 │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │           Forge Remote MCP Server                         │  │
│  │                                                            │  │
│  │  Tools (callable from Claude Code iOS/Web):                │  │
│  │  • forge_list_projects()                                   │  │
│  │  • forge_list_features(project)                            │  │
│  │  • forge_start_feature(project, feature_id)                │  │
│  │  • forge_stop_feature(project, feature_id)                 │  │
│  │  • forge_merge_check(project, feature_id)                  │  │
│  │  • forge_merge(project, feature_id)                        │  │
│  │  • forge_status(project)                                   │  │
│  │                                                            │  │
│  │  Also serves: Simple Web UI for browser access             │  │
│  └───────────────────────────────────────────────────────────┘  │
│                          │                                       │
│                          │ SSH to Mac (creates worktrees)        │
│                          ▼                                       │
└─────────────────────────────────────────────────────────────────┘
              │ Tailscale + MCP Protocol
              ▼
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│  Mac + CLI      │  │ iPhone Claude   │  │  Web Browser    │
│  (direct forge) │  │ Code (MCP!)     │  │  (simple UI)    │
└─────────────────┘  └─────────────────┘  └─────────────────┘
```

**The workflow from iPhone:**
1. Configure MCP server URL on claude.ai: `https://pi.tailnet:8081/mcp`
2. In Claude Code iOS: "Start the zone2-tracking feature on AirFit"
3. Claude calls `forge_start_feature("AirFit", "zone2-tracking")`
4. Pi creates worktree on Mac via SSH, returns prompt
5. Claude streams the prompt back to you, ready to paste into a new session

**New files:**
- `forge/mcp_server.py` - Remote MCP server implementation
- `forge/server.py` - FastAPI wrapper (serves MCP + web UI)

### 2C. Files to Create

| File | Purpose |
|------|---------|
| `forge/merge.py` | Merge orchestration, conflict detection |
| `forge/mcp_server.py` | Remote MCP server (THE key integration) |
| `forge/server.py` | FastAPI wrapper serving MCP + web UI |
| `forge/remote.py` | SSH execution on remote Mac |
| `forge/templates/` | Simple HTML templates for web UI |

---

## Phase 3: SwiftUI macOS App

### Design Approach: Meta-Bootstrapping

**Use Forge to design Forge's UI:**
1. `forge add "macOS App - Kanban Roadmap"` with UI/design tags
2. `forge start` triggers expert suggestion: Jony Ive, Dieter Rams, Apple HIG
3. Deep research on macOS design patterns if warranted
4. Generate design-focused prompt before implementation

### App Architecture

```
ForgeApp/
├── App/
│   └── ForgeApp.swift              # @main, WindowGroup
├── Models/
│   ├── Feature.swift               # Matches Python schema
│   ├── Project.swift               # Project config
│   └── AppState.swift              # @Observable state
├── Views/
│   ├── ContentView.swift           # Split view container
│   ├── Sidebar/
│   │   └── ProjectListView.swift   # Multi-project support
│   ├── Roadmap/
│   │   ├── KanbanView.swift        # Main Kanban board
│   │   ├── FeatureCard.swift       # Draggable card
│   │   └── StatusColumn.swift      # Column per status
│   ├── Detail/
│   │   ├── FeatureDetailView.swift # Edit feature
│   │   └── PromptPreview.swift     # Show generated prompt
│   └── Merge/
│       └── MergeQueueView.swift    # Merge orchestration UI
├── Services/
│   ├── CLIBridge.swift             # Calls `forge` via Process
│   ├── ServerBridge.swift          # Calls Forge server API
│   └── FileWatcher.swift           # Watches registry.json
└── project.yml                     # XcodeGen config
```

### Key UI Features

1. **Kanban Board**: Drag features between status columns
2. **One-Click Start**: Button creates worktree + copies prompt
3. **Merge Queue**: Visual merge order with conflict indicators
4. **Real-Time Updates**: FileWatcher reflects CLI changes instantly
5. **Multi-Project**: Sidebar shows all Forge-initialized projects

---

## Interoperability Matrix

| Client | Mechanism | Features |
|--------|-----------|----------|
| **Mac CLI** | Direct `forge` command | Full |
| **macOS App** | CLIBridge (subprocess) | Full |
| **iPhone Claude Code** | Remote MCP to Pi | **Full native!** |
| **Web Claude Code** | Remote MCP to Pi | **Full native!** |
| **Web Browser** | Pi web UI | Full (visual) |
| **Claude.ai chat** | Paste generated prompts | Prompt-only |

**The MCP integration means Claude Code on iPhone can natively call Forge tools** - no SSH needed, just natural language like "start the zone2 feature on AirFit".

---

## Meta-Bootstrapping: Build Forge with Forge

### Step 1: Initialize Forge on itself
```bash
cd ~/Projects/Active/Forge
source venv/bin/activate
forge init
```

### Step 2: Add Phase 2 Features
```bash
forge add "Merge Orchestration" --desc "forge sync, merge-check, merge commands" --tags "git,core" --priority 1
forge add "Forge Server" --desc "HTTP API for remote access" --tags "api,fastapi" --priority 2
forge add "macOS App - Kanban" --desc "SwiftUI Kanban roadmap view" --tags "ui,swiftui,design" --priority 3
forge add "macOS App - Detail Views" --desc "Feature detail, merge queue views" --tags "ui,swiftui" --priority 4
```

### Step 3: Parallel Development
```bash
# Terminal 1
forge start merge-orchestration
cd .forge-worktrees/merge-orchestration
claude --dangerously-skip-permissions

# Terminal 2
forge start forge-server
cd .forge-worktrees/forge-server
claude --dangerously-skip-permissions

# Terminal 3 (after merge/sync work)
forge start macos-app-kanban --deep-research  # Triggers UI expert consultation
```

---

## Implementation Order

### Immediate (This Session)
1. **merge.py** - Core merge orchestration
2. **CLI commands** - `forge sync`, `forge merge-check`, `forge merge`

### Next Session
3. **server.py** - HTTP API for Pi deployment
4. **Test on Pi** - Deploy, test remote access

### Following Session
5. **SwiftUI App** - Use Forge to plan, experts for design
6. **Polish** - Settings, multi-project, keyboard shortcuts

---

## Raspberry Pi Deployment Notes

### Architecture: Pi as Hub (via Tailscale)

**Tailscale is the secure network layer. MCP is the protocol. No SSH needed from iPhone.**

```
┌─────────────────────────────────────────────────────────────────┐
│                      Raspberry Pi                                │
│              (pi.tailnet - same network as AirFit)               │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  Forge MCP Server (:8081)        AirFit Server (:8080)     │ │
│  │  • MCP tools for Claude Code     • Chat, insights, etc     │ │
│  │  • Web UI for browser            • Already planned!        │ │
│  └────────────────────────────────────────────────────────────┘ │
│                          │                                       │
│                          │ Tailscale (or local if Mac = Pi)      │
│                          ▼                                       │
│                   Mac (worktrees here)                           │
└─────────────────────────────────────────────────────────────────┘
         ▲ Tailscale VPN (secure, no port forwarding)
         │
┌────────┴────────┬─────────────────┬─────────────────┐
│ iPhone Claude   │ Web Browser     │ Mac CLI/App     │
│ Code (MCP!)     │ (Web UI)        │ (direct forge)  │
└─────────────────┴─────────────────┴─────────────────┘
```

**Key insight**: Same Pi, same Tailscale network as AirFit. Forge just runs alongside it.

### Client Usage Patterns

**On Mac (primary):**
- Use beautiful **Forge macOS app** for visual management
- Or `forge` CLI directly when you prefer terminal
- Claude Code sessions run locally with full performance

**On iPhone (Claude Code iOS) - Native MCP!:**
1. One-time setup: Configure MCP server URL on claude.ai: `http://pi.tailnet:8081`
2. Then just use natural language in Claude Code iOS:

```
You: "Start the morning-briefings feature on AirFit"

Claude: [Calls forge_start_feature("AirFit", "morning-briefings")]

        ✅ Created worktree at /Users/brian/.../morning-briefings
        ✅ Branch: feature/morning-briefings

        Here's your implementation prompt:
        [Generated prompt with CLAUDE.md context, expert suggestions, etc.]

        Ready to implement! Open a new session in the worktree directory.
```

**No SSH, no curl, no manual steps** - Claude Code speaks directly to Forge via MCP.

**From Web Browser:**
- Navigate to `http://pi.tailnet:8081`
- Simple web UI shows all projects and features
- Click "Start Feature" → creates worktree, shows prompt to copy

### Deployment Steps

**Prerequisites:**
- Pi has Python 3.11+
- Tailscale running on Pi, Mac, iPhone
- Pi can SSH to Mac (for remote worktree creation)

**Deploy Forge Server:**
```bash
# On Pi
git clone <forge-repo> ~/forge
cd ~/forge
python -m venv venv
source venv/bin/activate
pip install -e .

# Configure connection to Mac
export FORGE_MAC_HOST="mac.tailnet"
export FORGE_MAC_USER="brian"
export FORGE_PROJECTS_PATH="/Users/brian/Projects/Active"

# Run server (or use systemd for auto-start)
python -m forge.server --host 0.0.0.0 --port 8081
```

**Access from anywhere:**
```
http://pi.tailnet:8081/                    # Web UI
http://pi.tailnet:8081/api/projects        # API
http://pi.tailnet:8081/api/AirFit/features # Features list
```

---

## Summary: When to Use What

| You're On | Use This | Experience |
|-----------|----------|------------|
| **Mac** | Forge macOS App | Beautiful Kanban, drag-drop, one-click start |
| **Mac (terminal fan)** | `forge` CLI | Full power, direct control |
| **iPhone** | Claude Code + SSH to Mac | Full workflow via Tailscale |
| **iPhone** | Claude Code + Pi API | Lighter, just get prompts |
| **Web browser** | Pi web UI | Quick status checks, start features |
| **Anywhere else** | Pi API | Programmatic access |
