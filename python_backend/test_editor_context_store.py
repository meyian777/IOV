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
                "workspace_files": ["main.dart"],
                "active_file": "/workspace/main.dart",
                "language_id": "dart",
                "document_text": "a" * 100_100,
                "selected_text": "b" * 20_100,
                "cursor_line": 12,
                "cursor_character": 4,
            }
        )

        self.assertTrue(result["connected"])
        self.assertEqual(result["language_id"], "dart")
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
                "document_text": "void main() {}",
                "selected_text": "main",
            }
        )

        prompt = store.prompt_context(context)

        self.assertIn("VS Code bridge: connected", prompt)
        self.assertIn("lib/main.dart", prompt)
        self.assertIn("void main() {}", prompt)
