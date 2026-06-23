import subprocess
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

from action_engine import ActionEngine


class ActionEngineTest(unittest.TestCase):
    @patch("action_engine.subprocess.Popen")
    @patch("action_engine.subprocess.run")
    def test_open_vscode_activates_running_instance(self, run, popen):
        run.return_value = subprocess.CompletedProcess(
            args=[],
            returncode=0,
            stdout="true\n",
            stderr="",
        )

        result = ActionEngine.execute("OPEN_VSCODE", "/workspace")

        self.assertTrue(result["success"])
        self.assertTrue(result["reused_existing_window"])
        command = popen.call_args.args[0]
        self.assertEqual(command[0], "osascript")
        self.assertIn("activate", command[-1])
        self.assertNotIn("open", command)

    @patch("action_engine.subprocess.Popen")
    @patch("action_engine.subprocess.run")
    def test_open_vscode_starts_app_only_when_not_running(self, run, popen):
        run.return_value = subprocess.CompletedProcess(
            args=[],
            returncode=0,
            stdout="false\n",
            stderr="",
        )

        result = ActionEngine.execute("OPEN_VSCODE", "/workspace")

        self.assertTrue(result["success"])
        self.assertFalse(result["reused_existing_window"])
        popen.assert_called_once_with(
            ["open", "-b", ActionEngine.VSCODE_BUNDLE_ID]
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
