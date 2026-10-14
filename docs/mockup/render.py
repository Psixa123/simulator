#!/usr/bin/env python3
"""Renders the Sky Lab UI mockup (docs/ui_mockup.html) to PNG with headless Chromium.

Usage (from the repo root):
    python docs/mockup/render.py            -> docs/ui_mockup.png (HUD) and docs/ui_components.png (kit)
    python docs/mockup/render.py hud        -> only the HUD
    python docs/mockup/render.py components -> only the component sheet

Both renders are 1280x720 at device scale 1, so every pixel in the PNG is one Roblox offset pixel on a
1280x720 screen. The page loads Fredoka One from assets/source/fonts and icons from assets/ui; pet art
for the tiles lives in docs/mockup/pets (hero renders from tools/pets).
"""

import glob
import os
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
PAGE = ROOT / "docs" / "ui_mockup.html"
JOBS = {
    "hud": ("hud", ROOT / "docs" / "ui_mockup.png"),
    "components": ("components", ROOT / "docs" / "ui_components.png"),
}

BROWSERS = [
    os.environ.get("CHROME_PATH", ""),
    *sorted(glob.glob("/opt/pw-browsers/chromium_headless_shell-*/chrome-linux/headless_shell"), reverse=True),
    *sorted(glob.glob(os.path.expanduser("~/.cache/ms-playwright/chromium_headless_shell-*/chrome-linux/headless_shell")), reverse=True),
    "/usr/bin/chromium",
    "/usr/bin/chromium-browser",
    "/usr/bin/google-chrome",
    r"C:\Program Files\Google\Chrome\Application\chrome.exe",
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
]


def find_browser():
    for path in BROWSERS:
        if path and os.path.exists(path):
            return path
    raise SystemExit("Could not find Chrome/Chromium (set CHROME_PATH).")


def render(browser, view, target):
    command = [
        browser,
        "--headless=new",
        "--no-sandbox",
        "--disable-gpu",
        "--hide-scrollbars",
        "--allow-file-access-from-files",
        "--force-device-scale-factor=1",
        "--virtual-time-budget=8000",
        "--window-size=1280,720",
        f"--screenshot={target}",
        PAGE.as_uri() + f"?view={view}",
    ]
    subprocess.run(command, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=120)
    print(f"  {target.relative_to(ROOT)}")


def main():
    wanted = sys.argv[1:] or list(JOBS)
    browser = find_browser()
    for name in wanted:
        view, target = JOBS[name]
        render(browser, view, target)


if __name__ == "__main__":
    main()
