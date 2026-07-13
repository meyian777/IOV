import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from staged_edit_validator import StagedEditValidator


class StagedEditValidatorTest(unittest.TestCase):
    @patch("staged_edit_validator.DiagnosticsRunner.run")
    def test_tests_replacement_in_isolated_project_copy(self, run):
        staged_contents = {}

        def inspect_staged_project(staged_path, environment=None):
            staged_contents["main.py"] = (
                Path(staged_path) / "main.py"
            ).read_text()
            self.assertEqual(
                environment["OPENAI_API_KEY"],
                "labvoice-staged-validation",
            )
            return {"success": True, "checks": []}

        run.side_effect = inspect_staged_project
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "main.py"
            source.write_text("value = 1\n")

            result = StagedEditValidator.run(
                str(root),
                {
                    "active_file": str(source),
                    "replacement": "value = 2\n",
                },
            )

            self.assertTrue(result["success"])
            self.assertEqual(staged_contents["main.py"], "value = 2\n")
            self.assertEqual(source.read_text(), "value = 1\n")

    def test_rejects_file_outside_project(self):
        with tempfile.TemporaryDirectory() as directory:
            result = StagedEditValidator.run(
                directory,
                {
                    "active_file": "/private/tmp/outside.py",
                    "replacement": "value = 2\n",
                },
            )

        self.assertFalse(result["success"])

    @patch("staged_edit_validator.DiagnosticsRunner.run")
    def test_tests_multiple_replacements_in_one_isolated_project_copy(self, run):
        staged_contents = {}

        def inspect_staged_project(staged_path, environment=None):
            staged_contents["a.py"] = (Path(staged_path) / "a.py").read_text()
            staged_contents["b.py"] = (Path(staged_path) / "b.py").read_text()
            return {"success": True, "checks": []}

        run.side_effect = inspect_staged_project
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            file_a = root / "a.py"
            file_b = root / "b.py"
            file_a.write_text("value = 'a'\n")
            file_b.write_text("value = 'b'\n")

            result = StagedEditValidator.run(
                str(root),
                {
                    "files": [
                        {
                            "active_file": str(file_a),
                            "replacement": "value = 'A'\n",
                        },
                        {
                            "active_file": str(file_b),
                            "replacement": "value = 'B'\n",
                        },
                    ]
                },
            )

            self.assertTrue(result["success"])
            self.assertEqual(staged_contents["a.py"], "value = 'A'\n")
            self.assertEqual(staged_contents["b.py"], "value = 'B'\n")
            self.assertEqual(file_a.read_text(), "value = 'a'\n")
            self.assertEqual(file_b.read_text(), "value = 'b'\n")
