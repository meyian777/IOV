from dataclasses import asdict, dataclass
from importlib import metadata, util
import sys


@dataclass(frozen=True)
class MLFramework:
    name: str
    package: str
    module: str
    installed: bool
    version: str | None
    role: str
    status: str
    compatible_with_python: bool
    install_command: str | None

    def to_dict(self) -> dict:
        return asdict(self)


class MLFrameworkRegistry:
    FRAMEWORKS = (
        {
            "name": "tensorflow",
            "package": "tensorflow",
            "module": "tensorflow",
            "role": "speaker_embedding_and_local_model_boundary",
            "python_min": (3, 10),
            "python_max": (3, 13),
            "install_command": "pip install tensorflow",
        },
        {
            "name": "pytorch",
            "package": "torch",
            "module": "torch",
            "role": "audio_embedding_and_experimental_model_boundary",
            "python_min": (3, 10),
            "python_max": (3, 14),
            "install_command": "pip install torch",
        },
    )

    @classmethod
    def inspect(cls) -> dict:
        frameworks = [cls._inspect_framework(config) for config in cls.FRAMEWORKS]
        installed = [framework for framework in frameworks if framework.installed]
        return {
            "success": True,
            "mode": "optional_provider_boundary",
            "ready": bool(installed),
            "default_provider": installed[0].name if installed else None,
            "recommended_provider": cls._recommended_provider(frameworks),
            "frameworks": {
                framework.name: framework.to_dict()
                for framework in frameworks
            },
            "message": (
                f"ML provider ready: {installed[0].name}."
                if installed
                else "TensorFlow and PyTorch are optional and not installed."
            ),
        }

    @staticmethod
    def _inspect_framework(config: dict) -> MLFramework:
        installed = util.find_spec(config["module"]) is not None
        compatible = MLFrameworkRegistry._python_compatible(
            config["python_min"],
            config["python_max"],
        )
        version = None
        if installed:
            try:
                version = metadata.version(config["package"])
            except metadata.PackageNotFoundError:
                version = "unknown"
        if installed:
            status = "available"
        elif compatible:
            status = "not_installed_optional"
        else:
            status = "python_version_unsupported"
        return MLFramework(
            name=config["name"],
            package=config["package"],
            module=config["module"],
            installed=installed,
            version=version,
            role=config["role"],
            status=status,
            compatible_with_python=compatible,
            install_command=config["install_command"] if compatible else None,
        )

    @staticmethod
    def _python_compatible(minimum: tuple[int, int], maximum: tuple[int, int]) -> bool:
        current = sys.version_info[:2]
        return minimum <= current <= maximum

    @staticmethod
    def _recommended_provider(frameworks: list[MLFramework]) -> str | None:
        for preferred in ("pytorch", "tensorflow"):
            framework = next(item for item in frameworks if item.name == preferred)
            if framework.installed or framework.compatible_with_python:
                return framework.name
        return None
