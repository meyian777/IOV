import unittest
from pathlib import Path
from unittest.mock import patch

from fastapi.testclient import TestClient

from main import (
    PROJECT_PATH,
    app,
    editor_context_store,
    editor_operation_store,
)


class EditorEditApiTest(unittest.TestCase):
    def setUp(self):
        editor_context_store._context = editor_context_store._empty_context()
        editor_operation_store._operations = {}
        editor_operation_store._latest_applied_id = None

    def test_prepare_requires_connected_editor(self):
        response = TestClient(app).post(
            "/editor/edit/prepare",
            json={"instruction": "Cambia el título", "language": "es"},
        )

        self.assertEqual(response.status_code, 409)
        self.assertEqual(
            response.json()["detail"]["code"],
            "editor_not_connected",
        )

    @patch("main.CodeEditPlanner.create")
    def test_prepare_preview_confirm_validate_and_undo(self, create):
        create.return_value = {
            "summary": "Renamed the function",
            "replacement": "void start() {}\n",
        }
        client = TestClient(app)
        active_file = str(Path(PROJECT_PATH).resolve() / "main.dart")
        client.post(
            "/editor/context",
            json={
                "workspace_roots": ["/workspace"],
                "workspace_files": ["main.dart"],
                "active_file": active_file,
                "relative_file": "main.dart",
                "language_id": "dart",
                "document_text": "void main() {}\n",
            },
        )

        prepared = client.post(
            "/editor/edit/prepare",
            json={"instruction": "Cambia main por start", "language": "es"},
        )

        self.assertEqual(prepared.status_code, 200)
        operation_id = prepared.json()["operation_id"]
        self.assertIn("-void main()", prepared.json()["diff"])
        self.assertIn("+void start()", prepared.json()["diff"])

        too_early = client.post(f"/editor/edit/{operation_id}/confirm")
        self.assertEqual(too_early.status_code, 409)

        previewed = client.post(
            f"/editor/operations/{operation_id}/status",
            json={"status": "previewed"},
        )
        self.assertEqual(previewed.status_code, 200)

        confirmed = client.post(f"/editor/edit/{operation_id}/confirm")
        self.assertEqual(confirmed.status_code, 200)
        self.assertEqual(confirmed.json()["status"], "approved")
        status = client.get(f"/editor/edit/{operation_id}")
        self.assertEqual(
            status.json()["operation"]["relative_file"],
            "main.dart",
        )
        self.assertNotIn("replacement", status.json()["operation"])

        with patch("main.StagedEditValidator.run") as run:
            run.return_value = {
                "success": True,
                "summary": {"passed": 3, "failed": 0},
                "checks": [],
            }
            validated = client.post(
                f"/editor/edit/{operation_id}/validate"
            )
        self.assertEqual(validated.status_code, 200)
        self.assertTrue(validated.json()["success"])

        client.post(
            f"/editor/operations/{operation_id}/status",
            json={"status": "applied"},
        )
        undo = client.post("/editor/edit/undo")
        self.assertEqual(undo.status_code, 200)
        self.assertEqual(undo.json()["operation_id"], operation_id)

    @patch("main.CodeEditPlanner.create")
    def test_extension_cannot_apply_before_voice_confirmation(self, create):
        create.return_value = {
            "summary": "Renamed the function",
            "replacement": "void start() {}\n",
        }
        client = TestClient(app)
        active_file = str(Path(PROJECT_PATH).resolve() / "main.dart")
        client.post(
            "/editor/context",
            json={
                "workspace_roots": ["/workspace"],
                "workspace_files": ["main.dart"],
                "active_file": active_file,
                "relative_file": "main.dart",
                "language_id": "dart",
                "document_text": "void main() {}\n",
            },
        )
        prepared = client.post(
            "/editor/edit/prepare",
            json={"instruction": "Cambia main por start", "language": "es"},
        )
        operation_id = prepared.json()["operation_id"]
        client.post(
            f"/editor/operations/{operation_id}/status",
            json={"status": "previewed"},
        )

        applied = client.post(
            f"/editor/operations/{operation_id}/status",
            json={"status": "applied"},
        )

        self.assertEqual(applied.status_code, 422)
        self.assertEqual(
            applied.json()["detail"]["code"],
            "invalid_operation_status",
        )

    def test_prepare_batch_requires_confirmation_before_apply(self):
        client = TestClient(app)
        root = Path(PROJECT_PATH).resolve()
        client.post(
            "/editor/context",
            json={
                "workspace_roots": [str(root)],
                "workspace_files": ["a.dart", "b.dart"],
                "active_file": str(root / "a.dart"),
                "relative_file": "a.dart",
                "language_id": "dart",
                "document_text": "void a() {}\n",
            },
        )

        prepared = client.post(
            "/editor/edit/prepare-batch",
            json={
                "instruction": "Renombra funciones relacionadas",
                "language": "es",
                "files": [
                    {
                        "active_file": str(root / "a.dart"),
                        "relative_file": "a.dart",
                        "language_id": "dart",
                        "original": "void a() {}\n",
                        "replacement": "void startA() {}\n",
                        "summary": "Rename a",
                    },
                    {
                        "active_file": str(root / "b.dart"),
                        "relative_file": "b.dart",
                        "language_id": "dart",
                        "original": "void b() {}\n",
                        "replacement": "void startB() {}\n",
                        "summary": "Rename b",
                    },
                ],
            },
        )

        self.assertEqual(prepared.status_code, 200)
        self.assertEqual(prepared.json()["file_count"], 2)
        operation_id = prepared.json()["operation_id"]
        next_operation = client.get("/editor/operations/next").json()["operation"]
        self.assertEqual(next_operation["type"], "replace_multiple_documents")
        self.assertEqual(len(next_operation["files"]), 2)

        applied = client.post(
            f"/editor/operations/{operation_id}/status",
            json={"status": "applied"},
        )
        self.assertEqual(applied.status_code, 422)

        previewed = client.post(
            f"/editor/operations/{operation_id}/status",
            json={"status": "previewed"},
        )
        self.assertEqual(previewed.status_code, 200)
        confirmed = client.post(f"/editor/edit/{operation_id}/confirm")
        self.assertEqual(confirmed.status_code, 200)
