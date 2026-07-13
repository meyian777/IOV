import unittest
from unittest.mock import patch

from fastapi.testclient import TestClient

from main import app


class VoiceApiTest(unittest.TestCase):
    @patch("main.local_whisper_engine.transcribe")
    def test_transcribes_wav_without_executing_an_action(self, transcribe):
        transcribe.return_value = {
            "success": True,
            "transcript": "OSvoz abre Visual Studio Code",
            "language": "es",
            "engine": "whisper.cpp",
            "execution": "local_offline",
            "audio": {"duration_seconds": 1.0},
        }
        wav_header = (
            b"RIFF"
            + (36).to_bytes(4, "little")
            + b"WAVE"
            + b"\x00" * 32
        )

        response = TestClient(app).post(
            "/voice/transcribe?language=es",
            content=wav_header,
            headers={"content-type": "audio/wav"},
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(
            response.json()["transcript"],
            "OSvoz abre Visual Studio Code",
        )

    def test_interprets_but_does_not_execute(self):
        response = TestClient(app).post(
            "/voice/interpret",
            json={
                "transcript": "OSvoz abre Visual Studio Code",
                "language": "es",
            },
        )

        self.assertEqual(response.status_code, 200)
        result = response.json()
        self.assertEqual(
            result["interpretation"]["action"],
            "OPEN_VSCODE",
        )
        self.assertFalse(result["interpretation"]["requires_confirmation"])
        self.assertFalse(result["safety"]["executed"])

    def test_routes_code_requests_to_software_capabilities(self):
        response = TestClient(app).post(
            "/voice/interpret",
            json={
                "transcript": "OSvoz explícame main.dart",
                "language": "es",
            },
        )

        self.assertEqual(response.status_code, 200)
        result = response.json()
        self.assertEqual(result["code_route"]["domain"], "software_engineering")
        self.assertEqual(result["code_route"]["capability"], "explain")

    def test_rejects_non_wav_audio(self):
        response = TestClient(app).post(
            "/voice/transcribe",
            content=b"not audio",
        )

        self.assertEqual(response.status_code, 415)
