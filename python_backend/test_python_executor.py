import tempfile
import unittest
from pathlib import Path

from python_executor import PythonExecutor


class PythonExecutorTest(unittest.TestCase):
    def test_runs_project_relative_python_script(self):
        with tempfile.TemporaryDirectory() as directory:
            project = Path(directory)
            script = project / "hello.py"
            script.write_text(
                "import sys\nprint('hello ' + sys.argv[1])\n",
                encoding="utf-8",
            )

            result = PythonExecutor.run_script(
                str(project),
                "hello.py",
                ["labvoice"],
            )

        self.assertTrue(result["success"])
        self.assertEqual(result["script"], "hello.py")
        self.assertEqual(result["output"], "hello labvoice")

    def test_rejects_script_outside_project(self):
        with tempfile.TemporaryDirectory() as directory:
            project = Path(directory)

            result = PythonExecutor.run_script(
                str(project),
                "../outside.py",
            )

        self.assertFalse(result["success"])
        self.assertEqual(result["error"], "invalid_python_execution")

    def test_rejects_non_python_file(self):
        with tempfile.TemporaryDirectory() as directory:
            project = Path(directory)
            (project / "notes.txt").write_text("print('no')\n", encoding="utf-8")

            result = PythonExecutor.run_script(str(project), "notes.txt")

        self.assertFalse(result["success"])
        self.assertIn("Only .py", result["message"])

    def test_returns_output_for_failed_script(self):
        with tempfile.TemporaryDirectory() as directory:
            project = Path(directory)
            script = project / "fail.py"
            script.write_text(
                "import sys\nprint('before failure')\nsys.exit(7)\n",
                encoding="utf-8",
            )

            result = PythonExecutor.run_script(str(project), "fail.py")

        self.assertFalse(result["success"])
        self.assertEqual(result["exit_code"], 7)
        self.assertIn("before failure", result["output"])


if __name__ == "__main__":
    unittest.main()
