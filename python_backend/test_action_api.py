import unittest
from unittest.mock import patch

from fastapi.testclient import TestClient

from main import app, audit_store


class ActionApiTest(unittest.TestCase):
    def test_core_health_and_audit_endpoints_are_available(self):
        client = TestClient(app)

        health = client.get("/core/health")
        latency = client.get("/core/latency")
        verification = client.get("/core/audit/verify")
        capabilities = client.get("/core/capabilities")

        self.assertEqual(health.status_code, 200)
        self.assertIn("x-osvoz-elapsed-ms", health.headers)
        self.assertIn("server-timing", health.headers)
        self.assertEqual(latency.status_code, 200)
        self.assertIn("GET /core/health", latency.json()["routes"])
        self.assertIn("warmup", latency.json())
        self.assertIn(health.json()["status"], {"ready", "degraded"})
        self.assertTrue(verification.json()["verification"]["valid"])
        self.assertTrue(
            capabilities.json()["capabilities"]["tamper_evident_audit"]
        )
        self.assertTrue(audit_store.verify()["valid"])

    def test_audit_event_endpoint_appends_sanitized_event(self):
        response = TestClient(app).post(
            "/core/audit/events",
            json={
                "event_type": "operator.preflight",
                "outcome": "blocked",
                "metadata": {
                    "action": "RUN_FLUTTER",
                    "token": "secret-token",
                },
            },
        )

        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.json()["success"])
        self.assertEqual(
            response.json()["event"]["event_type"],
            "operator.preflight",
        )
        self.assertTrue(audit_store.verify()["valid"])

    def test_operator_status_summarizes_health_and_records_audit(self):
        response = TestClient(app).get("/core/operator-status")

        self.assertEqual(response.status_code, 200)
        payload = response.json()
        self.assertTrue(payload["success"])
        self.assertIn(payload["status"], {"ready", "degraded"})
        self.assertIn("spoken_summary", payload)
        self.assertIn("es", payload["spoken_summary"])
        self.assertIn("implemented", payload["capabilities"])
        self.assertEqual(
            payload["audit_event"]["event_type"],
            "operator.status_checked",
        )
        self.assertTrue(audit_store.verify()["valid"])

    def test_operator_status_supports_detailed_summary_mode(self):
        response = TestClient(app).get(
            "/core/operator-status?summary_mode=detailed"
        )

        self.assertEqual(response.status_code, 200)
        payload = response.json()
        self.assertEqual(payload["summary_mode"], "detailed")
        self.assertIn("Seguridad:", payload["spoken_summary"]["es"])
        self.assertIn("abrir aplicaciones", payload["spoken_summary"]["es"])
        self.assertNotIn("system.open_app", payload["spoken_summary"]["es"])
        self.assertEqual(
            payload["audit_event"]["event_type"],
            "operator.status_checked",
        )

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

    @patch("main.ActionEngine.execute")
    def test_routine_system_action_executes_without_confirmation(self, execute):
        execute.return_value = {
            "success": True,
            "message": "Terminal opened",
        }

        result = TestClient(app).post(
            "/execute",
            json={"action": "OPEN_TERMINAL"},
        ).json()

        self.assertTrue(result["success"])
        self.assertFalse(result.get("requires_confirmation", False))
        execute.assert_called_once()

    def test_unknown_action_returns_not_found(self):
        response = TestClient(app).post(
            "/execute",
            json={"action": "UNKNOWN_ACTION"},
        )

        self.assertEqual(response.status_code, 404)
        self.assertEqual(response.json()["detail"]["code"], "unknown_action")

    @patch("main.ActionEngine.open_url")
    def test_browser_open_validates_and_opens_http_urls(self, open_url):
        open_url.return_value = {
            "success": True,
            "message": "Browser opened.",
        }

        response = TestClient(app).post(
            "/browser/open",
            json={"url": "https://www.youtube.com/results?search_query=test"},
        )

        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.json()["success"])
        open_url.assert_called_once()

    def test_browser_open_rejects_non_http_urls(self):
        response = TestClient(app).post(
            "/browser/open",
            json={"url": "file:///etc/passwd"},
        )

        self.assertEqual(response.status_code, 422)
        self.assertEqual(response.json()["detail"]["code"], "invalid_url")

    @patch("main.ActionEngine.open_youtube_music")
    def test_youtube_play_requests_music_playback(self, open_youtube_music):
        open_youtube_music.return_value = {
            "success": True,
            "message": "Playback requested.",
            "query": "Artista Libre",
            "play_attempted": True,
        }

        response = TestClient(app).post(
            "/browser/youtube/play",
            json={"query": "Artista Libre"},
        )

        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.json()["success"])
        self.assertTrue(response.json()["play_attempted"])
        open_youtube_music.assert_called_once_with(
            "Artista Libre",
            auto_skip_ads=False,
        )

    @patch("main.ActionEngine.open_youtube_music")
    def test_youtube_play_can_request_auto_skip_ads(self, open_youtube_music):
        open_youtube_music.return_value = {
            "success": True,
            "message": "Playback requested.",
            "query": "Artista Libre",
            "play_attempted": True,
            "auto_skip_ads": True,
        }

        response = TestClient(app).post(
            "/browser/youtube/play",
            json={"query": "Artista Libre", "auto_skip_ads": True},
        )

        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.json()["auto_skip_ads"])
        open_youtube_music.assert_called_once_with(
            "Artista Libre",
            auto_skip_ads=True,
        )

    @patch("main.ActionEngine.skip_youtube_ad")
    def test_youtube_skip_ad_uses_browser_control(self, skip_youtube_ad):
        skip_youtube_ad.return_value = {
            "success": True,
            "message": "YouTube skip ad button clicked.",
            "skipped": True,
        }

        response = TestClient(app).post("/browser/youtube/skip-ad")

        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.json()["success"])
        self.assertTrue(response.json()["skipped"])
        skip_youtube_ad.assert_called_once_with()

    def test_used_confirmation_returns_conflict(self):
        client = TestClient(app)
        prepared = client.post(
            "/execute",
            json={"action": "RUN_FLUTTER"},
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
