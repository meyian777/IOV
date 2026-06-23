from pathlib import Path
import subprocess


class ActionEngine:
    VSCODE_BUNDLE_ID = "com.microsoft.VSCode"

    @staticmethod
    def execute(action: str, project_path: str):
        root = Path(project_path).expanduser().resolve()
        if action == "OPEN_VSCODE":
            return ActionEngine._open_vscode()

        if action == "OPEN_PROJECT":
            return ActionEngine._open_project_in_vscode(root)

        if action == "RUN_FLUTTER":
            flutter_root = ActionEngine._find_flutter_project(root)
            if flutter_root is None:
                return {
                    "success": False,
                    "message": "No Flutter project was found.",
                }
            subprocess.Popen(
                [
                    "osascript",
                    "-e",
                    f'''
                    tell application "Terminal"
                        do script "cd {flutter_root} && flutter run -d chrome"
                        activate
                    end tell
                    ''',
                ]
            )

            return {
                "success": True,
                "message": "Launching Flutter in Chrome.",
            }

        if action == "OPEN_TERMINAL":
            subprocess.Popen(["open", "-a", "Terminal"])

            return {
                "success": True,
                "message": "Terminal opened successfully.",
            }

        if action == "LIST_FILES":
            files = subprocess.check_output(
                ["ls", str(root)]
            ).decode()

            return {
                "success": True,
                "message": files,
            }

        return {
            "success": False,
            "message": f"Unknown action: {action}",
        }

    @staticmethod
    def _find_flutter_project(root: Path):
        if (root / "pubspec.yaml").is_file():
            return root
        return next(
            (
                path.parent
                for path in root.rglob("pubspec.yaml")
                if ".dart_tool" not in path.parts and "build" not in path.parts
            ),
            None,
        )

    @staticmethod
    def _open_vscode() -> dict:
        if ActionEngine._is_vscode_running():
            subprocess.Popen(
                [
                    "osascript",
                    "-e",
                    (
                        f'tell application id "{ActionEngine.VSCODE_BUNDLE_ID}" '
                        "to activate"
                    ),
                ]
            )
            return {
                "success": True,
                "message": (
                    "Visual Studio Code was already open and is now active."
                ),
                "reused_existing_window": True,
            }

        subprocess.Popen(
            ["open", "-b", ActionEngine.VSCODE_BUNDLE_ID]
        )
        return {
            "success": True,
            "message": "Visual Studio Code opened successfully.",
            "reused_existing_window": False,
        }

    @staticmethod
    def _open_project_in_vscode(root: Path) -> dict:
        vscode_cli = ActionEngine._find_vscode_cli()
        if vscode_cli is not None:
            subprocess.Popen(
                [
                    str(vscode_cli),
                    "--reuse-window",
                    str(root),
                ]
            )
            return {
                "success": True,
                "message": (
                    "LabVoice project opened in the existing Visual Studio "
                    "Code window."
                ),
                "reused_existing_window": True,
            }

        subprocess.Popen(
            [
                "open",
                "-b",
                ActionEngine.VSCODE_BUNDLE_ID,
                str(root),
            ]
        )
        return {
            "success": True,
            "message": "LabVoice project opened successfully.",
            "reused_existing_window": ActionEngine._is_vscode_running(),
        }

    @staticmethod
    def _is_vscode_running() -> bool:
        result = subprocess.run(
            [
                "osascript",
                "-e",
                (
                    f'application id "{ActionEngine.VSCODE_BUNDLE_ID}" '
                    "is running"
                ),
            ],
            capture_output=True,
            text=True,
            check=False,
        )
        return result.returncode == 0 and result.stdout.strip() == "true"

    @staticmethod
    def _find_vscode_cli() -> Path | None:
        candidates = (
            Path(
                "/Applications/Visual Studio Code.app/Contents/Resources/"
                "app/bin/code"
            ),
            Path.home()
            / "Applications/Visual Studio Code.app/Contents/Resources/app/bin/code",
        )
        for candidate in candidates:
            if candidate.is_file():
                return candidate

        volumes = Path("/Volumes")
        if volumes.is_dir():
            for candidate in volumes.glob(
                "*/Visual Studio Code.app/Contents/Resources/app/bin/code"
            ):
                if candidate.is_file():
                    return candidate
        return None
