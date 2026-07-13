import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from core_health import CoreHealth


class CoreHealthTest(unittest.TestCase):
    def test_reports_ready_when_critical_components_are_healthy(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            database = root / "session.db"
            database.touch()
            with patch.dict(
                os.environ,
                {"OPENAI_API_KEY": "test-key"},
            ):
                result = CoreHealth.inspect(
                    str(root),
                    str(database),
                    {"connected": False},
                    {"valid": True, "event_count": 1},
                    {"framework": "tensorflow_or_pytorch_boundary"},
                    {"success": True, "language": "rust"},
                    {"success": True, "engine": "whisper.cpp"},
                    {"success": True, "ready": False},
                )

        self.assertEqual(result["status"], "ready")
        self.assertTrue(result["critical_ready"])
        self.assertFalse(result["checks"]["editor_bridge"])
        self.assertTrue(result["checks"]["ml_framework_boundary"])

    def test_reports_degraded_for_invalid_audit_chain(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            database = root / "session.db"
            database.touch()
            with patch.dict(
                os.environ,
                {"OPENAI_API_KEY": "test-key"},
            ):
                result = CoreHealth.inspect(
                    str(root),
                    str(database),
                    {"connected": True},
                    {"valid": False},
                    {"framework": "boundary"},
                    {"success": True},
                    {"success": True},
                    {"success": True, "ready": False},
                )

        self.assertEqual(result["status"], "degraded")
        self.assertFalse(result["critical_ready"])
