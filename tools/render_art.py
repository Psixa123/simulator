"""Renders the game icon, thumbnails, gamepass/product badges and the Shop's card pieces to PNG with headless Chrome.

Usage:  python tools/render_art.py                  (render everything)
        python tools/render_art.py icon             (only names containing "icon")
        python tools/render_art.py icon thumbnail   (the game icon and the three thumbnails)
        python tools/render_art.py ads              (the Ads Manager image creatives, assets/ads)
        python tools/render_art.py badges           (the Roblox badge icons, assets/badges, + build/badges checks)
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

# Roblox badge icons (src/shared/Config/Badges.luau, docs/BADGES.md): badges3d.html puts each badge's 3D medal and hero
# (assets/source/badges3d, tools/icons/render_icons.py --set badges) on a sunburst -> assets/badges/<Key>.png
BADGES = ["Welcome", "FirstCatch", "RareCatch", "StormChaser", "Zone_Thunder", "Zone_Dunes", "Zone_Frost", "Zone_Volcano",
          "Zone_Sky", "FirstHatch", "LegendaryPet", "GoldenPet", "RainbowPet", "ClimateShift", "MegaStorm", "StormChampion",
          "Millionaire", "SecretPet"]
BADGE_REACH = 230  # px at 512: Roblox crops badge icons to a circle; the medal and its art must stay inside this radius

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
JOBS += [(f"badges/{name}.png", "badges3d.html", f"?id={name}", 512, 512) for name in BADGES]


def find_browser():
    for path in BROWSERS:
        if path and os.path.exists(path):
            return path
    raise SystemExit("Could not find Chrome or Edge to render the artwork.")


def render(browser, output, page, query, width, height, target=None):
    source = SOURCE / page
    if not source.exists():
        print(f"  skip {output} (missing {page})")
        return
    target = target or OUT / output
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
    if target == OUT / output:
        print(f"  {output}  ({width}x{height})")


def badge_checks(browser):
    """build/badges: each badge without its background (to measure how far the medal and its art reach from the
    centre; Roblox crops badge icons to a circle) and a contact sheet of the badges at 150 px, circle-cropped as
    Roblox shows them, on a light and a dark row."""
    from PIL import Image, ImageDraw, ImageFont

    build = ROOT / "build" / "badges"
    (build / "nobg").mkdir(parents=True, exist_ok=True)
    problems = []
    for name in BADGES:
        target = build / "nobg" / f"{name}.png"
        render(browser, f"badges/{name}.png", "badges3d.html", f"?id={name}&bg=0", 512, 512, target)
        alpha = Image.open(target).convert("RGBA").getchannel("A")
        reach = 0.0
        pixels = alpha.load()
        for y in range(0, 512, 2):
            for x in range(0, 512, 2):
                if pixels[x, y] > 128:
                    reach = max(reach, ((x - 255.5) ** 2 + (y - 255.5) ** 2) ** 0.5)
        if reach > BADGE_REACH:
            problems.append(f"{name}: art reaches {reach:.0f} px from the centre (limit {BADGE_REACH})")
    cell, pad, label = 150, 22, 24
    cols = 6
    rows = (len(BADGES) + cols - 1) // cols
    width = cols * (cell + pad) + pad
    band = rows * (cell + label + pad) + pad
    sheet = Image.new("RGB", (width, 2 * band + 60), (234, 243, 255))
    draw = ImageDraw.Draw(sheet)
    draw.rectangle((0, 60 + band, width, 60 + 2 * band), fill=(25, 27, 31))
    try:
        font = ImageFont.truetype(str(SOURCE / "fonts" / "FredokaOne-Regular.ttf"), 14)
        title = ImageFont.truetype(str(SOURCE / "fonts" / "FredokaOne-Regular.ttf"), 26)
    except OSError:
        font = title = ImageFont.load_default()
    draw.text((width / 2, 32), "Storm Catcher Simulator - badges (150 px, circle-cropped)", font=title,
              fill=(35, 48, 102), anchor="mm")
    mask = Image.new("L", (cell * 4, cell * 4), 0)
    ImageDraw.Draw(mask).ellipse((0, 0, cell * 4 - 1, cell * 4 - 1), fill=255)
    mask = mask.resize((cell, cell), Image.LANCZOS)
    for i, name in enumerate(BADGES):
        icon = Image.open(OUT / "badges" / f"{name}.png").convert("RGBA").resize((cell, cell), Image.LANCZOS)
        icon.putalpha(Image.composite(icon.getchannel("A"), Image.new("L", (cell, cell), 0), mask))
        r, c = divmod(i, cols)
        for row_band, ink in ((0, (35, 48, 102)), (1, (230, 234, 245))):
            x, y = pad + c * (cell + pad), 60 + row_band * band + pad + r * (cell + label + pad)
            sheet.paste(icon, (x, y), icon)
            draw.text((x + cell / 2, y + cell + 12), name, font=font, fill=ink, anchor="mm")
    sheet.save(build / "contact_sheet.png", optimize=True)
    print(f"  build/badges/contact_sheet.png  ({len(BADGES)} badges)")
    for problem in problems:
        print("  ! " + problem)
    return not problems


def main():
    wanted = sys.argv[1:]
    browser = find_browser()
    print("Rendering with", browser)
    badges = False
    for output, page, query, width, height in JOBS:
        if wanted and not any(word.lower() in output.lower() for word in wanted):
            continue
        render(browser, output, page, query, width, height)
        badges = badges or output.startswith("badges/")
    if badges and all((OUT / "badges" / f"{name}.png").exists() for name in BADGES) and not badge_checks(browser):
        sys.exit("badge art outside the circle Roblox shows")


if __name__ == "__main__":
    main()
