import unittest
import math
from unittest.mock import patch

from ml_provider import (
    DisabledMLProvider,
    MLProviderManager,
    ProviderSmokeTest,
    PyTorchMLProvider,
)


class MLProviderTest(unittest.TestCase):
    def test_pytorch_provider_returns_stable_embedding_shape(self):
        provider = PyTorchMLProvider(FakeTorch())

        result = provider.audio_embedding([0.1, 0.2, 0.3, 0.4])

        self.assertTrue(result["success"])
        self.assertEqual(result["provider"]["framework"], "pytorch")
        self.assertEqual(len(result["embedding"]), 8)

    def test_pytorch_provider_is_deterministic_for_same_features(self):
        provider = PyTorchMLProvider(FakeTorch())
        features = [0.1, -0.2, 0.3, -0.4, 0.5]

        first = provider.audio_embedding(features)["embedding"]
        second = provider.audio_embedding(features)["embedding"]

        self.assertEqual(first, second)

    def test_pytorch_provider_returns_finite_normalized_embedding(self):
        provider = PyTorchMLProvider(FakeTorch())

        embedding = provider.audio_embedding([0.1, 0.2, 0.3, 0.4])["embedding"]
        norm = math.sqrt(sum(value * value for value in embedding))

        self.assertTrue(all(math.isfinite(value) for value in embedding))
        self.assertLessEqual(norm, 1.000001)

    def test_disabled_provider_fails_cleanly(self):
        result = DisabledMLProvider().audio_embedding([0.1])

        self.assertFalse(result["success"])
        self.assertEqual(result["error"], "ml_provider_unavailable")

    def test_manager_exposes_provider_status(self):
        with patch.object(
            ProviderSmokeTest,
            "pytorch",
            return_value={"success": False, "error": "timeout"},
        ):
            result = MLProviderManager.status()

        self.assertTrue(result["success"])
        self.assertIn("provider", result)
        self.assertIn("frameworks", result)
        self.assertIn("operational", result)

    def test_rejects_invalid_features(self):
        with self.assertRaises(ValueError):
            PyTorchMLProvider(FakeTorch()).audio_embedding([float("nan")])


class FakeTensor:
    def __init__(self, values):
        self.values = [float(value) for value in values]

    def numel(self):
        return len(self.values)

    def mean(self):
        if not self.values:
            return 0.0
        return sum(self.values) / len(self.values)

    def tolist(self):
        return list(self.values)

    def __truediv__(self, scalar):
        return FakeTensor([value / scalar for value in self.values])


class FakeNoGrad:
    def __enter__(self):
        return None

    def __exit__(self, exc_type, exc, traceback):
        return False


class FakeLinalg:
    @staticmethod
    def vector_norm(tensor):
        return math.sqrt(sum(value * value for value in tensor.values))


class FakeTorch:
    float32 = "float32"
    linalg = FakeLinalg()

    @staticmethod
    def tensor(values, dtype=None):
        return FakeTensor(values)

    @staticmethod
    def zeros(length):
        return FakeTensor([0.0 for _ in range(length)])

    @staticmethod
    def cat(tensors):
        values = []
        for tensor in tensors:
            values.extend(tensor.values)
        return FakeTensor(values)

    @staticmethod
    def tensor_split(tensor, chunks):
        size = len(tensor.values)
        result = []
        for index in range(chunks):
            start = round(index * size / chunks)
            end = round((index + 1) * size / chunks)
            result.append(FakeTensor(tensor.values[start:end]))
        return result

    @staticmethod
    def stack(values):
        return FakeTensor(values)

    @staticmethod
    def no_grad():
        return FakeNoGrad()


if __name__ == "__main__":
    unittest.main()
