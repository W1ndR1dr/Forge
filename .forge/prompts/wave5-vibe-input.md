# Implement: Vibe Input (Single Text Entry)

## Workflow Context

You're in a FlowForge-managed worktree for this feature.
- **Branch:** Isolated from main (changes don't affect main until merge)
- **When finished:** Human clicks "Stop" in FlowForge → build validation → merge
- **Your focus:** Implement the feature. Human decides when it's done.

## Feature
Replace 'Add Feature' with prominent text input at top. Type idea -> Enter -> build flow.

**Tags:** wave5, gui, ux

## Expert Consultation

Consider perspectives from domain experts relevant to this feature.
Identify 2-3 real-world experts whose viewpoints would be valuable.
Synthesize their approaches in your implementation.

## Research Guidance

If this feature involves novel patterns, complex architecture, or
unfamiliar APIs, conduct web research before implementing.
Cite official documentation where applicable.

## Project Context
## Project Overview

FlowForge is an AI-assisted parallel development orchestrator. It enables systematic, parallel AI-assisted development by managing feature backlogs, generating optimized Claude Code prompts, automating Git worktree workflows, and orchestrating merges.

**Philosophy**: Built for "vibecoders" - developers who work extensively with AI assistance but may not be Git experts. FlowForge handles the complexity so users can focus on features.

## Architecture

```
flowforge/
├── cli.py                # Typer CLI commands (main entry point)
├── config.py             # Project configuration (FlowForgeConfig, ProjectConfig)
├── registry.py           # Feature registry (Feature dataclass, CRUD, hierarchy)
├── worktree.py           # Git worktree management (WorktreeManager, ClaudeCodeLauncher)
├── intelligence.py       # Tiered AI intelligence (expert suggestion, research detection)
├── prompt_builder.py     # Implementation prompt generation
├── merge.py              # Merge orchestration (MergeOrchestrator, conflict detection)
├── mcp_server.py         # Remote MCP server for Claude Code (FlowForgeMCPServer)
├── server.py             # FastAPI wrapper (MCP + REST + Web UI at /)
└── remote.py             # SSH execution for Pi→Mac remote worktree creation
```

## Coding Style

- 4-space indentation, type hints on all function signatures
- Dataclasses for data models, Pydantic for API models
- Typer for CLI, Rich for output formatting
- Snake_case for functions/variables

## Build Commands

```bash
# Install in development mode
pip install -e .

# Install with server dependencies (for MCP server/web UI)
pip install -e ".[server]"

# Run CLI
forge --help
forge init
forge add "Feature Title"
forge start feature-id

# Run MCP/HTTP server (for remote access from Pi or mobile)
forge-server

# Server environment variables:
FLOWFORGE_PROJECTS_PATH=/Users/Brian/Projects/Active  # Where to find projects
FLOWFORGE_MAC_HOST=macs-tailscale-hostname            # For Pi→Mac SSH
FLOWFORGE_MAC_USER=Brian                               # Mac username
FLOWFORGE_PORT=8081                                    # Server port
FLOWFORGE_HOST=0.0.0.0                                 # Bind address
```

## Instructions

You're helping a novice vibecoder who isn't a Git expert.
All Git operations should be explained and handled safely.

**Engage plan mode and ultrathink before implementing.**
Present your plan for approval before writing code.

When complete:
1. Commit your changes with conventional commit format
2. Ensure any new files follow existing patterns
3. Test manually on the target device/environment

Ask clarifying questions if the specification is unclear before proceeding.
