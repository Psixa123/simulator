#!/usr/bin/env python3
"""Builds the nine Secret Stormlings in Blender and exports them for the pet pack.

Run with Blender's Python module (bpy), from the repo root, e.g.:

    python3 -m venv /tmp/blender-venv && /tmp/blender-venv/bin/pip install bpy     # once (bpy 5.x, Python 3.13)
    /tmp/blender-venv/bin/python tools/pets/blender/build_secret_pets.py             # all 9: export + renders
    /tmp/blender-venv/bin/python tools/pets/blender/build_secret_pets.py --pets Hypercane --no-render
    /tmp/blender-venv/bin/python tools/pets/blender/build_secret_pets.py --blend     # also save .blend sources

Writes per pet:
    assets/source/pets/blender/<PetId>.glb      the finished meshes ("<PetId>" node > "<PetId>.<Role>" meshes)
    assets/source/pets/blender/<PetId>.blend    (--blend) the finished Blender scene
    build/pets/blender/<PetId>_<view>.png       Cycles renders (hero/front/side/back)
then `python tools/pets/build_pets.py` merges the GLBs into assets/models/StormlingPets.glb.
"""

import argparse
import json
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import bpy  # noqa: E402

import kit  # noqa: E402
import render  # noqa: E402
import secret_pets  # noqa: E402

ROOT = HERE.parents[2]
SOURCE = ROOT / "assets" / "source" / "pets" / "blender"
RENDERS = ROOT / "build" / "pets" / "blender"
SECRET_BUDGET = 10000  # triangles per Secret pet (build_pets.py MAX_TRIS_SECRET)
MAX_VISIBLE = 12


def build(pet_id, args):
    kit.reset()
    started = time.time()
    pet = secret_pets.BUILDERS[pet_id]()
    total = pet.finish(SECRET_BUDGET)
    visible = len(pet.final)
    print(f"{pet_id}: {total} tris, {visible} visible meshes ({time.time() - started:.1f}s)")
    print(pet.report())
    if total > SECRET_BUDGET or visible > MAX_VISIBLE:
        raise SystemExit(f"{pet_id} is over budget")
    info = {"tris": total, "meshes": {r: kit.tri_count(o) for r, o in pet.final.items()}}
    if not args.no_export:
        path = kit.export_pet(pet, SOURCE / f"{pet_id}.glb")
        print(f"  wrote {path.relative_to(ROOT)} ({path.stat().st_size / 1024:.0f} KB)")
    if args.blend:
        path = SOURCE / f"{pet_id}.blend"
        bpy.ops.wm.save_as_mainfile(filepath=str(path), compress=True)
        print(f"  wrote {path.relative_to(ROOT)} ({path.stat().st_size / 1024:.0f} KB)")
    if not args.no_render:
        RENDERS.mkdir(parents=True, exist_ok=True)
        views = args.views.split(",")
        paths = render.render_views(pet.objects(), str(RENDERS / pet_id), views=views, size=args.size,
                                    samples=args.samples)
        print("  rendered", ", ".join(Path(p).name for p in paths))
    return info


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--pets", default="", help="comma separated pet ids (default: all 9)")
    parser.add_argument("--no-render", action="store_true")
    parser.add_argument("--no-export", action="store_true")
    parser.add_argument("--blend", action="store_true", help="also save assets/source/pets/blender/<PetId>.blend")
    parser.add_argument("--views", default="hero,front,side,back")
    parser.add_argument("--size", type=int, default=768)
    parser.add_argument("--samples", type=int, default=64)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else None)
    wanted = [p for p in args.pets.split(",") if p] or list(secret_pets.BUILDERS)
    summary = {}
    for pet_id in wanted:
        summary[pet_id] = build(pet_id, args)
    if not args.no_export and len(wanted) == len(secret_pets.BUILDERS):
        (SOURCE / "summary.json").write_text(json.dumps(summary, indent=1) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
