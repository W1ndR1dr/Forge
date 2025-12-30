# Implement: Unified Apple-Native Design System

## Workflow Context

You're in a FlowForge-managed worktree for this feature.
- **Feature ID:** `add-a-slight-border-around-each-major-category-ide`
- **Branch:** Isolated from main (changes won't affect main until shipped)
- **To ship:** When human says "ship it", run `forge merge add-a-slight-border-around-each-major-category-ide`
- **Your focus:** Implement the feature. Human decides when to ship.

## Feature
Establishes a cohesive Apple-native design language across the entire macOS app. Major sections (Idea Inbox, Ideas in Progress) get clear visual separation using native macOS materials and subtle borders. All UI elements are unified to follow consistent spacing, corner radii, and system color conventions.

How it works:
- **Section Containers**: Wrap each major section in a container with `.regularMaterial` or `.ultraThinMaterial` background, `1px` border using `.stroke(.separator)`, and `12pt` corner radius
- **Design Tokens**: Standardize in `DesignTokens.swift`:
- Corner radii: `small: 6`, `medium: 10`, `large: 12`
- Spacing scale: `4, 8, 12, 16, 24, 32`
- Colors: System only (`.primary`, `.secondary`, `.tertiary`, `.separator`, `.quaternary`)
- **Component Unification**:
- Buttons: Consistent use of `.buttonStyle(.bordered)` / `.borderedProminent`
- Cards/Feature items: Uniform padding (`12-16pt`), subtle hover states via `.onHover`
- Inputs: Native `TextField` styling with consistent heights
- Remove all hardcoded hex colors in favor of semantic system colors
- **Section Headers**: `.headline` or `.title3` typography, consistent vertical spacing above/below
- **Light/Dark Mode**: Fully automatic - system materials and colors adapt without manual overrides

Files likely affected:
- `FlowForgeApp/Design/DesignTokens.swift` - Spacing, radii, color semantic definitions
- `FlowForgeApp/Views/ContentView.swift` - Main layout with section containers
- `FlowForgeApp/Views/Kanban/` - Column and card styling
- `FlowForgeApp/Design/Components/` - VibeInput, buttons, reusable components
- `FlowForgeApp/Views/Sidebar/` - Sidebar styling alignment if needed

Estimated scope: Medium (2-3 hours)

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
