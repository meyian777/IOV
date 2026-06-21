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

    def test_unknown_action_returns_not_found(self):
        response = TestClient(app).post(
            "/execute",
            json={"action": "UNKNOWN_ACTION"},
        )

        self.assertEqual(response.status_code, 404)
        self.assertEqual(response.json()["detail"]["code"], "unknown_action")

    def test_used_confirmation_returns_conflict(self):
        client = TestClient(app)
        prepared = client.post(
            "/execute",
            json={"action": "OPEN_TERMINAL"},
        ).json()
        token = prepared["confirmation_token"]

        with patch("main.ActionEngine.execute") as execute:
            execute.return_value = {"success": True, "message": "Executed"}
            client.post(
                "/execute/confirm",
                json={"confirmation_token": token},
            )

        reused = client.post(
            "/execute/confirm",
            json={"confirmation_token": token},
        )

        self.assertEqual(reused.status_code, 409)
        self.assertEqual(
            reused.json()["detail"]["code"],
            "invalid_confirmation",
        )
