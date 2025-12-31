# Implement: Match Warp Terminal Corner Radius

## Workflow Context

You're in a FlowForge-managed worktree for this feature.
- **Feature ID:** `change-app-corner-radius-to-exactly-the-same-as-wa`
- **Branch:** Isolated from main (changes won't affect main until shipped)
- **To ship:** When human says "ship it", run `forge merge change-app-corner-radius-to-exactly-the-same-as-wa`
- **Your focus:** Implement the feature. Human decides when to ship.

## Feature
Updates the FlowForge app window corner radius to exactly match Warp terminal's corner radius, creating a more polished, consistent feel with modern macOS design language.

How it works:
- Research Warp terminal's exact corner radius (via screenshot measurement or documentation)
- Update the window corner radius in DesignTokens.swift to match
- Apply consistently across any components using the corner radius token

Files likely affected:
- FlowForgeApp/Design/DesignTokens.swift (corner radius constant)
- Possibly window configuration in App/ if corner radius is set at window level

Estimated scope: Small (< 1 hour)

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
- Run `forge merge change-app-corner-radius-to-exactly-the-same-as-wa` to merge to main and clean up
- This handles: merge → build validation → worktree cleanup → done

Ask clarifying questions if the specification is unclear.
