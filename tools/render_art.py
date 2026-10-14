"""Renders the game icon, thumbnails and gamepass/product icons to PNG with headless Chrome.

Usage:  python tools/render_art.py            (render everything)
        python tools/render_art.py icon       (only names containing "icon")
Sources live in assets/source (plain HTML + SVG), output goes to assets/.
"""

import glob
import os
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = ROOT / "assets" / "source"
OUT = ROOT / "assets"

BROWSERS = [
    os.environ.get("CHROME_PATH", ""),
    r"C:\Program Files\Google\Chrome\Application\chrome.exe",
    r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
    r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
    r"C:\Program Files\Microsoft\Edge\Application\msedge.exe",
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/usr/bin/google-chrome",
    "/usr/bin/chromium",
    "/usr/bin/chromium-browser",
    # Playwright's headless shell renders the exact window size on Linux
    *glob.glob("/opt/pw-browsers/chromium_headless_shell-*/chrome-linux/headless_shell"),
    "/opt/pw-browsers/chromium",
]

PASSES = ["VIP", "DoubleVolts", "DoubleEnergy", "AutoCatch", "RemoteSell", "MegaTank", "LuckyHatcher", "TripleHatch", "AutoHatch", "PetSlots", "StormRadar"]
PRODUCTS = ["VoltsSmall", "VoltsMedium", "VoltsLarge", "VoltsHuge", "EnergyBoost", "LuckBoost", "SummonMegaStorm"]

UI_ICONS = ["Pets", "Eggs", "Shop", "Upgrades", "Rewards", "Teleport", "ClimateShift", "Settings", "Index", "Volts", "Energy",
            "Power", "Range", "Speed", "Tank", "Luck", "Gift", "Daily", "Codes", "MegaStorm", "Radar", "Sell", "Close", "Lock",
            "Check", "Star", "Rainbow"]

# (output path, page, query string, width, height)
JOBS = [
    ("icon.png", "icon.html", "?size=512", 512, 512),
    ("icon_1024.png", "icon.html", "?size=1024", 1024, 1024),
    ("thumbnails/thumbnail_1.png", "thumbnail1.html", "", 1920, 1080),
    ("thumbnails/thumbnail_2.png", "thumbnail2.html", "", 1920, 1080),
    ("thumbnails/thumbnail_3.png", "thumbnail3.html", "", 1920, 1080),
]
JOBS += [(f"gamepasses/{name}.png", "badge.html", f"?id={name}", 512, 512) for name in PASSES]
JOBS += [(f"products/{name}.png", "badge.html", f"?id={name}", 512, 512) for name in PRODUCTS]
JOBS += [(f"ui/{name}.png", "ui_icons.html", f"?id={name}", 256, 256) for name in UI_ICONS]


def find_browser():
    for path in BROWSERS:
        if path and os.path.exists(path):
            return path
    raise SystemExit("Could not find Chrome or Edge to render the artwork.")


def render(browser, output, page, query, width, height):
    source = SOURCE / page
    if not source.exists():
        print(f"  skip {output} (missing {page})")
        return
    target = OUT / output
    target.parent.mkdir(parents=True, exist_ok=True)
    command = [
        browser,
        "--headless=new",
        "--no-sandbox",
        "--disable-gpu",
        "--hide-scrollbars",
        "--force-device-scale-factor=1",
        "--default-background-color=00000000",
        "--virtual-time-budget=6000",
        f"--window-size={width},{height}",
        f"--screenshot={target}",
        source.as_uri() + query,
    ]
    subprocess.run(command, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=120)
    print(f"  {output}  ({width}x{height})")


def main():
    wanted = sys.argv[1:]
    browser = find_browser()
    print("Rendering with", browser)
    for output, page, query, width, height in JOBS:
        if wanted and not any(word.lower() in output.lower() for word in wanted):
            continue
        render(browser, output, page, query, width, height)


if __name__ == "__main__":
    main()
