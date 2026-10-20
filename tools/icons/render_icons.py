#!/usr/bin/env python3
"""Renders the 3D UI icons (SketchUp models) to glossy cartoon PNGs.

Pipeline (tools/icons/README.md): the icons are modelled in Trimble SketchUp by
tools/icons/sketchup_icons.py, extracted with tools/world/sketchup/extract.py and imported into
assets/source/world/icons.json by tools/icons/import_icons.py. This script

  1. turns every icon's SketchUp polygons into triangles with smooth normals (per piece, with the
     piece's crease angle) and writes a small GLB (build/icons/StormIcons.glb; three.js axes: Y up,
     the icon's front towards +Z),
  2. renders each icon with tools/icons/viewer.html in headless Chromium at 2x (1024 px) from its own
     3/4 hero angle (ICONS below): soft toon shading with a cool shadow tint, a glossy highlight and a
     bright rim, plus a paint-id/depth pass,
  3. finishes the image in numpy: Ink (#233066) lines between parts (from the id/depth pass), a 7 px
     Ink outline around the silhouette, a soft Ink drop shadow inside the canvas, then 512 px RGBA:
         assets/ui/icons3d/<Key>.png
  4. a contact sheet on Mist at 128 px per icon (assets/ui/icons3d/_sheet.png) and a 48 px check
     (build/icons/check48.png: the icons at HUD size on Mist, on the white HUD badge and on the Sky band).

Usage (from the repo root):
    python3 tools/icons/render_icons.py                      all icons from assets/source/world/icons.json
    python3 tools/icons/render_icons.py --icons Volts,Star   only these
    python3 tools/icons/render_icons.py --source build/icons/offline/icons.json --out build/icons/offline
                                                             preview an offline dry run (import_icons.py offline)
    python3 tools/icons/render_icons.py --set zones          the zone emblems (assets/source/world/zone_emblems.json
                                                             -> assets/ui/icons3d/Zone_<Key>.png + _zones.png)
    python3 tools/icons/render_icons.py --set zones --source build/icons/zones/offline/icons.json

Requirements: Python 3.9+, numpy, Pillow, Chrome/Chromium (CHROME_PATH or Playwright's headless shell) and
three.js (`npm install` in tools/world).
"""

import argparse
import json
import math
import subprocess
import sys
import threading
from concurrent.futures import ThreadPoolExecutor
from functools import partial
from http.server import ThreadingHTTPServer
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
HERE = ROOT / "tools" / "icons"
WORLD = ROOT / "tools" / "world"
SOURCE = ROOT / "assets" / "source" / "world" / "icons.json"
ZONE_SOURCE = ROOT / "assets" / "source" / "world" / "zone_emblems.json"
OUT = ROOT / "assets" / "ui" / "icons3d"
BUILD = ROOT / "build" / "icons"
FONT = ROOT / "assets" / "source" / "fonts" / "FredokaOne-Regular.ttf"

sys.path.insert(0, str(WORLD))
import build_world_pack as wp  # noqa: E402  (tools/world: triangulation, normals, GLB writer, browser)

INK = (35, 48, 102)
MIST = (234, 243, 255)
SIZE = 512            # final icon size
SS = 2                # supersampling: the viewer renders SIZE * SS
OUTLINE_PX = 7.0      # silhouette outline at SIZE
LINE_PX = 3.2         # ink lines between parts at SIZE
SHADOW = dict(dx=1.5, dy=7.0, blur=5.0, alpha=0.30)  # drop shadow at SIZE, Ink
DEPTH_SCALE = 4096.0  # viewer.html: depth steps per stud
DEPTH_JUMP = 0.12     # studs between neighbouring pixels that count as an occlusion edge

# Every icon key (file assets/ui/icons3d/<Key>.png) with its hero angle: yaw = camera turned to the
# icon's right (degrees), pitch = raised above it, roll = tilt of the frame; fill = share of the frame the
# icon spans; noline = paints without ink lines (by default the white shine streaks, Neon_FFFFFF).
VIEW = {"yaw": -22, "pitch": 10, "roll": 0, "fill": 0.8, "noline": "Neon_FFFFFF"}
ICONS = {
    "Volts": {"yaw": -26, "pitch": 6},
    "Energy": {"yaw": -18, "pitch": 6},
    "Pets": {"yaw": -14, "pitch": 12},
    "Eggs": {"yaw": -16, "pitch": 6},
    "Shop": {"yaw": -26, "pitch": 12},
    "Upgrades": {"yaw": -26, "pitch": 8},
    "Rewards": {"yaw": -30, "pitch": 20},
    "Teleport": {"yaw": -20, "pitch": 10},
    "ClimateShift": {"yaw": -16, "pitch": 8},
    "Settings": {"yaw": -24, "pitch": 12},
    "Index": {"yaw": 30, "pitch": 16},
    "Radar": {"yaw": 14, "pitch": 12},
    "Lock": {"yaw": -24, "pitch": 10},
    "Check": {"yaw": -20, "pitch": 8},
    "Star": {"yaw": -20, "pitch": 8},
    "Rainbow": {"yaw": -14, "pitch": 12},
    "Luck": {"yaw": -16, "pitch": 12},
    "Tank": {"yaw": -22, "pitch": 12},
    "Power": {"yaw": -4, "pitch": 10},
    "Range": {"yaw": -24, "pitch": 8},
    "Speed": {"yaw": -16, "pitch": 8},
    "Codes": {"yaw": -24, "pitch": 14},
    "Daily": {"yaw": -26, "pitch": 12},
    "MegaStorm": {"yaw": -18, "pitch": 8},
    "Sell": {"yaw": -22, "pitch": 10},
    "Gift": {"yaw": -32, "pitch": 20},
    "Boost": {"yaw": -18, "pitch": 6},
    "Close": {"yaw": -20, "pitch": 6},
}

# The zone emblems (tools/icons/sketchup_zone_emblems.py): one gold medallion per region of
# src/shared/Config/Zones.luau, keyed Zone_<Zone.Key>, all from the same slight 3/4 angle so they read as a set.
ZONE_VIEW = {"yaw": -16, "pitch": 7, "fill": 0.86}
ZONE_ICONS = {f"Zone_{key}": dict(ZONE_VIEW) for key in
              ("Hub", "Meadows", "Thunder", "Dunes", "Frost", "Volcano", "Sky")}

# Icon sets: source, hero-angle table, contact sheet (in OUT), work folder (GLB, raw renders, check48)
SETS = {
    "icons": {"source": SOURCE, "table": ICONS, "sheet": "_sheet.png", "work": BUILD, "glb": "StormIcons.glb",
              "title": "3D UI icons"},
    "zones": {"source": ZONE_SOURCE, "table": ZONE_ICONS, "sheet": "_zones.png", "work": BUILD / "zones",
              "glb": "StormZoneEmblems.glb", "title": "zone emblems"},
}


def rel(path):
    path = Path(path).resolve()
    return path.relative_to(ROOT) if path.is_relative_to(ROOT) else path


# ------------------------------------------------------------------------------ meshes -> GLB

def to_three(v):
    """SketchUp inches (x, y, z), Z up, front -Y  ->  studs (x, z, -y): Y up, the front towards +Z."""
    v = np.asarray(v, dtype=np.float64).reshape(-1, 3)
    return np.stack([v[:, 0], v[:, 2], -v[:, 1]], axis=1) / 12.0


def build_icon(prop):
    """One source icon -> {"pieces": {paint: mesh}} like build_world_pack.build_prop (no prop contract)."""
    by_paint = {}
    for piece in prop["pieces"]:
        paint = piece["paint"]
        verts = to_three(piece["v"])
        tris = []
        for face in piece["f"]:
            tris += wp.triangulate_face(face, verts)
        tris = np.asarray(tris, dtype=np.int64).reshape(-1, 3)
        a, b, c = verts[tris[:, 0]], verts[tris[:, 1]], verts[tris[:, 2]]
        tris = tris[np.linalg.norm(np.cross(b - a, c - a), axis=1) >= 1e-10]
        if not len(tris):
            continue
        used = np.unique(tris)
        remap = np.full(len(verts), -1)
        remap[used] = np.arange(len(used))
        pos, nrm, t = wp.smooth_normals(verts[used], remap[tris], piece.get("crease") or wp.CREASE_DEG)
        e = by_paint.setdefault(paint, {"pos": [], "nrm": [], "tris": [], "n": 0, "rgb": piece.get("rgb")})
        e["pos"].append(pos)
        e["nrm"].append(nrm)
        e["tris"].append(t + e["n"])
        e["n"] += len(pos)
    pieces = {}
    for paint, e in by_paint.items():
        kind = wp.paint_kind(paint)
        rgb = paint.split("_")[1] if kind in ("Color", "Neon", "Glass") else (e["rgb"] or "C8C8C8")
        pieces[paint] = {"pos": np.concatenate(e["pos"]), "nrm": np.concatenate(e["nrm"]),
                         "tris": np.concatenate(e["tris"]), "rgb": rgb.upper(), "kind": kind, "paint": paint,
                         "collide": False}
    return {"pieces": pieces, "slot": np.zeros(3), "category": "icons", "solid": False}


def write_glb(source, target):
    props = json.loads(Path(source).read_text(encoding="utf-8"))["props"]
    built = {key: build_icon(props[key]) for key in sorted(props)}
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(wp.glb_bytes(built))
    return built


# ------------------------------------------------------------------------------ rendering

def render_raw(keys, glb_path, raw_dir, workers=4, table=None):
    """viewer.html screenshots: [shaded | ids+depth], SIZE*SS px each -> raw_dir/<Key>.png"""
    browser = wp.find_browser()
    if not browser:
        sys.exit("no Chrome/Chromium found (set CHROME_PATH)")
    if not (WORLD / "node_modules" / "three" / "build" / "three.module.js").exists():
        sys.exit("three.js missing - run `npm install` in tools/world")
    handler = type("IconHandler", (wp.QuietHandler,), {"pack": str(glb_path)})
    server = ThreadingHTTPServer(("127.0.0.1", 0), partial(handler, directory=str(ROOT)))
    threading.Thread(target=server.serve_forever, daemon=True).start()
    port = server.server_address[1]
    px = SIZE * SS
    raw_dir.mkdir(parents=True, exist_ok=True)

    def one(key):
        view = dict(VIEW, **(ICONS if table is None else table).get(key, {}))
        query = "&".join(f"{k}={view[k]}" for k in ("yaw", "pitch", "roll", "fill", "noline"))
        url = f"http://127.0.0.1:{port}/tools/icons/viewer.html?icon={key}&size={px}&glb=/pack.glb&{query}"
        target = raw_dir / f"{key}.png"
        command = [browser, "--headless=new", "--no-sandbox", "--use-angle=swiftshader", "--enable-unsafe-swiftshader",
                   "--hide-scrollbars", "--force-device-scale-factor=1", "--default-background-color=00000000",
                   "--virtual-time-budget=30000", f"--window-size={2 * px},{px}", f"--screenshot={target}", url]
        subprocess.run(command, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=240)
        return target

    try:
        with ThreadPoolExecutor(max_workers=workers) as pool:
            return dict(zip(keys, pool.map(one, keys)))
    finally:
        server.shutdown()


def shift(a, dx, dy):
    """a moved by (dx, dy) pixels, zero filled."""
    out = np.zeros_like(a)
    h, w = a.shape
    xs0, xs1 = max(0, -dx), min(w, w - dx)
    ys0, ys1 = max(0, -dy), min(h, h - dy)
    out[ys0 + dy:ys1 + dy, xs0 + dx:xs1 + dx] = a[ys0:ys1, xs0:xs1]
    return out


def dilate(a, r):
    """Round, antialiased dilation of a coverage map a (0..1) by r pixels."""
    out = a.copy()
    n = int(math.ceil(r + 1))
    for dy in range(-n, n + 1):
        for dx in range(-n, n + 1):
            w = min(1.0, max(0.0, r + 0.5 - math.hypot(dx, dy)))
            if w > 0 and (dx or dy):
                np.maximum(out, shift(a, dx, dy) * w, out=out)
    return out


def blur(a, radius):
    img = Image.fromarray(np.clip(a * 255.0 + 0.5, 0, 255).astype(np.uint8), "L")
    return np.asarray(img.filter(ImageFilter.GaussianBlur(radius)), dtype=np.float32) / 255.0


def over(top, bottom):
    """Premultiplied 'over': layers are (rgb premultiplied, alpha)."""
    rgb_t, a_t = top
    rgb_b, a_b = bottom
    k = (1.0 - a_t)[..., None]
    return rgb_t + rgb_b * k, a_t + a_b * (1.0 - a_t)


def solid(color, alpha):
    c = np.asarray(color, dtype=np.float32) / 255.0
    return c[None, None, :] * alpha[..., None], alpha


def finish(raw_path, target):
    """Shaded render + id/depth pass -> the finished 512 px icon."""
    raw = np.asarray(Image.open(raw_path).convert("RGBA"))
    px = raw.shape[0]
    shade = raw[:, :px].astype(np.float32) / 255.0
    data = raw[:, px:2 * px].astype(np.int32)
    ids = data[..., 0]
    depth = (data[..., 1] * 256 + data[..., 2]) / DEPTH_SCALE
    alpha = shade[..., 3]

    # ink lines: paint changes and depth jumps between neighbouring pixels, then thickened
    edge = np.zeros(ids.shape, dtype=bool)
    for dx, dy in ((1, 0), (0, 1)):
        nid, nd = shift(ids, dx, dy), shift(depth, dx, dy)
        e = (ids != nid) | ((ids > 0) & (nid > 0) & (np.abs(depth - nd) > DEPTH_JUMP))
        edge |= e | shift(e, -dx, -dy)
    line = dilate(edge.astype(np.float32), max(0.0, LINE_PX * SS / 2.0 - 1.0))
    line = blur(line, 0.6) * np.clip(alpha * 4.0, 0, 1)

    # silhouette outline (glass counts as solid) and drop shadow
    body = np.clip(alpha * 2.5, 0.0, 1.0)
    outline = dilate(body, OUTLINE_PX * SS)
    s = SS
    shadow = shift(outline, int(round(SHADOW["dx"] * s)), int(round(SHADOW["dy"] * s)))
    shadow = blur(shadow, SHADOW["blur"] * s) * SHADOW["alpha"]

    obj = (shade[..., :3] * alpha[..., None], alpha)
    img = over(solid(INK, line), obj)
    img = over(img, solid(INK, outline))
    img = over(img, solid(INK, shadow))
    rgb, a = img
    out = np.concatenate([rgb, a[..., None]], axis=2)
    out = Image.fromarray(np.clip(out * 255.0 + 0.5, 0, 255).astype(np.uint8), "RGBa")
    out = out.resize((SIZE, SIZE), Image.LANCZOS).convert("RGBA")
    target.parent.mkdir(parents=True, exist_ok=True)
    out.save(target, optimize=True)
    return target


# ------------------------------------------------------------------------------ sheets

def font(size):
    try:
        return ImageFont.truetype(str(FONT), size)
    except OSError:
        return ImageFont.load_default()


def contact_sheet(images, target, cell=128, columns=7, title="3D UI icons"):
    keys = list(images)
    rows = (len(keys) + columns - 1) // columns
    pad, label, header = 18, 26, 64
    w = columns * (cell + pad) + pad
    h = header + rows * (cell + label + pad) + pad
    sheet = Image.new("RGBA", (w, h), MIST + (255,))
    d = ImageDraw.Draw(sheet)
    d.text((w / 2, header / 2 + 4), "Storm Catcher Simulator - " + title, font=font(30), fill=INK, anchor="mm")
    for i, key in enumerate(keys):
        r, c = divmod(i, columns)
        x, y = pad + c * (cell + pad), header + r * (cell + label + pad)
        icon = Image.open(images[key]).convert("RGBA").resize((cell, cell), Image.LANCZOS)
        sheet.alpha_composite(icon, (x, y))
        d.text((x + cell / 2, y + cell + 12), key, font=font(15), fill=INK, anchor="mm")
    sheet.convert("RGB").save(target, optimize=True)
    return target


def check48(images, target, columns=14):
    """The icons at HUD size: on Mist, inside the 68 px white HUD badge (3 px Sky ring, Ink outline) and on
    the Sky header band; shown 1:1 and enlarged x2 (nearest) for inspection."""
    keys = list(images)
    rows = (len(keys) + columns - 1) // columns
    cell = 76
    band_h = rows * cell
    w, h = columns * cell + 16, 3 * band_h + 16
    img = Image.new("RGBA", (w, h), MIST + (255,))
    d = ImageDraw.Draw(img)
    sky_top, sky_bottom = np.array([92, 200, 255]), np.array([47, 134, 242])
    grad = (sky_top[None, :] + (sky_bottom - sky_top)[None, :] * np.linspace(0, 1, band_h)[:, None]).astype(np.uint8)
    img.paste(Image.fromarray(np.repeat(grad[:, None, :], w, axis=1)).convert("RGBA"), (0, 8 + 2 * band_h))
    for i, key in enumerate(keys):
        r, c = divmod(i, columns)
        icon = Image.open(images[key]).convert("RGBA").resize((48, 48), Image.LANCZOS)
        for band in range(3):
            x, y = 8 + c * cell, 8 + band * band_h + r * cell
            if band == 1:
                d.ellipse((x + 4, y + 4, x + 72, y + 72), fill=INK)
                d.ellipse((x + 6, y + 6, x + 70, y + 70), fill=(92, 200, 255))
                d.ellipse((x + 9, y + 9, x + 67, y + 67), fill=(255, 255, 255))
            img.alpha_composite(icon, (x + 14, y + 14))
    img = img.convert("RGB")
    big = img.resize((w * 2, h * 2), Image.NEAREST)
    both = Image.new("RGB", (w * 2, h + h * 2 + 8), MIST)
    both.paste(img, (0, 0))
    both.paste(big, (0, h + 8))
    both.save(target, optimize=True)
    return target


# ------------------------------------------------------------------------------ main

def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--set", choices=sorted(SETS), default="icons", help="icons (default) or zones (zone emblems)")
    parser.add_argument("--source", default=None, help="icon source json (default the set's: assets/source/world/"
                                                       "icons.json or zone_emblems.json)")
    parser.add_argument("--out", default=None, help="output folder (default assets/ui/icons3d; for --source previews "
                                                    "the source's folder)")
    parser.add_argument("--icons", default="", help="comma-separated icon keys (default all)")
    parser.add_argument("--workers", type=int, default=4)
    args = parser.parse_args()

    spec = SETS[args.set]
    table = spec["table"]
    source = Path(args.source or spec["source"]).resolve()
    preview = source != Path(spec["source"]).resolve()
    out = Path(args.out).resolve() if args.out else (source.parent if preview else OUT)
    work = (source.parent if preview else spec["work"])
    glb = work / spec["glb"]
    built = write_glb(source, glb)
    print(f"wrote {rel(glb)} ({glb.stat().st_size // 1024} KB, {len(built)} icons)")
    wanted = [k for k in args.icons.split(",") if k] or [k for k in table if k in built] + \
        [k for k in built if k not in table]
    missing = [k for k in wanted if k not in built]
    if missing:
        sys.exit("not in the source: " + ", ".join(missing))
    raws = render_raw(wanted, glb, work / "raw", args.workers, table)
    for key in wanted:
        finish(raws[key], out / f"{key}.png")
        tris = sum(len(p["tris"]) for p in built[key]["pieces"].values())
        print(f"  {key:<13} {len(built[key]['pieces']):>2} paints {tris:>5} tris -> {rel(out / (key + '.png'))}")
    images = {k: out / f"{k}.png" for k in list(table) + [k for k in built if k not in table]
              if (out / f"{k}.png").exists()}
    sheet = contact_sheet(images, out / spec["sheet"], columns=min(7, max(1, len(images))), title=spec["title"])
    chk = check48(images, work / "check48.png")
    print(f"wrote {rel(sheet)} and {rel(chk)}")


if __name__ == "__main__":
    main()
