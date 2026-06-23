from copy import deepcopy
from datetime import datetime, timezone
from hashlib import sha256
from threading import Lock
import secrets


class EditorOperationStore:
    ACTIVE_STATUSES = {
        "awaiting_preview",
        "previewed",
        "approved",
        "undo_requested",
    }

    def __init__(self):
        self._lock = Lock()
        self._operations = {}
        self._latest_applied_id = None

    def create(
        self,
        *,
        instruction: str,
        active_file: str,
        relative_file: str,
        language_id: str,
        original: str,
        replacement: str,
        summary: str,
        diff: str,
    ) -> dict:
        operation_id = secrets.token_urlsafe(18)
        operation = {
            "id": operation_id,
            "type": "replace_active_document",
            "status": "awaiting_preview",
            "instruction": instruction,
            "active_file": active_file,
            "relative_file": relative_file,
            "language_id": language_id,
            "original": original,
            "original_hash": sha256(original.encode()).hexdigest(),
            "replacement": replacement,
            "summary": summary,
            "diff": diff,
            "diagnostics": None,
            "error": None,
            "created_at": datetime.now(timezone.utc).isoformat(),
            "updated_at": datetime.now(timezone.utc).isoformat(),
        }
        with self._lock:
            self._operations[operation_id] = operation
            return deepcopy(operation)

    def get(self, operation_id: str) -> dict | None:
        with self._lock:
            operation = self._operations.get(operation_id)
            return deepcopy(operation) if operation else None

    def next_for_extension(self) -> dict | None:
        with self._lock:
            active = [
                operation
                for operation in self._operations.values()
                if operation["status"] in self.ACTIVE_STATUSES
            ]
            if not active:
                return None
            return deepcopy(max(active, key=lambda item: item["created_at"]))

    def update(
        self,
        operation_id: str,
        status: str,
        *,
        diagnostics=None,
        error: str | None = None,
    ) -> dict | None:
        with self._lock:
            operation = self._operations.get(operation_id)
            if operation is None:
                return None
            operation["status"] = status
            operation["diagnostics"] = diagnostics
            operation["error"] = error
            operation["updated_at"] = datetime.now(timezone.utc).isoformat()
            if status == "applied":
                self._latest_applied_id = operation_id
            elif status == "undone" and self._latest_applied_id == operation_id:
                self._latest_applied_id = None
            return deepcopy(operation)

    def request_undo(self) -> dict | None:
        with self._lock:
            if self._latest_applied_id is None:
                return None
            operation = self._operations.get(self._latest_applied_id)
            if operation is None or operation["status"] != "applied":
                return None
            operation["status"] = "undo_requested"
            operation["updated_at"] = datetime.now(timezone.utc).isoformat()
            return deepcopy(operation)
