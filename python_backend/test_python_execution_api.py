import tempfile
import unittest
from pathlib import Path

from fastapi.testclient import TestClient

import main
from main import app


class PythonExecutionApiTest(unittest.TestCase):
    def test_executes_python_script_in_active_project(self):
        with tempfile.TemporaryDirectory() as directory:
            project = Path(directory)
            (project / "tool.py").write_text(
                "import sys\nprint('value=' + sys.argv[1])\n",
                encoding="utf-8",
            )

            previous_project_path = main.PROJECT_PATH
            main.PROJECT_PATH = str(project)
            try:
                response = TestClient(app).post(
                    "/python/execute",
                    json={
                        "script_path": "tool.py",
                        "arguments": ["42"],
                    },
                )
            finally:
                main.PROJECT_PATH = previous_project_path

        self.assertEqual(response.status_code, 200)
        result = response.json()
        self.assertTrue(result["success"])
        self.assertEqual(result["output"], "value=42")

    def test_failed_script_returns_execution_details(self):
        with tempfile.TemporaryDirectory() as directory:
            project = Path(directory)
            (project / "tool.py").write_text(
                "import sys\nprint('bad input')\nsys.exit(4)\n",
                encoding="utf-8",
            )

            previous_project_path = main.PROJECT_PATH
            main.PROJECT_PATH = str(project)
            try:
                response = TestClient(app).post(
                    "/python/execute",
                    json={"script_path": "tool.py"},
                )
            finally:
                main.PROJECT_PATH = previous_project_path

        self.assertEqual(response.status_code, 422)
        detail = response.json()["detail"]
        self.assertEqual(detail["code"], "python_execution_failed")
        self.assertEqual(detail["exit_code"], 4)
        self.assertIn("bad input", detail["output"])


if __name__ == "__main__":
    unittest.main()
