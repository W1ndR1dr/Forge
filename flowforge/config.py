"""Configuration management for FlowForge."""

from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional
import json


@dataclass
class ProjectConfig:
    """Project-specific FlowForge configuration."""

    name: str
    main_branch: str = "main"
    claude_md_path: str = "CLAUDE.md"
    build_command: Optional[str] = None
    test_command: Optional[str] = None
    worktree_base: str = ".flowforge-worktrees"
    default_persona: Optional[str] = None

    # Claude Code integration
    claude_command: str = "claude"
    claude_flags: list[str] = field(default_factory=lambda: ["--dangerously-skip-permissions"])


@dataclass
class FlowForgeConfig:
    """Global FlowForge configuration."""

    project: ProjectConfig
    version: str = "1.0.0"

    @classmethod
    def load(cls, project_root: Path) -> "FlowForgeConfig":
        """Load config from .flowforge/config.json."""
        config_path = project_root / ".flowforge" / "config.json"

        if not config_path.exists():
            raise FileNotFoundError(
                f"FlowForge not initialized. Run 'forge init' first.\n"
                f"Expected config at: {config_path}"
            )

        with open(config_path) as f:
            data = json.load(f)

        project_data = data.get("project", {})
        project = ProjectConfig(**project_data)

        return cls(
            project=project,
            version=data.get("version", "1.0.0")
        )

    def save(self, project_root: Path) -> None:
        """Save config to .flowforge/config.json."""
        config_path = project_root / ".flowforge" / "config.json"
        config_path.parent.mkdir(parents=True, exist_ok=True)

        data = {
            "version": self.version,
            "project": {
                "name": self.project.name,
                "main_branch": self.project.main_branch,
                "claude_md_path": self.project.claude_md_path,
                "build_command": self.project.build_command,
                "test_command": self.project.test_command,
                "worktree_base": self.project.worktree_base,
                "default_persona": self.project.default_persona,
                "claude_command": self.project.claude_command,
                "claude_flags": self.project.claude_flags,
            }
        }

        with open(config_path, "w") as f:
            json.dump(data, f, indent=2)


def find_project_root(start_path: Optional[Path] = None) -> Path:
    """
    Find the project root by looking for .flowforge directory.

    Walks up the directory tree from start_path (or cwd) until it finds
    a .flowforge directory or reaches the filesystem root.
    """
    current = start_path or Path.cwd()

    while current != current.parent:
        if (current / ".flowforge").exists():
            return current
        current = current.parent

    # If not found, assume cwd is project root (for init)
    return start_path or Path.cwd()


def detect_project_settings(project_root: Path) -> ProjectConfig:
    """
    Auto-detect project settings from existing files.

    Looks for:
    - CLAUDE.md for AI instructions
    - project.yml for XcodeGen (iOS projects)
    - package.json for Node projects
    - pyproject.toml for Python projects
    - .git for repository info
    """
    # Default name from directory
    name = project_root.name

    # Detect CLAUDE.md
    claude_md_path = "CLAUDE.md"
    if not (project_root / "CLAUDE.md").exists():
        # Check common alternatives
        for alt in ["claude.md", "docs/CLAUDE.md", ".claude/CLAUDE.md"]:
            if (project_root / alt).exists():
                claude_md_path = alt
                break

    # Detect build command
    build_command = None
    if (project_root / "project.yml").exists():
        # XcodeGen iOS project
        build_command = "xcodegen generate && xcodebuild -scheme $(basename $(pwd)) build"
    elif (project_root / "package.json").exists():
        build_command = "npm run build"
    elif (project_root / "pyproject.toml").exists():
        build_command = "pip install -e . && python -m pytest"
    elif (project_root / "Makefile").exists():
        build_command = "make"

    # Detect main branch
    main_branch = "main"
    try:
        import subprocess
        result = subprocess.run(
            ["git", "symbolic-ref", "refs/remotes/origin/HEAD"],
            cwd=project_root,
            capture_output=True,
            text=True
        )
        if result.returncode == 0:
            # refs/remotes/origin/main -> main
            main_branch = result.stdout.strip().split("/")[-1]
    except Exception:
        pass

    return ProjectConfig(
        name=name,
        main_branch=main_branch,
        claude_md_path=claude_md_path,
        build_command=build_command,
    )
