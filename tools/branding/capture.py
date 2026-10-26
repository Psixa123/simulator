#!/usr/bin/env python3
"""Captures the 3D renders the game page art (icon and thumbnails) is built from, all from real game content.

The icon and thumbnails are HTML pages in assets/source (icon.html, thumbnail1..3.html) that
tools/render_art.py turns into PNGs. They lay out pictures this script renders into assets/source/branding:

  pets/<PetId>[_<Tier>][_<View>].png   Stormlings from the real mesh pack (assets/models/StormlingPets.glb)
                                      drawn by tools/pets/viewer.html (Golden/Rainbow tiers like the game
                                      paints them), with a thick Ink sticker outline, cropped to the pet
  map/<shot>.jpg                      the real map (MapService) with real weather cells in every field and a
                                      Mega Storm in the arena (tools/branding/BrandingScene.luau), rendered by
                                      tools/preview_map.py
  studio/<Name>.png                   single models the game builds, from the same scene's "studio":
                                      Weather_<Type> (WeatherModels.Build), Egg_<EggId> (EggModels.Build) and
                                      MegaStorm_<Key> (WeatherModels.BuildMegaStorm), drawn on a transparent
                                      background by tools/branding/stage.html with the pets' look

Usage (from the repo root):
    python3 tools/branding/capture.py                 everything (~3 min)
    python3 tools/branding/capture.py pets            only some groups: pets, map (map shots + studio), studio
                                                      (studio only, from the last map run's build/branding/raw/map)
    python3 tools/branding/capture.py pets --pets AuroraGryphon,VoltWyrm --out build/branding/try
                                                      try other pets without touching assets/source
    python3 tools/branding/capture.py --all --out build/branding/all
                                                      every pet and every weather cell / egg / Mega Storm
then  python3 tools/render_art.py icon thumbnail      to rebuild the icon and the thumbnails, and
      python3 tools/branding/capture.py sheet          for build/branding/contact_sheet.png: the finished icon
                                                      and thumbnails big and at the sizes Roblox shows them
                                                      (icon 150/100/60 px, thumbnails 480 x 270)

Requirements: Python 3.9+ with numpy and Pillow, Chrome/Chromium (CHROME_PATH or Playwright's headless
shell), three.js (`npm install` in tools/pets and tools/preview) and, for the map, the `luau` command line
(on PATH or LUAU=path; see tools/preview_map.py).
"""

import argparse
import glob
import json
import os
import re
import subprocess
import sys
import threading
from concurrent.futures import ThreadPoolExecutor
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
HERE = ROOT / "tools" / "branding"
OUT = ROOT / "assets" / "source" / "branding"
WORK = ROOT / "build" / "branding"
PETS_LUAU = ROOT / "src" / "shared" / "Config" / "Pets.luau"

INK = (35, 48, 102)
SUPERSAMPLE = 2

# (pet id, tier, view, size in px): the pets the pages use. view: hero (3/4 from the left), three4 (3/4 from
# the right) or front. --all renders every pet of Pets.luau (hero view) for trying out other line-ups.
PETS = [
    ("AuroraGryphon", "Normal", "front", 1024),  # the icon
    ("AuroraGryphon", "Normal", "hero", 1024),
    *[(pet, "Normal", "hero", 640) for pet in (
        "BreezeKing", "ThunderPup", "PhoenixChick", "AuroraFox",  # thumbnail 1 (and 2)
        "Droplet", "Zappy", "CactusCub", "Icicle", "LavaPup", "Nebula", "Sunny", "VoltBat", "Scarab", "Moonbeam",
        "Ember", "InfernoDrake",  # thumbnail 2
        "Puffling", "Prism", "StormLord", "MirageDjinn", "YetiKing", "GalaxyGuardian",  # ads
    )],
    ("ThunderPup", "Golden", "hero", 640),
    ("ThunderPup", "Rainbow", "hero", 640),
    ("AuroraFox", "Rainbow", "hero", 640),
    *[(pet, "Normal", "three4", 640) for pet in (  # thumbnail 3: the Mega Storm exclusives
        "TempestTitan", "VoltWyrm", "FrostColossus", "CycloneDrake", "MaelstromSpirit", "RainbowRoc",
    )],
]

# Studio models (BrandingScene.luau buildStudio): name prefix -> (size in px, camera azimuth, elevation)
STUDIO = {
    "Weather_": (1024, -20, 12),
    "Egg_": (512, -25, 10),
    "MegaStorm_": (1024, -20, 6),
    "Gear_Vacuum": (1024, -100, 14),  # side view, nozzle to the left
    "Gear_Player": (1024, 125, 8),  # from behind on the left: the vacuum aims up and to the right
}
# The studio models the pages use (--all renders every one)
STUDIO_USED = {
    "Weather_StormCloud", "Weather_RainbowMist", "Weather_Starstorm", "Weather_CosmicVortex", "Weather_Thunderhead",
    "Weather_RainCloud", "Weather_Breeze",
    "Egg_MeadowEgg", "Egg_ThunderEgg", "Egg_DuneEgg", "Egg_FrostEgg", "Egg_MagmaEgg", "Egg_CosmicEgg",
    "Gear_Vacuum", "Gear_Player",
}
# BrandingScene.luau's studio slots
STUDIO_ORIGIN = (0, 3000, 9000)
STUDIO_STEP = 300

# Map shots (tools/preview_map.py --shot specs): name -> camera
MAP_SHOTS = {
    # thumbnail 1: the seven sky islands in a row, seen from behind the Storm Station
    "islands": "pos=-430,250,0 look=420,40,0 fov=46 light=hub fog=900,5200 size=2400x1350",
    # thumbnail 2: Sunny Plains around its egg incubator
    "plains": "target=150,10,0 az=125 el=16 dist=170 fov=50 light=1 size=2400x1350",
    # thumbnail 3: the Mega Storm (Cosmic Maelstrom) in the Storm Station arena, from low down
    "arena": "target=-112,75,0 az=235 el=-2 dist=135 fov=66 light=hub size=2400x1350",
    # ads: standing in Thunder Valley's field among the storm clouds
    "thunder_field": "pos=380,22,60 look=520,20,-10 fov=60 light=2 size=2400x1350",
    # ads: the whole chain of sky islands over the cloud sea, from the side
    "chain": "target=850,0,0 az=160 el=36 dist=1350 fov=40 light=hub fog=2000,8000 size=2400x1350",
}


# --------------------------------------------------------------------------------------- browser

def find_browser():
    candidates = [os.environ.get("CHROME_PATH", "")]
    candidates += sorted(glob.glob("/opt/pw-browsers/chromium_headless_shell-*/chrome-linux/headless_shell"), reverse=True)
    candidates += sorted(glob.glob(os.path.expanduser("~/.cache/ms-playwright/chromium_headless_shell-*/chrome-linux/headless_shell")),
                         reverse=True)
    candidates += ["/usr/bin/chromium", "/usr/bin/chromium-browser", "/usr/bin/google-chrome"]
    for candidate in candidates:
        if candidate and os.path.exists(candidate):
            return candidate
    sys.exit("Could not find Chrome/Chromium (set CHROME_PATH).")


class QuietHandler(SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass


def start_server():
    server = ThreadingHTTPServer(("127.0.0.1", 0), partial(QuietHandler, directory=str(ROOT)))
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server


def screenshot(browser, url, target, size):
    target.parent.mkdir(parents=True, exist_ok=True)
    command = [browser, "--headless=new", "--no-sandbox", "--use-angle=swiftshader", "--enable-unsafe-swiftshader",
               "--hide-scrollbars", "--force-device-scale-factor=1", "--default-background-color=00000000",
               "--virtual-time-budget=30000", f"--window-size={size},{size}", f"--screenshot={target}", url]
    subprocess.run(command, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=300)


def render_pages(jobs, workers=4):
    """jobs: (page path relative to the repo root + query, raw png, size) -> screenshots, in parallel."""
    browser = find_browser()
    server = start_server()
    port = server.server_address[1]
    try:
        with ThreadPoolExecutor(max_workers=workers) as pool:
            list(pool.map(lambda job: screenshot(browser, f"http://127.0.0.1:{port}/{job[0]}", job[1], job[2]), jobs))
    finally:
        server.shutdown()


# --------------------------------------------------------------------------------------- sticker finish

def disk_offsets(radius):
    r = int(np.ceil(radius))
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            distance = (dx * dx + dy * dy) ** 0.5
            weight = min(1.0, max(0.0, radius + 0.5 - distance))
            if weight > 0:
                yield dx, dy, weight


def dilate(alpha, radius):
    """Round, anti-aliased dilation of an alpha mask (float32, 0..1)."""
    pad = int(np.ceil(radius)) + 1
    padded = np.pad(alpha, pad)
    h, w = alpha.shape
    result = np.zeros_like(padded)
    for dx, dy, weight in disk_offsets(radius):
        shifted = padded[pad + dy:pad + dy + h, pad + dx:pad + dx + w] * weight
        np.maximum(result[pad:pad + h, pad:pad + w], shifted, out=result[pad:pad + h, pad:pad + w])
    return result[pad:pad + h, pad:pad + w]


def sticker(raw_path, target, size, outline):
    """Supersampled render -> `size` px, a thick Ink outline around the silhouette, cropped to it (+ margin)."""
    image = Image.open(raw_path).convert("RGBA").resize((size, size), Image.LANCZOS)
    rgba = np.asarray(image).astype(np.float32) / 255.0
    alpha = rgba[..., 3]
    ring = dilate(alpha, outline)
    ink = np.array(INK, dtype=np.float32) / 255.0
    # the render over an Ink silhouette (premultiplied "over")
    out_alpha = alpha + ring * (1 - alpha)
    out_rgb = (rgba[..., :3] * alpha[..., None] + ink * ring[..., None] * (1 - alpha[..., None]))
    out_rgb = np.where(out_alpha[..., None] > 0, out_rgb / np.maximum(out_alpha[..., None], 1e-6), 0)
    out = np.dstack([out_rgb, out_alpha])
    result = Image.fromarray(np.clip(out * 255 + 0.5, 0, 255).astype(np.uint8), "RGBA")
    box = result.getchannel("A").point(lambda a: 255 if a > 8 else 0).getbbox()
    if box:
        margin = int(size * 0.02)
        box = (max(0, box[0] - margin), max(0, box[1] - margin), min(size, box[2] + margin), min(size, box[3] + margin))
        result = result.crop(box)
    target.parent.mkdir(parents=True, exist_ok=True)
    result.save(target, optimize=True)
    return target


# --------------------------------------------------------------------------------------- groups

def rel(path):
    try:
        return path.relative_to(ROOT).as_posix()
    except ValueError:
        return str(path)


def pet_name(pet, tier, view):
    name = pet
    if tier != "Normal":
        name += f"_{tier}"
    if view != "hero":
        name += f"_{view}"
    return name


def all_pet_ids():
    """Every pet id of Pets.luau (the `Id = { Name = ...` lines of Pets.Pets)."""
    source = PETS_LUAU.read_text(encoding="utf-8")
    return re.findall(r"^\t(\w+) = \{ Name = ", source, flags=re.M)


def capture_pets(out_dir, only=None, everything=False):
    pets = PETS
    if only or everything:
        pets = [(pet, "Normal", "hero", 640) for pet in (only or all_pet_ids())]
    raw_dir = WORK / "raw" / "pets"
    jobs = []
    for pet, tier, view, size in pets:
        px = size * SUPERSAMPLE
        query = f"pet={pet}&view={view}&tier={tier}&size={px}"
        jobs.append((f"tools/pets/viewer.html?{query}", raw_dir / f"{pet_name(pet, tier, view)}.png", px))
    print(f"Rendering {len(jobs)} pets...")
    render_pages(jobs)
    for (pet, tier, view, size), (_, raw, _) in zip(pets, jobs):
        target = sticker(raw, out_dir / "pets" / f"{pet_name(pet, tier, view)}.png", size, outline=size * 0.014)
        print("  wrote", rel(target))


def capture_map(out_dir, everything=False):
    raw_dir = WORK / "raw" / "map"
    command = [sys.executable, str(ROOT / "tools" / "preview_map.py"), "--script", str(HERE / "BrandingScene.luau"),
               "--out", str(raw_dir)]
    for name, spec in MAP_SHOTS.items():
        command += ["--shot", f"{name} {spec}"]
    print("Rendering the map shots with tools/preview_map.py...")
    subprocess.run(command, check=True, cwd=ROOT)
    for name in MAP_SHOTS:
        target = out_dir / "map" / f"{name}.jpg"
        target.parent.mkdir(parents=True, exist_ok=True)
        Image.open(raw_dir / f"{name}.png").convert("RGB").save(target, quality=90, optimize=True)
        print("  wrote", rel(target))
    capture_studio(raw_dir, out_dir, everything)


def studio_slots(world):
    """{slot: name} from BrandingScene's "STUDIO <slot> <name>" prints."""
    slots = {}
    for line in world.get("Prints", []):
        match = re.match(r"STUDIO (\d+) (\S+)", line)
        if match:
            slots[int(match.group(1))] = match.group(2)
    return slots


def capture_studio(raw_dir, out_dir, everything=False):
    """Cuts the studio slots out of the map run's scene.json and renders them with stage.html."""
    world = json.loads((raw_dir / "world.json").read_text(encoding="utf-8"))
    scene = json.loads((raw_dir / "scene.json").read_text(encoding="utf-8"))
    slots = studio_slots(world)
    half = STUDIO_STEP / 2
    stage_dir = WORK / "raw" / "stage"
    stage_dir.mkdir(parents=True, exist_ok=True)
    jobs, finish = [], []
    for slot, name in sorted(slots.items()):
        if not everything and name not in STUDIO_USED:
            continue
        cx, cy, cz = STUDIO_ORIGIN[0] + slot * STUDIO_STEP, STUDIO_ORIGIN[1], STUDIO_ORIGIN[2]
        rows = []
        for row in scene["parts"]:
            x, y, z = row[4:7]
            if abs(x - cx) < half and abs(y - cy) < half and abs(z - cz) < half:
                rows.append(row[:4] + [x - cx, y - cy, z - cz] + row[7:])
        if not rows:
            print(f"  ! studio slot {slot} ({name}) is empty")
            continue
        meshes = {row[0][5:]: scene["meshes"]["items"][row[0][5:]] for row in rows if row[0].startswith("mesh:")}
        payload = {"rows": rows, "meshes": meshes, "bin": "/" + rel(raw_dir / "meshes.bin")}
        (stage_dir / f"{name}.json").write_text(json.dumps(payload), encoding="utf-8")
        size, azimuth, elevation = next(v for prefix, v in STUDIO.items() if name.startswith(prefix))  # first match
        px = size * SUPERSAMPLE
        query = f"parts=/{rel(stage_dir / (name + '.json'))}&size={px}&az={azimuth}&el={elevation}"
        jobs.append((f"tools/branding/stage.html?{query}", stage_dir / f"{name}.png", px))
        finish.append((name, size))
    print(f"Rendering {len(jobs)} studio models...")
    render_pages(jobs)
    for (_, raw, _), (name, size) in zip(jobs, finish):
        target = sticker(raw, out_dir / "studio" / f"{name}.png", size, outline=size * 0.012)
        print("  wrote", rel(target))


def contact_sheet():
    """The finished game page art on one page: big, and at the small sizes the game page and lists use."""
    assets = ROOT / "assets"
    icon = Image.open(assets / "icon_1024.png").convert("RGB")
    thumbs = [Image.open(assets / "thumbnails" / f"thumbnail_{i}.png").convert("RGB") for i in (1, 2, 3)]
    font = ImageFont.truetype(str(ROOT / "assets" / "source" / "fonts" / "FredokaOne-Regular.ttf"), 26)
    margin, big_w = 40, 960
    width = margin * 4 + big_w + 480 + 300
    height = margin * 2 + 60 + max(512 + 300, 3 * (540 + 50))
    sheet = Image.new("RGB", (width, height), (234, 243, 255))
    draw = ImageDraw.Draw(sheet)
    ink = INK
    draw.text((margin, margin), "Storm Catcher Simulator - game page art", fill=ink, font=font)
    top = margin + 60
    x_big, x_small, x_icon = margin, margin * 2 + big_w, margin * 3 + big_w + 480
    for index, thumb in enumerate(thumbs):
        y = top + index * (540 + 50)
        sheet.paste(thumb.resize((big_w, 540), Image.LANCZOS), (x_big, y))
        sheet.paste(thumb.resize((480, 270), Image.LANCZOS), (x_small, y))
        draw.text((x_small, y + 280), f"thumbnail_{index + 1} at 480 x 270", fill=ink, font=font)
    sheet.paste(icon.resize((300, 300), Image.LANCZOS), (x_icon, top))
    y = top + 320
    for size in (150, 100, 60):
        sheet.paste(icon.resize((size, size), Image.LANCZOS), (x_icon, y))
        draw.text((x_icon + size + 12, y + size // 2 - 14), f"{size} px", fill=ink, font=font)
        y += size + 20
    target = WORK / "contact_sheet.png"
    target.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(target)
    print("  wrote", rel(target))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("groups", nargs="*", help="pets, map, studio, sheet (default: pets and map, which includes studio)")
    parser.add_argument("--pets", default="", help="comma-separated pet ids to try instead of the page set")
    parser.add_argument("--all", action="store_true", help="every pet and every studio model, not only the ones "
                                                          "the pages use (use with --out)")
    parser.add_argument("--out", default=None, help=f"output folder (default {OUT.relative_to(ROOT)})")
    args = parser.parse_args()
    groups = args.groups or ["pets", "map"]
    out_dir = Path(args.out).resolve() if args.out else OUT
    for group in groups:
        if group == "pets":
            capture_pets(out_dir, [p for p in args.pets.split(",") if p], args.all)
        elif group == "map":
            capture_map(out_dir, args.all)
        elif group == "studio":
            capture_studio(WORK / "raw" / "map", out_dir, args.all)
        elif group == "sheet":
            contact_sheet()
        else:
            parser.error(f"unknown group {group!r} (pets, map, studio, sheet)")


if __name__ == "__main__":
    main()
