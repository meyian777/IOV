from pathlib import Path
import os
import multiprocessing
import shutil
import subprocess
import tempfile
import wave


class LocalWhisperError(RuntimeError):
    pass


_WHISPER_DIAGNOSTIC_PREFIXES = (
    "_rsets_init:",
    "ggml_",
    "whisper_",
    "system_info:",
    "main:",
    "load_backend:",
)

_WHISPER_INTERNAL_ERROR_MARKERS = (
    "/opt/homebrew/",
    "/usr/local/",
    "libggml",
    "load_backend",
    "failed to initialize whisper context",
)


class LocalWhisperEngine:
    MAX_AUDIO_BYTES = 20 * 1024 * 1024
    MAX_AUDIO_SECONDS = 60

    def __init__(
        self,
        model_path: str | None = None,
        executable: str | None = None,
    ):
        backend_dir = Path(__file__).resolve().parent
        models_dir = backend_dir / "models"
        configured_model = (
            model_path
            or os.getenv("OSVOZ_WHISPER_MODEL")
            or str(self._preferred_local_model(models_dir))
        )
        configured_executable = (
            executable
            or os.getenv("OSVOZ_WHISPER_CLI")
            or "whisper-cli"
        )
        self.model_path = Path(configured_model).expanduser().resolve()
        self.executable = self._resolve_executable(configured_executable)
        self.no_gpu = os.getenv("OSVOZ_WHISPER_NO_GPU", "0") == "1"
        self.threads = self._configured_threads()

    @staticmethod
    def _preferred_local_model(models_dir: Path) -> Path:
        for filename in (
            "ggml-tiny.bin",
            "ggml-tiny.en.bin",
            "ggml-base.bin",
            "ggml-base.en.bin",
            "ggml-small.bin",
        ):
            candidate = models_dir / filename
            if candidate.is_file():
                return candidate
        return models_dir / "ggml-small.bin"

    @staticmethod
    def _configured_threads() -> int:
        configured = os.getenv("OSVOZ_WHISPER_THREADS")
        if configured:
            try:
                return max(1, min(int(configured), 8))
            except ValueError:
                pass
        cpu_count = multiprocessing.cpu_count() or 4
        return max(2, min(cpu_count, 6))

    @staticmethod
    def _resolve_executable(configured_executable: str) -> str:
        resolved = shutil.which(configured_executable)
        if resolved:
            return resolved
        homebrew_executable = Path("/opt/homebrew/bin") / configured_executable
        if homebrew_executable.is_file():
            return str(homebrew_executable)
        intel_homebrew_executable = Path("/usr/local/bin") / configured_executable
        if intel_homebrew_executable.is_file():
            return str(intel_homebrew_executable)
        return configured_executable

    def status(self) -> dict:
        executable_path = (
            self.executable
            if Path(self.executable).is_file()
            else shutil.which(self.executable)
        )
        model_ready = self.model_path.is_file()
        return {
            "success": bool(executable_path and model_ready),
            "engine": "whisper.cpp",
            "execution": "local_offline",
            "model": self.model_path.name,
            "model_ready": model_ready,
            "executable_ready": bool(executable_path),
            "multilingual": True,
            "gpu_acceleration": "disabled_safe_mode" if self.no_gpu else "enabled",
            "threads": self.threads,
        }

    def validate_wav(self, audio_path: str | Path) -> dict:
        path = Path(audio_path)
        if not path.is_file():
            raise LocalWhisperError("The audio file does not exist.")
        if path.stat().st_size > self.MAX_AUDIO_BYTES:
            raise LocalWhisperError("The audio file exceeds the 20 MB limit.")

        try:
            with wave.open(str(path), "rb") as audio:
                channels = audio.getnchannels()
                sample_width = audio.getsampwidth()
                sample_rate = audio.getframerate()
                frame_count = audio.getnframes()
        except (wave.Error, EOFError) as error:
            raise LocalWhisperError("The request is not a valid WAV file.") from error

        if sample_width != 2:
            raise LocalWhisperError("Audio must use 16-bit PCM samples.")
        if channels not in {1, 2}:
            raise LocalWhisperError("Audio must contain one or two channels.")
        if sample_rate <= 0:
            raise LocalWhisperError("The WAV sample rate is invalid.")

        duration_seconds = frame_count / sample_rate
        if duration_seconds > self.MAX_AUDIO_SECONDS and path.stat().st_size > 44:
            approximate_audio_bytes = path.stat().st_size - 44
            approximate_frames = approximate_audio_bytes / (channels * sample_width)
            duration_seconds = approximate_frames / sample_rate
        if duration_seconds > self.MAX_AUDIO_SECONDS:
            raise LocalWhisperError("Audio exceeds the 60 second limit.")
        return {
            "channels": channels,
            "sample_rate": sample_rate,
            "duration_seconds": round(duration_seconds, 3),
        }

    def transcribe(self, audio_path: str | Path, language: str = "es") -> dict:
        audio_details = self.validate_wav(audio_path)
        status = self.status()
        if not status["executable_ready"]:
            raise LocalWhisperError("whisper-cli is not installed.")
        if not status["model_ready"]:
            raise LocalWhisperError("The local Whisper model is not installed.")

        normalized_language = (language or "auto").lower().strip()
        if normalized_language not in {"auto", "es", "en"}:
            normalized_language = "auto"

        with tempfile.TemporaryDirectory(prefix="labvoice-whisper-") as directory:
            output_prefix = Path(directory) / "transcript"
            command = [
                self.executable,
                "-m",
                str(self.model_path),
                "-f",
                str(Path(audio_path).resolve()),
                "-l",
                normalized_language,
                "-otxt",
                "-of",
                str(output_prefix),
                "-np",
                "-nt",
                "-t",
                str(self.threads),
                "-bo",
                "1",
                "-bs",
                "1",
                "-nf",
            ]
            if self.no_gpu:
                command.append("-ng")
            try:
                completed = subprocess.run(
                    command,
                    capture_output=True,
                    text=True,
                    timeout=120,
                    check=False,
                )
            except subprocess.TimeoutExpired as error:
                raise LocalWhisperError(
                    "Local transcription exceeded the 120 second limit."
                ) from error

            transcript_path = output_prefix.with_suffix(".txt")
            transcript = (
                transcript_path.read_text(encoding="utf-8").strip()
                if transcript_path.is_file()
                else ""
            )
            if completed.returncode != 0:
                detail = self._stderr_error_summary(completed.stderr)
                raise LocalWhisperError(
                    detail or "No speech was detected in the audio."
                )
            if not transcript:
                raise LocalWhisperError("No speech was detected in the audio.")

        return {
            "success": True,
            "transcript": transcript,
            "language": normalized_language,
            "engine": status["engine"],
            "execution": status["execution"],
            "audio": audio_details,
        }

    @staticmethod
    def _stderr_error_summary(stderr: str) -> str:
        if LocalWhisperEngine._is_internal_whisper_failure(stderr):
            return "Local Whisper could not initialize."
        lines = []
        for raw_line in stderr.splitlines():
            line = raw_line.strip()
            if not line:
                continue
            if LocalWhisperEngine._is_diagnostic_line(line):
                continue
            lines.append(line)
        if not lines:
            return ""
        return "Local transcription failed: " + " ".join(lines)[-300:]

    @staticmethod
    def _is_diagnostic_line(line: str) -> bool:
        return line.startswith(_WHISPER_DIAGNOSTIC_PREFIXES)

    @staticmethod
    def _is_internal_whisper_failure(stderr: str) -> bool:
        normalized = stderr.lower()
        return any(marker in normalized for marker in _WHISPER_INTERNAL_ERROR_MARKERS)
