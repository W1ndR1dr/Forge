# Implement: Server - Basic Auth

## Feature
HTTP Basic Auth for Pi security

**Tags:** server, security

## Expert Perspectives

Consider these expert viewpoints while implementing:

- **Troy Hunt** (Security Researcher & Creator of Have I Been Pwned): Would emphasize proper implementation details like timing-safe comparisons, secure password storage, and common pitfalls in Basic Auth implementations.
- **Eben Upton** (Founder of Raspberry Pi Foundation): Would provide insights on balancing security with Pi's limited resources and typical home/edge network deployments.
- **Armin Ronacher** (Creator of Flask & Werkzeug): Would focus on leveraging existing Python libraries correctly, middleware patterns, and avoiding reinventing security wheels.

Synthesize their perspectives where relevant, noting when different experts might approach things differently.


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

Implement this feature following the project conventions above.

When complete:
1. Commit your changes with conventional commit format
2. Ensure any new files follow existing patterns
3. Test manually on the target device/environment

Ask clarifying questions if the specification is unclear before proceeding.
