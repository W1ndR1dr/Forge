# FlowForge: The Vibecoder's Studio

**The Great Council's Verdict, Distilled**

---

## The Essence

A creative studio where intent becomes implementation through conversation.

You are not a developer. You are an ambitious creator who vibes with AI. FlowForge is your studio—it knows your projects, understands your ideas, and ships your features. Git doesn't exist in your world. Neither do branches, worktrees, or merge conflicts. You just have:

**Ideas → Building → Shipped**

---

## The Five Pillars

### 1. Instant Onboarding
*"Point at folder, start working"*

```
You: "Add AirFit to FlowForge"
FlowForge: "AirFit is a SwiftUI fitness app with HealthKit integration.
            I found 3 open feature ideas in your roadmap.
            What would you like to build?"
```

No config files. No setup wizard. AI reads your README, CLAUDE.md, existing code—understands what you're building.

### 2. Conversational Ideation (Chat-to-Spec)
*"Talk to Claude in the app until prompt becomes a real spec"*

```
You: "I want heart rate zone alerts"
Claude: "When should alerts trigger? During workout only, or anytime?"
You: "Just workouts. Zone 2 specifically."
Claude: "Should it be audio, haptic, or visual? And what's the recovery logic?"
You: "Haptic. And it should chill out for 30 seconds after alerting."
Claude: "Got it. Here's the spec:

         FEATURE: Zone 2 Heart Rate Alerts
         - Monitors HR during active workout sessions
         - Triggers haptic when HR exceeds Zone 2 ceiling (calculated from user profile)
         - 30-second cooldown between alerts
         - UI: Simple toggle in workout settings

         Files affected: WorkoutManager.swift, SettingsView.swift
         Estimated: 2 hours

         [Ready to Build] [Refine More]"
```

The conversation continues until the spec is **excellent**. An LLM evaluator judges:
- Clarity (Is it unambiguous?)
- Scope (Clear boundaries? Shippable in one session?)
- Testability (Can success be verified?)

Only when excellent does it become a buildable feature.

### 3. Invisible Parallelization
*"Worktrees happen, user never knows"*

When you have 3 features building simultaneously:
- You see: "3 features in progress"
- Git sees: 3 worktrees, 3 branches, 3 isolated environments

When features complete:
- You see: "Feature shipped!"
- Git sees: merge, cleanup, branch deletion

You never type `git`. You never resolve conflicts. If there's a semantic collision between features, FlowForge asks: "These two features both modify user settings. Which approach should win?"

### 4. Session Continuity
*"Here's what happened while you were away"*

When you return to the app:

```
"Welcome back!

Since yesterday:
- Zone 2 Alerts: Implementation complete, waiting for your approval to ship
- Rest Day Logic: Claude has a question about recovery calculations
- Dark Mode: Building (45% complete)

What would you like to focus on?"
```

Context is never lost. The AI remembers your projects, your patterns, your previous decisions.

### 5. One-Word Undo
*"Full reversibility, no Git arcana"*

```
"That's not what I wanted."
→ Feature reverted. Try a different approach.
```

Every action reversible. No need to understand what "git reset --hard" means.

---

## The Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  iOS App                         macOS App (SUPERSET)       │
│  - Brainstorm (via Pi)           - Everything iOS has       │
│  - Track features (via Pi)       - PLUS: Native execution   │
│  - Quick capture                 - PLUS: Watch building     │
│  - Approve specs                 - PLUS: One-click ship     │
└──────────────────────┬───────────────────┬──────────────────┘
                       │                   │
         Tailscale     │                   │ ALSO Tailscale
                       │                   │
┌──────────────────────▼───────────────────▼──────────────────┐
│              Raspberry Pi (Single Source of Truth)          │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ BrainstormAgent: Claude CLI with your Max subscription │ │
│  │ FeatureRegistry: Synced to all clients                 │ │
│  │ SpecEvaluator: Quality gate (is this excellent?)       │ │
│  │ SessionMemory: Remembers everything                    │ │
│  └────────────────────────────────────────────────────────┘ │
└──────────────────────┬──────────────────────────────────────┘
                       │ SSH (when Mac needs to execute)
┌──────────────────────▼──────────────────────────────────────┐
│                    Mac (Build Machine)                      │
│  - Git worktrees live here (invisible to user)              │
│  - Implementation Claude Code runs HERE (native)            │
│  - claude --dangerously-skip-permissions (5 parallel max)   │
│  - Git Overlord manages merges (invisible to user)          │
│  - Xcode builds happen here                                 │
└─────────────────────────────────────────────────────────────┘
```

**Key insight**: Both apps connect to Pi for brainstorming and sync. Mac additionally runs implementations locally. User sees unified experience everywhere.

---

## The Pipeline

```
┌─────────┐    ┌───────────┐    ┌───────────┐    ┌──────────┐    ┌─────────┐
│  IDEA   │───▶│ BRAINSTORM│───▶│ EVALUATE  │───▶│  BUILD   │───▶│ SHIPPED │
│         │    │           │    │           │    │          │    │         │
│ "I want │    │ Chat with │    │ Is this   │    │ Claude   │    │ Merged  │
│  dark   │    │ Claude    │    │ excellent?│    │ Code     │    │ to main │
│  mode"  │    │ until spec│    │ (LLM gate)│    │ executes │    │ auto    │
│         │    │ crystals  │    │           │    │ in wktree│    │         │
└─────────┘    └───────────┘    └───────────┘    └──────────┘    └─────────┘
                    │                 │                │               │
                    ▼                 ▼                ▼               ▼
              Pi: Claude CLI    Pi: Evaluator    Mac: Native     Mac: Overlord
```

---

## What Gets Built

### Phase 1: Foundation (The Sync Fix)

**Goal**: Both apps connect to Pi. Unified state everywhere.

Files to modify:
- `FlowForgeApp/Shared/PlatformConfig.swift` → Both platforms point to Pi
- `flowforge/server.py` → Add brainstorm WebSocket endpoint

New files:
- `flowforge/agents/__init__.py` → Agents package
- `flowforge/agents/brainstorm.py` → Claude CLI wrapper for brainstorming

Deliverable: iOS and macOS show same feature list, can both brainstorm

---

### Phase 2: Chat-to-Spec (The Core Experience)

**Goal**: In-app conversation with Claude that crystallizes into specs.

New Swift files:
```
FlowForgeApp/Views/Brainstorm/
├── BrainstormChatView.swift      # Chat interface
├── MessageBubble.swift           # Chat message UI
└── SpecCrystalView.swift         # When spec is ready
```

New Python files:
```
flowforge/agents/
├── brainstorm.py                 # Runs claude CLI on Pi
├── spec_evaluator.py             # Judges spec quality
└── prompts.py                    # All system prompts
```

Server additions:
```python
@app.websocket("/ws/{project}/brainstorm")
async def brainstorm_ws(websocket, project):
    # Stream conversation with Claude CLI
    # User message → Claude → Response streamed back
    # Detect when spec crystallizes
```

Deliverable: Chat in app → Claude responds → Spec emerges

---

### Phase 3: Invisible Execution

**Goal**: Excellent specs auto-execute. User just sees "Building..."

New Python files:
```
flowforge/agents/
├── executor.py                   # Spawns Claude Code sessions
└── parallel_manager.py           # Manages 5 concurrent executions
```

How it works:
1. Spec approved → Executor triggered
2. SSH to Mac: Create worktree (invisible)
3. SSH to Mac: Run `claude --dangerously-skip-permissions -p "spec"`
4. Stream output to app (optional: user can watch or ignore)
5. Detect completion marker
6. Notify Git Overlord

Deliverable: "Build this" → Claude executes → Progress shown

---

### Phase 4: Git Overlord (The Invisible Merger)

**Goal**: Features ship without user touching git.

New Python file:
```
flowforge/agents/git_overlord.py
```

Responsibilities:
- Monitor completed implementations
- Run build validation in worktrees
- Check for semantic conflicts
- Execute merges in safe order
- Clean up after merge
- Ask user only when ambiguity exists

System prompt gives it:
- Full git context (branches, conflicts, history)
- Feature metadata
- Build commands
- Merge heuristics

Deliverable: Feature done → Auto-merged if safe → User sees "Shipped!"

---

### Phase 5: Session Continuity

**Goal**: "Here's what happened while you were away"

New Python file:
```
flowforge/session_memory.py
```

Tracks:
- What changed since last session
- Pending questions from AI
- Features in each state
- User's preferences and patterns

New Swift view:
```
FlowForgeApp/Views/Welcome/WelcomeBackView.swift
```

Shows:
- Summary of changes
- Pending items needing attention
- Suggested next action

Deliverable: App remembers context, greets user with status

---

## The Hard Rules (Dario's Constraints)

1. **Never push to main without approval**
   - Auto-merge is opt-in after trust established
   - Default: "Ready to ship. Approve?"

2. **Full reversibility**
   - Every action has an undo
   - "That's not what I wanted" → reverted

3. **Transparent reasoning**
   - Show WHY Claude made decisions
   - "Using CoreData because your project already uses it"
   - Not terminal logs—narrated choices

---

## The Design Principles (Ive's Mandates)

1. **One idea, one conversation, one outcome**
   - Parallelism is invisible infrastructure
   - User feels like working on ONE thing

2. **Every pixel considered**
   - Chat bubbles, spec cards, status indicators
   - No clutter, no chartjunk

3. **The creation is visible, the plumbing is not**
   - Show the app being built (previews)
   - Hide git, branches, merges

---

## Implementation Order

```
Week 1: Foundation
├── Fix PlatformConfig (both → Pi)
├── Create agents package
├── Add brainstorm WebSocket endpoint
└── Test: Both apps show same features

Week 2: Chat-to-Spec
├── BrainstormChatView.swift
├── brainstorm.py (Claude CLI wrapper)
├── spec_evaluator.py
└── Test: Chat → Spec in app

Week 3: Invisible Execution
├── executor.py
├── parallel_manager.py
├── ExecutionProgressView.swift
└── Test: Spec → Building → Complete

Week 4: Git Overlord
├── git_overlord.py
├── Auto-merge logic
├── ShippedView.swift
└── Test: Complete → Shipped automatically

Week 5: Polish
├── Session memory
├── WelcomeBackView
├── One-word undo
└── Test: Full pipeline, multiple features
```

---

## Success Metrics

1. **User never types a git command**
2. **User never resolves a merge conflict manually**
3. **Idea → Shipped in < 10 interactions**
4. **Features build in parallel without user awareness**
5. **Context preserved across sessions**

---

## The Council's Final Words

**Carmack**: "If it adds overhead, delete it."
**Ive**: "Every pixel considered. Less, but better."
**Karpathy**: "Build for the LLM paradigm, not around it."
**Ilya**: "The human provides values. The AI provides execution."
**Dario**: "Trust is earned through boundaries."
**Victor**: "Show the creation, hide the plumbing."

---

*This is FlowForge. The Vibecoder's Studio.*
*Intent → Shipped.*
