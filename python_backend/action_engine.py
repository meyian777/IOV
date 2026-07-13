from pathlib import Path
import re
import subprocess
from urllib import request
from urllib.parse import quote, urlencode


class ActionEngine:
    VSCODE_BUNDLE_ID = "com.microsoft.VSCode"

    @staticmethod
    def execute(action: str, project_path: str):
        root = Path(project_path).expanduser().resolve()
        try:
            if action == "OPEN_VSCODE":
                return ActionEngine._open_project_in_vscode(root)

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
                subprocess.Popen(["open", "-a", "Terminal", str(root)])

                return {
                    "success": True,
                    "message": "Terminal opened in the OSvoz project.",
                }

            if action == "LIST_FILES":
                files = subprocess.check_output(
                    ["ls", str(root)]
                ).decode()

                return {
                    "success": True,
                    "message": files,
                }
        except OSError as error:
            return {
                "success": False,
                "error": "system_action_failed",
                "message": f"Could not complete {action}: {error}",
            }

        return {
            "success": False,
            "message": f"Unknown action: {action}",
        }

    @staticmethod
    def open_url(url: str) -> dict:
        try:
            subprocess.Popen(["open", url])
        except OSError as error:
            return {
                "success": False,
                "error": "system_action_failed",
                "message": f"Could not open browser: {error}",
            }
        return {
            "success": True,
            "message": "Browser opened.",
            "url": url,
        }

    @staticmethod
    def open_youtube_music(query: str, auto_skip_ads: bool = False) -> dict:
        cleaned_query = " ".join(query.split()).strip() or "music"
        search_url = "https://www.youtube.com/results?" + urlencode(
            {"search_query": cleaned_query}
        )
        watch_url = ActionEngine._resolve_youtube_watch_url(cleaned_query)
        url = watch_url or search_url
        chrome_path = Path("/Applications/Google Chrome.app")
        if not chrome_path.exists():
            opened = ActionEngine.open_url(url)
            return {
                **opened,
                "message": (
                    "YouTube search opened. Chrome automation is unavailable."
                ),
                "query": cleaned_query,
                "play_attempted": False,
            }

        if watch_url:
            try:
                subprocess.Popen(["open", "-a", "Google Chrome", watch_url])
                if auto_skip_ads:
                    ActionEngine._start_youtube_ad_monitor()
            except OSError as error:
                return {
                    "success": False,
                    "error": "system_action_failed",
                    "message": f"Could not open YouTube video: {error}",
                    "query": cleaned_query,
                    "play_attempted": False,
                }
            return {
                "success": True,
                "message": "YouTube video opened directly.",
                "url": watch_url,
                "query": cleaned_query,
                "play_attempted": True,
                "direct_video": True,
                "auto_skip_ads": auto_skip_ads,
            }

        ad_monitor = (
            ActionEngine._youtube_ad_monitor_javascript()
            if auto_skip_ads
            else ""
        )
        javascript = """
        (() => {
          __OSVOZ_AD_MONITOR__
          const isPlayableVideo = (link) => {
            const href = link.getAttribute('href') || '';
            const title = (link.getAttribute('title') || link.textContent || '').trim();
            const container = link.closest('ytd-video-renderer,ytd-rich-item-renderer');
            if (!href.startsWith('/watch')) return false;
            if (!title) return false;
            if (container && container.innerText.toLowerCase().includes('sponsored')) return false;
            return true;
          };
          let attempts = 0;
          const timer = setInterval(() => {
            attempts += 1;
            const links = [...document.querySelectorAll('a#video-title,a.yt-simple-endpoint[href^="/watch"]')];
            const video = links.find(isPlayableVideo);
            if (video) {
              clearInterval(timer);
              video.scrollIntoView({block: 'center'});
              video.click();
            }
            if (attempts >= 18) clearInterval(timer);
          }, 500);
        })();
        """.replace("__OSVOZ_AD_MONITOR__", ad_monitor)
        script = f'''
        tell application "Google Chrome"
            activate
            if (count of windows) = 0 then make new window
            set URL of active tab of front window to "{ActionEngine._escape_applescript(url)}"
            delay 1.0
            tell active tab of front window to execute javascript "{ActionEngine._escape_applescript(javascript)}"
        end tell
        '''
        try:
            subprocess.Popen(["osascript", "-e", script])
        except OSError as error:
            opened = ActionEngine.open_url(url)
            return {
                **opened,
                "message": f"YouTube search opened after automation failed: {error}",
                "query": cleaned_query,
                "play_attempted": False,
            }
        return {
            "success": True,
            "message": "YouTube opened and first result playback was requested.",
            "url": url,
            "query": cleaned_query,
            "play_attempted": True,
            "direct_video": False,
            "auto_skip_ads": auto_skip_ads,
        }

    @staticmethod
    def open_music(
        query: str,
        platform: str,
        auto_skip_ads: bool = False,
    ) -> dict:
        cleaned_query = " ".join(query.split()).strip()
        if not cleaned_query:
            return {
                "success": False,
                "error": "missing_music_query",
                "message": "No music query was provided.",
            }

        if platform == "youtube":
            return ActionEngine.open_youtube_music(
                cleaned_query,
                auto_skip_ads=auto_skip_ads,
            )

        if platform == "spotify":
            app_url = "spotify:search:" + quote(cleaned_query)
            web_url = "https://open.spotify.com/search/" + quote(cleaned_query)
            label = "Spotify"
        elif platform == "apple_music":
            encoded = urlencode({"term": cleaned_query})
            app_url = "music://music.apple.com/search?" + encoded
            web_url = "https://music.apple.com/search?" + encoded
            label = "Apple Music"
        else:
            return {
                "success": False,
                "error": "unsupported_music_platform",
                "message": f"Unsupported music platform: {platform}",
            }

        try:
            subprocess.Popen(["open", app_url])
        except OSError:
            subprocess.Popen(["open", web_url])
            return {
                "success": True,
                "message": f"{label} web search opened.",
                "url": web_url,
                "query": cleaned_query,
                "platform": platform,
                "play_attempted": False,
                "app_deeplink": False,
            }
        return {
            "success": True,
            "message": f"{label} search opened.",
            "url": app_url,
            "query": cleaned_query,
            "platform": platform,
            "play_attempted": False,
            "app_deeplink": True,
        }

    @staticmethod
    def skip_youtube_ad() -> dict:
        chrome_path = Path("/Applications/Google Chrome.app")
        if not chrome_path.exists():
            return {
                "success": False,
                "error": "chrome_unavailable",
                "message": "Google Chrome is required for YouTube ad control.",
            }

        javascript = """
        (() => {
          const selectors = [
            '.ytp-ad-skip-button',
            '.ytp-ad-skip-button-modern',
            'button.ytp-ad-skip-button',
            'button.ytp-ad-skip-button-modern'
          ];
          const visible = (el) => {
            if (!el) return false;
            const rect = el.getBoundingClientRect();
            const style = window.getComputedStyle(el);
            return rect.width > 0 && rect.height > 0 &&
              style.visibility !== 'hidden' && style.display !== 'none';
          };
          const button = selectors
            .flatMap((selector) => [...document.querySelectorAll(selector)])
            .find(visible);
          if (button) {
            button.click();
            return 'skipped';
          }
          return 'not_available';
        })();
        """
        script = f'''
        tell application "Google Chrome"
            if (count of windows) = 0 then return "no_window"
            tell active tab of front window to execute javascript "{ActionEngine._escape_applescript(javascript)}"
        end tell
        '''
        try:
            result = subprocess.check_output(
                ["osascript", "-e", script],
                text=True,
                stderr=subprocess.STDOUT,
                timeout=3,
            ).strip()
        except (OSError, subprocess.SubprocessError) as error:
            error_text = ActionEngine._subprocess_error_text(error)
            fallback = ActionEngine._skip_youtube_ad_with_accessibility()
            if fallback.get("skipped"):
                return fallback
            if "Executing JavaScript through AppleScript is turned off" in error_text:
                return {
                    "success": True,
                    "message": (
                        "Chrome blocks YouTube automation until View > "
                        "Developer > Allow JavaScript from Apple Events is enabled."
                    ),
                    "skipped": False,
                    "state": "chrome_javascript_events_disabled",
                    "fallback_state": fallback.get("state"),
                }
            return {
                "success": True,
                "message": (
                    "YouTube ad control is not available in the current "
                    f"Chrome tab: {error_text}"
                ),
                "skipped": False,
                "state": "control_unavailable",
                "fallback_state": fallback.get("state"),
            }

        if result == "skipped":
            return {
                "success": True,
                "message": "YouTube skip ad button clicked.",
                "skipped": True,
            }
        return {
            "success": True,
            "message": "No official YouTube skip ad button is visible yet.",
            "skipped": False,
            "state": result or "not_available",
        }

    @staticmethod
    def _youtube_ad_monitor_javascript() -> str:
        return """
          if (!window.__osvozSkipAdMonitor) {
            window.__osvozSkipAdMonitor = setInterval(() => {
              const selectors = [
                '.ytp-ad-skip-button',
                '.ytp-ad-skip-button-modern',
                'button.ytp-ad-skip-button',
                'button.ytp-ad-skip-button-modern'
              ];
              const visible = (el) => {
                if (!el) return false;
                const rect = el.getBoundingClientRect();
                const style = window.getComputedStyle(el);
                return rect.width > 0 && rect.height > 0 &&
                  style.visibility !== 'hidden' && style.display !== 'none';
              };
              const button = selectors
                .flatMap((selector) => [...document.querySelectorAll(selector)])
                .find(visible);
              if (button) button.click();
            }, 500);
            setTimeout(() => {
              if (window.__osvozSkipAdMonitor) {
                clearInterval(window.__osvozSkipAdMonitor);
                window.__osvozSkipAdMonitor = null;
              }
            }, 180000);
          }
        """

    @staticmethod
    def _start_youtube_ad_monitor() -> None:
        javascript = f"(() => {{ {ActionEngine._youtube_ad_monitor_javascript()} }})();"
        script = f'''
        tell application "Google Chrome"
            activate
            delay 1.5
            tell active tab of front window to execute javascript "{ActionEngine._escape_applescript(javascript)}"
        end tell
        '''
        subprocess.Popen(["osascript", "-e", script])

    @staticmethod
    def _skip_youtube_ad_with_accessibility() -> dict:
        script = '''
        tell application "System Events"
            if not (exists process "Google Chrome") then return "chrome_missing"
            tell process "Google Chrome"
                set frontmost to true
                set skipNeedles to {"Skip", "skip", "Omitir", "omitir", "Saltar", "saltar"}
                try
                    set controls to entire contents of window 1
                    repeat with controlItem in controls
                        repeat with needle in skipNeedles
                            try
                                if ((name of controlItem) as text) contains needle then
                                    click controlItem
                                    return "skipped"
                                end if
                            end try
                            try
                                if ((description of controlItem) as text) contains needle then
                                    click controlItem
                                    return "skipped"
                                end if
                            end try
                            try
                                if ((value of controlItem) as text) contains needle then
                                    click controlItem
                                    return "skipped"
                                end if
                            end try
                        end repeat
                    end repeat
                end try
                try
                    set skipButtons to (every UI element of window 1 whose name contains "Skip")
                    if (count of skipButtons) > 0 then
                        click item 1 of skipButtons
                        return "skipped"
                    end if
                end try
            end tell
        end tell
        return "not_available"
        '''
        try:
            result = subprocess.check_output(
                ["osascript", "-e", script],
                text=True,
                stderr=subprocess.STDOUT,
                timeout=8,
            ).strip()
        except subprocess.TimeoutExpired:
            return {
                "success": True,
                "message": (
                    "macOS Accessibility scan timed out before finding an "
                    "official YouTube skip button."
                ),
                "skipped": False,
                "state": "accessibility_timeout",
            }
        except (OSError, subprocess.SubprocessError):
            return {
                "success": True,
                "message": (
                    "macOS Accessibility permission is required to click the "
                    "YouTube skip button without JavaScript control."
                ),
                "skipped": False,
                "state": "accessibility_unavailable",
            }
        if "not allowed assistive access" in result.lower():
            return {
                "success": True,
                "message": (
                    "macOS Accessibility permission is required to click the "
                    "YouTube skip button without JavaScript control."
                ),
                "skipped": False,
                "state": "accessibility_unavailable",
            }
        if result == "skipped":
            return {
                "success": True,
                "message": "YouTube skip ad button clicked.",
                "skipped": True,
                "method": "accessibility",
            }
        return {
            "success": True,
            "message": "No official YouTube skip ad button is visible yet.",
            "skipped": False,
            "state": result or "not_available",
        }

    @staticmethod
    def _subprocess_error_text(error: Exception) -> str:
        output = getattr(error, "output", None)
        if output:
            return str(output).strip()
        return str(error)

    @staticmethod
    def _resolve_youtube_watch_url(query: str) -> str | None:
        url = "https://www.youtube.com/results?" + urlencode(
            {"search_query": query}
        )
        try:
            req = request.Request(
                url,
                headers={
                    "User-Agent": (
                        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                        "AppleWebKit/537.36 (KHTML, like Gecko) "
                        "Chrome/120.0 Safari/537.36"
                    )
                },
            )
            with request.urlopen(req, timeout=2.5) as response:
                html = response.read(900_000).decode("utf-8", errors="ignore")
        except Exception:
            return None

        seen = set()
        for video_id in re.findall(r'"videoId":"([A-Za-z0-9_-]{11})"', html):
            if video_id in seen:
                continue
            seen.add(video_id)
            return "https://www.youtube.com/watch?" + urlencode(
                {"v": video_id, "autoplay": "1"}
            )
        return None

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
    def _escape_applescript(value: str) -> str:
        return value.replace("\\", "\\\\").replace('"', '\\"')

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
                    "OSvoz project opened in the existing Visual Studio "
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
            "message": "OSvoz project opened successfully.",
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
