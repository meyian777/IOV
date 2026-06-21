import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from diagnostics_runner import DiagnosticsRunner


class DiagnosticsRunnerTest(unittest.TestCase):
    def test_discovers_flutter_and_python_checks(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            flutter = root / "app"
            backend = root / "backend"
            flutter.mkdir()
            backend.mkdir()
            (flutter / "pubspec.yaml").write_text("name: app\n")
            (backend / "requirements.txt").write_text("fastapi\n")

            checks = DiagnosticsRunner._discover_checks(root)

            self.assertEqual(
                [check[0] for check in checks],
                ["Flutter analyze", "Flutter tests", "Python tests"],
            )

    @patch("diagnostics_runner.subprocess.run")
    def test_reports_passed_and_failed_checks(self, run):
        run.side_effect = [
            subprocess.CompletedProcess([], 0, "Clean", ""),
            subprocess.CompletedProcess([], 1, "", "One test failed"),
        ]

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "pubspec.yaml").write_text("name: app\n")

            result = DiagnosticsRunner.run(str(root))

            self.assertFalse(result["success"])
            self.assertEqual(result["summary"]["passed"], 1)
            self.assertEqual(result["summary"]["failed"], 1)
            self.assertEqual(result["checks"][1]["exit_code"], 1)
