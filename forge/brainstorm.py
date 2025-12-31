"""
Brainstorm mode for Forge.

Enables Claude chat sessions with a product strategist system prompt.
Parses READY_FOR_APPROVAL output into structured proposals.
"""

import json
import re
import subprocess
from dataclasses import dataclass, field, asdict
from pathlib import Path
from typing import Optional
from enum import Enum

from rich.console import Console
from rich.panel import Panel
from rich.markdown import Markdown

console = Console()


class ProposalStatus(str, Enum):
    """Status of a brainstorm proposal."""
    PENDING = "pending"
    APPROVED = "approved"
    DECLINED = "declined"
    DEFERRED = "deferred"


@dataclass
class Proposal:
    """A feature proposal from a brainstorm session."""

    title: str
    description: str
    priority: int = 3
    complexity: str = "medium"
    tags: list[str] = field(default_factory=list)
    rationale: str = ""
    status: ProposalStatus = ProposalStatus.PENDING

    def to_dict(self) -> dict:
        """Convert to dictionary for JSON serialization."""
        return {
            "title": self.title,
            "description": self.description,
            "priority": self.priority,
            "complexity": self.complexity,
            "tags": self.tags,
            "rationale": self.rationale,
            "status": self.status.value,
        }

    @classmethod
    def from_dict(cls, data: dict) -> "Proposal":
        """Create from dictionary."""
        status = data.get("status", "pending")
        if isinstance(status, str):
            status = ProposalStatus(status)
        return cls(
            title=data.get("title", "Untitled"),
            description=data.get("description", ""),
            priority=data.get("priority", 3),
            complexity=data.get("complexity", "medium"),
            tags=data.get("tags", []),
            rationale=data.get("rationale", ""),
            status=status,
        )


def parse_proposals(claude_output: str) -> list[Proposal]:
    """
    Extract proposals from Claude brainstorm output.

    Looks for READY_FOR_APPROVAL marker followed by JSON.
    Handles various JSON formats gracefully.
    """
    # Look for the marker
    marker_patterns = [
        r"READY_FOR_APPROVAL:\s*```json\s*(.*?)\s*```",  # Markdown code block
        r"READY_FOR_APPROVAL:\s*```\s*(.*?)\s*```",      # Generic code block
        r"READY_FOR_APPROVAL:\s*(\{.*\})",               # Inline JSON object
        r"READY_FOR_APPROVAL:\s*(\[.*\])",               # Inline JSON array
    ]

    json_str = None
    for pattern in marker_patterns:
        match = re.search(pattern, claude_output, re.DOTALL | re.IGNORECASE)
        if match:
            json_str = match.group(1).strip()
            break

    if not json_str:
        # Try to find any JSON after "READY_FOR_APPROVAL"
        marker_idx = claude_output.lower().find("ready_for_approval")
        if marker_idx != -1:
            after_marker = claude_output[marker_idx:]
            # Find first { or [
            json_start = -1
            for i, char in enumerate(after_marker):
                if char in "{[":
                    json_start = i
                    break
            if json_start != -1:
                json_str = after_marker[json_start:]

    if not json_str:
        return []

    # Try to parse JSON
    try:
        data = json.loads(json_str)
    except json.JSONDecodeError:
        # Try to fix common issues
        # Sometimes Claude adds trailing text
        for end_char in ["}]", "]}", "}", "]"]:
            try:
                end_idx = json_str.rfind(end_char) + len(end_char)
                data = json.loads(json_str[:end_idx])
                break
            except json.JSONDecodeError:
                continue
        else:
            console.print("[yellow]Warning: Could not parse proposals JSON[/yellow]")
            return []

    # Normalize to list of proposals
    proposals = []

    if isinstance(data, dict):
        if "proposals" in data:
            items = data["proposals"]
        elif "features" in data:
            items = data["features"]
        else:
            # Single proposal
            items = [data]
    elif isinstance(data, list):
        items = data
    else:
        return []

    for item in items:
        try:
            proposal = Proposal.from_dict(item)
            proposals.append(proposal)
        except Exception as e:
            console.print(f"[yellow]Warning: Skipping malformed proposal: {e}[/yellow]")

    return proposals


def build_system_prompt(
    project_name: str,
    project_context: Optional[str] = None,
    existing_features: Optional[list[str]] = None,
) -> str:
    """
    Build the product strategist system prompt for brainstorming.
    """
    features_summary = ""
    if existing_features:
        features_summary = "\n".join(f"- {f}" for f in existing_features[:20])
        if len(existing_features) > 20:
            features_summary += f"\n... and {len(existing_features) - 20} more"

    prompt = f"""You are a product strategist helping brainstorm features for {project_name}.

{f"Project Vision:{chr(10)}{project_context}" if project_context else ""}

{f"Current Features:{chr(10)}{features_summary}" if features_summary else "No features defined yet."}

Help the user explore ideas, refine concepts, and prioritize. Ask clarifying questions.
Be opinionated but flexible. Suggest improvements to their ideas.

When the user indicates they're satisfied with a set of features (e.g., "that's good",
"let's go with those", "ready to add these", "looks good"), output:

READY_FOR_APPROVAL:
```json
{{
  "proposals": [
    {{
      "title": "Feature Title",
      "description": "What it does and why",
      "priority": 1,
      "complexity": "medium",
      "tags": ["tag1", "tag2"],
      "rationale": "Why this feature matters"
    }}
  ]
}}
```

Priority scale: 1 (critical) to 5 (nice-to-have)
Complexity: trivial, simple, medium, complex, epic

Continue chatting naturally until the user signals satisfaction."""

    return prompt


class BrainstormSession:
    """
    Manages a brainstorming session with Claude.
    """

    def __init__(
        self,
        project_root: Path,
        project_name: str,
        project_context: Optional[str] = None,
        existing_features: Optional[list[str]] = None,
    ):
        self.project_root = project_root
        self.project_name = project_name
        self.system_prompt = build_system_prompt(
            project_name,
            project_context,
            existing_features,
        )
        self.proposals: list[Proposal] = []
        self.chat_history: list[str] = []

    def start_interactive(self) -> list[Proposal]:
        """
        Start an interactive Claude session for brainstorming.

        Returns proposals when session ends.
        """
        console.print(Panel(
            f"[bold]Brainstorming Session: {self.project_name}[/bold]\n\n"
            "Chat with Claude about feature ideas.\n"
            "When ready, say 'that looks good' or 'ready to add these'.\n"
            "Claude will output structured proposals for review.",
            title="Forge Brainstorm",
        ))

        # Launch Claude with the system prompt
        try:
            result = subprocess.run(
                [
                    "claude",
                    "--append-system-prompt", self.system_prompt,
                ],
                cwd=self.project_root,
                text=True,
            )

            # After Claude exits, check if there's output to parse
            # Note: In interactive mode, we can't easily capture output
            # The user would need to copy the READY_FOR_APPROVAL section

        except FileNotFoundError:
            console.print("[red]Error: Claude CLI not found. Is it installed?[/red]")
            return []
        except KeyboardInterrupt:
            console.print("\n[yellow]Brainstorm session cancelled.[/yellow]")
            return []

        return self.proposals

    def parse_from_text(self, text: str) -> list[Proposal]:
        """
        Parse proposals from pasted text (for GUI flow).
        """
        self.proposals = parse_proposals(text)
        return self.proposals


@dataclass
class BrainstormResult:
    """Result of a brainstorm session."""
    proposals: list[Proposal]
    session_log: str = ""

    def to_dict(self) -> dict:
        return {
            "proposals": [p.to_dict() for p in self.proposals],
            "session_log": self.session_log,
        }


def save_proposals(
    project_root: Path,
    proposals: list[Proposal],
    session_name: Optional[str] = None,
) -> Path:
    """Save proposals to .forge/brainstorms/."""
    brainstorms_dir = project_root / ".forge" / "brainstorms"
    brainstorms_dir.mkdir(parents=True, exist_ok=True)

    if not session_name:
        import datetime
        session_name = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")

    filepath = brainstorms_dir / f"{session_name}.json"

    data = {
        "proposals": [p.to_dict() for p in proposals],
    }

    filepath.write_text(json.dumps(data, indent=2))
    return filepath


def load_proposals(project_root: Path, session_name: str) -> list[Proposal]:
    """Load proposals from a saved brainstorm session."""
    filepath = project_root / ".forge" / "brainstorms" / f"{session_name}.json"

    if not filepath.exists():
        return []

    data = json.loads(filepath.read_text())
    return [Proposal.from_dict(p) for p in data.get("proposals", [])]


# =============================================================================
# Scope Creep Detection (Wave 4)
# =============================================================================

# Phrases that indicate scope creep - trying to do too much in one feature
SCOPE_CREEP_INDICATORS = [
    r"\band\s+also\b",
    r"\bplus\b",
    r"\badditionally\b",
    r"\bas\s+well\s+as\b",
    r"\balong\s+with\b",
    r"\btogether\s+with\b",
    r"\bon\s+top\s+of\b",
    r"\bin\s+addition\b",
    r"\bfurthermore\b",
    r"\bmoreover\b",
    r"\bnot\s+only\b.*\bbut\s+also\b",
    r"\bmultiple\b.*\bfeatures?\b",
    r"\bseveral\b.*\bthings?\b",
]

# Complexity levels that suggest scope is too large
HIGH_COMPLEXITY_LEVELS = ["large", "complex", "epic"]


@dataclass
class ScopeCreepWarning:
    """Warning about potential scope creep."""
    issue: str
    suggestion: str
    severity: str = "warning"  # warning, error


def detect_scope_creep(
    title: str,
    description: str = "",
    complexity: str = "medium",
) -> list[ScopeCreepWarning]:
    """
    Detect potential scope creep in a feature.

    Returns a list of warnings if the feature seems too broad.
    """
    warnings = []
    text = f"{title} {description}".lower()

    # Check for scope creep indicator phrases
    for pattern in SCOPE_CREEP_INDICATORS:
        if re.search(pattern, text, re.IGNORECASE):
            match = re.search(pattern, text, re.IGNORECASE)
            warnings.append(ScopeCreepWarning(
                issue=f"Found scope creep indicator: '{match.group()}'",
                suggestion="Consider splitting into separate features that can ship independently.",
                severity="warning",
            ))
            break  # One warning is enough

    # Check complexity
    if complexity.lower() in HIGH_COMPLEXITY_LEVELS:
        warnings.append(ScopeCreepWarning(
            issue=f"High complexity ({complexity}) suggests this might be too big.",
            suggestion="Break into smaller, medium-complexity features you can ship in 4 hours.",
            severity="warning",
        ))

    # Check for multiple distinct concepts (heuristic: many commas or semicolons)
    if text.count(",") >= 4 or text.count(";") >= 2:
        warnings.append(ScopeCreepWarning(
            issue="Description lists many items - might be multiple features in one.",
            suggestion="Each feature should do ONE thing well. Split this list.",
            severity="warning",
        ))

    # Check title length (long titles often indicate scope creep)
    if len(title) > 60:
        warnings.append(ScopeCreepWarning(
            issue="Long title suggests feature does too many things.",
            suggestion="A good feature title fits in a tweet. What's the ONE thing?",
            severity="warning",
        ))

    return warnings


def suggest_split(title: str, description: str = "") -> list[str]:
    """
    Suggest how to split a feature that has scope creep.

    Returns a list of suggested smaller feature titles.
    """
    text = f"{title}. {description}".lower()
    suggestions = []

    # Look for "and" splits
    and_parts = re.split(r"\s+and\s+|\s*,\s+and\s+", text)
    if len(and_parts) > 1:
        for part in and_parts:
            clean = part.strip().capitalize()
            if len(clean) > 10:  # Skip trivial parts
                suggestions.append(clean[:80])

    # Look for comma-separated items
    if not suggestions:
        comma_parts = [p.strip() for p in text.split(",") if len(p.strip()) > 10]
        if len(comma_parts) > 2:
            suggestions = [p.capitalize()[:80] for p in comma_parts[:4]]

    # If no split found, suggest breaking by phase
    if not suggestions:
        suggestions = [
            f"{title} - Core functionality",
            f"{title} - UI polish",
            f"{title} - Error handling",
        ]

    return suggestions[:4]  # Max 4 suggestions


def check_shippable(title: str, description: str = "", complexity: str = "medium") -> dict:
    """
    Check if a feature is shippable in 4 hours (the shipping machine constraint).

    Returns a dict with:
    - shippable: bool - can this ship today?
    - warnings: list - any scope creep warnings
    - suggestions: list - if not shippable, how to split
    """
    warnings = detect_scope_creep(title, description, complexity)

    # Feature is shippable if no warnings and complexity is small/medium
    shippable = len(warnings) == 0 and complexity.lower() in ["small", "medium", "trivial", "simple"]

    result = {
        "shippable": shippable,
        "warnings": [{"issue": w.issue, "suggestion": w.suggestion, "severity": w.severity} for w in warnings],
        "suggestions": [],
    }

    if not shippable and warnings:
        result["suggestions"] = suggest_split(title, description)

    return result
