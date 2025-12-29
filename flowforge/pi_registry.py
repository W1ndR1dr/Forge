"""
Pi-Local Registry Storage for FlowForge.

This module manages registry files locally on the Raspberry Pi at:
    /var/flowforge/registries/{project}/registry.json

This enables offline operation - viewing and adding features works even when
the MacBook is asleep. Git operations (start, merge) still require Mac.
"""

from pathlib import Path
from typing import Optional
import json
import os

from .registry import FeatureRegistry, Feature, ShippingStats, MergeQueueItem
from .config import FlowForgeConfig, ProjectConfig


def get_registry_base_path() -> Path:
    """Get the base path for Pi-local registries from environment."""
    return Path(os.environ.get(
        "FLOWFORGE_REGISTRY_PATH",
        "/var/flowforge/registries"
    ))


class PiRegistryManager:
    """
    Manages Pi-local registry storage.

    Stores registries at {base_path}/{project}/registry.json matching
    the Mac's .flowforge/registry.json format exactly.
    """

    def __init__(self, base_path: Optional[Path] = None):
        """
        Initialize the Pi registry manager.

        Args:
            base_path: Base directory for registries. Defaults to
                       FLOWFORGE_REGISTRY_PATH or /var/flowforge/registries
        """
        self.base_path = base_path or get_registry_base_path()

    def _project_dir(self, project_name: str) -> Path:
        """Get the directory for a project's registry."""
        return self.base_path / project_name

    def _registry_path(self, project_name: str) -> Path:
        """Get the registry.json path for a project."""
        return self._project_dir(project_name) / "registry.json"

    def _config_path(self, project_name: str) -> Path:
        """Get the config.json path for a project."""
        return self._project_dir(project_name) / "config.json"

    def registry_exists(self, project_name: str) -> bool:
        """Check if a project's registry exists locally."""
        return self._registry_path(project_name).exists()

    def list_projects(self) -> list[dict]:
        """
        List all projects with local registries.

        Returns:
            List of {name, path, last_modified} dicts
        """
        projects = []

        if not self.base_path.exists():
            return projects

        for project_dir in self.base_path.iterdir():
            if not project_dir.is_dir():
                continue

            registry_path = project_dir / "registry.json"
            if not registry_path.exists():
                continue

            # Get Mac path from config if available
            config_path = project_dir / "config.json"
            mac_path = None
            if config_path.exists():
                try:
                    with open(config_path) as f:
                        config_data = json.load(f)
                        mac_path = config_data.get("mac_path")
                except Exception:
                    pass

            projects.append({
                "name": project_dir.name,
                "path": mac_path or f"/Users/Brian/Projects/Active/{project_dir.name}",
                "last_modified": registry_path.stat().st_mtime,
            })

        return sorted(projects, key=lambda p: p["name"])

    def get_registry(self, project_name: str) -> FeatureRegistry:
        """
        Load a project's registry from Pi-local storage.

        Args:
            project_name: Name of the project

        Returns:
            FeatureRegistry populated with local data

        Raises:
            FileNotFoundError: If registry doesn't exist locally
        """
        registry_path = self._registry_path(project_name)

        if not registry_path.exists():
            raise FileNotFoundError(f"Registry not found for: {project_name}")

        # Create a FeatureRegistry with a dummy path (we'll override save behavior)
        # Use the actual Mac path from config if available
        mac_path = self._get_mac_path(project_name)
        registry = FeatureRegistry(Path(mac_path))

        # Override the registry path to point to our local file
        registry.registry_path = registry_path

        # Load the data
        with open(registry_path) as f:
            data = json.load(f)

        for fid, fdata in data.get("features", {}).items():
            registry._features[fid] = Feature.from_dict(fdata)

        for item in data.get("merge_queue", []):
            registry._merge_queue.append(MergeQueueItem(**item))

        if "shipping_stats" in data:
            registry._shipping_stats = ShippingStats.from_dict(data["shipping_stats"])

        return registry

    def save_registry(self, project_name: str, registry: FeatureRegistry) -> None:
        """
        Save a registry to Pi-local storage.

        Args:
            project_name: Name of the project
            registry: FeatureRegistry to save
        """
        project_dir = self._project_dir(project_name)
        project_dir.mkdir(parents=True, exist_ok=True)

        registry_path = self._registry_path(project_name)

        # Use the same format as FeatureRegistry.save()
        from dataclasses import asdict
        data = {
            "version": "1.0.0",
            "features": {fid: f.to_dict() for fid, f in registry._features.items()},
            "merge_queue": [asdict(item) for item in registry._merge_queue],
            "shipping_stats": registry._shipping_stats.to_dict(),
        }

        with open(registry_path, "w") as f:
            json.dump(data, f, indent=2)

    def get_config(self, project_name: str) -> Optional[FlowForgeConfig]:
        """
        Load a project's config from Pi-local storage.

        Args:
            project_name: Name of the project

        Returns:
            FlowForgeConfig or None if not found
        """
        config_path = self._config_path(project_name)

        if not config_path.exists():
            return None

        with open(config_path) as f:
            data = json.load(f)

        project_data = data.get("project", {})
        # Filter to only known fields (handles schema migrations gracefully)
        from dataclasses import fields
        known_fields = {f.name for f in fields(ProjectConfig)}
        filtered_project_data = {k: v for k, v in project_data.items() if k in known_fields}
        project_config = ProjectConfig(**filtered_project_data)

        return FlowForgeConfig(
            project=project_config,
            version=data.get("version", "1.0.0"),
        )

    def save_config(self, project_name: str, config: FlowForgeConfig, mac_path: str) -> None:
        """
        Save a project's config to Pi-local storage.

        Args:
            project_name: Name of the project
            config: FlowForgeConfig to save
            mac_path: Path to the project on Mac (for reference)
        """
        project_dir = self._project_dir(project_name)
        project_dir.mkdir(parents=True, exist_ok=True)

        config_path = self._config_path(project_name)

        from dataclasses import asdict
        data = {
            "version": config.version,
            "project": asdict(config.project),
            "mac_path": mac_path,
        }

        with open(config_path, "w") as f:
            json.dump(data, f, indent=2)

    def _get_mac_path(self, project_name: str) -> str:
        """Get the Mac path for a project from stored config."""
        config_path = self._config_path(project_name)

        if config_path.exists():
            try:
                with open(config_path) as f:
                    data = json.load(f)
                    if "mac_path" in data:
                        return data["mac_path"]
            except Exception:
                pass

        # Default to standard path structure
        return f"/Users/Brian/Projects/Active/{project_name}"

    def import_from_mac(
        self,
        project_name: str,
        registry_json: str,
        config_json: Optional[str] = None,
        mac_path: Optional[str] = None,
    ) -> None:
        """
        Import a registry from Mac (used during migration).

        Args:
            project_name: Name of the project
            registry_json: Raw JSON content of registry.json from Mac
            config_json: Optional raw JSON content of config.json from Mac
            mac_path: Path to the project on Mac
        """
        project_dir = self._project_dir(project_name)
        project_dir.mkdir(parents=True, exist_ok=True)

        # Write registry
        registry_path = self._registry_path(project_name)
        with open(registry_path, "w") as f:
            f.write(registry_json)

        # Write config if provided, adding mac_path
        if config_json:
            config_data = json.loads(config_json)
            config_data["mac_path"] = mac_path or f"/Users/Brian/Projects/Active/{project_name}"

            config_path = self._config_path(project_name)
            with open(config_path, "w") as f:
                json.dump(config_data, f, indent=2)

    def delete_project(self, project_name: str) -> bool:
        """
        Delete a project's local registry.

        Args:
            project_name: Name of the project

        Returns:
            True if deleted, False if didn't exist
        """
        project_dir = self._project_dir(project_name)

        if not project_dir.exists():
            return False

        import shutil
        shutil.rmtree(project_dir)
        return True


# Global instance (lazy initialization)
_pi_registry_manager: Optional[PiRegistryManager] = None


def get_pi_registry_manager() -> PiRegistryManager:
    """Get or create the global Pi registry manager instance."""
    global _pi_registry_manager
    if _pi_registry_manager is None:
        _pi_registry_manager = PiRegistryManager()
    return _pi_registry_manager
