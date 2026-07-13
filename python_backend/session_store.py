from datetime import datetime, timezone
from pathlib import Path
import sqlite3


DEFAULT_SESSION = {
    "current_goal": "Build OSvoz Developer OS",
    "current_task": "Create persistent session memory",
    "last_action": "Project Inspector completed",
    "next_action": "Connect persistent memory to Flutter",
    "working_mode": "developer",
    "active_project": "ian_labvoice",
}


class SessionStore:
    def __init__(self, database_path: str):
        self.database_path = Path(database_path).expanduser().resolve()
        self.database_path.parent.mkdir(parents=True, exist_ok=True)
        self._initialize()

    def _connect(self):
        connection = sqlite3.connect(self.database_path)
        connection.row_factory = sqlite3.Row
        return connection

    def _initialize(self):
        with self._connect() as connection:
            connection.execute(
                """
                CREATE TABLE IF NOT EXISTS active_session (
                    id INTEGER PRIMARY KEY CHECK (id = 1),
                    current_goal TEXT NOT NULL,
                    current_task TEXT NOT NULL,
                    last_action TEXT NOT NULL,
                    next_action TEXT NOT NULL,
                    working_mode TEXT NOT NULL,
                    active_project TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                )
                """
            )
            connection.execute(
                """
                INSERT OR IGNORE INTO active_session (
                    id,
                    current_goal,
                    current_task,
                    last_action,
                    next_action,
                    working_mode,
                    active_project,
                    updated_at
                ) VALUES (1, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    DEFAULT_SESSION["current_goal"],
                    DEFAULT_SESSION["current_task"],
                    DEFAULT_SESSION["last_action"],
                    DEFAULT_SESSION["next_action"],
                    DEFAULT_SESSION["working_mode"],
                    DEFAULT_SESSION["active_project"],
                    self._timestamp(),
                ),
            )

    def get(self) -> dict:
        with self._connect() as connection:
            row = connection.execute(
                "SELECT * FROM active_session WHERE id = 1"
            ).fetchone()

        return dict(row)

    def update(self, values: dict) -> dict:
        current = self.get()
        fields = {
            key: values.get(key, current[key])
            for key in DEFAULT_SESSION
        }

        with self._connect() as connection:
            connection.execute(
                """
                UPDATE active_session
                SET current_goal = ?,
                    current_task = ?,
                    last_action = ?,
                    next_action = ?,
                    working_mode = ?,
                    active_project = ?,
                    updated_at = ?
                WHERE id = 1
                """,
                (
                    fields["current_goal"],
                    fields["current_task"],
                    fields["last_action"],
                    fields["next_action"],
                    fields["working_mode"],
                    fields["active_project"],
                    self._timestamp(),
                ),
            )

        return self.get()

    @staticmethod
    def _timestamp() -> str:
        return datetime.now(timezone.utc).isoformat()
