# Implement: Quick Brainstorm Button (Contextual Idea Generator)

## Workflow Context

You're in a FlowForge-managed worktree for this feature.
- **Worktree:** `/Users/Brian/Projects/Active/FlowForge/.flowforge-worktrees/should-move-the-brain-button-and-the-plus-button-s`
- **Branch:** Isolated from main (changes don't affect main until merge)
- **When finished:** Human clicks "Stop" in FlowForge → build validation → merge
- **Your focus:** Implement the feature. Human decides when it's done.

## Feature
Separates the capture UI into two distinct buttons: a + button for freetext quick capture, and a brain button that generates 3 contextual idea suggestions based on the project's existing features and recent commits. Users tap any suggestion to add it to the inbox instantly.

How it works:
- + button opens existing quick capture input (freetext, low friction)
- Brain button shows a popover with loading state (pulsing brain or skeleton chips)
- Backend fetches: project name, existing feature titles, last ~15 git commits
- AI generates 3 short-phrase ideas that don't duplicate existing/completed features
- Ideas appear as tappable chips in the popover
- Tapping a chip instantly adds it to inbox as "idea" status
- User can tap brain again for 3 more if nothing resonates (magic 8-ball style)
- Popover dismisses after selection or tap-outside

Files likely affected:
- `FlowForgeApp/Views/VibeInput.swift` (split into + and brain buttons)
- `flowforge/server.py` (new `/brainstorm/quick` endpoint)
- `flowforge/intelligence.py` (quick brainstorm prompt generation)
- `FlowForgeApp/Services/APIClient.swift` (new endpoint call)
- `FlowForgeApp/Views/Components/BrainstormPopover.swift` (new view)

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

You're helping a novice vibecoder who isn't a Git expert.
All Git operations should be explained and handled safely.

**Engage plan mode and ultrathink before implementing.**
Present your plan for approval before writing code.

When complete:
1. Commit your changes with conventional commit format
2. Ensure any new files follow existing patterns
3. Test manually on the target device/environment

Ask clarifying questions if the specification is unclear before proceeding.
