import unittest
from unittest.mock import patch

from ml_provider_evaluator import MLProviderEvaluator


class MLProviderEvaluatorTest(unittest.TestCase):
    def test_evaluator_reports_latency_and_stability(self):
        with patch(
            "ml_provider_evaluator.MLProviderManager.status",
            return_value={
                "provider": {"framework": "fake", "embedding_dimensions": 8},
                "frameworks": {"success": True},
            },
        ), patch(
            "ml_provider_evaluator.MLProviderManager.audio_embedding",
            return_value={
                "success": True,
                "embedding": [1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
            },
        ):
            result = MLProviderEvaluator.run(iterations=10, feature_count=8)

        self.assertTrue(result["success"])
        self.assertEqual(result["stress"]["failure_count"], 0)
        self.assertTrue(result["stress"]["deterministic_repeated_input"])
        self.assertIn("p95", result["latency_ms"])


if __name__ == "__main__":
    unittest.main()
