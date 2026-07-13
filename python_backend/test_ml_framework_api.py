import unittest

from fastapi.testclient import TestClient

from main import app


class MLFrameworkApiTest(unittest.TestCase):
    def test_ml_framework_endpoint_reports_tensorflow_and_pytorch(self):
        response = TestClient(app).get("/ml/frameworks")

        self.assertEqual(response.status_code, 200)
        result = response.json()
        self.assertTrue(result["success"])
        self.assertIn("tensorflow", result["frameworks"])
        self.assertIn("pytorch", result["frameworks"])
        self.assertEqual(result["mode"], "optional_provider_boundary")


if __name__ == "__main__":
    unittest.main()
