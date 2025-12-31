"""
Forge Agents - AI-powered development automation.

This package contains specialized agents that power the autonomous
development pipeline:

- BrainstormAgent: Chat-to-spec conversations via Claude CLI
- SpecEvaluator: Quality gate for specs (is it excellent?)
- AutoExecutor: Spawns Claude Code sessions for implementation
- GitOverlord: Manages all git operations invisibly
- Orchestrator: Coordinates the full pipeline
"""

from .brainstorm import BrainstormAgent
from .spec_evaluator import SpecEvaluator, evaluate_spec
from .executor import AutoExecutor, ParallelExecutionManager
from .git_overlord import GitOverlord, OverlordService
from .prompts import (
    BRAINSTORM_SYSTEM_PROMPT,
    SPEC_EVALUATOR_PROMPT,
    EXECUTOR_SYSTEM_PROMPT,
    GIT_OVERLORD_PROMPT,
)

__all__ = [
    # Agents
    "BrainstormAgent",
    "SpecEvaluator",
    "AutoExecutor",
    "GitOverlord",
    # Managers/Services
    "ParallelExecutionManager",
    "OverlordService",
    # Functions
    "evaluate_spec",
    # Prompts
    "BRAINSTORM_SYSTEM_PROMPT",
    "SPEC_EVALUATOR_PROMPT",
    "EXECUTOR_SYSTEM_PROMPT",
    "GIT_OVERLORD_PROMPT",
]
