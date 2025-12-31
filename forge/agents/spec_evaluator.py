"""
SpecEvaluator - Quality gate for feature specs.

This agent evaluates whether a spec is "excellent" - ready for an AI
to implement without further clarification. It uses Claude to score
specs on multiple dimensions.
"""

import asyncio
import json
import subprocess
from dataclasses import dataclass
from typing import Optional

from .prompts import SPEC_EVALUATOR_PROMPT


@dataclass
class EvaluationScores:
    """Individual scores for a spec evaluation."""
    clarity: int
    scope: int
    testability: int
    feasibility: int
    completeness: int

    @property
    def average(self) -> float:
        scores = [self.clarity, self.scope, self.testability, self.feasibility, self.completeness]
        return sum(scores) / len(scores)

    @property
    def is_excellent(self) -> bool:
        return self.average >= 8.0

    def to_dict(self) -> dict:
        return {
            "clarity": self.clarity,
            "scope": self.scope,
            "testability": self.testability,
            "feasibility": self.feasibility,
            "completeness": self.completeness,
            "average": round(self.average, 1),
            "is_excellent": self.is_excellent,
        }


@dataclass
class EvaluationResult:
    """Complete evaluation result for a spec."""
    scores: EvaluationScores
    is_excellent: bool
    feedback: str
    suggested_questions: list[str]

    def to_dict(self) -> dict:
        return {
            "scores": self.scores.to_dict(),
            "is_excellent": self.is_excellent,
            "feedback": self.feedback,
            "suggested_questions": self.suggested_questions,
        }


class SpecEvaluator:
    """
    Evaluates feature specs for quality.

    Uses Claude to score specs on:
    - Clarity: Is it unambiguous?
    - Scope: Are boundaries clear?
    - Testability: Can success be verified?
    - Feasibility: Can it ship in one session?
    - Completeness: Are edge cases covered?

    A spec is "excellent" if average score >= 8.0.
    """

    async def evaluate(self, spec: str) -> EvaluationResult:
        """
        Evaluate a spec and return scoring results.

        Args:
            spec: The feature spec text to evaluate

        Returns:
            EvaluationResult with scores, feedback, and suggested questions
        """
        prompt = f"""{SPEC_EVALUATOR_PROMPT}

---

SPEC TO EVALUATE:

{spec}

---

Respond with the JSON evaluation:"""

        # Run Claude CLI
        result = await self._run_claude(prompt)

        # Parse the response
        return self._parse_evaluation(result)

    async def evaluate_and_refine(
        self,
        spec: str,
        max_iterations: int = 3,
    ) -> tuple[str, EvaluationResult]:
        """
        Evaluate a spec and auto-refine until excellent or max iterations.

        Returns the final spec and evaluation result.
        """
        current_spec = spec
        evaluation = await self.evaluate(current_spec)

        iteration = 0
        while not evaluation.is_excellent and iteration < max_iterations:
            # Generate refinement based on feedback
            refinement_prompt = f"""The following spec was evaluated and needs improvement:

CURRENT SPEC:
{current_spec}

EVALUATION FEEDBACK:
{evaluation.feedback}

SUGGESTED QUESTIONS TO ANSWER:
{chr(10).join(f'- {q}' for q in evaluation.suggested_questions)}

Please rewrite the spec addressing all the feedback. Output ONLY the improved spec, no explanation."""

            refined = await self._run_claude(refinement_prompt)
            current_spec = refined
            evaluation = await self.evaluate(current_spec)
            iteration += 1

        return current_spec, evaluation

    async def _run_claude(self, prompt: str) -> str:
        """Run Claude CLI and return the response."""
        cmd = ["claude", "-p", prompt, "--no-markdown"]

        process = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )

        stdout, stderr = await process.communicate()

        if process.returncode != 0:
            raise RuntimeError(f"Claude CLI failed: {stderr.decode()}")

        return stdout.decode("utf-8").strip()

    def _parse_evaluation(self, response: str) -> EvaluationResult:
        """Parse Claude's JSON response into an EvaluationResult."""
        try:
            # Try to extract JSON from response
            json_start = response.find("{")
            json_end = response.rfind("}") + 1

            if json_start == -1 or json_end == 0:
                raise ValueError("No JSON found in response")

            json_str = response[json_start:json_end]
            data = json.loads(json_str)

            scores = EvaluationScores(
                clarity=data.get("scores", {}).get("clarity", 5),
                scope=data.get("scores", {}).get("scope", 5),
                testability=data.get("scores", {}).get("testability", 5),
                feasibility=data.get("scores", {}).get("feasibility", 5),
                completeness=data.get("scores", {}).get("completeness", 5),
            )

            return EvaluationResult(
                scores=scores,
                is_excellent=scores.is_excellent,
                feedback=data.get("feedback", ""),
                suggested_questions=data.get("suggested_questions", []),
            )

        except (json.JSONDecodeError, ValueError) as e:
            # Return default/failing evaluation if parsing fails
            return EvaluationResult(
                scores=EvaluationScores(
                    clarity=5,
                    scope=5,
                    testability=5,
                    feasibility=5,
                    completeness=5,
                ),
                is_excellent=False,
                feedback=f"Could not parse evaluation: {str(e)}",
                suggested_questions=["Please review the spec manually"],
            )


# Quick evaluation function for use in server
async def evaluate_spec(spec: str) -> dict:
    """Convenience function to evaluate a spec and return dict result."""
    evaluator = SpecEvaluator()
    result = await evaluator.evaluate(spec)
    return result.to_dict()


async def test_evaluator():
    """Quick test of the spec evaluator."""
    test_spec = """
FEATURE: Dark Mode Toggle

WHAT IT DOES:
Adds a toggle in settings that switches the app between light and dark themes.

HOW IT WORKS:
- Toggle in Settings > Appearance
- Saves preference to UserDefaults
- Immediately applies theme without restart
- Respects system setting by default, can override

COMPLEXITY:
Small
"""

    evaluator = SpecEvaluator()
    result = await evaluator.evaluate(test_spec)

    print("Evaluation Result:")
    print(json.dumps(result.to_dict(), indent=2))
    print(f"\nIs Excellent: {result.is_excellent}")


if __name__ == "__main__":
    asyncio.run(test_evaluator())
