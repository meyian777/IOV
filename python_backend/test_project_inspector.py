import subprocess
import tempfile
import unittest
from pathlib import Path

from project_inspector import ProjectInspector


class ProjectInspectorTest(unittest.TestCase):
    def test_detects_flutter_project_and_git_state(self):
        with tempfile.TemporaryDirectory() as directory:
            project = Path(directory)
            (project / "pubspec.yaml").write_text(
                "name: sample\n",
                encoding="utf-8",
            )
            (project / "lib").mkdir()
            (project / "lib" / "main.dart").write_text(
                "void main() {}\n",
                encoding="utf-8",
            )

            subprocess.run(
                ["git", "init", "-q", str(project)],
                check=True,
            )

            result = ProjectInspector.inspect(str(project))

            self.assertTrue(result["success"])
            self.assertEqual(result["project"]["technologies"], ["Flutter"])
            self.assertEqual(result["project"]["file_count"], 2)
            self.assertEqual(result["project"]["key_files"], ["pubspec.yaml"])
            self.assertTrue(result["project"]["git"]["available"])

    def test_rejects_missing_directory(self):
        result = ProjectInspector.inspect("/path/that/does/not/exist")

        self.assertFalse(result["success"])
