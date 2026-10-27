#!/usr/bin/env python3
"""Contact sheets for the Blender Secret Stormlings (normal Python + Pillow, no bpy needed).

    python3 tools/pets/blender/sheets.py                 # build/pets/blender_secret_sheet.png (Blender renders)
    python3 tools/pets/blender/sheets.py --compare       # + build/pets/secret_old_vs_blender.png
    python3 tools/pets/blender/sheets.py --views hero    # only some views

Inputs: build/pets/blender/<PetId>_<view>.png (build_secret_pets.py), and for --compare the three.js pack
renders of the old SketchUp models (build/pets/old/<PetId>.png, see tools/pets/README.md) and of the new
pack (build/pets/<PetId>.png).
"""

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "build" / "pets"
FONT = ROOT / "assets" / "source" / "fonts" / "FredokaOne-Regular.ttf"
SECRETS = ["EyeOfTheStorm", "ThunderKirin", "SandstormSphinx", "BlizzardMonarch", "TempestPhoenix",
           "PyroclasmDragon", "VoidLeviathan", "NovaSeraph", "Hypercane"]
NAMES = {"EyeOfTheStorm": "Eye of the Storm", "ThunderKirin": "Thunderclap Kirin", "SandstormSphinx": "Sandstorm Sphinx",
         "BlizzardMonarch": "Blizzard Monarch", "TempestPhoenix": "Tempest Phoenix", "PyroclasmDragon": "Pyroclasm Dragon",
         "VoidLeviathan": "Void Leviathan", "NovaSeraph": "Nova Seraph", "Hypercane": "Hypercane"}
INK = (35, 48, 102)


def font(size):
    try:
        return ImageFont.truetype(str(FONT), size)
    except OSError:
        return ImageFont.load_default()


def backdrop(width, height, top=(150, 120, 230), bottom=(52, 30, 110)):
    img = Image.new("RGB", (width, height))
    draw = ImageDraw.Draw(img)
    for y in range(height):
        t = y / max(1, height - 1)
        draw.line([(0, y), (width, y)], fill=tuple(int(a + (b - a) * t) for a, b in zip(top, bottom)))
    return img.convert("RGBA")


def tile(path, size, label=None, card=(244, 247, 255), shadow=True):
    t = Image.new("RGBA", (size, size + (36 if label else 0)), (0, 0, 0, 0))
    d = ImageDraw.Draw(t)
    d.rounded_rectangle((0, 0, size - 1, t.height - 1), radius=18, fill=card + (255,), outline=INK + (255,), width=3)
    if shadow:
        sh = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        ImageDraw.Draw(sh).ellipse((size * 0.26, size * 0.84, size * 0.74, size * 0.93), fill=(30, 20, 70, 80))
        t.alpha_composite(sh.filter(ImageFilter.GaussianBlur(6)))
    if path and Path(path).exists():
        im = Image.open(path).convert("RGBA").resize((size - 12, size - 12), Image.LANCZOS)
        t.alpha_composite(im, (6, 4))
    else:
        d.text((size / 2, size / 2), "missing", font=font(18), fill=INK, anchor="mm")
    if label:
        d.text((size / 2, size + 12), label, font=font(20), fill=INK, anchor="mm")
    return t


def blender_sheet(views, size=260):
    pad, head, left = 16, 90, 230
    w = left + len(views) * (size + pad) + pad
    h = head + len(SECRETS) * (size + pad) + pad
    img = backdrop(w, h)
    d = ImageDraw.Draw(img)
    d.text((w / 2, 46), "SECRET STORMLINGS  -  BLENDER", font=font(44), fill="white", anchor="mm", stroke_width=4,
           stroke_fill=INK)
    for c, view in enumerate(views):
        d.text((left + c * (size + pad) + size / 2, head - 8), view.upper(), font=font(20), fill="white", anchor="mm",
               stroke_width=2, stroke_fill=INK)
    for r, pet in enumerate(SECRETS):
        y = head + 8 + r * (size + pad)
        d.text((left - 14, y + size / 2), NAMES[pet], font=font(24), fill="white", anchor="rm", stroke_width=3,
               stroke_fill=INK)
        for c, view in enumerate(views):
            img.alpha_composite(tile(OUT / "blender" / f"{pet}_{view}.png", size), (left + c * (size + pad), y))
    target = OUT / "blender_secret_sheet.png"
    img.convert("RGB").save(target)
    return target


def compare_sheet(size=250):
    cols = [("SketchUp (old pack)", OUT / "old"), ("Blender (new pack, in-game look)", OUT), ("Blender render", None)]
    pad, head, left = 16, 110, 230
    w = left + len(cols) * (size + pad) + pad
    h = head + len(SECRETS) * (size + pad) + pad
    img = backdrop(w, h)
    d = ImageDraw.Draw(img)
    d.text((w / 2, 40), "SECRET PETS: OLD vs BLENDER", font=font(42), fill="white", anchor="mm", stroke_width=4,
           stroke_fill=INK)
    for c, (title, _) in enumerate(cols):
        d.text((left + c * (size + pad) + size / 2, head - 22), title, font=font(19), fill="white", anchor="mm",
               stroke_width=2, stroke_fill=INK)
    for r, pet in enumerate(SECRETS):
        y = head + r * (size + pad)
        d.text((left - 14, y + size / 2), NAMES[pet], font=font(24), fill="white", anchor="rm", stroke_width=3,
               stroke_fill=INK)
        for c, (_, folder) in enumerate(cols):
            path = (folder / f"{pet}.png") if folder else (OUT / "blender" / f"{pet}_hero.png")
            card = (226, 226, 232) if c == 0 else (244, 247, 255)
            img.alpha_composite(tile(path, size, card=card), (left + c * (size + pad), y))
    target = OUT / "secret_old_vs_blender.png"
    img.convert("RGB").save(target)
    return target


def grid(view, target, size=340, columns=3):
    """A quick review grid of one view of all nine pets."""
    rows = (len(SECRETS) + columns - 1) // columns
    img = backdrop(columns * size, rows * size, top=(170, 196, 240), bottom=(120, 150, 220))
    for i, pet in enumerate(SECRETS):
        path = OUT / "blender" / f"{pet}_{view}.png"
        if path.exists():
            im = Image.open(path).convert("RGBA").resize((size, size), Image.LANCZOS)
            img.alpha_composite(im, ((i % columns) * size, (i // columns) * size))
    img.convert("RGB").save(target)
    return target


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--views", default="hero,front,side,back")
    parser.add_argument("--compare", action="store_true")
    parser.add_argument("--size", type=int, default=260)
    parser.add_argument("--grid", default="", help="only write a 3x3 review grid of this view to --out")
    parser.add_argument("--out", default="")
    args = parser.parse_args()
    if args.grid:
        print("wrote", grid(args.grid, Path(args.out)))
        return
    print("wrote", blender_sheet(args.views.split(","), args.size).relative_to(ROOT))
    if args.compare:
        print("wrote", compare_sheet().relative_to(ROOT))


if __name__ == "__main__":
    main()
