"""
Tiered intelligence system for FlowForge.

Instead of hardcoded personas, this module provides dynamic expert suggestion
and deep research orchestration based on feature context.

Tiers:
1. Quick Expert Suggestion - Claude suggests 2-3 relevant domain experts
2. Deep Research Mode - Spin out research threads for complex/novel features
3. Multi-Model Research - Research across Claude/Gemini/ChatGPT for critical decisions
"""

from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional
from datetime import datetime
import subprocess
import json
import webbrowser


@dataclass
class SuggestedExpert:
    """An expert suggested for consultation on a feature."""

    name: str
    title: str
    relevance: str  # Why this expert is relevant to the feature
    perspective: str  # What perspective/approach they'd bring


@dataclass
class ResearchRecommendation:
    """Recommendation for deep research on a feature."""

    should_research: bool
    reasoning: str
    topics: list[str] = field(default_factory=list)
    providers: list[str] = field(default_factory=list)  # claude, gemini, chatgpt
    search_queries: list[str] = field(default_factory=list)
    official_docs: list[str] = field(default_factory=list)  # URLs to official docs


@dataclass
class ResearchSession:
    """A deep research session for a feature."""

    feature_id: str
    created_at: str = field(default_factory=lambda: datetime.now().isoformat())
    topics: list[str] = field(default_factory=list)
    providers_used: list[str] = field(default_factory=list)
    outputs: dict[str, str] = field(default_factory=dict)  # provider -> output
    synthesis: Optional[str] = None
    status: str = "pending"  # pending, in_progress, completed


class IntelligenceEngine:
    """
    Orchestrates intelligent prompt enhancement for FlowForge.

    Uses Claude CLI to dynamically:
    - Suggest relevant domain experts for any feature
    - Determine if deep research is warranted
    - Generate research prompts for multiple providers
    - Synthesize research into implementation context
    """

    def __init__(
        self,
        project_root: Path,
        claude_command: str = "claude",
    ):
        self.project_root = project_root
        self.claude_command = claude_command
        self.research_dir = project_root / ".flowforge" / "research"

    def _call_claude(self, prompt: str, timeout: int = 60) -> str:
        """Call Claude CLI with a prompt and return the response."""
        try:
            result = subprocess.run(
                [self.claude_command, "--print", "-p", prompt],
                capture_output=True,
                text=True,
                timeout=timeout,
                cwd=self.project_root,
            )
            return result.stdout.strip()
        except subprocess.TimeoutExpired:
            return "Error: Claude CLI timed out"
        except FileNotFoundError:
            return "Error: Claude CLI not found"
        except Exception as e:
            return f"Error: {e}"

    def should_invoke_experts(
        self,
        feature_title: str,
        feature_description: str,
        tags: list[str] = None,
    ) -> bool:
        """
        Determine if a feature warrants expert consultation.

        Most features don't need expert perspectives - only invoke for:
        - Novel or complex design challenges
        - UX/interaction design decisions
        - Architecture choices with major trade-offs
        - Domain-specific expertise (health, finance, accessibility)
        """
        tags_str = ", ".join(tags) if tags else "general"

        prompt = f"""Decide if this feature warrants channeling expert perspectives.

Feature: {feature_title}
Description: {feature_description}
Tags: {tags_str}

Expert consultation is valuable for:
- Novel UX patterns or interaction design (Jony Ive, Mike Matas territory)
- Complex architecture with real trade-offs (Patrick Collison, Werner Vogels)
- Domain expertise needs (health: cardiologists, finance: risk experts)
- Design philosophy decisions (Dieter Rams "less but better")

Expert consultation is NOT needed for:
- Routine bug fixes
- Simple CRUD features
- Incremental improvements
- Straightforward UI additions
- Backend plumbing / glue code

Respond with ONLY "yes" or "no".
"""
        response = self._call_claude(prompt, timeout=30).strip().lower()
        return response.startswith("yes")

    def suggest_experts(
        self,
        feature_title: str,
        feature_description: str,
        tags: list[str] = None,
        max_experts: int = 3,
    ) -> list[SuggestedExpert]:
        """
        Suggest relevant domain experts for a feature.

        Uses Claude to identify 2-3 real-world experts whose perspectives
        would be valuable for implementing this specific feature.

        Call should_invoke_experts() first to determine if this is warranted.
        """
        tags_str = ", ".join(tags) if tags else "general"

        prompt = f"""You are helping select domain experts to consult (in spirit) for implementing a software feature.

Feature: {feature_title}
Description: {feature_description}
Tags: {tags_str}

Suggest {max_experts} real-world experts whose perspectives would be most valuable for implementing this feature. Consider:
- Domain expertise directly relevant to the feature
- Technical implementation expertise
- Design/UX expertise if applicable
- Mix of perspectives (not all from same domain)

For each expert, provide:
1. Name (real person, well-known in their field)
2. Title/role (brief)
3. Relevance (1 sentence on why they're relevant to THIS feature)
4. Perspective (1 sentence on what unique viewpoint they'd bring)

Format as JSON array:
[
  {{"name": "...", "title": "...", "relevance": "...", "perspective": "..."}},
  ...
]

Return ONLY the JSON array, no other text."""

        response = self._call_claude(prompt)

        try:
            # Parse JSON response
            data = json.loads(response)
            return [SuggestedExpert(**expert) for expert in data]
        except (json.JSONDecodeError, TypeError, KeyError):
            # Fallback: return empty list if parsing fails
            return []

    def analyze_research_need(
        self,
        feature_title: str,
        feature_description: str,
        tags: list[str] = None,
    ) -> ResearchRecommendation:
        """
        Analyze whether a feature warrants deep research.

        Uses Claude to determine if this feature is complex/novel enough
        to benefit from dedicated research threads.
        """
        tags_str = ", ".join(tags) if tags else "general"

        prompt = f"""Analyze whether this software feature warrants deep research before implementation.

Feature: {feature_title}
Description: {feature_description}
Tags: {tags_str}

Deep research is warranted when:
- Feature involves complex AI/ML architecture decisions
- Significant prior art exists (memory systems, RAG, specific algorithms)
- Official documentation from major providers (Anthropic, OpenAI, Apple, Google) would be valuable
- Academic literature or industry best practices would inform implementation
- Feature is novel enough that exploration would prevent costly mistakes

Analyze this feature and respond with JSON:
{{
  "should_research": true/false,
  "reasoning": "1-2 sentences explaining your decision",
  "topics": ["topic1", "topic2"],  // if research recommended
  "providers": ["claude", "gemini", "chatgpt"],  // which AI providers to research with
  "search_queries": ["query1", "query2"],  // web search queries
  "official_docs": ["url1", "url2"]  // specific documentation URLs if known
}}

Return ONLY the JSON, no other text."""

        response = self._call_claude(prompt)

        try:
            data = json.loads(response)
            return ResearchRecommendation(**data)
        except (json.JSONDecodeError, TypeError, KeyError):
            return ResearchRecommendation(
                should_research=False,
                reasoning="Could not analyze feature (parsing error)",
            )

    def generate_research_prompts(
        self,
        feature_title: str,
        feature_description: str,
        topics: list[str],
        providers: list[str] = None,
    ) -> dict[str, str]:
        """
        Generate tailored research prompts for each provider.

        Different providers have different strengths:
        - Claude: Nuanced analysis, Anthropic-specific docs
        - Gemini: Technical depth, Google ecosystem
        - ChatGPT: Broad coverage, code examples
        """
        providers = providers or ["claude"]
        prompts = {}

        base_context = f"""I'm implementing a feature: {feature_title}

Description: {feature_description}

Research topics: {', '.join(topics)}
"""

        if "claude" in providers:
            prompts["claude"] = f"""{base_context}

Please provide comprehensive research on implementing this feature, focusing on:
1. Anthropic's documented approaches and philosophy (if relevant)
2. Best practices and design patterns
3. Potential pitfalls and how to avoid them
4. Architecture recommendations
5. Relevant code patterns or pseudocode

Be thorough - this research will inform the actual implementation."""

        if "gemini" in providers:
            prompts["gemini"] = f"""{base_context}

Please research this feature with focus on:
1. Technical implementation details and algorithms
2. Google/Android/Firebase approaches (if relevant)
3. Performance considerations
4. Scalability patterns
5. Code examples in Python or Swift

Provide comprehensive, implementation-ready guidance."""

        if "chatgpt" in providers:
            prompts["chatgpt"] = f"""{base_context}

Please provide research on implementing this feature:
1. Common implementation patterns
2. OpenAI's approaches (if relevant to AI features)
3. Popular libraries and frameworks
4. Community best practices
5. Working code examples

Focus on practical, copy-paste-ready guidance."""

        if "openevidence" in providers:
            prompts["openevidence"] = f"""{base_context}

I'm implementing a health/fitness feature in my app and need evidence-based guidance.

Please research:
1. Peer-reviewed literature on the relevant physiological concepts
2. Clinical validation studies for similar approaches
3. Medical/health guidelines from authoritative sources (WHO, AHA, ACSM, etc.)
4. Safety considerations and contraindications
5. Evidence quality assessment (strength of recommendations)

Focus on peer-reviewed, clinically validated information I can cite."""

        if "perplexity" in providers:
            prompts["perplexity"] = f"""{base_context}

Please search for:
1. Recent articles and documentation on this topic
2. GitHub repos with similar implementations
3. Stack Overflow discussions and solutions
4. Blog posts from practitioners
5. Current best practices and gotchas

Include links to your sources."""

        return prompts

    def open_research_sessions(
        self,
        feature_id: str,
        prompts: dict[str, str],
    ) -> ResearchSession:
        """
        Open browser tabs with research prompts for each provider.

        This allows the user to conduct research manually and paste
        results back into FlowForge for synthesis.
        """
        session = ResearchSession(
            feature_id=feature_id,
            providers_used=list(prompts.keys()),
        )

        # Provider URLs
        provider_urls = {
            "claude": "https://claude.ai/new",
            "gemini": "https://gemini.google.com/app",
            "chatgpt": "https://chat.openai.com/",
        }

        for provider, prompt in prompts.items():
            if provider in provider_urls:
                # URL-encode the prompt for potential query param use
                # (Most chat UIs don't support pre-filled prompts via URL,
                # so we'll copy to clipboard instead)
                url = provider_urls[provider]
                webbrowser.open(url)

        # Save session
        self._save_session(session)

        return session

    def _save_session(self, session: ResearchSession) -> None:
        """Save a research session to disk."""
        session_dir = self.research_dir / session.feature_id
        session_dir.mkdir(parents=True, exist_ok=True)

        session_file = session_dir / "session.json"
        with open(session_file, "w") as f:
            json.dump({
                "feature_id": session.feature_id,
                "created_at": session.created_at,
                "topics": session.topics,
                "providers_used": session.providers_used,
                "outputs": session.outputs,
                "synthesis": session.synthesis,
                "status": session.status,
            }, f, indent=2)

    def load_session(self, feature_id: str) -> Optional[ResearchSession]:
        """Load a research session from disk."""
        session_file = self.research_dir / feature_id / "session.json"

        if not session_file.exists():
            return None

        with open(session_file) as f:
            data = json.load(f)

        return ResearchSession(**data)

    def save_research_output(
        self,
        feature_id: str,
        provider: str,
        output: str,
    ) -> None:
        """Save research output from a provider."""
        session = self.load_session(feature_id)
        if not session:
            session = ResearchSession(feature_id=feature_id)

        session.outputs[provider] = output
        session.status = "in_progress"

        # Also save as individual file for easy reading
        output_file = self.research_dir / feature_id / f"{provider}_output.md"
        output_file.parent.mkdir(parents=True, exist_ok=True)
        output_file.write_text(f"# {provider.title()} Research Output\n\n{output}")

        self._save_session(session)

    def synthesize_research(self, feature_id: str) -> str:
        """
        Synthesize research outputs into unified implementation context.

        Uses Claude to combine research from multiple providers into
        a coherent set of recommendations and context.
        """
        session = self.load_session(feature_id)
        if not session or not session.outputs:
            return "No research outputs to synthesize."

        outputs_text = "\n\n---\n\n".join([
            f"## {provider.title()} Research\n\n{output}"
            for provider, output in session.outputs.items()
        ])

        prompt = f"""Synthesize the following research outputs into a unified implementation guide.

{outputs_text}

---

Create a synthesis that:
1. Identifies consensus recommendations across sources
2. Notes important differences in approach
3. Provides a clear recommended architecture/approach
4. Lists key implementation considerations
5. Highlights potential pitfalls to avoid

Format as a clear, actionable implementation guide."""

        synthesis = self._call_claude(prompt, timeout=120)

        # Save synthesis
        session.synthesis = synthesis
        session.status = "completed"
        self._save_session(session)

        # Also save as file
        synthesis_file = self.research_dir / feature_id / "synthesis.md"
        synthesis_file.write_text(f"# Research Synthesis\n\n{synthesis}")

        return synthesis

    def generate_expert_preamble(
        self,
        experts: list[SuggestedExpert],
    ) -> str:
        """
        Generate a prompt preamble that invokes the perspectives of selected experts.

        Uses strong invocation language to channel expert perspectives,
        not just "consider" them passively.
        """
        if not experts:
            return ""

        expert_descriptions = "\n".join([
            f"- **{e.name}** ({e.title}): {e.perspective}"
            for e in experts
        ])

        return f"""## Channel These Experts

As you implement this feature, embody the perspectives of:

{expert_descriptions}

Think as they would think. What would {experts[0].name} obsess over? What would they refuse to compromise on? Let their standards guide your decisions.
"""
