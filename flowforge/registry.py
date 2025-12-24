"""Feature registry for FlowForge."""

from dataclasses import dataclass, field, asdict
from datetime import datetime
from enum import Enum
from pathlib import Path
from typing import Optional
import json
import re


class FeatureStatus(str, Enum):
    """Status of a feature in the development lifecycle."""

    PLANNED = "planned"
    IN_PROGRESS = "in-progress"
    REVIEW = "review"
    COMPLETED = "completed"
    BLOCKED = "blocked"


class Complexity(str, Enum):
    """Estimated complexity/size of a feature."""

    SMALL = "small"      # 1-2 files, < 1 hour
    MEDIUM = "medium"    # 3-5 files, few hours
    LARGE = "large"      # 6+ files, multi-day
    EPIC = "epic"        # Multiple features, multi-week


@dataclass
class Feature:
    """A feature or sub-feature in the development roadmap."""

    id: str
    title: str
    description: str = ""
    status: FeatureStatus = FeatureStatus.PLANNED
    priority: int = 5  # 1 = highest, 10 = lowest
    complexity: Complexity = Complexity.MEDIUM

    # Hierarchy
    parent_id: Optional[str] = None
    children: list[str] = field(default_factory=list)

    # Dependencies
    depends_on: list[str] = field(default_factory=list)
    blocked_by: list[str] = field(default_factory=list)

    # Git integration
    branch: Optional[str] = None
    worktree_path: Optional[str] = None

    # Timestamps
    created_at: str = field(default_factory=lambda: datetime.now().isoformat())
    updated_at: str = field(default_factory=lambda: datetime.now().isoformat())

    # Documentation
    spec_path: Optional[str] = None
    prompt_path: Optional[str] = None
    notes: Optional[str] = None

    # Metadata
    tags: list[str] = field(default_factory=list)
    session_id: Optional[str] = None  # Claude Code session for continuity
    extensions: dict = field(default_factory=dict)

    def to_dict(self) -> dict:
        """Convert to dictionary for JSON serialization."""
        data = asdict(self)
        data["status"] = self.status.value
        data["complexity"] = self.complexity.value
        return data

    @classmethod
    def from_dict(cls, data: dict) -> "Feature":
        """Create Feature from dictionary."""
        data = data.copy()
        data["status"] = FeatureStatus(data.get("status", "planned"))
        data["complexity"] = Complexity(data.get("complexity", "medium"))
        return cls(**data)


@dataclass
class MergeQueueItem:
    """An item in the merge queue."""

    feature_id: str
    queued_at: str = field(default_factory=lambda: datetime.now().isoformat())
    status: str = "pending"  # pending, validating, ready, conflict, merged
    validation_status: Optional[str] = None
    conflict_files: list[str] = field(default_factory=list)


class FeatureRegistry:
    """
    Manages the feature registry for a project.

    Stores features in .flowforge/registry.json with full CRUD operations,
    hierarchical relationships, and dependency tracking.
    """

    def __init__(self, project_root: Path):
        self.project_root = project_root
        self.registry_path = project_root / ".flowforge" / "registry.json"
        self._features: dict[str, Feature] = {}
        self._merge_queue: list[MergeQueueItem] = []

    @classmethod
    def load(cls, project_root: Path) -> "FeatureRegistry":
        """Load registry from disk."""
        registry = cls(project_root)

        if registry.registry_path.exists():
            with open(registry.registry_path) as f:
                data = json.load(f)

            for fid, fdata in data.get("features", {}).items():
                registry._features[fid] = Feature.from_dict(fdata)

            for item in data.get("merge_queue", []):
                registry._merge_queue.append(MergeQueueItem(**item))

        return registry

    @classmethod
    def create_new(cls, project_root: Path) -> "FeatureRegistry":
        """Create a new empty registry."""
        registry = cls(project_root)
        registry.save()
        return registry

    def save(self) -> None:
        """Save registry to disk."""
        self.registry_path.parent.mkdir(parents=True, exist_ok=True)

        data = {
            "version": "1.0.0",
            "features": {fid: f.to_dict() for fid, f in self._features.items()},
            "merge_queue": [asdict(item) for item in self._merge_queue],
        }

        with open(self.registry_path, "w") as f:
            json.dump(data, f, indent=2)

    # CRUD Operations

    def add_feature(self, feature: Feature) -> Feature:
        """Add a new feature to the registry."""
        if feature.id in self._features:
            raise ValueError(f"Feature already exists: {feature.id}")

        self._features[feature.id] = feature

        # Update parent's children list if this is a sub-feature
        if feature.parent_id and feature.parent_id in self._features:
            parent = self._features[feature.parent_id]
            if feature.id not in parent.children:
                parent.children.append(feature.id)
                parent.updated_at = datetime.now().isoformat()

        self.save()
        return feature

    def get_feature(self, feature_id: str) -> Optional[Feature]:
        """Get a feature by ID."""
        return self._features.get(feature_id)

    def update_feature(self, feature_id: str, **updates) -> Feature:
        """Update a feature's attributes."""
        if feature_id not in self._features:
            raise ValueError(f"Feature not found: {feature_id}")

        feature = self._features[feature_id]

        for key, value in updates.items():
            if hasattr(feature, key):
                if key == "status" and isinstance(value, str):
                    value = FeatureStatus(value)
                elif key == "complexity" and isinstance(value, str):
                    value = Complexity(value)
                setattr(feature, key, value)

        feature.updated_at = datetime.now().isoformat()
        self.save()
        return feature

    def remove_feature(self, feature_id: str, force: bool = False) -> None:
        """
        Remove a feature from the registry.

        Safety: Requires force=True if feature has children or is in-progress.
        """
        if feature_id not in self._features:
            return

        feature = self._features[feature_id]

        if not force:
            if feature.children:
                raise ValueError(
                    f"Feature has children: {feature.children}. Use force=True to remove."
                )
            if feature.status == FeatureStatus.IN_PROGRESS:
                raise ValueError(
                    "Feature is in-progress. Use force=True to remove."
                )

        # Remove from parent's children list
        if feature.parent_id and feature.parent_id in self._features:
            parent = self._features[feature.parent_id]
            if feature_id in parent.children:
                parent.children.remove(feature_id)

        del self._features[feature_id]
        self.save()

    def list_features(
        self,
        status: Optional[FeatureStatus] = None,
        parent_id: Optional[str] = None,
        tags: Optional[list[str]] = None,
    ) -> list[Feature]:
        """List features with optional filtering."""
        features = list(self._features.values())

        if status:
            features = [f for f in features if f.status == status]

        if parent_id is not None:
            features = [f for f in features if f.parent_id == parent_id]

        if tags:
            features = [f for f in features if any(t in f.tags for t in tags)]

        return sorted(features, key=lambda f: (f.priority, f.created_at))

    def get_root_features(self) -> list[Feature]:
        """Get top-level features (no parent)."""
        return self.list_features(parent_id=None)

    def get_children(self, feature_id: str) -> list[Feature]:
        """Get children of a feature."""
        return self.list_features(parent_id=feature_id)

    # Dependency operations

    def get_ready_features(self) -> list[Feature]:
        """
        Get features that are ready to start (planned, no unmet dependencies).
        """
        ready = []
        for feature in self.list_features(status=FeatureStatus.PLANNED):
            deps_met = all(
                self._features.get(dep, Feature(id="", title="")).status == FeatureStatus.COMPLETED
                for dep in feature.depends_on
            )
            if deps_met and not feature.blocked_by:
                ready.append(feature)
        return ready

    def get_merge_candidates(self) -> list[Feature]:
        """Get features in review status ready for merge."""
        return self.list_features(status=FeatureStatus.REVIEW)

    # ID generation

    @staticmethod
    def generate_id(title: str) -> str:
        """Generate a URL-safe ID from a title."""
        # Lowercase, replace spaces with hyphens, remove special chars
        id_str = title.lower()
        id_str = re.sub(r"[^\w\s-]", "", id_str)
        id_str = re.sub(r"[\s_]+", "-", id_str)
        id_str = re.sub(r"-+", "-", id_str)
        return id_str.strip("-")[:50]  # Max 50 chars

    # Statistics

    def get_stats(self) -> dict:
        """Get summary statistics."""
        by_status = {}
        for status in FeatureStatus:
            by_status[status.value] = len(self.list_features(status=status))

        return {
            "total": len(self._features),
            "by_status": by_status,
            "active_worktrees": len([
                f for f in self._features.values() if f.worktree_path
            ]),
            "ready_to_start": len(self.get_ready_features()),
            "ready_to_merge": len(self.get_merge_candidates()),
        }
