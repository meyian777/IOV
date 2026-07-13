import subprocess
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

from action_engine import ActionEngine


class ActionEngineTest(unittest.TestCase):
    @patch("action_engine.subprocess.Popen")
    @patch.object(ActionEngine, "_find_vscode_cli")
    def test_open_vscode_opens_project_in_reused_window(self, find_cli, popen):
        find_cli.return_value = Path("/mock/code")

        result = ActionEngine.execute("OPEN_VSCODE", "/workspace")

        self.assertTrue(result["success"])
        self.assertTrue(result["reused_existing_window"])
        popen.assert_called_once_with(
            ["/mock/code", "--reuse-window", "/workspace"]
        )

    @patch("action_engine.subprocess.Popen")
    @patch.object(ActionEngine, "_find_vscode_cli")
    @patch("action_engine.subprocess.run")
    def test_open_vscode_falls_back_to_bundle(self, run, find_cli, popen):
        find_cli.return_value = None
        run.return_value = subprocess.CompletedProcess(
            args=[], returncode=0, stdout="false\n", stderr=""
        )

        result = ActionEngine.execute("OPEN_VSCODE", "/workspace")

        self.assertTrue(result["success"])
        self.assertFalse(result["reused_existing_window"])
        popen.assert_called_once_with(
            ["open", "-b", ActionEngine.VSCODE_BUNDLE_ID, "/workspace"]
        )

    @patch("action_engine.subprocess.Popen")
    @patch.object(ActionEngine, "_find_vscode_cli")
    def test_open_project_forces_reuse_window(self, find_cli, popen):
        find_cli.return_value = Path("/mock/code")

        result = ActionEngine.execute("OPEN_PROJECT", "/workspace")

        self.assertTrue(result["success"])
        self.assertTrue(result["reused_existing_window"])
        popen.assert_called_once_with(
            ["/mock/code", "--reuse-window", "/workspace"]
        )

    @patch("action_engine.subprocess.Popen")
    def test_open_terminal_opens_project_directory(self, popen):
        result = ActionEngine.execute("OPEN_TERMINAL", "/workspace")

        self.assertTrue(result["success"])
        popen.assert_called_once_with(["open", "-a", "Terminal", "/workspace"])

    @patch("action_engine.subprocess.Popen")
    @patch("action_engine.Path.exists")
    @patch.object(ActionEngine, "_resolve_youtube_watch_url")
    def test_youtube_music_uses_chrome_playback_bridge(
        self, resolve, exists, popen
    ):
        resolve.return_value = None
        exists.return_value = True

        result = ActionEngine.open_youtube_music("Artista Libre")

        self.assertTrue(result["success"])
        self.assertTrue(result["play_attempted"])
        self.assertEqual(result["query"], "Artista Libre")
        command = popen.call_args.args[0]
        self.assertEqual(command[:2], ["osascript", "-e"])
        self.assertIn("execute javascript", command[2])
        self.assertIn("search_query=Artista+Libre", command[2])

    @patch("action_engine.subprocess.Popen")
    @patch("action_engine.Path.exists")
    @patch.object(ActionEngine, "_resolve_youtube_watch_url")
    def test_youtube_music_can_enable_auto_skip_ads(
        self, resolve, exists, popen
    ):
        resolve.return_value = None
        exists.return_value = True

        result = ActionEngine.open_youtube_music(
            "Artista Libre",
            auto_skip_ads=True,
        )

        self.assertTrue(result["success"])
        self.assertTrue(result["auto_skip_ads"])
        command = popen.call_args.args[0]
        self.assertIn("__osvozSkipAdMonitor", command[2])
        self.assertIn("ytp-ad-skip-button", command[2])

    @patch("action_engine.subprocess.Popen")
    @patch("action_engine.Path.exists")
    @patch.object(ActionEngine, "_resolve_youtube_watch_url")
    def test_youtube_music_opens_direct_video_when_resolved(
        self, resolve, exists, popen
    ):
        exists.return_value = True
        resolve.return_value = "https://www.youtube.com/watch?v=abc12345678&autoplay=1"

        result = ActionEngine.open_youtube_music("Banda Solar")

        self.assertTrue(result["success"])
        self.assertTrue(result["play_attempted"])
        self.assertTrue(result["direct_video"])
        popen.assert_called_once_with(
            [
                "open",
                "-a",
                "Google Chrome",
                "https://www.youtube.com/watch?v=abc12345678&autoplay=1",
            ]
        )

    @patch("action_engine.subprocess.Popen")
    @patch("action_engine.Path.exists")
    @patch.object(ActionEngine, "_resolve_youtube_watch_url")
    def test_youtube_direct_video_starts_ad_monitor(
        self, resolve, exists, popen
    ):
        exists.return_value = True
        resolve.return_value = "https://www.youtube.com/watch?v=abc12345678&autoplay=1"

        result = ActionEngine.open_youtube_music(
            "Banda Solar",
            auto_skip_ads=True,
        )

        self.assertTrue(result["success"])
        self.assertTrue(result["auto_skip_ads"])
        self.assertEqual(popen.call_count, 2)

    @patch("action_engine.subprocess.Popen")
    def test_open_music_uses_spotify_deeplink(self, popen):
        result = ActionEngine.open_music("Grupo Prisma", "spotify")

        self.assertTrue(result["success"])
        self.assertEqual(result["platform"], "spotify")
        self.assertTrue(result["app_deeplink"])
        popen.assert_called_once_with(["open", "spotify:search:Grupo%20Prisma"])

    @patch("action_engine.subprocess.Popen")
    def test_open_music_uses_apple_music_deeplink(self, popen):
        result = ActionEngine.open_music("Proyecto Lunar", "apple_music")

        self.assertTrue(result["success"])
        self.assertEqual(result["platform"], "apple_music")
        self.assertTrue(result["app_deeplink"])
        self.assertIn(
            "music://music.apple.com/search?term=Proyecto+Lunar",
            popen.call_args.args[0],
        )

    @patch("action_engine.subprocess.check_output")
    @patch("action_engine.Path.exists")
    def test_skip_youtube_ad_clicks_official_button(self, exists, check_output):
        exists.return_value = True
        check_output.return_value = "skipped\n"

        result = ActionEngine.skip_youtube_ad()

        self.assertTrue(result["success"])
        self.assertTrue(result["skipped"])
        command = check_output.call_args.args[0]
        self.assertEqual(command[:2], ["osascript", "-e"])
        self.assertIn("ytp-ad-skip-button", command[2])

    @patch("action_engine.subprocess.check_output")
    @patch("action_engine.Path.exists")
    def test_skip_youtube_ad_reports_missing_button(self, exists, check_output):
        exists.return_value = True
        check_output.return_value = "not_available\n"

        result = ActionEngine.skip_youtube_ad()

        self.assertTrue(result["success"])
        self.assertFalse(result["skipped"])

    @patch("action_engine.subprocess.check_output")
    def test_accessibility_skip_supports_spanish_labels(self, check_output):
        check_output.return_value = "not_available\n"

        result = ActionEngine._skip_youtube_ad_with_accessibility()

        self.assertTrue(result["success"])
        self.assertFalse(result["skipped"])
        script = check_output.call_args.args[0][2]
        self.assertIn("Omitir", script)
        self.assertIn("Saltar", script)

    @patch("action_engine.subprocess.check_output")
    def test_accessibility_skip_reports_timeout(self, check_output):
        check_output.side_effect = subprocess.TimeoutExpired(["osascript"], 8)

        result = ActionEngine._skip_youtube_ad_with_accessibility()

        self.assertTrue(result["success"])
        self.assertFalse(result["skipped"])
        self.assertEqual(result["state"], "accessibility_timeout")

    @patch("action_engine.subprocess.check_output")
    @patch("action_engine.Path.exists")
    def test_skip_youtube_ad_degrades_when_control_unavailable(
        self, exists, check_output
    ):
        exists.return_value = True
        check_output.side_effect = subprocess.CalledProcessError(
            1,
            ["osascript"],
        )

        result = ActionEngine.skip_youtube_ad()

        self.assertTrue(result["success"])
        self.assertFalse(result["skipped"])
        self.assertEqual(result["state"], "control_unavailable")

    @patch("action_engine.subprocess.check_output")
    @patch("action_engine.Path.exists")
    def test_skip_youtube_ad_reports_chrome_javascript_setting(
        self, exists, check_output
    ):
        exists.return_value = True
        check_output.side_effect = [
            subprocess.CalledProcessError(
                1,
                ["osascript"],
                output="Executing JavaScript through AppleScript is turned off.",
            ),
            subprocess.CalledProcessError(1, ["osascript"]),
        ]

        result = ActionEngine.skip_youtube_ad()

        self.assertTrue(result["success"])
        self.assertFalse(result["skipped"])
        self.assertEqual(result["state"], "chrome_javascript_events_disabled")
