# AGI-Pilled Development Workflow

A philosophy and system for working with AI coding assistants (Claude Code, Gemini CLI, OpenAI Codex CLI etc.) that embraces the non-linear nature of LLM conversations while maintaining engineering discipline at the boundaries.

## Core Philosophy

**"Loose in the middle, tight at the edges."**

- **Loose in the middle**: Let Claude explore, iterate, and solve problems in whatever way makes sense. Don't over-constrain the creative process.
- **Tight at the edges**: Enforce discipline at system boundaries—git commits, merges, and deployments.

This mirrors how humans actually think: scattered and associative during exploration, focused during delivery.

---

## The Workflow Loop

```
┌─────────────────────────────────────────────────────────────────┐
│  CAPTURE                                                         │
│  "I have an idea..." - jot it down before you forget            │
│  Quick, rough, incomplete is fine                                │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│  REFINE                                                          │
│  Review rough ideas, discuss with LLM, refine into               │
│  a clear feature description with context                        │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│  START                                                           │
│  Create isolated workspace (git worktree)                        │
│  Generate implementation prompt with codebase context            │
│  Launch Claude Code with the prompt                              │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│  BUILD (Claude Code)                                             │
│  Free-form conversation, exploration, implementation             │
│  Multiple iterations, tangents are OK                            │
│  This is the "loose in the middle" part                          │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│  STOP                                                            │
│  Human clicks "done" - the checkpoint                            │
│  Feature moves to review state                                   │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│  SHIP                                                            │
│  Conflict check → Build validation → Merge to main               │
│  This is the "tight at the edges" part                           │
└─────────────────────────────────────────────────────────────────┘
```

---

## Why Manual Checkpoints?

**Q: Why not have Claude automatically signal when it's done?**

A: The "done" button is a **human-in-loop checkpoint**. Benefits:

1. **You verify** the feature works as intended
2. **You decide** when something is shippable
3. **You catch** things Claude might have missed
4. **You maintain** agency in the development process

Automation is great for plumbing. Human judgment is for deciding "is this ready?"

---

## Safeguards Against Vibecoding Mistakes

When working fast with AI assistance, mistakes happen. Here's how to not break things:

### 1. Isolation (Git Worktrees)
Each feature gets its own directory. Changes can't interfere with other work or main branch until explicitly merged.

### 2. Build Validation Before Merge
Before any merge, run the build command. Catches type errors, test failures, and obvious breakage.

### 3. Conflict Detection
Check for merge conflicts before attempting merge. Know what you're getting into.

### 4. Git Bisect-ability
Every merge is a single commit. If something breaks later, `git bisect` can pinpoint exactly which feature caused it.

### 5. Easy Rollback
Single-commit merges mean `git revert` cleanly undoes any feature.

---

## The AGI-Pilled Mindset

### Trust the Model
Claude is remarkably capable. Don't over-constrain with rigid prompts or excessive structure. Give it context and goals, let it figure out how.

### Embrace Non-Linear Thinking
LLM conversations are associative and exploratory. That's a feature, not a bug. Tangents often lead to better solutions.

### Ship Over Organize
Resist the urge to categorize, prioritize, and organize your backlog. Pick something, ship it, repeat. Organization is often procrastination.

### Context Over Structure
Rich context in prompts beats rigid templates. Tell Claude what you're trying to achieve and why, not just the mechanical steps.

### Human Judgment at Boundaries
Let Claude do what it's good at (coding, exploring, iterating). Keep humans at decision points (what to build, when it's ready, whether to ship).

---

## Anti-Patterns to Avoid

### Over-Engineering Prompts
Don't write 500-line prompts with every possible edge case. Trust Claude to ask clarifying questions.

### Micromanaging the Model
Don't tell Claude exactly how to implement something unless you have strong preferences. Let it propose solutions.

### Premature Optimization
Ship the simple version first. You can always iterate. Don't design for hypothetical future requirements.

### Category Paralysis
"Should this be under Backend or Infrastructure?" Stop. Just capture the idea and move on.

### Waiting for Perfect
Good enough and shipped beats perfect and stuck in backlog.

---

## When Things Go Wrong

### "I broke something and didn't notice"
1. Each feature is a single merge commit
2. Use `git bisect` to find when the break was introduced
3. `git revert <commit>` to undo the problematic feature
4. Fix the issue, re-ship

### "Claude went off the rails"
1. Your worktree is isolated—main is safe
2. `git reset --hard HEAD` in the worktree to start over
3. Or just delete the worktree and create a new one

### "This feature is way more complex than I thought"
1. Stop, mark as blocked
2. Break into smaller features
3. Ship incrementally

---

## For Claude Code Sessions

When working in this workflow, Claude Code should understand:

1. **You're in a worktree** - Changes here don't affect main until merged
2. **Ship small** - Prefer smaller, focused changes over large refactors
3. **Build must pass** - Every commit should leave the project buildable
4. **Ask, don't assume** - If requirements are unclear, ask before implementing
5. **Done = user says done** - Don't announce completion, let the human decide

---

## Summary

> **Ship fast, stay safe.**
>
> Give Claude rich context and freedom to explore.
> Keep humans at decision points.
> Enforce discipline at git boundaries.
> Trust the model, verify the results.
> When in doubt, ship something small.
