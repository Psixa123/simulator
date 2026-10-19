#!/usr/bin/env python3
"""Source files of the 3D UI icons: offline dry runs, SketchUp imports and checks.

The icons are modelled in Trimble SketchUp by tools/icons/sketchup_icons.py (with the world prop kit's
helper library tools/world/sketchup/lib.py), pulled out with tools/world/sketchup/extract.py and kept as
raw SketchUp polygons in assets/source/world/icons.json. tools/icons/render_icons.py renders them.

    python3 tools/icons/import_icons.py offline [--out build/icons/offline/icons.json]
        run lib.py + sketchup_icons.py + extract.py locally against the SketchUp stand-in
        (tools/world/offline_sketchup.py) - a quick preview source that needs no SketchUp
    python3 tools/icons/import_icons.py import <tool-result file | extraction .json> [--replace]
        merge a SketchUp extraction into assets/source/world/icons.json (icons in the extraction replace
        icons of the same key; --replace rewrites the file with only the extraction)
    python3 tools/icons/import_icons.py check
        sandbox safety of sketchup_icons.py, a dry run of it, and that assets/source/world/icons.json
        holds every icon in render_icons.ICONS

icons.json uses the world source layout (tools/world/import_sketchup.py) with its own format tag
"storm-icons-source/1", so the world prop pack (tools/world/build_world_pack.py) skips it.
"""

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = ROOT / "tools" / "icons"
WORLD = ROOT / "tools" / "world"
SCRIPT = HERE / "sketchup_icons.py"
SOURCE = ROOT / "assets" / "source" / "world" / "icons.json"
OFFLINE = ROOT / "build" / "icons" / "offline" / "icons.json"
FORMAT = "storm-icons-source/1"
CATEGORY = "icons"

sys.path.insert(0, str(WORLD))
sys.path.insert(0, str(HERE))
import import_sketchup  # noqa: E402  (tools/world)
import offline_sketchup  # noqa: E402  (tools/world)


def rel(path):
    path = Path(path).resolve()
    return path.relative_to(ROOT) if path.is_relative_to(ROOT) else path


def to_source(extraction):
    """{icon key: source entry} from an extract.py result (only the "icons" category)."""
    props = {}
    for prop in extraction["props"]:
        if (prop.get("category") or CATEGORY) != CATEGORY:
            continue
        pieces = [import_sketchup.clean_piece(x) for x in prop["pieces"] if x.get("f")]
        if not pieces:
            print(f"  ! {prop['id']}: no faces - skipped")
            continue
        props[prop["id"]] = {"solid": False, "slot": [import_sketchup.r2(x) for x in prop.get("slot", [0, 0, 0])],
                             "paints": {}, "pieces": pieces}
    return props


def write_source(props, path):
    text = import_sketchup.dumps_source(CATEGORY, props)
    text = text.replace(f'"format": "{import_sketchup.FORMAT}"', f'"format": "{FORMAT}"', 1)
    text = text.replace('"units": "inch (SketchUp: Z up, front -Y, origin at the base centre of each prop)"',
                        '"units": "inch (SketchUp: Z up, front -Y, origin at the base centre of each icon)"', 1)
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    for key in sorted(props):
        p = props[key]
        faces = sum(len(x["f"]) for x in p["pieces"])
        paints = sorted({x["paint"] for x in p["pieces"]})
        print(f"  {key:<13} {len(p['pieces']):>3} pieces {faces:>5} faces  {', '.join(paints)}")
    print(f"wrote {rel(path)} ({len(props)} icons)")


def load_source(path=SOURCE):
    path = Path(path)
    if not path.exists():
        return {}
    data = json.loads(path.read_text(encoding="utf-8"))
    if data.get("format") != FORMAT:
        raise SystemExit(f"{rel(path)}: not an icon source (format {data.get('format')!r})")
    return data["props"]


def cross2(a, b):
    return a[0] * b[1] - a[1] * b[0]


def face_problems(props):
    """Faces SketchUp would refuse or mangle: self-intersecting outlines (e.g. a slab outline inset past
    its narrowest part). Returns ["Icon/paint: n bad faces", ...]."""
    import numpy as np

    out = []
    for key, prop in sorted(props.items()):
        for piece in prop["pieces"]:
            v = np.asarray(piece["v"], dtype=float).reshape(-1, 3)
            bad = 0
            for face in piece["f"]:
                loop = face[0]
                if len(loop) < 5:
                    continue
                pts = v[loop]
                n = np.zeros(3)
                for i in range(len(pts)):
                    a, b = pts[i], pts[(i + 1) % len(pts)]
                    n += [(a[1] - b[1]) * (a[2] + b[2]), (a[2] - b[2]) * (a[0] + b[0]), (a[0] - b[0]) * (a[1] + b[1])]
                ax = int(np.argmax(np.abs(n)))
                q = np.delete(pts, ax, axis=1)
                m = len(q)
                hit = False
                for i in range(m):
                    p1, p2 = q[i], q[(i + 1) % m]
                    for j in range(i + 2, m):
                        if i == 0 and j == m - 1:
                            continue
                        q1, q2 = q[j], q[(j + 1) % m]
                        d1 = cross2(q2 - q1, p1 - q1)
                        d2 = cross2(q2 - q1, p2 - q1)
                        d3 = cross2(p2 - p1, q1 - p1)
                        d4 = cross2(p2 - p1, q2 - p1)
                        if d1 * d2 < -1e-9 and d3 * d4 < -1e-9:
                            hit = True
                            break
                    if hit:
                        break
                bad += hit
            if bad:
                out.append(f"{key}/{piece['paint']}: {bad} self-intersecting face(s)")
    return out


def dry_run():
    """lib.py + sketchup_icons.py + extract.py in one offline SketchUp stand-in session."""
    session = offline_sketchup.Session()
    session.run_file(WORLD / "sketchup" / "lib.py")
    reports = []
    for res in session.run_file(SCRIPT):
        reports.extend((res or {}).get("built", []))
    extraction = session.call((WORLD / "sketchup" / "extract.py").read_text(encoding="utf-8"), "extract.py")
    return reports, extraction


def cmd_offline(args):
    reports, extraction = dry_run()
    for r in reports:
        warn = ("  ! " + "; ".join(r["warnings"])) if r["warnings"] else ""
        print(f"  {r['id']:<13} {r['pieces']:>3} pieces {r['tris']:>5} tris  size {r['size']}{warn}")
    props = to_source(extraction)
    for problem in face_problems(props):
        print(f"  ! {problem}")
    write_source(props, args.out)


def cmd_import(args):
    extraction = import_sketchup.load_extraction(args.result)
    props = to_source(extraction)
    if not props:
        sys.exit("the extraction holds no icons")
    merged = {} if args.replace else load_source(args.out)
    merged.update(props)
    write_source(merged, args.out)


def cmd_check(args):
    import render_icons

    failures = 0
    problems = offline_sketchup.check_source(SCRIPT)
    print(f"Sandbox safety: {'ok' if not problems else 'FAIL'}  {rel(SCRIPT)}")
    for p in problems:
        print(f"    ! {p}")
    failures += len(problems)
    try:
        reports, extraction = dry_run()
        bad = [r for r in reports if r["warnings"]]
        print(f"Dry run: {'ok' if not bad else 'WARN'}  {len(reports)} icons built offline")
        for r in bad:
            print(f"    ~ {r['id']}: {'; '.join(r['warnings'])}")
        scripted = {p["id"] for p in extraction["props"]}
    except Exception as e:  # noqa: BLE001 - report any script failure
        print(f"Dry run: FAIL {type(e).__name__}: {e}")
        failures += 1
        scripted = set()
    source = load_source()
    bad = face_problems(source)
    print(f"Faces: {'ok' if not bad else 'FAIL'}  no self-intersecting faces in the source")
    for b in bad:
        print(f"    ! {b}")
    failures += len(bad)
    wanted = list(render_icons.ICONS)
    missing = [k for k in wanted if k not in source]
    print(f"Source: {'ok' if not missing else 'FAIL'}  {rel(SOURCE)} holds {len(source)} icons")
    for k in missing:
        print(f"    ! {k} is not imported yet")
    failures += len(missing)
    for k in wanted:
        if scripted and k not in scripted:
            print(f"    ! {k} is in no build chunk of {SCRIPT.name}")
            failures += 1
    out = render_icons.OUT
    stale = [k for k in wanted if not (out / f"{k}.png").exists()]
    print(f"Renders: {'ok' if not stale else 'FAIL'}  {rel(out)}/<Key>.png")
    for k in stale:
        print(f"    ! {k}.png is missing")
    failures += len(stale)
    print("check passed" if not failures else f"check FAILED ({failures} problem(s))")
    sys.exit(1 if failures else 0)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("offline", help="dry run of the SketchUp script -> a preview source")
    p.add_argument("--out", default=str(OFFLINE))
    p.set_defaults(fn=cmd_offline)
    p = sub.add_parser("import", help="merge a SketchUp extraction into assets/source/world/icons.json")
    p.add_argument("result")
    p.add_argument("--replace", action="store_true")
    p.add_argument("--out", default=str(SOURCE))
    p.set_defaults(fn=cmd_import)
    p = sub.add_parser("check", help="sandbox safety, dry run, source + renders complete")
    p.set_defaults(fn=cmd_check)
    args = parser.parse_args()
    args.fn(args)


if __name__ == "__main__":
    main()
