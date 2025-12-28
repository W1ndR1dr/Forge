"""
BrainstormAgent - Chat-to-spec conversations via Claude CLI.

This agent runs Claude Code CLI to enable real-time brainstorming conversations.
It's designed to run on the Pi and use the user's authenticated Claude Max
subscription (NOT API keys - uses the CLI which routes through Max).

Key CLI flags used:
- `--tools ""` - Chat-only mode, no file/bash access (pure conversation)
- `--output-format text` - Simple text streaming via stdout chunks

The conversation history is rebuilt in each prompt. This is slightly less
efficient than using --resume, but more reliable across reconnections.
"""

import asyncio
import json
import re
from dataclasses import dataclass, field
from typing import AsyncGenerator, Optional


@dataclass
class BrainstormMessage:
    """A message in the brainstorm conversation."""
    role: str  # "user" or "assistant"
    content: str


@dataclass
class SpecResult:
    """A refined spec from brainstorming."""
    title: str
    what_it_does: str
    how_it_works: list[str]
    files_affected: list[str]
    estimated_scope: str
    raw_spec: str

    def to_dict(self) -> dict:
        return {
            "title": self.title,
            "what_it_does": self.what_it_does,
            "how_it_works": self.how_it_works,
            "files_affected": self.files_affected,
            "estimated_scope": self.estimated_scope,
            "raw_spec": self.raw_spec,
        }


@dataclass
class BrainstormSession:
    """A brainstorming session with Claude."""
    project_name: str
    project_context: str
    existing_features: list[str]
    existing_feature_title: Optional[str] = None  # For refining mode
    messages: list[BrainstormMessage] = field(default_factory=list)
    spec_ready: bool = False
    current_spec: Optional[SpecResult] = None

    @property
    def is_refining(self) -> bool:
        """Whether we're refining an existing feature vs brainstorming new ideas."""
        return self.existing_feature_title is not None

    def get_system_prompt(self) -> str:
        """Generate the system prompt for this session."""
        from .prompts import BRAINSTORM_SYSTEM_PROMPT, REFINE_SYSTEM_PROMPT

        features_str = "\n".join(f"- {f}" for f in self.existing_features) if self.existing_features else "(none yet)"

        if self.is_refining:
            return REFINE_SYSTEM_PROMPT.format(
                project_name=self.project_name,
                project_context=self.project_context or "(no project context provided)",
                feature_title=self.existing_feature_title,
                existing_features=features_str,
            )
        else:
            return BRAINSTORM_SYSTEM_PROMPT.format(
                project_name=self.project_name,
                project_context=self.project_context or "(no project context provided)",
                existing_features=features_str,
            )


class BrainstormAgent:
    """
    Agent that facilitates brainstorming conversations via Claude CLI.

    Runs on the Pi, uses the user's Claude Max subscription (not API keys).
    Streams responses back for real-time chat experience.

    Uses --tools "" for pure chat mode (no file access).
    """

    def __init__(
        self,
        project_name: str,
        project_context: str = "",
        existing_features: Optional[list[str]] = None,
        existing_feature_title: Optional[str] = None,
        existing_history: Optional[list[dict]] = None,
    ):
        self.session = BrainstormSession(
            project_name=project_name,
            project_context=project_context,
            existing_features=existing_features or [],
            existing_feature_title=existing_feature_title,
        )

        # Load existing history if provided (for UI display)
        if existing_history:
            for msg in existing_history:
                self.session.messages.append(
                    BrainstormMessage(role=msg["role"], content=msg["content"])
                )

    async def send_message(
        self,
        user_message: str,
    ) -> AsyncGenerator[str, None]:
        """
        Send a message and stream the response.

        Yields chunks of the response as they come in.
        """
        # Add user message to history
        self.session.messages.append(BrainstormMessage(role="user", content=user_message))

        # Run claude CLI with streaming
        async for chunk in self._run_claude_streaming(user_message):
            yield chunk

        # After streaming complete, check if spec is ready
        if self.session.messages and self.session.messages[-1].role == "assistant":
            last_response = self.session.messages[-1].content
            if "SPEC_READY" in last_response:
                self.session.spec_ready = True
                self.session.current_spec = self._parse_spec(last_response)

    async def _run_claude_streaming(self, user_message: str) -> AsyncGenerator[str, None]:
        """
        Run Claude CLI and stream the response.

        Uses:
        - `--tools ""` for chat-only mode (no file access)
        - `--output-format text` for streaming (reads stdout in chunks)
        - `--append-system-prompt` for brainstorm instructions

        Note: We rebuild the conversation in the prompt each time since
        --resume requires session persistence on the Pi, which may not
        be reliable. This trades efficiency for reliability.
        """
        # Build full prompt with conversation history
        full_prompt = self._build_conversation_prompt(user_message)

        cmd = [
            "claude",
            "-p", full_prompt,
            "--tools", "",  # Chat-only, no file access
            "--output-format", "text",
        ]

        process = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )

        full_response = []
        timeout_seconds = 120  # 2 minute timeout for large prompts

        try:
            # Read stdout in chunks for streaming effect
            start_time = asyncio.get_event_loop().time()
            while True:
                try:
                    chunk = await asyncio.wait_for(
                        process.stdout.read(100),
                        timeout=30  # 30 sec timeout per chunk (allows for slow starts)
                    )
                except asyncio.TimeoutError:
                    # Check total time
                    elapsed = asyncio.get_event_loop().time() - start_time
                    if elapsed > timeout_seconds:
                        yield "\n\n[Timeout - Claude is taking too long. Try a shorter prompt.]"
                        process.kill()
                        break
                    continue  # Keep waiting for next chunk

                if not chunk:
                    break

                text = chunk.decode("utf-8", errors="replace")
                full_response.append(text)
                yield text

            # Wait for process to complete
            await asyncio.wait_for(process.wait(), timeout=10)
        except asyncio.TimeoutError:
            yield "\n\n[Process timeout - killing Claude CLI]"
            process.kill()

        # Check stderr for errors
        stderr = await process.stderr.read()
        if stderr and process.returncode != 0:
            error_msg = stderr.decode("utf-8", errors="replace")
            print(f"Claude CLI stderr: {error_msg}")

        # Store the full response
        response_text = "".join(full_response)
        if response_text:
            self.session.messages.append(BrainstormMessage(role="assistant", content=response_text))

    def _build_conversation_prompt(self, new_message: str) -> str:
        """Build prompt with system prompt + conversation history."""
        parts = [self.session.get_system_prompt()]
        parts.append("\n\n---\n\nConversation:\n")

        # Include all messages except the last user message (which is new_message)
        for msg in self.session.messages[:-1]:  # Skip the message we just added
            role_label = "User" if msg.role == "user" else "Assistant"
            parts.append(f"\n{role_label}: {msg.content}\n")

        # Add the new user message
        parts.append(f"\nUser: {new_message}\n")
        parts.append("\nAssistant: ")

        return "".join(parts)

    def _parse_spec(self, response: str) -> Optional[SpecResult]:
        """Parse a SPEC_READY response into a SpecResult."""
        try:
            spec_match = re.search(r"SPEC_READY\s*\n(.*)", response, re.DOTALL)
            if not spec_match:
                return None

            spec_text = spec_match.group(1).strip()

            title = ""
            title_match = re.search(r"FEATURE:\s*(.+?)(?:\n|$)", spec_text)
            if title_match:
                title = title_match.group(1).strip()

            what_it_does = ""
            what_match = re.search(r"WHAT IT DOES:\s*\n(.+?)(?=\n\n|\nHOW IT WORKS:)", spec_text, re.DOTALL)
            if what_match:
                what_it_does = what_match.group(1).strip()

            how_it_works = []
            how_match = re.search(r"HOW IT WORKS:\s*\n(.+?)(?=\n\n|\nFILES|$)", spec_text, re.DOTALL)
            if how_match:
                how_text = how_match.group(1)
                how_it_works = [line.strip().lstrip("- ") for line in how_text.split("\n") if line.strip()]

            files_affected = []
            files_match = re.search(r"FILES LIKELY AFFECTED:\s*\n(.+?)(?=\n\n|\nESTIMATED|$)", spec_text, re.DOTALL)
            if files_match:
                files_text = files_match.group(1)
                files_affected = [line.strip().lstrip("- ") for line in files_text.split("\n") if line.strip()]

            estimated_scope = "Medium"
            scope_match = re.search(r"ESTIMATED SCOPE:\s*(.+?)(?:\n|$)", spec_text)
            if scope_match:
                estimated_scope = scope_match.group(1).strip()

            return SpecResult(
                title=title,
                what_it_does=what_it_does,
                how_it_works=how_it_works,
                files_affected=files_affected,
                estimated_scope=estimated_scope,
                raw_spec=spec_text,
            )
        except Exception:
            return None

    def get_conversation_state(self) -> dict:
        """Get the current state of the conversation."""
        return {
            "project_name": self.session.project_name,
            "message_count": len(self.session.messages),
            "spec_ready": self.session.spec_ready,
            "current_spec": self.session.current_spec.to_dict() if self.session.current_spec else None,
            "messages": [
                {"role": msg.role, "content": msg.content}
                for msg in self.session.messages
            ],
        }

    def is_spec_ready(self) -> bool:
        """Check if a spec is ready from the conversation."""
        return self.session.spec_ready

    def get_spec(self) -> Optional[SpecResult]:
        """Get the refined spec, if ready."""
        return self.session.current_spec


async def test_brainstorm():
    """Quick test of the brainstorm agent."""
    agent = BrainstormAgent(
        project_name="TestApp",
        project_context="A simple todo app",
        existing_features=["Add tasks", "Mark complete"],
    )

    print("Testing brainstorm agent...")
    print("=" * 50)
    async for chunk in agent.send_message("I want to add due dates to tasks"):
        print(chunk, end="", flush=True)
    print("\n" + "=" * 50)
    print(f"Spec ready: {agent.is_spec_ready()}")


if __name__ == "__main__":
    asyncio.run(test_brainstorm())
