import unittest
from unittest.mock import patch

from permission_engine import PermissionEngine


class PermissionEngineTest(unittest.TestCase):
    def test_read_only_action_is_approved_immediately(self):
        result = PermissionEngine().prepare("LIST_FILES")

        self.assertTrue(result["approved"])
        self.assertFalse(result["requires_confirmation"])

    def test_sensitive_action_requires_single_use_confirmation(self):
        engine = PermissionEngine()
        prepared = engine.prepare("RUN_FLUTTER")

        self.assertFalse(prepared["approved"])
        token = prepared["confirmation_token"]
        self.assertTrue(engine.confirm(token)["approved"])
        self.assertFalse(engine.confirm(token)["success"])

    def test_confirmation_expires(self):
        engine = PermissionEngine(confirmation_ttl_seconds=1)
        with patch("permission_engine.time.monotonic", side_effect=[10, 12]):
            prepared = engine.prepare("OPEN_TERMINAL")
            result = engine.confirm(prepared["confirmation_token"])

        self.assertEqual(result["error"], "expired_confirmation")

    def test_cancel_removes_pending_action(self):
        engine = PermissionEngine()
        prepared = engine.prepare("OPEN_VSCODE")
        token = prepared["confirmation_token"]

        self.assertTrue(engine.cancel(token)["success"])
        self.assertFalse(engine.confirm(token)["success"])
