import tempfile
import unittest
from pathlib import Path

from file_access_layer import FileAccessError, FileAccessLayer


class FileAccessLayerTest(unittest.TestCase):
    def test_lists_project_files_without_ignored_directories(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "lib").mkdir()
            (root / "lib" / "main.dart").write_text("void main() {}\n")
            (root / ".git").mkdir()
            (root / ".git" / "config").write_text("secret")

            result = FileAccessLayer(str(root)).list_files("lib")

            self.assertTrue(result["success"])
            self.assertEqual(result["files"][0]["path"], "lib/main.dart")

    def test_reads_text_file_inside_project(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "README.md").write_text("# OSvoz\n", encoding="utf-8")

            result = FileAccessLayer(str(root)).read_file("README.md")

            self.assertEqual(result["content"], "# OSvoz\n")
            self.assertEqual(result["permission"], "read_only_project_scope")

    def test_blocks_path_traversal(self):
        with tempfile.TemporaryDirectory() as directory:
            layer = FileAccessLayer(directory)

            with self.assertRaises(FileAccessError) as context:
                layer.read_file("../outside.txt")

            self.assertEqual(context.exception.code, "path_outside_project")

    def test_blocks_large_files(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "large.txt").write_text(
                "x" * (FileAccessLayer.MAX_READ_BYTES + 1),
                encoding="utf-8",
            )

            with self.assertRaises(FileAccessError) as context:
                FileAccessLayer(str(root)).read_file("large.txt")

            self.assertEqual(context.exception.code, "file_too_large")

    def test_hides_sensitive_files_from_listing(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / ".env.save").write_text("OPENAI_API_KEY=secret")
            (root / "README.md").write_text("# Public\n")

            result = FileAccessLayer(str(root)).list_files()

            paths = [file["path"] for file in result["files"]]
            self.assertIn("README.md", paths)
            self.assertNotIn(".env.save", paths)

    def test_blocks_sensitive_file_reads(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "service.key").write_text("secret")

            with self.assertRaises(FileAccessError) as context:
                FileAccessLayer(str(root)).read_file("service.key")

            self.assertEqual(context.exception.code, "sensitive_file_blocked")

    def test_allows_safe_dotfile_gitignore(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / ".gitignore").write_text("build/\n")

            result = FileAccessLayer(str(root)).read_file(".gitignore")

            self.assertEqual(result["content"], "build/\n")


if __name__ == "__main__":
    unittest.main()
