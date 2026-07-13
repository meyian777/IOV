from dataclasses import asdict, dataclass
import json
import math
import subprocess
import sys
from typing import Protocol

from ml_framework_registry import MLFrameworkRegistry


MAX_FEATURES = 512
PROVIDER_SMOKE_TEST_TIMEOUT_SECONDS = 15


@dataclass(frozen=True)
class MLProviderStatus:
    name: str
    framework: str
    available: bool
    embedding_dimensions: int
    mode: str

    def to_dict(self) -> dict:
        return asdict(self)


class MLProvider(Protocol):
    def status(self) -> MLProviderStatus: ...

    def audio_embedding(self, features: list[float]) -> dict: ...


class DisabledMLProvider:
    def status(self) -> MLProviderStatus:
        return MLProviderStatus(
            name="disabled",
            framework="none",
            available=False,
            embedding_dimensions=0,
            mode="no_ml_framework_available",
        )

    def audio_embedding(self, features: list[float]) -> dict:
        return {
            "success": False,
            "error": "ml_provider_unavailable",
            "message": "No ML provider is available.",
        }


class PyTorchMLProvider:
    EMBEDDING_DIMENSIONS = 8

    def __init__(self, torch_module=None):
        self._torch = torch_module

    def status(self) -> MLProviderStatus:
        return MLProviderStatus(
            name="pytorch_audio_embeddings",
            framework="pytorch",
            available=True,
            embedding_dimensions=self.EMBEDDING_DIMENSIONS,
            mode="framework_backed_feature_embedding",
        )

    def audio_embedding(self, features: list[float]) -> dict:
        torch = self._torch
        if torch is None:
            try:
                import torch as imported_torch
            except ImportError:
                return DisabledMLProvider().audio_embedding(features)
            torch = imported_torch

        if torch is None:
            return DisabledMLProvider().audio_embedding(features)

        safe_features = _validate_features(features)
        tensor = torch.tensor(safe_features, dtype=torch.float32)
        if tensor.numel() < self.EMBEDDING_DIMENSIONS:
            padding = torch.zeros(self.EMBEDDING_DIMENSIONS - tensor.numel())
            tensor = torch.cat((tensor, padding))
        with torch.no_grad():
            chunks = torch.tensor_split(tensor, self.EMBEDDING_DIMENSIONS)
            pooled = torch.stack([chunk.mean() for chunk in chunks])
            norm = torch.linalg.vector_norm(pooled)
            if float(norm) > 0:
                pooled = pooled / norm
        return {
            "success": True,
            "provider": self.status().to_dict(),
            "embedding": [round(float(value), 8) for value in pooled.tolist()],
        }


class TensorFlowMLProvider:
    def status(self) -> MLProviderStatus:
        return MLProviderStatus(
            name="tensorflow_audio_embeddings",
            framework="tensorflow",
            available=False,
            embedding_dimensions=0,
            mode="provider_stub_waiting_for_supported_python_runtime",
        )

    def audio_embedding(self, features: list[float]) -> dict:
        return {
            "success": False,
            "error": "tensorflow_provider_not_enabled",
            "message": "TensorFlow provider is not enabled in this Python runtime.",
        }


class MLProviderManager:
    @staticmethod
    def default_provider() -> MLProvider:
        frameworks = MLFrameworkRegistry.inspect()["frameworks"]
        if frameworks["pytorch"]["installed"] and ProviderSmokeTest.pytorch()["success"]:
            return PyTorchMLProvider()
        if frameworks["tensorflow"]["installed"]:
            return TensorFlowMLProvider()
        return DisabledMLProvider()

    @staticmethod
    def status() -> dict:
        provider = MLProviderManager.default_provider()
        return {
            "success": True,
            "provider": provider.status().to_dict(),
            "frameworks": MLFrameworkRegistry.inspect(),
            "operational": {
                "pytorch": ProviderSmokeTest.pytorch(),
            },
        }

    @staticmethod
    def audio_embedding(features: list[float]) -> dict:
        provider = MLProviderManager.default_provider()
        return provider.audio_embedding(features)


def _validate_features(features: list[float]) -> list[float]:
    if not features:
        raise ValueError("At least one audio feature is required.")
    if len(features) > MAX_FEATURES:
        raise ValueError(f"At most {MAX_FEATURES} audio features are allowed.")
    safe_features = []
    for feature in features:
        value = float(feature)
        if not math.isfinite(value):
            raise ValueError("Audio features must be finite numbers.")
        safe_features.append(value)
    return safe_features


class ProviderSmokeTest:
    _pytorch_result: dict | None = None

    @classmethod
    def pytorch(cls) -> dict:
        if cls._pytorch_result is not None:
            return cls._pytorch_result
        started = __import__("time").perf_counter()
        try:
            completed = subprocess.run(
                [
                    sys.executable,
                    "-c",
                    (
                        "import json, time\n"
                        "started=time.perf_counter()\n"
                        "import torch\n"
                        "tensor=torch.tensor([1.0, 2.0, 3.0])\n"
                        "value=float(torch.linalg.vector_norm(tensor))\n"
                        "print(json.dumps({"
                        "'success': True, "
                        "'version': torch.__version__, "
                        "'result': value, "
                        "'import_ms': round((time.perf_counter()-started)*1000, 4)"
                        "}))"
                    ),
                ],
                capture_output=True,
                text=True,
                timeout=PROVIDER_SMOKE_TEST_TIMEOUT_SECONDS,
                check=False,
            )
        except subprocess.TimeoutExpired:
            cls._pytorch_result = {
                "success": False,
                "error": "provider_import_timeout",
                "timeout_seconds": PROVIDER_SMOKE_TEST_TIMEOUT_SECONDS,
                "duration_ms": round((__import__("time").perf_counter() - started) * 1000, 4),
            }
            return cls._pytorch_result

        if completed.returncode != 0:
            cls._pytorch_result = {
                "success": False,
                "error": "provider_import_failed",
                "exit_code": completed.returncode,
                "stderr": completed.stderr[-2000:],
            }
            return cls._pytorch_result
        try:
            cls._pytorch_result = json.loads(completed.stdout)
        except json.JSONDecodeError:
            cls._pytorch_result = {
                "success": False,
                "error": "provider_invalid_smoke_response",
                "stdout": completed.stdout[-2000:],
            }
        return cls._pytorch_result
