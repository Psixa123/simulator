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
        holds every icon in render_icons.ICONS (and the same for the zone emblems)

--set zones works on the zone emblems instead (tools/icons/sketchup_zone_emblems.py, built on top of the
icon helpers in chunks 1-2 of sketchup_icons.py, kept in assets/source/world/zone_emblems.json):

    python3 tools/icons/import_icons.py --set zones offline   -> build/icons/zones/offline/icons.json
    python3 tools/icons/import_icons.py --set zones import zones.txt --replace

--set store works on the store heroes (the gamepass/product icon models, tools/icons/sketchup_store_icons.py,
also built on the icon helpers, kept in assets/source/world/store_icons.json):

    python3 tools/icons/import_icons.py --set store offline   -> build/icons/store/offline/icons.json
    python3 tools/icons/import_icons.py --set store verify digest.txt [--write]
        compare a SketchUp digest (extract.py + tools/icons/digest.py sent as one build_model call) with the same
        digest of the offline dry run; --write stores the dry run as the source when every prop matches

icons.json and zone_emblems.json use the world source layout (tools/world/import_sketchup.py) with their
own format tag "storm-icons-source/1", so the world prop pack (tools/world/build_world_pack.py) skips them.
"""

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = ROOT / "tools" / "icons"
WORLD = ROOT / "tools" / "world"
SCRIPT = HERE / "sketchup_icons.py"
DIGEST = HERE / "digest.py"
SOURCE = ROOT / "assets" / "source" / "world" / "icons.json"
OFFLINE = ROOT / "build" / "icons" / "offline" / "icons.json"
FORMAT = "storm-icons-source/1"
CATEGORY = "icons"
# The icon sets: their SketchUp script, the helper chunks of other scripts sent before it (after lib.py),
# their source file and the default output of an offline dry run.
SETS = {
    "icons": {"script": SCRIPT, "helpers": [], "source": SOURCE, "offline": OFFLINE},
    "zones": {"script": HERE / "sketchup_zone_emblems.py", "helpers": [(SCRIPT, 2)],
              "source": ROOT / "assets" / "source" / "world" / "zone_emblems.json",
              "offline": ROOT / "build" / "icons" / "zones" / "offline" / "icons.json"},
    "store": {"script": HERE / "sketchup_store_icons.py", "helpers": [(SCRIPT, 2)],
              "source": ROOT / "assets" / "source" / "world" / "store_icons.json",
              "offline": ROOT / "build" / "icons" / "store" / "offline" / "icons.json"},
}

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


def dry_run(name="icons", digest=False):
    """lib.py + the set's helper chunks + its script + extract.py in one offline SketchUp stand-in session.
    digest=True also returns the digest of the extraction (extract.py + digest.py in one call, as sent to
    SketchUp)."""
    spec = SETS[name]
    session = offline_sketchup.Session()
    session.run_file(WORLD / "sketchup" / "lib.py")
    for path, count in spec["helpers"]:
        for n, chunk in enumerate(offline_sketchup.chunks(path)[:count], 1):
            session.call(chunk, f"{Path(path).name}#{n}")
    reports = []
    for res in session.run_file(spec["script"]):
        reports.extend((res or {}).get("built", []))
    extract = (WORLD / "sketchup" / "extract.py").read_text(encoding="utf-8")
    extraction = session.call(extract, "extract.py")
    if not digest:
        return reports, extraction
    summary = session.call(extract + "\n" + DIGEST.read_text(encoding="utf-8"), "extract.py+digest.py")
    return reports, extraction, summary


def cmd_offline(args):
    reports, extraction = dry_run(args.set)
    for r in reports:
        warn = ("  ! " + "; ".join(r["warnings"])) if r["warnings"] else ""
        print(f"  {r['id']:<13} {r['pieces']:>3} pieces {r['tris']:>5} tris  size {r['size']}{warn}")
    props = to_source(extraction)
    for problem in face_problems(props):
        print(f"  ! {problem}")
    write_source(props, args.out or SETS[args.set]["offline"])


def cmd_import(args):
    extraction = import_sketchup.load_extraction(args.result)
    props = to_source(extraction)
    if not props:
        sys.exit("the extraction holds no icons")
    out = args.out or SETS[args.set]["source"]
    merged = {} if args.replace else load_source(out)
    merged.update(props)
    write_source(merged, out)


def find_digest(obj, depth=0):
    """The digest.py result inside a saved tool result (dicts, lists, JSON text)."""
    if depth > 8:
        return None
    if isinstance(obj, dict):
        if "storm_icons_digest" in obj:
            return obj
        obj = list(obj.values())
    if isinstance(obj, list):
        for value in obj:
            found = find_digest(value, depth + 1)
            if found is not None:
                return found
    elif isinstance(obj, str) and "storm_icons_digest" in obj:
        start = obj.find("{")
        while start >= 0:
            try:
                return find_digest(json.JSONDecoder().raw_decode(obj, start)[0], depth + 1)
            except ValueError:
                start = obj.find("{", start + 1)
    return None


def cmd_verify(args):
    text = Path(args.result).read_text(encoding="utf-8")
    try:
        data = json.loads(text)
    except ValueError:
        data = text
    remote = find_digest(data)
    if remote is None:
        sys.exit(f"{args.result}: no digest.py result (key 'storm_icons_digest') found")
    _, extraction, local = dry_run(args.set, digest=True)
    keys = sorted(set(remote["props"]) | set(local["props"]))
    bad = 0
    for key in keys:
        a, b = remote["props"].get(key), local["props"].get(key)
        if a == b:
            state = "same"
        elif a is None or b is None:
            state = "only in " + ("the dry run" if a is None else "SketchUp")
        elif a[:3] == b[:3] and a[4] == b[4]:
            state = "same geometry, other order"
        else:
            state = f"DIFFERENT (SketchUp {a[:3]}, dry run {b[:3]})"
        bad += state != "same"
        print(f"  {key:<24} {state}")
    if bad:
        sys.exit(f"{bad} prop(s) differ: import a full extraction of those instead (extract.py with ONLY = [...])")
    print(f"all {len(keys)} props match the offline dry run")
    if args.write:
        write_source(to_source(extraction), args.out or SETS[args.set]["source"])


def check_set(name, table, out):
    """Checks of one icon set; returns the number of problems."""
    spec = SETS[name]
    script = spec["script"]
    failures = 0
    print(f"[{name}]")
    problems = offline_sketchup.check_source(script)
    print(f"Sandbox safety: {'ok' if not problems else 'FAIL'}  {rel(script)}")
    for p in problems:
        print(f"    ! {p}")
    failures += len(problems)
    try:
        reports, extraction = dry_run(name)
        bad = [r for r in reports if r["warnings"]]
        print(f"Dry run: {'ok' if not bad else 'WARN'}  {len(reports)} icons built offline")
        for r in bad:
            print(f"    ~ {r['id']}: {'; '.join(r['warnings'])}")
        scripted = {p["id"] for p in extraction["props"]}
    except Exception as e:  # noqa: BLE001 - report any script failure
        print(f"Dry run: FAIL {type(e).__name__}: {e}")
        failures += 1
        scripted = set()
    source = load_source(spec["source"])
    bad = face_problems(source)
    print(f"Faces: {'ok' if not bad else 'FAIL'}  no self-intersecting faces in the source")
    for b in bad:
        print(f"    ! {b}")
    failures += len(bad)
    wanted = list(table)
    missing = [k for k in wanted if k not in source]
    print(f"Source: {'ok' if not missing else 'FAIL'}  {rel(spec['source'])} holds {len(source)} icons")
    for k in missing:
        print(f"    ! {k} is not imported yet")
    failures += len(missing)
    for k in wanted:
        if scripted and k not in scripted:
            print(f"    ! {k} is in no build chunk of {script.name}")
            failures += 1
    stale = [k for k in wanted if not (out / f"{k}.png").exists()]
    print(f"Renders: {'ok' if not stale else 'FAIL'}  {rel(out)}/<Key>.png")
    for k in stale:
        print(f"    ! {k}.png is missing")
    failures += len(stale)
    return failures


def cmd_check(args):
    import render_icons

    names = [args.set] if args.set_given else list(SETS)
    failures = 0
    for name in names:
        spec = render_icons.SETS[name]
        table = [k for k in spec["table"] if k not in spec.get("scenes", ())]  # scenes are not SketchUp models
        failures += check_set(name, table, spec.get("out", render_icons.OUT))
    print("check passed" if not failures else f"check FAILED ({failures} problem(s))")
    sys.exit(1 if failures else 0)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--set", choices=sorted(SETS), default=None,
                        help="icon set: icons (default), zones (the zone emblems) or store (the store heroes); check "
                             "runs every set unless given")
    sub = parser.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("offline", help="dry run of the SketchUp script -> a preview source")
    p.add_argument("--out", default=None, help="default build/icons/offline/icons.json (zones/store: build/icons/<set>/offline)")
    p.set_defaults(fn=cmd_offline)
    p = sub.add_parser("import", help="merge a SketchUp extraction into the set's source (assets/source/world)")
    p.add_argument("result")
    p.add_argument("--replace", action="store_true")
    p.add_argument("--out", default=None, help="default assets/source/world/icons.json (zones: zone_emblems.json, "
                                               "store: store_icons.json)")
    p.set_defaults(fn=cmd_import)
    p = sub.add_parser("verify", help="compare a SketchUp digest (extract.py + digest.py) with the dry run")
    p.add_argument("result")
    p.add_argument("--write", action="store_true", help="store the dry run as the source when everything matches")
    p.add_argument("--out", default=None, help="default: the set's source (assets/source/world/...)")
    p.set_defaults(fn=cmd_verify)
    p = sub.add_parser("check", help="sandbox safety, dry run, source + renders complete")
    p.set_defaults(fn=cmd_check)
    args = parser.parse_args()
    args.set_given = args.set is not None
    args.set = args.set or "icons"
    args.fn(args)


if __name__ == "__main__":
    main()
