import unittest

from fastapi.testclient import TestClient

from capability_registry import CapabilityRegistry
from main import app


class CapabilityRegistryTest(unittest.TestCase):
    def test_registry_exposes_voice_authorized_operator_model(self):
        status = CapabilityRegistry.status()
        capability_ids = {
            capability["id"] for capability in status["capabilities"]
        }

        self.assertEqual(
            status["model"],
            "voice_authorized_operator_capabilities",
        )
        self.assertIn("system.open_app", capability_ids)
        self.assertIn("project.read", capability_ids)
        self.assertIn("code.apply_edit", capability_ids)
        self.assertIn("project.run_diagnostics", capability_ids)
        self.assertIn("browser.control", capability_ids)
        self.assertIn("api.connect_external", capability_ids)
        self.assertIn("critical.transfer_or_credentials", capability_ids)

    def test_operator_capabilities_endpoint_groups_by_security_level(self):
        response = TestClient(app).get("/core/operator-capabilities")

        self.assertEqual(response.status_code, 200)
        body = response.json()
        self.assertTrue(body["success"])
        self.assertIn("1", body["by_security_level"])
        self.assertIn("2", body["by_security_level"])
        self.assertIn("3", body["by_security_level"])

        critical = next(
            capability
            for capability in body["capabilities"]
            if capability["id"] == "critical.transfer_or_credentials"
        )
        self.assertFalse(critical["voice_access"]["confirm_by_voice"])
        self.assertTrue(critical["voice_access"]["silent_factor_required"])


if __name__ == "__main__":
    unittest.main()
