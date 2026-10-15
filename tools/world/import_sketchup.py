#!/usr/bin/env python3
"""Imports a SketchUp prop extraction into assets/source/world/<category>.json.

tools/world/sketchup/extract.py, run in SketchUp through the Trimble SketchUp MCP (build_model),
returns every Prop_<PropId> group as raw polygons. Big build_model results are saved by the agent
harness to a tool-result file; small ones come back inline (save them to a .json file). This script
reads either (or a plain JSON dump of the result), finds the extraction in it and writes one source
file per prop category:

    assets/source/world/<category>.json
        {"format": "storm-world-source/1", "category": "common", "units": "inch", "props": {
            "TreeRound": {"solid": true, "slot": [x, y, z], "paints": {"Primary": "5CC94F", ...},
                          "pieces": [{"paint": "Primary", "rgb": "5CC94F", "alpha": 255, "collide": null, "crease": 40,
                                      "v": [x, y, z, ...], "f": [[[outer...], [hole...]], ...]}, ...]}}}

Coordinates stay in SketchUp space (inches, Z up, front -Y, prop-local), rounded to 0.01 in;
tools/world/build_world_pack.py converts them to studs and Roblox axes. Props in the extraction
replace props of the same id; other props already in the file are kept unless --replace.

Usage:
    python3 tools/world/import_sketchup.py <tool-result file | extraction .json> [--replace] [--out DIR]
"""

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "assets" / "source" / "world"
FORMAT = "storm-world-source/1"


def find_extraction(obj, depth=0):
    """The extract.py result dict somewhere inside a tool-result structure (dicts, lists, JSON text)."""
    if depth > 8:
        return None
    if isinstance(obj, dict):
        if "storm_world_extract" in obj:
            return obj
        for value in obj.values():
            found = find_extraction(value, depth + 1)
            if found is not None:
                return found
    elif isinstance(obj, list):
        for value in obj:
            found = find_extraction(value, depth + 1)
            if found is not None:
                return found
    elif isinstance(obj, str) and "storm_world_extract" in obj:
        try:
            return find_extraction(json.loads(obj), depth + 1)
        except ValueError:
            pass
        decoder = json.JSONDecoder()
        start = obj.find("{")
        while start >= 0:
            try:
                value, _ = decoder.raw_decode(obj, start)
                found = find_extraction(value, depth + 1)
                if found is not None:
                    return found
            except ValueError:
                pass
            start = obj.find("{", start + 1)
    return None


def load_extraction(path):
    text = Path(path).read_text(encoding="utf-8")
    try:
        data = json.loads(text)
    except ValueError:
        data = text
    found = find_extraction(data)
    if found is None:
        raise SystemExit(f"{path}: no extract.py result (key 'storm_world_extract') found")
    return found


def r2(x):
    x = round(float(x), 2)
    return int(x) if x == int(x) else x


def clean_piece(piece):
    return {"paint": piece.get("paint") or "Unpainted", "rgb": piece.get("rgb"), "alpha": int(piece.get("alpha", 255)),
            "collide": piece.get("collide"), "crease": None if piece.get("crease") is None else r2(piece["crease"]),
            "v": [r2(x) for x in piece["v"]],
            "f": [[[int(i) for i in loop] for loop in face] for face in piece["f"]]}


def dumps_source(category, props):
    """Readable JSON: one line per piece header, vertex table and face list."""
    out = ["{", f'  "format": "{FORMAT}",', f'  "category": {json.dumps(category)},',
           '  "units": "inch (SketchUp: Z up, front -Y, origin at the base centre of each prop)",', '  "props": {']
    ids = sorted(props)
    for n, prop_id in enumerate(ids):
        p = props[prop_id]
        out.append(f"    {json.dumps(prop_id)}: {{")
        out.append(f'      "solid": {json.dumps(bool(p["solid"]))}, "slot": {json.dumps(p["slot"])}, '
                   f'"paints": {json.dumps(p["paints"], sort_keys=True)},')
        out.append('      "pieces": [')
        for k, piece in enumerate(p["pieces"]):
            head = {key: piece.get(key) for key in ("paint", "rgb", "alpha", "collide", "crease")}
            out.append("        {" + json.dumps(head)[1:-1] + ",")
            out.append('         "v": ' + json.dumps(piece["v"], separators=(",", ":")) + ",")
            out.append('         "f": ' + json.dumps(piece["f"], separators=(",", ":")) + "}"
                       + ("," if k < len(p["pieces"]) - 1 else ""))
        out.append("      ]")
        out.append("    }" + ("," if n < len(ids) - 1 else ""))
    out += ["  }", "}", ""]
    return "\n".join(out)


def import_extraction(extraction, out_dir=SOURCE, replace=False):
    """Writes/updates <out_dir>/<category>.json from an extraction; returns the written paths."""
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    by_cat = {}
    for prop in extraction["props"]:
        pieces = [clean_piece(x) for x in prop["pieces"] if x.get("f")]
        if not pieces:
            print(f"  ! {prop['id']}: no faces - skipped")
            continue
        entry = {"solid": bool(prop.get("solid")), "slot": [r2(x) for x in prop.get("slot", [0, 0, 0])],
                 "paints": {k: str(v).upper() for k, v in (prop.get("paints") or {}).items()}, "pieces": pieces}
        by_cat.setdefault(prop.get("category") or "misc", {})[prop["id"]] = entry
    written = []
    for cat, props in sorted(by_cat.items()):
        path = out_dir / f"{cat}.json"
        merged = {}
        if path.exists() and not replace:
            merged = json.loads(path.read_text(encoding="utf-8")).get("props", {})
        merged.update(props)
        path.write_text(dumps_source(cat, merged), encoding="utf-8")
        written.append(path)
        for prop_id, p in sorted(props.items()):
            faces = sum(len(x["f"]) for x in p["pieces"])
            paints = sorted({x["paint"] for x in p["pieces"]})
            print(f"  {cat}/{prop_id}: {len(p['pieces'])} pieces, {faces} faces, paints {', '.join(paints)}")
    return written


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("result", help="tool-result file or JSON holding the extract.py result")
    parser.add_argument("--replace", action="store_true", help="replace whole category files instead of merging")
    parser.add_argument("--out", default=str(SOURCE), help=f"output folder (default {SOURCE.relative_to(ROOT)})")
    args = parser.parse_args()
    extraction = load_extraction(args.result)
    if not extraction.get("props"):
        sys.exit("the extraction holds no props")
    written = import_extraction(extraction, args.out, args.replace)
    for p in written:
        print(f"wrote {p.relative_to(ROOT) if p.is_relative_to(ROOT) else p}")


if __name__ == "__main__":
    main()
