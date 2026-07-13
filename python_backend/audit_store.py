from datetime import datetime, timezone
from hashlib import sha256
from pathlib import Path
from threading import Lock
import json
import sqlite3


class AuditStore:
    GENESIS_HASH = "0" * 64

    def __init__(self, database_path: str):
        self.database_path = Path(database_path).expanduser().resolve()
        self.database_path.parent.mkdir(parents=True, exist_ok=True)
        self._lock = Lock()
        self._initialize()

    def _connect(self):
        connection = sqlite3.connect(self.database_path)
        connection.row_factory = sqlite3.Row
        return connection

    def _initialize(self):
        with self._connect() as connection:
            connection.execute(
                """
                CREATE TABLE IF NOT EXISTS audit_events (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    occurred_at TEXT NOT NULL,
                    event_type TEXT NOT NULL,
                    outcome TEXT NOT NULL,
                    metadata_json TEXT NOT NULL,
                    previous_hash TEXT NOT NULL,
                    event_hash TEXT NOT NULL UNIQUE
                )
                """
            )

    def append(
        self,
        event_type: str,
        outcome: str,
        metadata: dict | None = None,
    ) -> dict:
        safe_metadata = self._sanitize(metadata or {})
        occurred_at = datetime.now(timezone.utc).isoformat()
        metadata_json = json.dumps(
            safe_metadata,
            sort_keys=True,
            separators=(",", ":"),
        )
        with self._lock, self._connect() as connection:
            self._initialize_connection(connection)
            row = connection.execute(
                "SELECT event_hash FROM audit_events ORDER BY id DESC LIMIT 1"
            ).fetchone()
            previous_hash = (
                row["event_hash"] if row is not None else self.GENESIS_HASH
            )
            event_hash = self._event_hash(
                occurred_at,
                event_type,
                outcome,
                metadata_json,
                previous_hash,
            )
            cursor = connection.execute(
                """
                INSERT INTO audit_events (
                    occurred_at,
                    event_type,
                    outcome,
                    metadata_json,
                    previous_hash,
                    event_hash
                ) VALUES (?, ?, ?, ?, ?, ?)
                """,
                (
                    occurred_at,
                    event_type[:100],
                    outcome[:50],
                    metadata_json,
                    previous_hash,
                    event_hash,
                ),
            )
            return {
                "id": cursor.lastrowid,
                "occurred_at": occurred_at,
                "event_type": event_type[:100],
                "outcome": outcome[:50],
                "metadata": safe_metadata,
                "previous_hash": previous_hash,
                "event_hash": event_hash,
            }

    def verify(self) -> dict:
        with self._connect() as connection:
            self._initialize_connection(connection)
            rows = connection.execute(
                "SELECT * FROM audit_events ORDER BY id"
            ).fetchall()

        previous_hash = self.GENESIS_HASH
        for row in rows:
            expected = self._event_hash(
                row["occurred_at"],
                row["event_type"],
                row["outcome"],
                row["metadata_json"],
                previous_hash,
            )
            if row["previous_hash"] != previous_hash or row["event_hash"] != expected:
                return {
                    "valid": False,
                    "event_count": len(rows),
                    "first_invalid_event_id": row["id"],
                }
            previous_hash = row["event_hash"]
        return {
            "valid": True,
            "event_count": len(rows),
            "head_hash": previous_hash,
        }

    @staticmethod
    def _initialize_connection(connection: sqlite3.Connection) -> None:
        connection.execute(
            """
            CREATE TABLE IF NOT EXISTS audit_events (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                occurred_at TEXT NOT NULL,
                event_type TEXT NOT NULL,
                outcome TEXT NOT NULL,
                metadata_json TEXT NOT NULL,
                previous_hash TEXT NOT NULL,
                event_hash TEXT NOT NULL UNIQUE
            )
            """
        )

    @staticmethod
    def _event_hash(
        occurred_at: str,
        event_type: str,
        outcome: str,
        metadata_json: str,
        previous_hash: str,
    ) -> str:
        payload = "|".join(
            (
                occurred_at,
                event_type,
                outcome,
                metadata_json,
                previous_hash,
            )
        )
        return sha256(payload.encode()).hexdigest()

    @staticmethod
    def _sanitize(metadata: dict) -> dict:
        blocked = {
            "api_key",
            "audio",
            "content",
            "document_text",
            "key",
            "message",
            "original",
            "replacement",
            "secret",
            "selected_text",
            "text",
            "token",
        }
        result = {}
        for key, value in metadata.items():
            normalized = str(key).lower()
            if normalized in blocked or any(word in normalized for word in blocked):
                continue
            if isinstance(value, (str, int, float, bool)) or value is None:
                result[str(key)[:100]] = (
                    value[:500] if isinstance(value, str) else value
                )
        return result
