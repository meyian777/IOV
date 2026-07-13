import unittest
from unittest.mock import patch

from fastapi.testclient import TestClient

from main import app


class MLProviderApiTest(unittest.TestCase):
    def test_ml_provider_endpoint_reports_selected_provider(self):
        response = TestClient(app).get("/ml/provider")

        self.assertEqual(response.status_code, 200)
        result = response.json()
        self.assertTrue(result["success"])
        self.assertIn("provider", result)
        self.assertIn("framework", result["provider"])

    def test_audio_embedding_endpoint_returns_embedding(self):
        with patch(
            "main.MLProviderManager.audio_embedding",
            return_value={
                "success": True,
                "embedding": [1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
            },
        ):
            response = TestClient(app).post(
                "/ml/audio/embedding",
                json={"features": [0.1, 0.2, 0.3, 0.4]},
            )

        self.assertEqual(response.status_code, 200)
        result = response.json()
        self.assertTrue(result["success"])
        self.assertEqual(len(result["embedding"]), 8)

    def test_audio_embedding_reports_unavailable_provider(self):
        with patch(
            "main.MLProviderManager.audio_embedding",
            return_value={
                "success": False,
                "error": "ml_provider_unavailable",
                "message": "No ML provider is available.",
            },
        ):
            response = TestClient(app).post(
                "/ml/audio/embedding",
                json={"features": [0.1]},
            )

        self.assertEqual(response.status_code, 503)

    def test_audio_embedding_rejects_invalid_features(self):
        response = TestClient(app).post(
            "/ml/audio/embedding",
            json={"features": []},
        )

        self.assertEqual(response.status_code, 422)


if __name__ == "__main__":
    unittest.main()
