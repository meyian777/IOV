import unittest

from workflow_orchestrator import WorkflowOrchestrator


class WorkflowOrchestratorTest(unittest.TestCase):
    def test_plans_project_inspection_as_fast_read_only_workflow(self):
        result = WorkflowOrchestrator.plan("OSvoz analiza el proyecto")

        self.assertTrue(result["success"])
        self.assertEqual(result["intent"], "inspect_project")
        self.assertEqual(result["risk"], "read_only")
        self.assertFalse(result["requires_confirmation"])
        self.assertTrue(result["state_policy"]["memory_required"])
        self.assertTrue(result["state_policy"]["audit_required"])
        self.assertEqual(
            [step["id"] for step in result["steps"]],
            ["understand", "inspect", "remember"],
        )

    def test_plans_python_execution_with_confirmation_and_audit(self):
        result = WorkflowOrchestrator.plan("OSvoz ejecuta script Python")

        self.assertEqual(result["intent"], "run_python_script")
        self.assertEqual(result["risk"], "process_execution")
        self.assertTrue(result["requires_confirmation"])
        self.assertIn(
            "audit",
            [step["id"] for step in result["steps"]],
        )

    def test_conversation_stays_read_only(self):
        result = WorkflowOrchestrator.plan("Explícame qué es un closure")

        self.assertEqual(result["intent"], "conversation")
        self.assertEqual(result["risk"], "read_only")
        self.assertFalse(result["requires_confirmation"])
        self.assertFalse(result["state_policy"]["rollback_required"])


if __name__ == "__main__":
    unittest.main()
