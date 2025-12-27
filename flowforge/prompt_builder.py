"""
Prompt builder for FlowForge.

Generates rich, context-aware prompts for Claude Code implementation sessions
by combining project context, feature specifications, and expert perspectives.
"""

from dataclasses import dataclass
from pathlib import Path
from typing import Optional
import re

from .registry import Feature, FeatureRegistry
from .intelligence import IntelligenceEngine, SuggestedExpert


@dataclass
class PromptContext:
    """Context gathered for prompt generation."""

    project_name: str
    claude_md_content: str
    feature: Feature
    spec_content: Optional[str] = None
    research_synthesis: Optional[str] = None
    expert_preamble: Optional[str] = None
    dependency_context: Optional[str] = None
    worktree_path: Optional[Path] = None
    project_context: Optional[str] = None  # From project-context.md


class PromptBuilder:
    """
    Builds implementation prompts for Claude Code.

    Combines:
    - Project CLAUDE.md for coding conventions
    - Feature specification
    - Expert perspectives (dynamically generated)
    - Research synthesis (if deep research was conducted)
    - Dependency context
    """

    def __init__(
        self,
        project_root: Path,
        registry: FeatureRegistry,
        intelligence: IntelligenceEngine,
    ):
        self.project_root = project_root
        self.registry = registry
        self.intelligence = intelligence

    def _read_claude_md(self, claude_md_path: str) -> str:
        """Read and extract relevant sections from CLAUDE.md."""
        full_path = self.project_root / claude_md_path

        if not full_path.exists():
            return "# No CLAUDE.md found\n\nFollow standard coding conventions."

        content = full_path.read_text()

        # Extract the most relevant sections for implementation
        # Keep: Overview, Architecture, Coding Style, Key Files, Common Patterns
        # Trim: Long data dumps, debugging endpoints, environment variables

        sections_to_keep = [
            r"## Project Overview.*?(?=##|\Z)",
            r"## Design Philosophy.*?(?=##|\Z)",
            r"## Architecture.*?(?=##|\Z)",
            r"## Coding Style.*?(?=##|\Z)",
            r"## Key Files.*?(?=##|\Z)",
            r"## Common Patterns.*?(?=##|\Z)",
            r"## Build Commands.*?(?=##|\Z)",
        ]

        extracted = []
        for pattern in sections_to_keep:
            match = re.search(pattern, content, re.DOTALL | re.IGNORECASE)
            if match:
                extracted.append(match.group(0).strip())

        if extracted:
            return "\n\n".join(extracted)

        # If no sections matched, return trimmed version (first 3000 chars)
        if len(content) > 3000:
            return content[:3000] + "\n\n... (truncated for brevity)"

        return content

    def _read_spec(self, spec_path: Optional[str]) -> Optional[str]:
        """Read feature specification file if it exists."""
        if not spec_path:
            return None

        full_path = self.project_root / spec_path

        if not full_path.exists():
            return None

        content = full_path.read_text()

        # Trim if too long
        if len(content) > 5000:
            return content[:5000] + "\n\n... (truncated for brevity)"

        return content

    def _build_dependency_context(self, feature: Feature) -> Optional[str]:
        """Build context about feature dependencies."""
        if not feature.depends_on:
            return None

        dep_info = []
        for dep_id in feature.depends_on:
            dep = self.registry.get_feature(dep_id)
            if dep:
                status = "✅ completed" if dep.status.value == "completed" else f"⚠️ {dep.status.value}"
                dep_info.append(f"- **{dep.title}** ({status}): {dep.description[:100]}")

        if not dep_info:
            return None

        return "## Dependencies\n\nThis feature depends on:\n" + "\n".join(dep_info)

    def _read_project_context(self) -> Optional[str]:
        """Read project context from .flowforge/project-context.md."""
        context_path = self.project_root / ".flowforge" / "project-context.md"
        if not context_path.exists():
            return None
        return context_path.read_text()

    def gather_context(
        self,
        feature_id: str,
        claude_md_path: str = "CLAUDE.md",
        include_experts: bool = True,
        include_research: bool = True,
    ) -> PromptContext:
        """
        Gather all context needed for prompt generation.

        This is separated from build() to allow inspection before generation.
        """
        feature = self.registry.get_feature(feature_id)
        if not feature:
            raise ValueError(f"Feature not found: {feature_id}")

        # Read project context (from enhanced init)
        project_context = self._read_project_context()

        # Read CLAUDE.md
        claude_md_content = self._read_claude_md(claude_md_path)

        # Read feature spec
        spec_content = self._read_spec(feature.spec_path)

        # Load research synthesis if available
        research_synthesis = None
        if include_research:
            session = self.intelligence.load_session(feature_id)
            if session and session.synthesis:
                research_synthesis = session.synthesis

        # Generate expert preamble (or load if already generated)
        expert_preamble = None
        if include_experts and not research_synthesis:
            # Only auto-suggest experts if no deep research was done
            experts = self.intelligence.suggest_experts(
                feature.title,
                feature.description,
                feature.tags,
            )
            if experts:
                expert_preamble = self.intelligence.generate_expert_preamble(experts)

        # Build dependency context
        dependency_context = self._build_dependency_context(feature)

        return PromptContext(
            project_name=self.project_root.name,
            claude_md_content=claude_md_content,
            feature=feature,
            spec_content=spec_content,
            research_synthesis=research_synthesis,
            expert_preamble=expert_preamble,
            dependency_context=dependency_context,
            worktree_path=Path(feature.worktree_path) if feature.worktree_path else None,
            project_context=project_context,
        )

    def build(self, context: PromptContext) -> str:
        """
        Build the final implementation prompt from gathered context.

        Uses the AGI-pilled prompt template with:
        - Expert consultation patterns (Claude decides who)
        - Research guidance (Claude decides when)
        - Vibecoder context
        - Plan mode + ultrathink instructions
        """
        sections = []

        # Header
        sections.append(f"# Implement: {context.feature.title}")
        sections.append("")

        # Workflow context (situational awareness, not prescriptive)
        sections.append("## Workflow Context")
        sections.append("")
        sections.append("You're in a FlowForge-managed worktree for this feature.")
        if context.worktree_path:
            sections.append(f"- **Worktree:** `{context.worktree_path}`")
        sections.append(f"- **Branch:** Isolated from main (changes don't affect main until merge)")
        sections.append("- **When finished:** Human clicks \"Stop\" in FlowForge → build validation → merge")
        sections.append("- **Your focus:** Implement the feature. Human decides when it's done.")
        sections.append("")

        # Feature description
        sections.append("## Feature")
        sections.append(context.feature.description or "(No description provided)")
        sections.append("")

        if context.feature.tags:
            sections.append(f"**Tags:** {', '.join(context.feature.tags)}")
            sections.append("")

        # Research synthesis (highest priority context)
        if context.research_synthesis:
            sections.append("## Research & Design Context")
            sections.append(context.research_synthesis)
            sections.append("")

        # Expert perspectives (if research was done, these were synthesized)
        if context.expert_preamble and not context.research_synthesis:
            sections.append(context.expert_preamble)
            sections.append("")
        elif not context.research_synthesis:
            # Add the expert consultation pattern for Claude to follow
            sections.append("## Expert Consultation")
            sections.append("")
            sections.append("Consider perspectives from domain experts relevant to this feature.")
            sections.append("Identify 2-3 real-world experts whose viewpoints would be valuable.")
            sections.append("Synthesize their approaches in your implementation.")
            sections.append("")

        # Research guidance pattern
        if not context.research_synthesis:
            sections.append("## Research Guidance")
            sections.append("")
            sections.append("If this feature involves novel patterns, complex architecture, or")
            sections.append("unfamiliar APIs, conduct web research before implementing.")
            sections.append("Cite official documentation where applicable.")
            sections.append("")

        # Feature specification
        if context.spec_content:
            sections.append("## Specification")
            sections.append(context.spec_content)
            sections.append("")

        # Dependencies
        if context.dependency_context:
            sections.append(context.dependency_context)
            sections.append("")

        # Project context (from enhanced init)
        if context.project_context:
            sections.append("## Project Vision")
            sections.append(context.project_context)
            sections.append("")

        # CLAUDE.md content
        sections.append("## Project Context")
        sections.append(context.claude_md_content)
        sections.append("")

        # Implementation instructions (AGI-pilled)
        sections.append("## Instructions")
        sections.append("")
        sections.append("You're helping a novice vibecoder who isn't a Git expert.")
        sections.append("All Git operations should be explained and handled safely.")
        sections.append("")
        sections.append("**Engage plan mode and ultrathink before implementing.**")
        sections.append("Present your plan for approval before writing code.")
        sections.append("")
        sections.append("When complete:")
        sections.append("1. Commit your changes with conventional commit format")
        sections.append("2. Ensure any new files follow existing patterns")
        sections.append("3. Test manually on the target device/environment")
        sections.append(f"4. Run `forge stop {context.feature.id}` to mark ready for review")
        sections.append("")
        sections.append("Ask clarifying questions if the specification is unclear before proceeding.")
        sections.append("")

        return "\n".join(sections)

    def build_for_feature(
        self,
        feature_id: str,
        claude_md_path: str = "CLAUDE.md",
        include_experts: bool = True,
        include_research: bool = True,
    ) -> str:
        """
        Convenience method to gather context and build prompt in one call.
        """
        context = self.gather_context(
            feature_id,
            claude_md_path,
            include_experts,
            include_research,
        )
        return self.build(context)

    def save_prompt(self, feature_id: str, prompt: str) -> Path:
        """Save generated prompt to .flowforge/prompts/."""
        prompts_dir = self.project_root / ".flowforge" / "prompts"
        prompts_dir.mkdir(parents=True, exist_ok=True)

        prompt_path = prompts_dir / f"{feature_id}.md"
        prompt_path.write_text(prompt)

        return prompt_path


class QuickPromptBuilder:
    """
    Lightweight prompt builder for simple features.

    Skips expert consultation and research for quick iteration.
    """

    def __init__(self, project_root: Path):
        self.project_root = project_root

    def build(
        self,
        title: str,
        description: str,
        claude_md_path: str = "CLAUDE.md",
    ) -> str:
        """Build a simple prompt without full context gathering."""
        claude_md = self.project_root / claude_md_path
        claude_content = claude_md.read_text() if claude_md.exists() else ""

        return f"""# Implement: {title}

## Workflow Context

You're in a FlowForge-managed worktree for this feature.
- **Branch:** Isolated from main (changes don't affect main until merge)
- **When finished:** Human clicks "Stop" in FlowForge → build validation → merge
- **Your focus:** Implement the feature. Human decides when it's done.

## Feature
{description}

## Project Context
{claude_content[:3000]}

## Instructions
Implement this feature following the project conventions above.
Commit with conventional commit format when complete.
"""
