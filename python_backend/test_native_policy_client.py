import tempfile
import unittest
from pathlib import Path

from native_policy_client import NativePolicyClient


class NativePolicyClientTest(unittest.TestCase):
    def test_built_binary_exposes_health_and_policy(self):
        client = NativePolicyClient()

        health = client.health()
        policy = client.policy("OPEN_TERMINAL")

        self.assertTrue(health["success"])
        self.assertEqual(health["language"], "rust")
        self.assertEqual(policy["risk"], "routine_system")
        self.assertFalse(policy["requires_confirmation"])

    def test_missing_binary_fails_closed(self):
        with tempfile.TemporaryDirectory() as directory:
            client = NativePolicyClient(
                str(Path(directory) / "missing-native-core")
            )

            result = client.policy("OPEN_TERMINAL")

        self.assertFalse(result["success"])
        self.assertEqual(result["error"], "native_core_unavailable")
