import sqlite3
import tempfile
import unittest
from pathlib import Path

from audit_store import AuditStore


class AuditStoreTest(unittest.TestCase):
    def test_chain_verifies_and_excludes_sensitive_metadata(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "audit.db"
            store = AuditStore(str(path))
            event = store.append(
                "action.requested",
                "pending",
                {"action": "OPEN_VSCODE", "token": "must-not-appear"},
            )

            self.assertNotIn("token", event["metadata"])
            self.assertTrue(store.verify()["valid"])

    def test_tampering_breaks_chain_verification(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "audit.db"
            store = AuditStore(str(path))
            store.append("first", "ok")
            store.append("second", "ok")
            with sqlite3.connect(path) as connection:
                connection.execute(
                    "UPDATE audit_events SET outcome = 'tampered' WHERE id = 1"
                )

            result = store.verify()

            self.assertFalse(result["valid"])
            self.assertEqual(result["first_invalid_event_id"], 1)

    def test_verify_recovers_missing_table(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "audit.db"
            with sqlite3.connect(path) as connection:
                connection.execute("CREATE TABLE unrelated (id INTEGER)")

            store = AuditStore(str(path))
            with sqlite3.connect(path) as connection:
                connection.execute("DROP TABLE audit_events")

            result = store.verify()

            self.assertTrue(result["valid"])
            self.assertEqual(result["event_count"], 0)
