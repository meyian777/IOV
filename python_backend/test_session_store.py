import tempfile
import unittest
from pathlib import Path

from session_store import SessionStore


class SessionStoreTest(unittest.TestCase):
    def test_session_survives_store_recreation(self):
        with tempfile.TemporaryDirectory() as directory:
            database = Path(directory) / "session.db"
            store = SessionStore(str(database))
            store.update(
                {
                    "current_task": "Inspect OSvoz",
                    "last_action": "Read project state",
                }
            )

            restored = SessionStore(str(database)).get()

            self.assertEqual(restored["current_task"], "Inspect OSvoz")
            self.assertEqual(restored["last_action"], "Read project state")
            self.assertTrue(restored["updated_at"])

    def test_partial_update_preserves_other_fields(self):
        with tempfile.TemporaryDirectory() as directory:
            store = SessionStore(str(Path(directory) / "session.db"))
            original = store.get()

            updated = store.update({"next_action": "Run tests"})

            self.assertEqual(updated["next_action"], "Run tests")
            self.assertEqual(updated["current_goal"], original["current_goal"])
