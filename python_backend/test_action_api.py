import unittest
from unittest.mock import patch

from fastapi.testclient import TestClient

from main import app


class ActionApiTest(unittest.TestCase):
    @patch("main.ActionEngine.execute")
    def test_sensitive_action_cannot_execute_without_confirmation(self, execute):
        client = TestClient(app)

        prepared = client.post(
            "/execute",
            json={"action": "RUN_FLUTTER"},
        ).json()

        self.assertTrue(prepared["requires_confirmation"])
        execute.assert_not_called()

        execute.return_value = {
            "success": True,
            "message": "Executed",
        }
        confirmed = client.post(
            "/execute/confirm",
            json={"confirmation_token": prepared["confirmation_token"]},
        ).json()

        self.assertTrue(confirmed["success"])
        execute.assert_called_once()

    @patch("main.ActionEngine.execute")
    def test_read_only_action_executes_without_confirmation(self, execute):
        execute.return_value = {
            "success": True,
            "message": "Files",
        }

        result = TestClient(app).post(
            "/execute",
            json={"action": "LIST_FILES"},
        ).json()

        self.assertTrue(result["success"])
        execute.assert_called_once()
