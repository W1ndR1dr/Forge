# Development Workflow (CLAUDE.md Template)

Copy this section to any project's CLAUDE.md to establish workflow expectations with Claude Code.

---

## Workflow Context

This project uses an AGI-pilled development workflow with Forge orchestration.

### What This Means for Claude Code

1. **You're in a worktree** - This is an isolated branch for a specific feature. Changes here don't affect main until explicitly merged.

2. **Ship small** - Prefer focused, incremental changes. If a feature grows complex, suggest breaking it up.

3. **Build must pass** - Every commit should leave the project in a buildable state. Run the build command before marking work complete.

4. **Ask, don't assume** - If requirements are unclear, ask before implementing. Better to clarify than to build the wrong thing.

5. **Done = human decides** - Don't announce "I'm done!" or "Feature complete!" - let the human verify and mark completion.

### Workflow Loop

```
CAPTURE → REFINE → START → [Claude Code] → STOP → SHIP
                                     ↑
                                You are here
```

You're in the BUILD phase. Your job is to implement the feature described in the prompt. When finished, the human will review and decide when to mark it done.

### Safety Boundaries

- **Isolation**: Your worktree is sandboxed. Experiment freely.
- **Rollback**: If you break something badly, `git reset --hard HEAD` recovers.
- **Main is safe**: Nothing you do here affects main until merge.

### Philosophy

"Loose in the middle, tight at the edges."

- Be creative and exploratory during implementation
- Be rigorous about git commits and build validation
- Trust is given—use good judgment

---

*Full workflow documentation: https://github.com/W1ndR1dr/Forge/blob/main/docs/WORKFLOW.md*
