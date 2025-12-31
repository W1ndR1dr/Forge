# Implement: Rename FlowForge to Forge (Full Rebrand)

## Workflow Context

You're in a FlowForge-managed worktree for this feature.
- **Feature ID:** `rename-the-app-from-flowforge-to-just-forge`
- **Branch:** Isolated from main (changes won't affect main until shipped)
- **To ship:** When human says "ship it", run `forge merge rename-the-app-from-flowforge-to-just-forge`
- **Your focus:** Implement the feature. Human decides when to ship.

## Feature
Renames the entire project from "FlowForge" to "Forge" across all layers - Python package, CLI (already `forge`), macOS app, iOS app, folder names, GitHub repo, documentation, and all internal references. After this, "FlowForge" appears nowhere in the codebase.

How it works:
- Python package: `flowforge/` → `forge/`, all imports updated
- Project folder: `~/Projects/Active/FlowForge/` → `~/Projects/Active/Forge/`
- Swift apps: `FlowForgeApp/` → `ForgeApp/`, bundle IDs `com.flowforge.*` → `com.forge.*`
- macOS app name: "FlowForge.app" → "Forge.app"
- iOS app name: Update display name and bundle ID
- GitHub repo: Rename from `flowforge` to `forge`
- Documentation: CLAUDE.md, all docs/, README
- Pi systemd service: `flowforge.service` → `forge.service`
- Environment variables: `FLOWFORGE_*` → `FORGE_*`
- Internal references: Class names like `FlowForgeConfig` → `ForgeConfig`, `FlowForgeMCPServer` → `ForgeMCPServer`
- Git history: Preserved (rename, not recreate)

Files likely affected:
- Every Python file (imports, class names)
- `pyproject.toml`, `setup.py` if exists
- `FlowForgeApp/project.yml` and all Swift files
- `CLAUDE.md`, `docs/*.md`, `README.md`
- `scripts/*.sh` (paths, service names)
- Pi config: `/etc/systemd/system/flowforge.service`
- Environment configs referencing FLOWFORGE_*

Estimated scope: Large (3+ hours) - High file count, needs careful find/replace across languages, must update Pi deployment, requires App Store Connect changes for iOS bundle ID

## Research

If this feature involves novel patterns, complex architecture, or unfamiliar APIs:
- **Ask the human** to run deep research threads if you need authoritative context
- For clinical/medical evidence, specifically ask them to check OpenEvidence
- Cite official documentation where applicable

## Project Context
# No CLAUDE.md found

Follow standard coding conventions.

## Instructions

You're helping a vibecoder who isn't a Git expert.
Handle all Git operations safely without requiring them to understand Git.

**Engage plan mode and ultrathink before implementing.**
Present your plan for approval before writing code.

When implementing:
- Commit changes with conventional commit format
- Follow existing patterns in the codebase
- Test on target device/environment

When human says "ship it":
- Run `forge merge rename-the-app-from-flowforge-to-just-forge` to merge to main and clean up
- This handles: merge → build validation → worktree cleanup → done

Ask clarifying questions if the specification is unclear.
