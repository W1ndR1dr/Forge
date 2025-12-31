"""
SessionMemory - Remembers what happened while you were away.

Tracks changes, pending questions, and generates welcome-back summaries.
"""

import json
from dataclasses import dataclass, field, asdict
from datetime import datetime
from pathlib import Path
from typing import Optional


@dataclass
class FeatureChange:
    """A change to a feature since last session."""
    feature_id: str
    feature_title: str
    change_type: str  # created, started, completed, merged, blocked
    timestamp: str
    details: Optional[str] = None


@dataclass
class PendingQuestion:
    """A question from AI that needs user input."""
    feature_id: str
    feature_title: str
    question: str
    context: Optional[str] = None
    asked_at: str = field(default_factory=lambda: datetime.now().isoformat())


@dataclass
class SessionState:
    """State of a session for a project."""
    project_name: str
    last_seen: str
    changes_since: list[FeatureChange] = field(default_factory=list)
    pending_questions: list[PendingQuestion] = field(default_factory=list)
    features_in_progress: list[str] = field(default_factory=list)
    features_ready_to_ship: list[str] = field(default_factory=list)
    current_streak: int = 0

    def to_dict(self) -> dict:
        return {
            "project_name": self.project_name,
            "last_seen": self.last_seen,
            "changes_since": [asdict(c) for c in self.changes_since],
            "pending_questions": [asdict(q) for q in self.pending_questions],
            "features_in_progress": self.features_in_progress,
            "features_ready_to_ship": self.features_ready_to_ship,
            "current_streak": self.current_streak,
        }

    @classmethod
    def from_dict(cls, data: dict) -> "SessionState":
        return cls(
            project_name=data.get("project_name", ""),
            last_seen=data.get("last_seen", ""),
            changes_since=[
                FeatureChange(**c) for c in data.get("changes_since", [])
            ],
            pending_questions=[
                PendingQuestion(**q) for q in data.get("pending_questions", [])
            ],
            features_in_progress=data.get("features_in_progress", []),
            features_ready_to_ship=data.get("features_ready_to_ship", []),
            current_streak=data.get("current_streak", 0),
        )


class SessionMemory:
    """
    Tracks session state for projects.

    Remembers:
    - When you last interacted
    - What changed since then
    - Pending questions from AI
    - Current work-in-progress
    """

    def __init__(self, data_dir: Path):
        self.data_dir = data_dir
        self.sessions_file = data_dir / "sessions.json"
        self._sessions: dict[str, SessionState] = {}
        self._load()

    def _load(self):
        """Load session data from disk."""
        if self.sessions_file.exists():
            try:
                data = json.loads(self.sessions_file.read_text())
                self._sessions = {
                    project: SessionState.from_dict(state)
                    for project, state in data.items()
                }
            except (json.JSONDecodeError, KeyError):
                self._sessions = {}

    def _save(self):
        """Save session data to disk."""
        self.data_dir.mkdir(parents=True, exist_ok=True)
        data = {
            project: state.to_dict()
            for project, state in self._sessions.items()
        }
        self.sessions_file.write_text(json.dumps(data, indent=2))

    def get_session(self, project_name: str) -> SessionState:
        """Get or create session state for a project."""
        if project_name not in self._sessions:
            self._sessions[project_name] = SessionState(
                project_name=project_name,
                last_seen=datetime.now().isoformat(),
            )
        return self._sessions[project_name]

    def record_visit(self, project_name: str):
        """Record that user visited a project (clears changes)."""
        session = self.get_session(project_name)
        session.last_seen = datetime.now().isoformat()
        session.changes_since = []
        self._save()

    def record_change(
        self,
        project_name: str,
        feature_id: str,
        feature_title: str,
        change_type: str,
        details: Optional[str] = None,
    ):
        """Record a change to a feature."""
        session = self.get_session(project_name)
        session.changes_since.append(FeatureChange(
            feature_id=feature_id,
            feature_title=feature_title,
            change_type=change_type,
            timestamp=datetime.now().isoformat(),
            details=details,
        ))
        self._save()

    def add_pending_question(
        self,
        project_name: str,
        feature_id: str,
        feature_title: str,
        question: str,
        context: Optional[str] = None,
    ):
        """Add a pending question that needs user input."""
        session = self.get_session(project_name)
        session.pending_questions.append(PendingQuestion(
            feature_id=feature_id,
            feature_title=feature_title,
            question=question,
            context=context,
        ))
        self._save()

    def clear_question(self, project_name: str, feature_id: str):
        """Clear pending questions for a feature."""
        session = self.get_session(project_name)
        session.pending_questions = [
            q for q in session.pending_questions
            if q.feature_id != feature_id
        ]
        self._save()

    def update_in_progress(
        self,
        project_name: str,
        feature_titles: list[str],
    ):
        """Update the list of in-progress features."""
        session = self.get_session(project_name)
        session.features_in_progress = feature_titles
        self._save()

    def update_ready_to_ship(
        self,
        project_name: str,
        feature_titles: list[str],
    ):
        """Update the list of features ready to ship."""
        session = self.get_session(project_name)
        session.features_ready_to_ship = feature_titles
        self._save()

    def update_streak(self, project_name: str, streak: int):
        """Update the current shipping streak."""
        session = self.get_session(project_name)
        session.current_streak = streak
        self._save()

    def generate_welcome_message(self, project_name: str) -> str:
        """Generate a welcome-back message for a project."""
        session = self.get_session(project_name)

        if not session.changes_since and not session.pending_questions:
            return f"Welcome to {project_name}! Ready to build something?"

        parts = [f"Welcome back to {project_name}!"]

        # Time since last visit
        last_seen = datetime.fromisoformat(session.last_seen)
        delta = datetime.now() - last_seen

        if delta.days > 0:
            parts.append(f"\nIt's been {delta.days} day(s) since your last session.")
        elif delta.seconds > 3600:
            hours = delta.seconds // 3600
            parts.append(f"\nIt's been {hours} hour(s) since your last session.")

        # Changes
        if session.changes_since:
            parts.append("\n\nSince then:")
            for change in session.changes_since[-5:]:  # Last 5 changes
                emoji = {
                    "created": "+",
                    "started": "->",
                    "completed": "!",
                    "merged": "v",
                    "blocked": "X",
                }.get(change.change_type, "-")
                parts.append(f"  {emoji} {change.feature_title}: {change.change_type}")

        # Pending questions
        if session.pending_questions:
            parts.append("\n\nNeeds your input:")
            for q in session.pending_questions:
                parts.append(f"  ? {q.feature_title}: {q.question}")

        # Current state
        if session.features_ready_to_ship:
            parts.append(f"\n\nReady to ship: {len(session.features_ready_to_ship)} feature(s)")

        if session.features_in_progress:
            parts.append(f"In progress: {len(session.features_in_progress)} feature(s)")

        if session.current_streak > 0:
            parts.append(f"\nStreak: {session.current_streak} days!")

        return "\n".join(parts)


def test_memory():
    """Quick test of session memory."""
    import tempfile

    with tempfile.TemporaryDirectory() as tmpdir:
        memory = SessionMemory(Path(tmpdir))

        # Record some activity
        memory.record_change("TestApp", "dark-mode", "Dark Mode", "created")
        memory.record_change("TestApp", "dark-mode", "Dark Mode", "started")
        memory.add_pending_question(
            "TestApp",
            "dark-mode",
            "Dark Mode",
            "Should dark mode follow system setting by default?",
        )
        memory.update_streak("TestApp", 5)

        # Simulate returning
        welcome = memory.generate_welcome_message("TestApp")
        print(welcome)


if __name__ == "__main__":
    test_memory()
