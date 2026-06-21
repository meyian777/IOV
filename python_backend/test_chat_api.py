import unittest
from unittest.mock import patch

from fastapi.testclient import TestClient

from main import app


class ChatApiTest(unittest.TestCase):
    def test_empty_message_is_rejected(self):
        response = TestClient(app).post("/chat", json={"message": ""})

        self.assertEqual(response.status_code, 422)

    @patch("main.client.responses.create")
    def test_ai_failure_returns_safe_gateway_error(self, create):
        create.side_effect = RuntimeError("secret provider details")

        response = TestClient(app).post(
            "/chat",
            json={"message": "Hello"},
        )

        self.assertEqual(response.status_code, 502)
        self.assertEqual(
            response.json()["detail"]["code"],
            "ai_service_unavailable",
        )
        self.assertNotIn("secret provider details", response.text)
