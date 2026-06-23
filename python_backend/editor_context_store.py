from copy import deepcopy
from datetime import datetime, timezone
from threading import Lock


class EditorContextStore:
    MAX_WORKSPACE_ROOTS = 10
    MAX_WORKSPACE_FILES = 5000
    MAX_OPEN_FILES = 100
    MAX_DOCUMENT_TEXT = 100_000
    MAX_SELECTED_TEXT = 20_000

    def __init__(self):
        self._lock = Lock()
        self._context = self._empty_context()

    @staticmethod
    def _empty_context() -> dict:
        return {
            "connected": False,
            "workspace_roots": [],
            "workspace_files": [],
            "open_files": [],
            "active_file": "",
            "relative_file": "",
            "language_id": "",
            "document_text": "",
            "selected_text": "",
            "cursor_line": 0,
            "cursor_character": 0,
            "updated_at": None,
        }

    @staticmethod
    def _bounded_text(value, limit: int) -> str:
        return str(value or "")[:limit]

    @classmethod
    def _bounded_list(cls, values, count: int, text_limit: int) -> list[str]:
        if not isinstance(values, list):
            return []
        return [
            cls._bounded_text(value, text_limit)
            for value in values[:count]
            if value
        ]

    def update(self, values: dict) -> dict:
        context = {
            "connected": True,
            "workspace_roots": self._bounded_list(
                values.get("workspace_roots"),
                self.MAX_WORKSPACE_ROOTS,
                1000,
            ),
            "workspace_files": self._bounded_list(
                values.get("workspace_files"),
                self.MAX_WORKSPACE_FILES,
                1000,
            ),
            "open_files": self._bounded_list(
                values.get("open_files"),
                self.MAX_OPEN_FILES,
                1000,
            ),
            "active_file": self._bounded_text(
                values.get("active_file"),
                1000,
            ),
            "relative_file": self._bounded_text(
                values.get("relative_file"),
                1000,
            ),
            "language_id": self._bounded_text(
                values.get("language_id"),
                100,
            ),
            "document_text": self._bounded_text(
                values.get("document_text"),
                self.MAX_DOCUMENT_TEXT,
            ),
            "selected_text": self._bounded_text(
                values.get("selected_text"),
                self.MAX_SELECTED_TEXT,
            ),
            "cursor_line": max(0, int(values.get("cursor_line") or 0)),
            "cursor_character": max(
                0,
                int(values.get("cursor_character") or 0),
            ),
            "updated_at": datetime.now(timezone.utc).isoformat(),
        }
        with self._lock:
            self._context = context
            return deepcopy(self._context)

    def get(self) -> dict:
        with self._lock:
            return deepcopy(self._context)

    @staticmethod
    def prompt_context(context: dict) -> str:
        if not context.get("connected"):
            return "VS Code bridge: disconnected."

        workspace_files = "\n".join(context.get("workspace_files", []))
        return (
            "VS Code bridge: connected.\n"
            f"Workspace roots: {context.get('workspace_roots', [])}\n"
            f"Active file: {context.get('active_file', '')}\n"
            f"Relative file: {context.get('relative_file', '')}\n"
            f"Language: {context.get('language_id', '')}\n"
            f"Cursor: line {context.get('cursor_line', 0) + 1}, "
            f"character {context.get('cursor_character', 0) + 1}\n"
            f"Open files: {context.get('open_files', [])}\n"
            f"Selected text:\n{context.get('selected_text', '')}\n"
            f"Active document:\n{context.get('document_text', '')}\n"
            f"Workspace file map:\n{workspace_files[:50_000]}"
        )
