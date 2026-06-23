import unittest

from editor_operation_store import EditorOperationStore


class EditorOperationStoreTest(unittest.TestCase):
    def test_operation_moves_from_preview_to_apply_and_undo(self):
        store = EditorOperationStore()
        operation = store.create(
            instruction="Rename it",
            active_file="/workspace/main.dart",
            relative_file="main.dart",
            language_id="dart",
            original="void main() {}",
            replacement="void start() {}",
            summary="Rename main",
            diff="- main\n+ start",
        )

        self.assertEqual(
            store.next_for_extension()["status"],
            "awaiting_preview",
        )
        store.update(operation["id"], "previewed")
        store.update(operation["id"], "approved")
        store.update(operation["id"], "applied")
        undo = store.request_undo()

        self.assertEqual(undo["status"], "undo_requested")
        self.assertEqual(undo["original"], "void main() {}")
