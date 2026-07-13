import unittest
from unittest.mock import patch

from ml_framework_registry import MLFrameworkRegistry


class MLFrameworkRegistryTest(unittest.TestCase):
    @patch("ml_framework_registry.metadata.version")
    @patch("ml_framework_registry.sys.version_info", (3, 12, 0))
    @patch("ml_framework_registry.util.find_spec")
    def test_reports_available_tensorflow_provider(self, find_spec, version):
        find_spec.side_effect = lambda module: object() if module == "tensorflow" else None
        version.return_value = "2.99.0"

        result = MLFrameworkRegistry.inspect()

        self.assertTrue(result["success"])
        self.assertTrue(result["ready"])
        self.assertEqual(result["default_provider"], "tensorflow")
        self.assertEqual(result["recommended_provider"], "pytorch")
        self.assertEqual(
            result["frameworks"]["tensorflow"]["status"],
            "available",
        )
        self.assertEqual(result["frameworks"]["tensorflow"]["version"], "2.99.0")
        self.assertFalse(result["frameworks"]["pytorch"]["installed"])

    @patch("ml_framework_registry.sys.version_info", (3, 14, 0))
    @patch("ml_framework_registry.util.find_spec", return_value=None)
    def test_reports_optional_boundary_when_frameworks_are_missing(self, find_spec):
        result = MLFrameworkRegistry.inspect()

        self.assertTrue(result["success"])
        self.assertFalse(result["ready"])
        self.assertIsNone(result["default_provider"])
        self.assertEqual(result["recommended_provider"], "pytorch")
        self.assertEqual(
            result["frameworks"]["pytorch"]["status"],
            "not_installed_optional",
        )
        self.assertEqual(
            result["frameworks"]["tensorflow"]["status"],
            "python_version_unsupported",
        )
        self.assertIsNone(result["frameworks"]["tensorflow"]["install_command"])


if __name__ == "__main__":
    unittest.main()
