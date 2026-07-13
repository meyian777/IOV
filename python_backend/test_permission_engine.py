import unittest
from unittest.mock import patch

from permission_engine import PermissionEngine


class FakeNativePolicyClient:
    POLICIES = {
        "LIST_FILES": {
            "name": "LIST_FILES",
            "description": "List files.",
            "risk": "read_only",
            "requires_confirmation": False,
        },
        "RUN_FLUTTER": {
            "name": "RUN_FLUTTER",
            "description": "Run Flutter.",
            "risk": "process_execution",
            "requires_confirmation": True,
        },
        "OPEN_TERMINAL": {
            "name": "OPEN_TERMINAL",
            "description": "Open Terminal.",
            "risk": "routine_system",
            "requires_confirmation": False,
        },
        "OPEN_VSCODE": {
            "name": "OPEN_VSCODE",
            "description": "Open VS Code.",
            "risk": "routine_system",
            "requires_confirmation": False,
        },
        "RUN_PYTHON_SCRIPT": {
            "name": "RUN_PYTHON_SCRIPT",
            "description": "Run Python script.",
            "risk": "process_execution",
            "requires_confirmation": True,
        },
        "SEND_MONEY": {
            "name": "SEND_MONEY",
            "description": "Send money.",
            "risk": "critical_financial",
            "requires_confirmation": True,
        },
        "CHANGE_PASSWORD": {
            "name": "CHANGE_PASSWORD",
            "description": "Change password.",
            "risk": "credential_change",
            "requires_confirmation": True,
        },
    }

    def policy(self, action):
        policy = self.POLICIES.get(action)
        if policy is None:
            return {"success": False, "error": "unknown_action"}
        return {"success": True, **policy}


class PermissionEngineTest(unittest.TestCase):
    def engine(self, **kwargs):
        return PermissionEngine(
            native_client=FakeNativePolicyClient(),
            **kwargs,
        )

    def test_read_only_action_is_approved_immediately(self):
        result = self.engine().prepare("LIST_FILES")

        self.assertTrue(result["approved"])
        self.assertFalse(result["requires_confirmation"])
        self.assertEqual(result["policy"]["authority"], "rust_native_core")
        self.assertEqual(result["policy"]["security_level"], 1)
        self.assertEqual(
            result["policy"]["required_factors"],
            ["wake_word", "active_session"],
        )

    def test_sensitive_action_requires_single_use_confirmation(self):
        engine = self.engine()
        prepared = engine.prepare("RUN_FLUTTER")

        self.assertFalse(prepared["approved"])
        self.assertIn("Security level 2", prepared["message"])
        token = prepared["confirmation_token"]
        self.assertTrue(engine.confirm(token)["approved"])
        self.assertFalse(engine.confirm(token)["success"])

    def test_python_execution_requires_confirmation(self):
        prepared = self.engine().prepare("RUN_PYTHON_SCRIPT")

        self.assertFalse(prepared["approved"])
        self.assertEqual(prepared["policy"]["risk"], "process_execution")
        self.assertEqual(prepared["policy"]["security_level"], 2)
        self.assertEqual(
            prepared["policy"]["required_factors"],
            ["trusted_device", "voice_id", "preview_confirmation"],
        )
        self.assertTrue(prepared["requires_confirmation"])

    def test_critical_financial_action_requires_strong_factors(self):
        prepared = self.engine().prepare("SEND_MONEY")

        self.assertFalse(prepared["approved"])
        self.assertEqual(prepared["policy"]["security_level"], 3)
        self.assertEqual(prepared["policy"]["security_name"], "dangerous")
        self.assertEqual(
            prepared["policy"]["required_factors"],
            [
                "trusted_device",
                "face_id_or_touch_id",
                "apple_watch_presence",
                "passkey",
                "explicit_preview_confirmation",
            ],
        )

    def test_credential_change_requires_strong_factors(self):
        prepared = self.engine().prepare("CHANGE_PASSWORD")

        self.assertFalse(prepared["approved"])
        self.assertEqual(prepared["policy"]["security_level"], 3)
        self.assertIn("passkey", prepared["policy"]["required_factors"])

    def test_confirmation_expires(self):
        engine = self.engine(confirmation_ttl_seconds=1)
        with patch("permission_engine.time.monotonic", side_effect=[10, 12]):
            prepared = engine.prepare("RUN_FLUTTER")
            result = engine.confirm(prepared["confirmation_token"])

        self.assertEqual(result["error"], "expired_confirmation")

    def test_cancel_removes_pending_action(self):
        engine = self.engine()
        prepared = engine.prepare("RUN_FLUTTER")
        token = prepared["confirmation_token"]

        self.assertTrue(engine.cancel(token)["success"])
        self.assertFalse(engine.confirm(token)["success"])

    def test_native_core_failure_blocks_action(self):
        class Unavailable:
            def policy(self, action):
                return {
                    "success": False,
                    "error": "native_core_unavailable",
                }

        result = PermissionEngine(native_client=Unavailable()).prepare(
            "OPEN_TERMINAL"
        )

        self.assertFalse(result["success"])
        self.assertEqual(result["error"], "native_core_unavailable")

    def test_routine_system_actions_are_approved_immediately(self):
        terminal = self.engine().prepare("OPEN_TERMINAL")
        vscode = self.engine().prepare("OPEN_VSCODE")

        self.assertTrue(terminal["approved"])
        self.assertFalse(terminal["requires_confirmation"])
        self.assertEqual(terminal["policy"]["risk"], "routine_system")
        self.assertTrue(vscode["approved"])
        self.assertFalse(vscode["requires_confirmation"])
