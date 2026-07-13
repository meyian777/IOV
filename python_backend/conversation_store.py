from collections import deque
from threading import Lock


class ConversationStore:
    def __init__(self, max_turns: int = 8):
        self._turns = deque(maxlen=max_turns)
        self._lock = Lock()

    def add(self, user_message: str, assistant_response: str) -> None:
        with self._lock:
            self._turns.append(
                {
                    "user": user_message[:10_000],
                    "assistant": assistant_response[:10_000],
                }
            )

    def prompt_context(self) -> str:
        with self._lock:
            if not self._turns:
                return "No previous conversational turns."
            lines = []
            for turn in self._turns:
                lines.append(f"User: {turn['user']}")
                lines.append(f"OSvoz: {turn['assistant']}")
            return "\n".join(lines)

    def clear(self) -> None:
        with self._lock:
            self._turns.clear()
