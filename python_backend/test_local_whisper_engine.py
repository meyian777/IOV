import tempfile
import unittest
import wave
from pathlib import Path
from unittest.mock import patch

from local_whisper_engine import LocalWhisperEngine, LocalWhisperError


def create_wav(path: Path, seconds: float = 0.1):
    sample_rate = 16000
    with wave.open(str(path), "wb") as audio:
        audio.setnchannels(1)
        audio.setsampwidth(2)
        audio.setframerate(sample_rate)
        audio.writeframes(b"\x00\x00" * int(sample_rate * seconds))


class LocalWhisperEngineTest(unittest.TestCase):
    def test_prefers_fastest_available_local_model(self):
        with tempfile.TemporaryDirectory() as directory:
            models = Path(directory)
            (models / "ggml-small.bin").touch()
            (models / "ggml-base.bin").touch()

            self.assertEqual(
                LocalWhisperEngine._preferred_local_model(models).name,
                "ggml-base.bin",
            )

            (models / "ggml-tiny.bin").touch()
            self.assertEqual(
                LocalWhisperEngine._preferred_local_model(models).name,
                "ggml-tiny.bin",
            )

    def test_validates_pcm_wav(self):
        with tempfile.TemporaryDirectory() as directory:
            audio_path = Path(directory) / "sample.wav"
            create_wav(audio_path)
            result = LocalWhisperEngine().validate_wav(audio_path)

        self.assertEqual(result["sample_rate"], 16000)
        self.assertEqual(result["channels"], 1)

    def test_rejects_non_wav_content(self):
        with tempfile.TemporaryDirectory() as directory:
            audio_path = Path(directory) / "sample.wav"
            audio_path.write_bytes(b"not-a-wav")
            with self.assertRaises(LocalWhisperError):
                LocalWhisperEngine().validate_wav(audio_path)

    @patch("local_whisper_engine.subprocess.run")
    @patch("local_whisper_engine.shutil.which", return_value="/usr/bin/whisper-cli")
    def test_transcribes_using_local_cli(self, _which, run):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            model_path = root / "model.bin"
            model_path.touch()
            audio_path = root / "sample.wav"
            create_wav(audio_path)

            def complete(command, **_kwargs):
                output_prefix = Path(command[command.index("-of") + 1])
                output_prefix.with_suffix(".txt").write_text(
                    "OSvoz abre Visual Studio Code",
                    encoding="utf-8",
                )
                return type("Completed", (), {"returncode": 0, "stderr": ""})()

            run.side_effect = complete
            result = LocalWhisperEngine(
                model_path=str(model_path),
                executable="whisper-cli",
            ).transcribe(audio_path, "es")

        self.assertEqual(
            result["transcript"],
            "OSvoz abre Visual Studio Code",
        )
        self.assertEqual(result["execution"], "local_offline")
        command = run.call_args.args[0]
        self.assertIn("-t", command)
        self.assertGreaterEqual(int(command[command.index("-t") + 1]), 1)

    @patch("local_whisper_engine.subprocess.run")
    @patch("local_whisper_engine.shutil.which", return_value="/usr/bin/whisper-cli")
    def test_does_not_expose_metal_diagnostics_as_user_error(self, _which, run):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            model_path = root / "model.bin"
            model_path.touch()
            audio_path = root / "sample.wav"
            create_wav(audio_path)

            run.return_value = type(
                "Completed",
                (),
                {
                    "returncode": 1,
                    "stderr": "\n".join(
                        [
                            "_rsets_init: creating a residency set collection",
                            "ggml_metal_device_init: GPU name: MTL0",
                            "ggml_metal_device_init: has unified memory = true",
                        ]
                    ),
                },
            )()

            with self.assertRaises(LocalWhisperError) as context:
                LocalWhisperEngine(
                    model_path=str(model_path),
                    executable="whisper-cli",
                ).transcribe(audio_path, "es")

        self.assertEqual(
            str(context.exception),
            "No speech was detected in the audio.",
        )

    @patch("local_whisper_engine.subprocess.run")
    @patch("local_whisper_engine.shutil.which", return_value="/usr/bin/whisper-cli")
    def test_does_not_expose_homebrew_backend_paths_as_user_error(self, _which, run):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            model_path = root / "model.bin"
            model_path.touch()
            audio_path = root / "sample.wav"
            create_wav(audio_path)

            run.return_value = type(
                "Completed",
                (),
                {
                    "returncode": 1,
                    "stderr": "\n".join(
                        [
                            "load_backend: loaded BLAS backend from /opt/homebrew/Cellar/ggml/0.15.2/libexec/libggml-blas.so",
                            "load_backend: loaded MTL backend from /opt/homebrew/Cellar/ggml/0.15.2/libexec/libggml-metal.so",
                            "error: failed to initialize whisper context",
                        ]
                    ),
                },
            )()

            with self.assertRaises(LocalWhisperError) as context:
                LocalWhisperEngine(
                    model_path=str(model_path),
                    executable="whisper-cli",
                ).transcribe(audio_path, "es")

        self.assertEqual(
            str(context.exception),
            "Local Whisper could not initialize.",
        )
