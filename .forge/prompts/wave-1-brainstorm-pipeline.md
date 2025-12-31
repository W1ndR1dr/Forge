# Wave 1: Brainstorming & GUI Core

## Overview

Implement the complete brainstorming pipeline for FlowForge - from Claude chat integration through proposal review UI. This is a cohesive data pipeline where each component must understand the formats flowing through.

```
forge brainstorm → Claude Chat → READY_FOR_APPROVAL → Parser → Proposals → GUI Review → Registry
```

---

## Features to Implement

### 1. Brainstorm Mode (Python CLI)

**File**: `flowforge/brainstorm.py` (NEW) + `flowforge/cli.py`

Create a `forge brainstorm` command that launches Claude with a product strategist system prompt.

```bash
forge brainstorm
# Interactive Claude session for exploring ideas
# When user signals satisfaction, Claude outputs structured proposals
```

**Implementation Details:**
- Use `--append-system-prompt` to add product strategist context
- Include project context from `.flowforge/project-context.md`
- System prompt should instruct Claude to output `READY_FOR_APPROVAL:` marker followed by JSON when user is satisfied
- Support `--project` flag to specify which project (for multi-project setups)

**System Prompt Template:**
```
You are a product strategist helping brainstorm features for {project_name}.

Project Vision:
{project_context}

Current Features:
{existing_features_summary}

Help the user explore ideas, refine concepts, and prioritize. Ask clarifying questions.
When the user indicates they're satisfied with a set of features, output:

READY_FOR_APPROVAL:
```json
{
  "proposals": [
    {
      "title": "Feature Title",
      "description": "What it does and why",
      "priority": 1-5,
      "complexity": "trivial|simple|medium|complex|epic",
      "tags": ["tag1", "tag2"],
      "rationale": "Why this feature matters"
    }
  ]
}
```

Continue chatting until the user says something like "that's good", "let's go with those", or "ready to add these".
```

**CLI Integration:**
```python
@app.command()
def brainstorm(
    project: Optional[str] = typer.Option(None, "--project", "-p"),
):
    """Start a brainstorming session with Claude."""
    # Launch Claude with system prompt
    # Capture output
    # Parse for READY_FOR_APPROVAL
    # Return proposals
```

---

### 2. Proposal Parser (Python)

**File**: `flowforge/brainstorm.py`

Parse the `READY_FOR_APPROVAL:` output from Claude into structured Proposal objects.

```python
@dataclass
class Proposal:
    title: str
    description: str
    priority: int = 3
    complexity: str = "medium"
    tags: list[str] = field(default_factory=list)
    rationale: str = ""

    # Review state (not from Claude)
    status: str = "pending"  # pending, approved, declined, deferred

def parse_proposals(claude_output: str) -> list[Proposal]:
    """Extract proposals from Claude brainstorm output."""
    # Find READY_FOR_APPROVAL marker
    # Parse JSON after marker
    # Validate and return Proposal objects
    # Handle malformed JSON gracefully
```

**API Endpoint** (for GUI):
```python
# In server.py
@app.post("/api/{project}/brainstorm/parse")
async def parse_brainstorm(project: str, request: BrainstormParseRequest):
    """Parse brainstorm output into proposals."""
    proposals = parse_proposals(request.claude_output)
    return {"proposals": [p.__dict__ for p in proposals]}

@app.post("/api/{project}/proposals/approve")
async def approve_proposals(project: str, request: ApproveRequest):
    """Add approved proposals to registry."""
    # request.proposal_ids = list of indices to approve
    # Add each to registry via registry.add_feature()
```

---

### 3. Approve/Decline/Defer UI (SwiftUI)

**Files**:
- `FlowForgeApp/Views/Brainstorm/ProposalReviewView.swift` (NEW)
- `FlowForgeApp/Views/Brainstorm/ProposalCard.swift` (NEW)
- `FlowForgeApp/Models/Proposal.swift` (NEW)

Create a review interface for brainstorm proposals.

**Proposal Model:**
```swift
struct Proposal: Identifiable, Codable {
    let id: UUID
    var title: String
    var description: String
    var priority: Int
    var complexity: String
    var tags: [String]
    var rationale: String
    var status: ProposalStatus

    enum ProposalStatus: String, Codable {
        case pending, approved, declined, deferred
    }
}
```

**ProposalReviewView:**
- Show list of proposals from brainstorm session
- Each proposal card has: title, description, rationale, priority badge
- Action buttons: Approve (green), Decline (red), Defer (yellow)
- "Approve All" and "Decline All" batch actions
- "Submit Approved" button to add to registry
- "Back to Chat" button to refine further

**Visual Design:**
- Use cards similar to FeatureCard but with approval actions
- Show rationale in an expandable section
- Color-code by priority (P1 = red accent, P5 = gray)
- Approved items get checkmark overlay
- Declined items get strikethrough + fade

---

### 4. Copy Prompt to Clipboard (SwiftUI)

**Files**:
- `FlowForgeApp/Views/Kanban/FeatureCard.swift`
- `FlowForgeApp/Services/APIClient.swift`
- `FlowForgeApp/Models/AppState.swift`

Add one-click prompt copying from feature cards.

**Implementation:**
```swift
// In FeatureCard.swift
Button(action: { copyPrompt(feature) }) {
    Image(systemName: "doc.on.clipboard")
}
.help("Copy implementation prompt")

func copyPrompt(_ feature: Feature) {
    Task {
        let prompt = await apiClient.getPrompt(project: project.name, featureId: feature.id)
        NSPasteboard.general.setString(prompt, forType: .string)
        // Show toast/confirmation
    }
}
```

**API Endpoint:**
```python
# In server.py
@app.get("/api/{project}/features/{feature_id}/prompt")
async def get_feature_prompt(project: str, feature_id: str):
    """Generate and return implementation prompt for a feature."""
    prompt = prompt_builder.build_for_feature(feature_id)
    return {"prompt": prompt}
```

**Toast Notification:**
- Show brief "Copied!" confirmation
- Use SwiftUI overlay or custom toast view
- Auto-dismiss after 2 seconds

---

### 5. GUI Feature Editing (SwiftUI)

**Files**:
- `FlowForgeApp/Views/Kanban/FeatureCard.swift`
- `FlowForgeApp/Views/Kanban/FeatureEditSheet.swift` (NEW)
- `FlowForgeApp/Services/APIClient.swift`

Enable editing features directly in the GUI.

**Approach A - Edit Sheet:**
```swift
// FeatureEditSheet.swift
struct FeatureEditSheet: View {
    @Binding var feature: Feature
    @Environment(\.dismiss) var dismiss
    let onSave: (Feature) -> Void

    var body: some View {
        Form {
            TextField("Title", text: $feature.title)
            TextEditor(text: $feature.description)
            Picker("Status", selection: $feature.status) { ... }
            Picker("Priority", selection: $feature.priority) { ... }
            Picker("Complexity", selection: $feature.complexity) { ... }
            // Tags editor
        }
        .toolbar {
            Button("Save") { save() }
            Button("Cancel") { dismiss() }
        }
    }
}
```

**Approach B - Inline Editing:**
- Double-click title to edit inline
- Right-click context menu for other fields
- More fluid but more complex

**Recommend Approach A** (Edit Sheet) for simplicity.

**API Integration:**
```swift
// APIClient.swift
func updateFeature(project: String, featureId: String, updates: FeatureUpdate) async throws {
    // PATCH /api/{project}/features/{featureId}
}
```

---

## Data Flow Summary

```
┌─────────────────┐
│ forge brainstorm│ ─── Claude chat with system prompt
└────────┬────────┘
         │ User: "ready"
         ▼
┌─────────────────┐
│READY_FOR_APPROVAL│ ─── Claude outputs JSON
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ parse_proposals │ ─── Python extracts Proposal objects
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ProposalReviewView│ ─── SwiftUI shows approve/decline UI
└────────┬────────┘
         │ User approves
         ▼
┌─────────────────┐
│ registry.add()  │ ─── Features added to registry
└─────────────────┘
```

---

## File Checklist

### Python (New)
- [ ] `flowforge/brainstorm.py` - Brainstorm mode + proposal parsing

### Python (Modified)
- [ ] `flowforge/cli.py` - Add `brainstorm` command
- [ ] `flowforge/server.py` - Add brainstorm/proposal endpoints, prompt endpoint

### Swift (New)
- [ ] `FlowForgeApp/Models/Proposal.swift`
- [ ] `FlowForgeApp/Views/Brainstorm/ProposalReviewView.swift`
- [ ] `FlowForgeApp/Views/Brainstorm/ProposalCard.swift`
- [ ] `FlowForgeApp/Views/Kanban/FeatureEditSheet.swift`

### Swift (Modified)
- [ ] `FlowForgeApp/Views/Kanban/FeatureCard.swift` - Copy prompt + edit button
- [ ] `FlowForgeApp/Services/APIClient.swift` - New endpoints
- [ ] `FlowForgeApp/Models/AppState.swift` - Proposal state

---

## Success Criteria

After implementation:
- [ ] `forge brainstorm` launches Claude with product strategist prompt
- [ ] Claude outputs READY_FOR_APPROVAL JSON when user is satisfied
- [ ] Parser extracts proposals from Claude output
- [ ] GUI shows proposals for review with approve/decline/defer
- [ ] Approved proposals get added to feature registry
- [ ] One-click copy prompt from feature cards
- [ ] Features can be edited in GUI (sheet approach)

---

## Project Context

**Philosophy**: FlowForge = Better Organization + Better Prompts. This wave adds the "brainstorming" stage of the pipeline.

**User Role**: Vibecoder who focuses on ideas, not Git.

**Claude CLI Flags** (verified working with MAX subscription):
- `--append-system-prompt` - Add to default prompt
- `--output-format json` - For parsing (optional)
- `--dangerously-skip-permissions` - For automation

---

## Instructions

You're helping a novice vibecoder who isn't a Git expert.
All Git operations should be explained and handled safely.

**Engage plan mode and ultrathink before implementing.**
Present your plan for approval before writing code.

Implementation order suggestion:
1. Python: brainstorm.py with Proposal dataclass and parser
2. Python: CLI command and server endpoints
3. Swift: Proposal model and API client methods
4. Swift: ProposalReviewView and ProposalCard
5. Swift: Copy prompt button on FeatureCard
6. Swift: FeatureEditSheet

When complete:
1. Commit your changes with conventional commit format
2. Ensure any new files follow existing patterns
3. Test manually - especially the Claude chat → parse → review flow

Ask clarifying questions if the specification is unclear before proceeding.
