from pathlib import Path
import subprocess


class ActionEngine:
    @staticmethod
    def execute(action: str, project_path: str):
        root = Path(project_path).expanduser().resolve()
        if action == "OPEN_VSCODE":
            subprocess.Popen(["open", "-a", "Visual Studio Code"])

            return {
                "success": True,
                "message": "Visual Studio Code opened successfully.",
            }

        if action == "OPEN_PROJECT":
            subprocess.Popen(
                [
                    "open",
                    "-a",
                    "Visual Studio Code",
                    str(root),
                ]
            )

            return {
                "success": True,
                "message": "LabVoice project opened successfully.",
            }

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
