import unittest

from editor_context_store import EditorContextStore


class EditorContextStoreTest(unittest.TestCase):
    def test_starts_disconnected(self):
        self.assertFalse(EditorContextStore().get()["connected"])

    def test_update_bounds_editor_content(self):
        store = EditorContextStore()
        result = store.update(
            {
                "workspace_roots": ["/workspace"],
                "workspace_name": "OSvoz",
                "workspace_files": ["main.dart"],
                "active_file": "/workspace/main.dart",
                "language_id": "dart",
                "document_version": 3,
                "document_hash": "abc123",
                "document_text": "a" * 100_100,
                "selected_text": "b" * 20_100,
                "cursor_line": 12,
                "cursor_character": 4,
                "selection_start_line": 11,
                "selection_start_character": 2,
                "selection_end_line": 12,
                "selection_end_character": 8,
                "visible_start_line": 7,
                "visible_end_line": 18,
                "diagnostics": [
                    {
                        "severity": 0,
                        "message": "Example diagnostic",
                        "source": "test",
                        "code": "E001",
                        "start_line": 12,
                        "start_character": 4,
                        "end_line": 12,
                        "end_character": 8,
                    }
                ],
            }
        )

        self.assertTrue(result["connected"])
        self.assertEqual(result["workspace_name"], "OSvoz")
        self.assertEqual(result["language_id"], "dart")
        self.assertEqual(result["document_version"], 3)
        self.assertEqual(result["document_hash"], "abc123")
        self.assertEqual(result["selection_start_line"], 11)
        self.assertEqual(result["visible_end_line"], 18)
        self.assertEqual(result["diagnostics"][0]["message"], "Example diagnostic")
        self.assertEqual(len(result["document_text"]), 100_000)
        self.assertEqual(len(result["selected_text"]), 20_000)
        self.assertIsNotNone(result["updated_at"])

    def test_prompt_context_contains_active_editor_state(self):
        store = EditorContextStore()
        context = store.update(
            {
                "active_file": "/workspace/lib/main.dart",
                "relative_file": "lib/main.dart",
                "language_id": "dart",
                "document_version": 7,
                "document_hash": "hash",
                "document_text": "void main() {}",
                "selected_text": "main",
                "diagnostics": [{"message": "Lint says hello", "start_line": 0}],
            }
        )

        prompt = store.prompt_context(context)

        self.assertIn("VS Code bridge: connected", prompt)
        self.assertIn("lib/main.dart", prompt)
        self.assertIn("Document version: 7", prompt)
        self.assertIn("Document hash: hash", prompt)
        self.assertIn("Lint says hello", prompt)
        self.assertIn("void main() {}", prompt)
