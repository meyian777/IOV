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

    @patch("main.client.responses.create")
    def test_chat_receives_language_and_session_context(self, create):
        create.return_value.output_text = "Entendido."

        response = TestClient(app).post(
            "/chat",
            json={
                "message": "¿Qué sigue?",
                "language": "es",
            },
        )

        self.assertEqual(response.status_code, 200)
        system_content = create.call_args.kwargs["input"][0]["content"]
        self.assertIn("Respond in language code: es", system_content)
        self.assertIn("Current operational context", system_content)
