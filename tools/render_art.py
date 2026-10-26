"""Renders the game icon, thumbnails, gamepass/product badges and the Shop's card pieces to PNG with headless Chrome.

Usage:  python tools/render_art.py                  (render everything)
        python tools/render_art.py icon             (only names containing "icon")
        python tools/render_art.py icon thumbnail   (the game icon and the three thumbnails)
        python tools/render_art.py ads              (the Ads Manager image creatives, assets/ads)
Sources live in assets/source (plain HTML + SVG), output goes to assets/. The game icon and thumbnails
(icon.html, thumbnail1..3.html) lay out 3D renders of the real game content from assets/source/branding,
which tools/branding/capture.py makes.
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

# Gamepass and product badges: store3d.html puts each item's 3D hero render (assets/source/store3d/Store_<Key>.png,
# tools/icons/render_icons.py --set store) on a sunburst badge with candy labels (tools/icons/README.md, "Store icons")
PASSES = ["VIP", "DoubleVolts", "DoubleEnergy", "AutoCatch", "RemoteSell", "MegaTank", "InfiniteTank", "LuckyHatcher",
          "TripleHatch", "AutoHatch", "PetSlots", "StormRadar"]
PRODUCTS = ["VoltsSmall", "VoltsMedium", "VoltsLarge", "VoltsHuge", "EnergyBoost", "LuckBoost", "SummonMegaStorm", "AuroraGryphon"]
# Transparent pieces the in-game Shop draws its cards with (badge.html RAW; uploaded by upload_store_icons.py)
SHOP_ART = [("ShopRays", 1024), ("Robux", 128)]

# Roblox Ads Manager image creatives (16:9), one per hook: ads.html?id=<key> -> assets/ads/ad_0N_<key>.png
ADS = ["catch", "hatch", "mega", "islands", "tiers", "legendary", "scene", "title"]

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
JOBS += [(f"gamepasses/{name}.png", "store3d.html", f"?id={name}", 512, 512) for name in PASSES]
JOBS += [(f"products/{name}.png", "store3d.html", f"?id={name}", 512, 512) for name in PRODUCTS]
JOBS += [(f"ui/{name}.png", "ui_icons.html", f"?id={name}", 256, 256) for name in UI_ICONS]
JOBS += [(f"ui/shop/{name}.png", "badge.html", f"?id={name}&size={size}", size, size) for name, size in SHOP_ART]
JOBS += [(f"ads/ad_{index:02d}_{key}.png", "ads.html", f"?id={key}", 1920, 1080) for index, key in enumerate(ADS, 1)]


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
