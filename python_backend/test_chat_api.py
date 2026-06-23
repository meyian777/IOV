import unittest
from unittest.mock import patch

from fastapi.testclient import TestClient

from main import app, conversation_store, editor_context_store


class ChatApiTest(unittest.TestCase):
    def setUp(self):
        editor_context_store._context = editor_context_store._empty_context()
        conversation_store.clear()

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
        self.assertIn("Recent conversation", system_content)
        self.assertIn("Capability routing", system_content)
        self.assertIn("routing", response.json())

    def test_code_route_endpoint_exposes_specialized_capability(self):
        response = TestClient(app).post(
            "/code/route",
            json={"message": "Depura este error de Flutter"},
        )

        self.assertEqual(response.status_code, 200)
        routing = response.json()["routing"]
        self.assertEqual(routing["domain"], "software_engineering")
        self.assertEqual(routing["capability"], "debug")
        self.assertEqual(routing["language"], "dart")

    def test_editor_context_endpoint_accepts_vscode_state(self):
        response = TestClient(app).post(
            "/editor/context",
            json={
                "workspace_roots": ["/workspace"],
                "workspace_files": ["lib/main.dart", "pubspec.yaml"],
                "active_file": "/workspace/lib/main.dart",
                "relative_file": "lib/main.dart",
                "language_id": "dart",
                "document_text": "void main() {}",
                "selected_text": "main",
                "cursor_line": 0,
                "cursor_character": 5,
            },
        )

        self.assertEqual(response.status_code, 200)
        context = response.json()["context"]
        self.assertTrue(context["connected"])
        self.assertEqual(context["relative_file"], "lib/main.dart")
        self.assertEqual(context["workspace_file_count"], 2)

    @patch("main.client.responses.create")
    def test_chat_receives_current_vscode_context(self, create):
        create.return_value.output_text = "Este archivo inicia la aplicación."
        client = TestClient(app)
        client.post(
            "/editor/context",
            json={
                "workspace_roots": ["/workspace"],
                "workspace_files": ["lib/main.dart"],
                "active_file": "/workspace/lib/main.dart",
                "relative_file": "lib/main.dart",
                "language_id": "dart",
                "document_text": "void main() {}",
                "selected_text": "main",
            },
        )

        response = client.post(
            "/chat",
            json={"message": "Explícame este archivo", "language": "es"},
        )

        self.assertEqual(response.status_code, 200)
        system_content = create.call_args.kwargs["input"][0]["content"]
        self.assertIn("VS Code bridge: connected", system_content)
        self.assertIn("lib/main.dart", system_content)
        self.assertIn("void main() {}", system_content)
        self.assertTrue(response.json()["editor"]["connected"])
        self.assertEqual(response.json()["routing"]["language"], "dart")

    @patch("main.client.responses.create")
    def test_chat_receives_previous_conversational_turn(self, create):
        create.return_value.output_text = "Primera respuesta."
        client = TestClient(app)
        client.post(
            "/chat",
            json={"message": "Recuerda esta tarea", "language": "es"},
        )
        create.return_value.output_text = "Continuemos."

        client.post(
            "/chat",
            json={"message": "Sigamos", "language": "es"},
        )

        system_content = create.call_args.kwargs["input"][0]["content"]
        self.assertIn("Recuerda esta tarea", system_content)
        self.assertIn("Primera respuesta.", system_content)

    @patch("main.client.audio.speech.create")
    def test_speech_returns_natural_voice_audio(self, create):
        create.return_value.content = b"ID3-test-audio"

        response = TestClient(app).post(
            "/speech",
            json={"text": "Hola Ian", "language": "es"},
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.headers["content-type"], "audio/mpeg")
        self.assertEqual(response.content, b"ID3-test-audio")
        self.assertEqual(create.call_args.kwargs["voice"], "cedar")
        self.assertIn(
            "Latin American Spanish",
            create.call_args.kwargs["instructions"],
        )

    @patch("main.client.audio.speech.create")
    def test_speech_failure_does_not_expose_provider_details(self, create):
        create.side_effect = RuntimeError("secret provider details")

        response = TestClient(app).post(
            "/speech",
            json={"text": "Hello", "language": "en"},
        )

        self.assertEqual(response.status_code, 502)
        self.assertEqual(
            response.json()["detail"]["code"],
            "speech_service_unavailable",
        )
        self.assertNotIn("secret provider details", response.text)
