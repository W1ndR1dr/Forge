"""
Brainstorm mode for FlowForge.

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
            title="FlowForge Brainstorm",
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
    """Save proposals to .flowforge/brainstorms/."""
    brainstorms_dir = project_root / ".flowforge" / "brainstorms"
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
    filepath = project_root / ".flowforge" / "brainstorms" / f"{session_name}.json"

    if not filepath.exists():
        return []

    data = json.loads(filepath.read_text())
    return [Proposal.from_dict(p) for p in data.get("proposals", [])]
