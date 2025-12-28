# Implement: Smart "Mark as Done" with Clear Feedback

## Workflow Context

You're in a FlowForge-managed worktree for this feature.
- **Feature ID:** `the-done-button-gives-unclear-outcome`
- **Branch:** Isolated from main (changes won't affect main until shipped)
- **To ship:** When human says "ship it", run `forge merge the-done-button-gives-unclear-outcome`
- **Your focus:** Implement the feature. Human decides when to ship.

## Feature
The "Mark as Done" button intelligently detects whether a feature has already been merged to main and either ships it immediately or marks it for review. It shows a loading state during the operation and provides clear feedback about what action was taken.

How it works:
- When pressed, show a loading spinner/state on the button
- Check if the feature's branch has been merged to main (git branch --merged main)
- If already merged: Clean up worktree, move feature to "Shipped", show "✓ Shipped!" toast
- If not merged: Move to "Ready for Review", show "Marked for review - merge when ready" toast
- If worktree doesn't exist but status is "building": Allow manual status advancement with warning
- Handle server latency gracefully (disable button during operation, show spinner)

Files likely affected:
- FlowForgeApp/Views/FeatureRow.swift (button UI, loading state)
- FlowForgeApp/Services/APIClient.swift (new endpoint or enhanced mark-done logic)
- flowforge/server.py or flowforge/mcp_server.py (smart merge detection endpoint)
- flowforge/worktree.py (helper to check if branch merged to main)

Estimated scope: Medium (1-3 hours)

## Expert Consultation

Consider perspectives from domain experts relevant to this feature.
Identify 2-3 real-world experts whose viewpoints would be valuable.
Synthesize their approaches in your implementation.

## Research Guidance

If this feature involves novel patterns, complex architecture, or
unfamiliar APIs, conduct web research before implementing.
Cite official documentation where applicable.

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
- Run `forge merge the-done-button-gives-unclear-outcome` to merge to main and clean up
- This handles: merge → build validation → worktree cleanup → done

Ask clarifying questions if the specification is unclear.
