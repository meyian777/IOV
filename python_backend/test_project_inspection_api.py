import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from fastapi.testclient import TestClient

import main
from main import app


class ProjectInspectionApiTest(unittest.TestCase):
    @patch("main.DiagnosticsRunner.run")
    def test_inspection_can_include_diagnostics(self, run):
        with tempfile.TemporaryDirectory() as directory:
            project = Path(directory)
            (project / "requirements.txt").write_text(
                "fastapi\n",
                encoding="utf-8",
            )
            run.return_value = {
                "success": True,
                "message": "Diagnostics completed: 1 passed and 0 failed.",
                "summary": {"total": 1, "passed": 1, "failed": 0},
                "checks": [{"name": "Python tests", "success": True}],
            }

            previous_project_path = main.PROJECT_PATH
            main.PROJECT_PATH = str(project)
            try:
                response = TestClient(app).get(
                    "/project/inspect?run_diagnostics=true"
                )
            finally:
                main.PROJECT_PATH = previous_project_path

        self.assertEqual(response.status_code, 200)
        result = response.json()
        self.assertEqual(result["diagnostics"]["summary"]["failed"], 0)
        self.assertEqual(
            result["explanation"]["next_action"],
            "Choose the next development task",
        )
        run.assert_called_once_with(str(project))


if __name__ == "__main__":
    unittest.main()
