import subprocess


class ActionEngine:

    @staticmethod
    def execute(action: str):

        print(f"ACTION RECEIVED: {action}")

        if action == "OPEN_VSCODE":
            subprocess.Popen(
                ["open", "-a", "Visual Studio Code"]
            )

            return {
                "success": True,
                "message": "Visual Studio Code opened successfully."
            }

        if action == "OPEN_PROJECT":
            subprocess.Popen(
                [
                    "open",
                    "-a",
                    "Visual Studio Code",
                    "/Users/ianmey/Desktop/ian_labvoice/labvoice"
                ]
            )

            return {
                "success": True,
                "message": "LabVoice project opened successfully."
            }

        if action == "RUN_FLUTTER":

            subprocess.Popen(
                [
                    "osascript",
                    "-e",
                    '''
                    tell application "Terminal"
                        do script "cd ~/Desktop/ian_labvoice/labvoice && flutter run -d chrome"
                        activate
                    end tell
                    '''
                ]
            )

            return {
                "success": True,
                "message": "Launching Flutter in Chrome."
            }

        if action == "OPEN_TERMINAL":

            subprocess.Popen(
                ["open", "-a", "Terminal"]
            )

            return {
                "success": True,
                "message": "Terminal opened successfully."
            }

        if action == "LIST_FILES":

            files = subprocess.check_output(
                [
                    "ls",
                    "/Users/ianmey/Desktop/ian_labvoice"
                ]
            ).decode()

            return {
                "success": True,
                "message": files
            }

        return {
            "success": False,
            "message": f"Unknown action: {action}"
        }