# Implement: Sidebar Project Hide/Reveal

## Workflow Context

You're in a FlowForge-managed worktree for this feature.
- **Worktree:** `/Users/Brian/Projects/Active/FlowForge/.flowforge-worktrees/add-hidereveal-for-sidebar-projects`
- **Branch:** Isolated from main (changes don't affect main until merge)
- **When finished:** Human clicks "Stop" in FlowForge → build validation → merge
- **Your focus:** Implement the feature. Human decides when it's done.

## Feature
Users can hide individual projects from the sidebar to reduce clutter, with a collapsible "Hidden" section at the bottom to reveal and restore them. Hidden state persists across app launches.

How it works:
- Right-click (macOS) or long-press (iOS) on a project shows context menu with "Hide Project" option
- Hidden projects move to a collapsible "Hidden (N)" section at the bottom of the sidebar
- Clicking the "Hidden" section header expands/collapses the list
- Right-click/long-press on a hidden project shows "Show Project" to restore it
- Hidden project IDs stored in UserDefaults/AppStorage
- Hidden projects still sync and update in background, just not displayed in main list

Files likely affected:
- `FlowForgeApp/Views/Sidebar/ProjectListView.swift` (or equivalent sidebar view)
- `FlowForgeApp/Models/AppState.swift` (add hiddenProjectIds: Set<String>)
- `FlowForgeApp/Services/APIClient.swift` (filter hidden from display, not from fetch)

Estimated scope: Small (< 1 hour)

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

You're helping a novice vibecoder who isn't a Git expert.
All Git operations should be explained and handled safely.

**Engage plan mode and ultrathink before implementing.**
Present your plan for approval before writing code.

When complete:
1. Commit your changes with conventional commit format
2. Ensure any new files follow existing patterns
3. Test manually on the target device/environment
4. Run `forge stop add-hidereveal-for-sidebar-projects` to mark ready for review

Ask clarifying questions if the specification is unclear before proceeding.
