# Implement: Linear-Style Design System

## Workflow Context

You're in a FlowForge-managed worktree for this feature.
- **Feature ID:** `add-a-slight-border-around-each-major-category-ide`
- **Branch:** Isolated from main (changes won't affect main until shipped)
- **To ship:** When human says "ship it", run `forge merge add-a-slight-border-around-each-major-category-ide`
- **Your focus:** Implement the feature. Human decides when to ship.

## Feature
Transforms the macOS app's visual language to a Linear-inspired aesthetic - crisp, dark, information-dense, and professional. Major sections (Idea Inbox, Ideas in Progress) get clear visual separation with hairline borders on solid dark backgrounds. The entire app gets unified with this modern dev-tool aesthetic that complements terminal workflows like Warp.

How it works:
- **Section Containers**: Solid dark backgrounds (`#1a1a1a` / `#242424`), hairline `1px` borders (`#333` or `rgba(255,255,255,0.08)`), tight `6-8px` corner radius
- **Color Palette** (in `DesignTokens.swift`):
- Backgrounds: `#0a0a0a` (base), `#141414` (elevated), `#1a1a1a` (card), `#242424` (hover)
- Borders: `#2a2a2a` (subtle), `#333` (visible)
- Text: `#fafafa` (primary), `#a0a0a0` (secondary), `#666` (tertiary)
- Accent: Single brand color for interactive elements (buttons, selection states)
- **Typography**: System font but tighter line-height, `13-14px` base size, medium weight for headers
- **Spacing Scale**: Tighter than Apple native - `2, 4, 8, 12, 16, 24` (denser information display)
- **Component Styling**:
- Buttons: Solid fills with subtle borders, no gradients, crisp hover states
- Cards/List items: `12px` padding, `6px` radius, hover → background shift to `#242424`
- Inputs: Dark fill (`#141414`), subtle border, no heavy focus rings
- Section headers: `12px` caps or `14px` medium weight, `#666` color, generous top margin
- **Interactions**: Subtle transitions (`150ms ease`), background color shifts on hover, no bounce/spring physics
- **Light Mode**: Optional - can be monochromatic light (`#fafafa` base) or dark-only for simplicity

Files likely affected:
- `FlowForgeApp/Design/DesignTokens.swift` - New color palette, spacing, radii
- `FlowForgeApp/Views/ContentView.swift` - Section containers, base background
- `FlowForgeApp/Views/Kanban/` - Column and card restyling
- `FlowForgeApp/Design/Components/` - Button styles, VibeInput, hover states
- `FlowForgeApp/App/FlowForgeApp.swift` - May need to disable system appearance overrides

Estimated scope: Medium-Large (3-4 hours) - Custom color system requires more manual work than Apple-native, plus testing dark/light handling

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
- Run `forge merge add-a-slight-border-around-each-major-category-ide` to merge to main and clean up
- This handles: merge → build validation → worktree cleanup → done

Ask clarifying questions if the specification is unclear.
