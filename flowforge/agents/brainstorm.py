"""
BrainstormAgent - Chat-to-spec conversations via Claude CLI.

This agent runs Claude Code CLI to enable real-time brainstorming conversations.
It's designed to run on the Pi and use the user's authenticated Claude Max
subscription (NOT API keys - uses the CLI which routes through Max).

Key CLI flags used:
- `--tools ""` - Chat-only mode, no file/bash access (pure conversation)
- `--output-format stream-json` - Real-time streaming with session metadata
- `--resume <session_id>` - Continue existing conversation natively

Uses Claude Code's native session management for multi-turn conversations.
Falls back to prompt rebuild if session expires or is unavailable.
"""

import asyncio
import json
import re
from dataclasses import dataclass, field
from typing import AsyncGenerator, Optional

# Prompt size limits to prevent hang with long conversations
MAX_PROMPT_SIZE = 32000  # ~32KB limit for prompt
MIN_MESSAGES_TO_KEEP = 4  # Always keep at least 4 most recent messages


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
    claude_session_id: Optional[str] = None  # Claude Code session for --resume

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
        existing_session_id: Optional[str] = None,
    ):
        self.session = BrainstormSession(
            project_name=project_name,
            project_context=project_context,
            existing_features=existing_features or [],
            existing_feature_title=existing_feature_title,
            claude_session_id=existing_session_id,
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

        Uses Claude Code's native session management:
        - If we have a session_id, use --resume for fast continuation
        - Otherwise, start a new session with system prompt
        - Falls back to prompt rebuild if --resume fails

        Uses stream-json format to get real-time streaming + session_id.
        """
        # Try --resume first if we have a session
        if self.session.claude_session_id:
            success = False
            async for chunk in self._try_resume_session(user_message):
                if chunk == "__RESUME_FAILED__":
                    # Fall back to new session
                    print(f"Warning: --resume failed for session {self.session.claude_session_id}, falling back")
                    self.session.claude_session_id = None
                    break
                success = True
                yield chunk

            if success:
                return

        # No session or fallback: start new session with full system prompt
        async for chunk in self._start_new_session(user_message):
            yield chunk

    async def _try_resume_session(self, user_message: str) -> AsyncGenerator[str, None]:
        """Try to resume an existing Claude Code session."""
        cmd = [
            "claude",
            "-p", user_message,  # Just the new message!
            "--resume", self.session.claude_session_id,
            "--output-format", "stream-json",
            "--tools", "",
        ]

        process = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )

        full_response = []
        async for chunk in self._parse_stream_events(process, full_response):
            yield chunk

        # Check for failure
        if process.returncode != 0:
            yield "__RESUME_FAILED__"
            return

        # Store the response
        response_text = "".join(full_response)
        if response_text:
            self.session.messages.append(BrainstormMessage(role="assistant", content=response_text))

    async def _start_new_session(self, user_message: str) -> AsyncGenerator[str, None]:
        """Start a new Claude Code session with full system prompt."""
        # Build initial prompt with system context
        prompt = self._build_initial_prompt(user_message)

        cmd = [
            "claude",
            "-p", prompt,
            "--output-format", "stream-json",
            "--tools", "",
        ]

        process = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )

        full_response = []
        async for chunk in self._parse_stream_events(process, full_response):
            yield chunk

        # Check for errors
        if process.returncode != 0:
            stderr = await process.stderr.read()
            if stderr:
                error_msg = stderr.decode("utf-8", errors="replace")
                print(f"Claude CLI error: {error_msg}")

        # Store the response
        response_text = "".join(full_response)
        if response_text:
            self.session.messages.append(BrainstormMessage(role="assistant", content=response_text))

    async def _parse_stream_events(
        self,
        process: asyncio.subprocess.Process,
        full_response: list[str],
    ) -> AsyncGenerator[str, None]:
        """Parse stream-json events from Claude CLI output."""
        timeout_seconds = 180  # 3 minute overall timeout
        start_time = asyncio.get_event_loop().time()
        buffer = ""

        try:
            while True:
                try:
                    chunk = await asyncio.wait_for(
                        process.stdout.read(1024),
                        timeout=60  # 60 sec per chunk (Claude can think for a while)
                    )
                except asyncio.TimeoutError:
                    elapsed = asyncio.get_event_loop().time() - start_time
                    if elapsed > timeout_seconds:
                        yield "\n\n[Timeout - Claude is taking too long]"
                        process.kill()
                        break
                    continue

                if not chunk:
                    break

                buffer += chunk.decode("utf-8", errors="replace")

                # Process complete lines (newline-delimited JSON)
                while "\n" in buffer:
                    line, buffer = buffer.split("\n", 1)
                    line = line.strip()
                    if not line:
                        continue

                    try:
                        event = json.loads(line)
                        event_type = event.get("type", "")

                        if event_type == "start":
                            # Capture session_id for future --resume
                            session_id = event.get("session_id")
                            if session_id:
                                self.session.claude_session_id = session_id

                        elif event_type == "text":
                            # Stream text to client
                            content = event.get("content", "")
                            if content:
                                full_response.append(content)
                                yield content

                        elif event_type == "end":
                            # Session complete
                            pass

                        # Ignore tool_use, tool_result events (chat-only mode)

                    except json.JSONDecodeError:
                        # Not valid JSON, might be partial - continue
                        pass

            # Wait for process to complete
            await asyncio.wait_for(process.wait(), timeout=10)

        except asyncio.TimeoutError:
            yield "\n\n[Process timeout]"
            process.kill()

    def _build_initial_prompt(self, user_message: str) -> str:
        """Build the initial prompt with system context for a new session."""
        system_prompt = self.session.get_system_prompt()
        return f"{system_prompt}\n\n---\n\nUser: {user_message}"

    def _build_conversation_prompt(self, new_message: str) -> str:
        """Build prompt with system prompt + conversation history.

        Truncates older messages if prompt would exceed MAX_PROMPT_SIZE.
        Always keeps at least MIN_MESSAGES_TO_KEEP recent messages.
        """
        system_prompt = self.session.get_system_prompt()
        base_parts = [system_prompt, "\n\n---\n\nConversation:\n"]
        base_size = sum(len(p) for p in base_parts)

        # Build messages list (excluding the just-added user message)
        messages = self.session.messages[:-1]

        # Always include the new user message at the end
        new_msg_text = f"\nUser: {new_message}\n\nAssistant: "
        available_size = MAX_PROMPT_SIZE - base_size - len(new_msg_text)

        # Build message texts from newest to oldest
        message_texts = []
        for msg in reversed(messages):
            role_label = "User" if msg.role == "user" else "Assistant"
            msg_text = f"\n{role_label}: {msg.content}\n"
            message_texts.append(msg_text)

        # Select messages that fit, keeping at least MIN_MESSAGES_TO_KEEP
        selected = []
        total_size = 0
        for i, msg_text in enumerate(message_texts):
            if total_size + len(msg_text) > available_size and i >= MIN_MESSAGES_TO_KEEP:
                break
            selected.append(msg_text)
            total_size += len(msg_text)

        # Add truncation notice if we dropped messages
        truncation_notice = ""
        if len(selected) < len(message_texts):
            dropped_count = len(message_texts) - len(selected)
            truncation_notice = f"\n[{dropped_count} earlier messages omitted for brevity]\n"

        # Reassemble in chronological order
        selected.reverse()

        parts = base_parts + [truncation_notice] + selected + [new_msg_text]
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
