#!/usr/bin/env python3
"""Builds the world prop mesh pack (Roblox) from the SketchUp prop sources.

Pipeline (tools/world/README.md): props are modelled in Trimble SketchUp by the scripts in
tools/world/sketchup/, pulled out with extract.py and imported into assets/source/world/<category>.json
(raw SketchUp polygons) by import_sketchup.py. This script then

  1. converts every prop to studs and Roblox axes (SketchUp inches, Z up, front -Y  ->  studs, Y up,
     front -Z:  rbx = (-x, z, y) / 12), merges its leaf groups by paint, triangulates the polygons
     (ear clipping, holes bridged), computes smooth normals with a crease angle,
  2. validates the prop kit contract (paint names, <= 3000 triangles per prop, sane size, outward
     winding, a default colour for every tint paint),
  3. writes assets/models/StormWorldProps.glb     WorldProps -> <PropId> -> "<PropId>.<Paint>" meshes
                                                   + a 1-stud "<PropId>.Root" cube on the prop's origin
            src/shared/Config/WorldPropsData.luau  Size, Paints, Pieces, Footprint, Collide per prop
  4. renders previews with three.js in headless Chromium (tools/world/viewer.html):
            build/world/<PropId>.png and build/world/sheet.png

Usage (from the repo root):
    python3 tools/world/build_world_pack.py              pack + Luau + renders
    python3 tools/world/build_world_pack.py --no-render  pack + Luau only
    python3 tools/world/build_world_pack.py --check      validate only: script sandbox safety, a dry
                                                         run of the scripts, sources, stale outputs
    python3 tools/world/build_world_pack.py --views      also front/side/back/top renders (build/world/views/)
    python3 tools/world/build_world_pack.py --props TreeRound,LampPost   only render these props
    python3 tools/world/build_world_pack.py --source build/world/offline  preview a local dry run
                                                         (offline_sketchup.py); writes only to that folder

Requirements: Python 3.9+, numpy, Pillow; for renders Chrome/Chromium (CHROME_PATH or Playwright's
headless shell) and three.js (`npm install` in tools/world).
"""

import argparse
import glob
import json
import math
import os
import re
import struct
import subprocess
import sys
import threading
from concurrent.futures import ThreadPoolExecutor
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
HERE = ROOT / "tools" / "world"
SOURCE = ROOT / "assets" / "source" / "world"
GLB = ROOT / "assets" / "models" / "StormWorldProps.glb"
LUAU = ROOT / "src" / "shared" / "Config" / "WorldPropsData.luau"
OUT = ROOT / "build" / "world"
FONT = ROOT / "assets" / "source" / "fonts" / "FredokaOne-Regular.ttf"

INCH = 1.0 / 12.0
MAX_TRIS = 3000
CREASE_DEG = 45.0
ROOT_SIZE = 1.0
PAINT_RE = re.compile(r"^(Primary|Secondary|Tertiary|(Color|Neon|Glass)_[0-9A-F]{6})$")
TINTS = ("Primary", "Secondary", "Tertiary")
GLASS_ALPHA = 0.45
# Props whose origin is not the centre of their base (tools/world/PROPS.md): the base check is skipped
# and the previews frame the whole prop without a ground (viewer.html pivot=1)
PIVOT_PROPS = {"WindmillBlades"}  # origin at the hub centre: MapService spins the blades about it

sys.path.insert(0, str(HERE))


# ------------------------------------------------------------------------------ geometry

def to_roblox(v):
    """SketchUp inches (x, y, z), Z up, front -Y  ->  Roblox studs (-x, z, y), Y up, front -Z."""
    v = np.asarray(v, dtype=np.float64).reshape(-1, 3)
    return np.stack([-v[:, 0], v[:, 2], v[:, 1]], axis=1) * INCH


def newell(pts):
    n = np.zeros(3)
    for i in range(len(pts)):
        a, b = pts[i], pts[(i + 1) % len(pts)]
        n += [(a[1] - b[1]) * (a[2] + b[2]), (a[2] - b[2]) * (a[0] + b[0]), (a[0] - b[0]) * (a[1] + b[1])]
    return n


def cross2(o, a, b):
    return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])


def in_triangle(p, a, b, c):
    eps = -1e-12
    return cross2(a, b, p) >= eps and cross2(b, c, p) >= eps and cross2(c, a, p) >= eps


def segments_cross(p1, p2, q1, q2):
    d1, d2 = cross2(q1, q2, p1), cross2(q1, q2, p2)
    d3, d4 = cross2(p1, p2, q1), cross2(p1, p2, q2)
    return (d1 * d2 < -1e-18) and (d3 * d4 < -1e-18)


def bridge_holes(outer, holes, pts2):
    """Join each hole to the outer loop with a two-way bridge edge (indices into pts2)."""
    poly = list(outer)
    for hole in sorted(holes, key=lambda h: -max(pts2[i][0] for i in h)):
        m = max(range(len(hole)), key=lambda k: pts2[hole[k]][0])
        mp = pts2[hole[m]]
        edges = [(poly[k], poly[(k + 1) % len(poly)]) for k in range(len(poly))]
        for h in holes:
            edges += [(h[k], h[(k + 1) % len(h)]) for k in range(len(h))]
        best = None
        for k, vi in enumerate(poly):
            vp = pts2[vi]
            d = (vp[0] - mp[0]) ** 2 + (vp[1] - mp[1]) ** 2
            if best is not None and d >= best[0]:
                continue
            if any(segments_cross(mp, vp, pts2[a], pts2[b]) for a, b in edges if hole[m] not in (a, b) and vi not in (a, b)):
                continue
            best = (d, k)
        if best is None:
            raise ValueError("cannot bridge a hole")
        k = best[1]
        ring = hole[m:] + hole[:m]
        poly = poly[:k + 1] + ring + [ring[0]] + poly[k:]
    return poly


def ear_clip(poly, pts2):
    """Triangulate a counter-clockwise simple polygon (indices into pts2)."""
    idx = list(poly)
    tris = []
    guard = 0
    while len(idx) > 3 and guard < 10000:
        guard += 1
        n = len(idx)
        clipped = False
        for k in range(n):
            a, b, c = idx[k - 1], idx[k], idx[(k + 1) % n]
            pa, pb, pc = pts2[a], pts2[b], pts2[c]
            if cross2(pa, pb, pc) <= 1e-14:
                continue
            blocked = False
            for j in idx:
                if j in (a, b, c):
                    continue
                pj = pts2[j]
                if (pj[0], pj[1]) in ((pa[0], pa[1]), (pb[0], pb[1]), (pc[0], pc[1])):
                    continue
                if in_triangle(pj, pa, pb, pc):
                    blocked = True
                    break
            if not blocked:
                tris.append((a, b, c))
                del idx[k]
                clipped = True
                break
        if not clipped:  # degenerate leftovers: fan them so nothing is lost
            tris += [(idx[0], idx[i], idx[i + 1]) for i in range(1, len(idx) - 1)]
            return tris
    if len(idx) == 3:
        tris.append(tuple(idx))
    return tris


def triangulate_face(loops, verts):
    """Triangles (vertex ids) for one SketchUp face: outer loop + inner loops (holes)."""
    outer = loops[0]
    if len(loops) == 1 and len(outer) == 3:
        return [tuple(outer)]
    n = newell(verts[outer])
    if np.linalg.norm(n) < 1e-12:
        return []
    axis = int(np.argmax(np.abs(n)))
    u, w = [(1, 2), (2, 0), (0, 1)][axis]
    sign = 1.0 if n[axis] > 0 else -1.0
    pts2 = {i: (verts[i][u] * sign, verts[i][w]) for loop in loops for i in loop}
    if len(loops) == 1:
        ring = list(outer)
        convex = all(cross2(pts2[ring[k - 1]], pts2[ring[k]], pts2[ring[(k + 1) % len(ring)]]) > -1e-12
                     for k in range(len(ring)))
        if convex:
            return [(ring[0], ring[i], ring[i + 1]) for i in range(1, len(ring) - 1)]
        return ear_clip(ring, pts2)
    poly = bridge_holes(list(outer), [list(h) for h in loops[1:]], pts2)
    return ear_clip(poly, pts2)


def smooth_normals(pos, tris, crease_deg=CREASE_DEG):
    """Split vertices by crease angle: (positions, normals, triangles) with smooth shading below it."""
    pos = np.asarray(pos, dtype=np.float64)
    tris = np.asarray(tris, dtype=np.int64)
    p0, p1, p2 = pos[tris[:, 0]], pos[tris[:, 1]], pos[tris[:, 2]]
    fn = np.cross(p1 - p0, p2 - p0)
    fn /= np.maximum(np.linalg.norm(fn, axis=1, keepdims=True), 1e-20)
    angles = np.zeros(tris.shape)
    for k in range(3):
        a, b, c = (p0, p1, p2)[k], (p0, p1, p2)[(k + 1) % 3], (p0, p1, p2)[(k + 2) % 3]
        e1, e2 = b - a, c - a
        cos = np.einsum("ij,ij->i", e1, e2) / np.maximum(np.linalg.norm(e1, axis=1) * np.linalg.norm(e2, axis=1), 1e-20)
        angles[:, k] = np.arccos(np.clip(cos, -1, 1))
    keys = np.round(pos / 1e-4).astype(np.int64)
    _, weld = np.unique(keys, axis=0, return_inverse=True)
    weld = weld.reshape(-1)
    corners = {}
    for t in range(len(tris)):
        for k in range(3):
            corners.setdefault(int(weld[tris[t, k]]), []).append((t, k))
    limit = math.cos(math.radians(crease_deg))
    out_pos, out_nrm, lookup = [], [], {}
    out_tris = np.zeros_like(tris)
    for wid, items in corners.items():
        for t, k in items:
            n = np.zeros(3)
            for t2, k2 in items:
                if np.dot(fn[t], fn[t2]) >= limit:
                    n += fn[t2] * angles[t2, k2]
            n /= max(np.linalg.norm(n), 1e-20)
            key = (wid, int(round(n[0] * 1000)), int(round(n[1] * 1000)), int(round(n[2] * 1000)))
            if key not in lookup:
                lookup[key] = len(out_pos)
                out_pos.append(pos[tris[t, k]])
                out_nrm.append(n)
            out_tris[t, k] = lookup[key]
    return np.asarray(out_pos), np.asarray(out_nrm), out_tris


# ------------------------------------------------------------------------------ loading + validation

def paint_kind(paint):
    if paint in TINTS:
        return "Tint"
    return paint.split("_")[0] if PAINT_RE.match(paint) else "Unknown"


def load_sources(folder):
    props = {}
    for path in sorted(Path(folder).glob("*.json")):
        data = json.loads(path.read_text(encoding="utf-8"))
        if data.get("format") != "storm-world-source/1":
            continue
        for prop_id, prop in data["props"].items():
            if prop_id in props:
                raise SystemExit(f"{path.name}: prop {prop_id} also in {props[prop_id]['file']}")
            prop["category"] = data["category"]
            prop["file"] = path.name
            props[prop_id] = prop
    return props


def build_prop(prop_id, prop):
    """One source prop -> {"pieces": {paint: mesh}, ...} in Roblox studs, plus contract problems."""
    problems, warnings = [], []
    by_paint = {}
    for piece in prop["pieces"]:
        paint = piece["paint"]
        if not PAINT_RE.match(paint):
            problems.append(f'piece "{paint}": not a paint name (Primary/Secondary/Tertiary/Color_/Neon_/Glass_RRGGBB)')
            continue
        verts = to_roblox(piece["v"])
        tris = []
        for face in piece["f"]:
            try:
                tris += triangulate_face(face, verts)
            except ValueError as e:
                problems.append(f"{paint}: {e}")
        tris = np.asarray(tris, dtype=np.int64).reshape(-1, 3)
        a, b, c = verts[tris[:, 0]], verts[tris[:, 1]], verts[tris[:, 2]]
        tris = tris[np.linalg.norm(np.cross(b - a, c - a), axis=1) >= 1e-10]  # drop slivers
        if not len(tris):
            continue
        used = np.unique(tris)
        remap = np.full(len(verts), -1)
        remap[used] = np.arange(len(used))
        # shade each leaf group on its own, with the crease angle it was modelled with
        pos, nrm, t = smooth_normals(verts[used], remap[tris], piece.get("crease") or CREASE_DEG)
        entry = by_paint.setdefault(paint, {"pos": [], "nrm": [], "tris": [], "rgb": None, "collide": None, "n": 0})
        entry["pos"].append(pos)
        entry["nrm"].append(nrm)
        entry["tris"].append(t + entry["n"])
        entry["n"] += len(pos)
        if piece.get("collide") is not None:
            entry["collide"] = bool(piece["collide"]) or bool(entry["collide"])
        if entry["rgb"] is None:
            entry["rgb"] = piece.get("rgb")
    pieces = {}
    total = 0
    for paint, entry in sorted(by_paint.items(), key=lambda kv: (paint_kind(kv[0]) != "Tint", kv[0])):
        p, n, t = np.concatenate(entry["pos"]), np.concatenate(entry["nrm"]), np.concatenate(entry["tris"])
        a, b, c = p[t[:, 0]], p[t[:, 1]], p[t[:, 2]]
        vol = np.einsum("ij,ij->i", a, np.cross(b, c)).sum() / 6.0
        if vol <= 0:
            problems.append(f"{paint}: faces point inward (signed volume {vol:.3f})")
        total += len(t)
        rgb = entry["rgb"] or (prop.get("paints") or {}).get(paint)
        if paint_kind(paint) != "Tint":
            rgb = paint.split("_")[1]
        elif not rgb:
            problems.append(f"{paint}: no default colour (SketchUp material or paints attribute)")
            rgb = "C8C8C8"
        collide = entry["collide"] if entry["collide"] is not None else bool(prop["solid"])
        pieces[paint] = {"pos": p, "nrm": n, "tris": t, "rgb": rgb.upper(), "kind": paint_kind(paint),
                         "collide": collide and paint_kind(paint) not in ("Neon", "Glass")}
    if total > MAX_TRIS:
        problems.append(f"{total} triangles > {MAX_TRIS}")
    if not pieces:
        problems.append("no pieces")
        return {"pieces": {}, "tris": 0}, problems, warnings
    allp = np.concatenate([x["pos"] for x in pieces.values()])
    lo, hi = allp.min(0), allp.max(0)
    size = hi - lo
    if (size < 0.3).any() or (size > 150).any():
        problems.append(f"size {np.round(size, 2).tolist()} studs is not sane (0.3 .. 150 per axis)")
    if prop_id not in PIVOT_PROPS and not -1.5 <= lo[1] <= 0.5:
        problems.append(f"base at y={lo[1]:.2f}: the origin must be at the centre of the prop's base")
    centre = (lo + hi) / 2
    if math.hypot(centre[0], centre[2]) > 0.35 * max(size[0], size[2]) + 0.5:
        warnings.append(f"footprint centre ({centre[0]:.2f}, {centre[2]:.2f}) is far from the origin")
    footprint = float(np.sqrt(allp[:, 0] ** 2 + allp[:, 2] ** 2).max())
    slot = np.asarray(prop.get("slot") or [0, 0, 0], dtype=np.float64)
    return {"pieces": pieces, "tris": total, "lo": lo, "hi": hi, "size": size, "footprint": footprint,
            "slot": to_roblox(slot)[0] * np.array([1, 0, 1]), "solid": bool(prop["solid"]),
            "category": prop["category"]}, problems, warnings


def build_all(props):
    built, report = {}, []
    for prop_id in sorted(props):
        b, problems, warnings = build_prop(prop_id, props[prop_id])
        built[prop_id] = b
        report.append((prop_id, b, problems, warnings))
    return built, report


# ------------------------------------------------------------------------------ outputs

def srgb_to_linear(c):
    c = c / 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hex_rgb(code):
    return [int(code[i:i + 2], 16) for i in (0, 2, 4)]


def cube(size):
    h = size / 2.0
    pos, nrm, tris = [], [], []
    for axis in range(3):
        for s in (-1.0, 1.0):
            n = [0.0, 0.0, 0.0]
            n[axis] = s
            u, w = (axis + 1) % 3, (axis + 2) % 3
            base = len(pos)
            for a, b in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
                p = [0.0, 0.0, 0.0]
                p[axis], p[u], p[w] = s * h, a * h, b * h
                pos.append(p)
                nrm.append(n)
            quad = [(base, base + 1, base + 2), (base, base + 2, base + 3)]
            tris += quad if s > 0 else [(x, z, y) for x, y, z in quad]
    return np.asarray(pos), np.asarray(nrm), np.asarray(tris)


def glb_bytes(built):
    blob = bytearray()
    views, accessors, meshes, materials = [], [], [], []
    nodes = [{"name": "WorldProps", "children": [], "extras": {"generator": "tools/world/build_world_pack.py"}}]

    def add_view(data, target):
        while len(blob) % 4:
            blob.append(0)
        views.append({"buffer": 0, "byteOffset": len(blob), "byteLength": len(data), "target": target})
        blob.extend(data)
        return len(views) - 1

    def add_mesh(name, pos, nrm, tris, material):
        pos = np.asarray(pos, dtype=np.float32)
        nrm = np.asarray(nrm, dtype=np.float32)
        idx = np.asarray(tris, dtype=np.uint32 if len(pos) > 65535 else np.uint16).reshape(-1)
        accessors.append({"bufferView": add_view(pos.tobytes(), 34962), "componentType": 5126, "count": len(pos),
                          "type": "VEC3", "min": pos.min(0).tolist(), "max": pos.max(0).tolist()})
        accessors.append({"bufferView": add_view(nrm.tobytes(), 34962), "componentType": 5126, "count": len(nrm),
                          "type": "VEC3"})
        accessors.append({"bufferView": add_view(idx.tobytes(), 34963), "count": len(idx), "type": "SCALAR",
                          "componentType": 5125 if idx.dtype == np.uint32 else 5123})
        meshes.append({"name": name, "primitives": [{"attributes": {"POSITION": len(accessors) - 3,
                                                                    "NORMAL": len(accessors) - 2},
                                                     "indices": len(accessors) - 1, "material": material}]})
        return len(meshes) - 1

    materials.append({"name": "Root", "pbrMetallicRoughness": {"baseColorFactor": [0.8, 0.8, 0.8, 0.25],
                                                                "metallicFactor": 0.0, "roughnessFactor": 1.0},
                      "alphaMode": "BLEND"})
    root_geo = cube(ROOT_SIZE)
    for prop_id, b in built.items():
        prop_node = {"name": prop_id, "translation": [round(float(x), 4) for x in b["slot"]], "children": [],
                     "extras": {"prop": prop_id, "category": b["category"], "collide": b["solid"]}}
        nodes.append(prop_node)
        nodes[0]["children"].append(len(nodes) - 1)
        for paint, piece in b["pieces"].items():
            rgb = [srgb_to_linear(c) for c in hex_rgb(piece["rgb"])]
            mat = {"name": f"{prop_id}.{paint}", "pbrMetallicRoughness": {
                "baseColorFactor": rgb + [GLASS_ALPHA if piece["kind"] == "Glass" else 1.0],
                "metallicFactor": 0.0, "roughnessFactor": 0.6}}
            if piece["kind"] == "Neon":
                mat["emissiveFactor"] = rgb
            if piece["kind"] == "Glass":
                mat["alphaMode"] = "BLEND"
            materials.append(mat)
            mesh = add_mesh(f"{prop_id}.{paint}", piece["pos"], piece["nrm"], piece["tris"], len(materials) - 1)
            nodes.append({"name": f"{prop_id}.{paint}", "mesh": mesh,
                          "extras": {"prop": prop_id, "paint": paint, "kind": piece["kind"], "rgb": piece["rgb"],
                                     "collide": piece["collide"]}})
            prop_node["children"].append(len(nodes) - 1)
        mesh = add_mesh(f"{prop_id}.Root", *root_geo, 0)
        nodes.append({"name": f"{prop_id}.Root", "mesh": mesh, "extras": {"prop": prop_id, "paint": "Root"}})
        prop_node["children"].append(len(nodes) - 1)
    gltf = {"asset": {"version": "2.0", "generator": "Storm Catcher Simulator tools/world/build_world_pack.py"},
            "scene": 0, "scenes": [{"name": "StormWorldProps", "nodes": [0]}], "nodes": nodes, "meshes": meshes,
            "materials": materials, "accessors": accessors, "bufferViews": views,
            "buffers": [{"byteLength": len(blob)}]}
    while len(blob) % 4:
        blob.append(0)
    gltf["buffers"][0]["byteLength"] = len(blob)
    js = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    js += b" " * ((4 - len(js) % 4) % 4)
    out = bytearray(struct.pack("<4sII", b"glTF", 2, 12 + 8 + len(js) + 8 + len(blob)))
    out += struct.pack("<I4s", len(js), b"JSON") + js
    out += struct.pack("<I4s", len(blob), b"BIN\x00") + blob
    return bytes(out)


def fmt(x):
    s = f"{float(x):.3f}".rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


def v3(v):
    return f"Vector3.new({fmt(v[0])}, {fmt(v[1])}, {fmt(v[2])})"


def c3(code):
    r, g, b = hex_rgb(code)
    return f"Color3.fromRGB({r}, {g}, {b})"


def luau_text(built):
    lines = [
        "--!strict",
        "-- GENERATED by tools/world/build_world_pack.py from assets/source/world/*.json - do not edit by hand.",
        "-- The SketchUp world prop kit (docs/STYLE_GUIDE.md \"Prop kit\", tools/world/README.md). The meshes are in",
        "-- assets/models/StormWorldProps.glb: a model per prop holding MeshParts \"<PropId>.<Paint>\" and a 1-stud",
        "-- \"<PropId>.Root\" cube on the prop's origin (the centre of its base). Studs, Y up, front -Z.",
        "--   Size       bounding box of the prop's pieces; Center = its centre relative to the origin",
        "--   Footprint  radius around the origin (XZ) that the prop covers",
        "--   Collide    players should bump into it (solid in the build script); per piece in Pieces",
        "--   Paints     default colours of the tint paints (Primary/Secondary/Tertiary), recoloured per biome",
        "--   Pieces     Name, Paint, Kind (\"Tint\" | \"Color\" | \"Neon\" | \"Glass\"), Color, Center, Size, Collide, Tris",
        "",
        "export type Piece = {",
        "\tName: string,",
        "\tPaint: string,",
        "\tKind: string,",
        "\tColor: Color3,",
        "\tCenter: Vector3,",
        "\tSize: Vector3,",
        "\tCollide: boolean,",
        "\tTris: number,",
        "}",
        "",
        "export type Prop = {",
        "\tCategory: string,",
        "\tSize: Vector3,",
        "\tCenter: Vector3,",
        "\tFootprint: number,",
        "\tCollide: boolean,",
        "\tTris: number,",
        "\tPaints: { [string]: Color3 },",
        "\tPieces: { Piece },",
        "}",
        "",
        "local WorldPropsData = {}",
        "",
        "WorldPropsData.RootSize = " + fmt(ROOT_SIZE),
        "WorldPropsData.Order = { " + ", ".join(f'"{p}"' for p in built) + " }",
        "",
        "local Props: { [string]: Prop } = {",
    ]
    for prop_id, b in built.items():
        lines.append(f"\t{prop_id} = {{")
        lines.append(f'\t\tCategory = "{b["category"]}",')
        lines.append(f"\t\tSize = {v3(b['size'])},")
        lines.append(f"\t\tCenter = {v3((b['lo'] + b['hi']) / 2)},")
        lines.append(f"\t\tFootprint = {fmt(b['footprint'])},")
        lines.append(f"\t\tCollide = {'true' if b['solid'] else 'false'},")
        lines.append(f"\t\tTris = {b['tris']},")
        tints = [(paint, piece) for paint, piece in b["pieces"].items() if piece["kind"] == "Tint"]
        lines.append("\t\tPaints = { " + ", ".join(f"{paint} = {c3(piece['rgb'])}" for paint, piece in tints) + " },")
        lines.append("\t\tPieces = {")
        for paint, piece in b["pieces"].items():
            lo, hi = piece["pos"].min(0), piece["pos"].max(0)
            lines.append(f'\t\t\t{{ Name = "{prop_id}.{paint}", Paint = "{paint}", Kind = "{piece["kind"]}", '
                         f"Color = {c3(piece['rgb'])}, Center = {v3((lo + hi) / 2)}, Size = {v3(hi - lo)}, "
                         f"Collide = {'true' if piece['collide'] else 'false'}, Tris = {len(piece['tris'])} }},")
        lines.append("\t\t},")
        lines.append("\t},")
    lines += ["}", "", "WorldPropsData.Props = Props", "", "return WorldPropsData", ""]
    return "\n".join(lines)


# ------------------------------------------------------------------------------ rendering

def find_browser():
    candidates = [os.environ.get("CHROME_PATH", "")]
    candidates += sorted(glob.glob("/opt/pw-browsers/chromium_headless_shell-*/chrome-linux/headless_shell"), reverse=True)
    candidates += sorted(glob.glob(os.path.expanduser("~/.cache/ms-playwright/chromium_headless_shell-*/chrome-linux/headless_shell")), reverse=True)
    candidates += ["/usr/bin/chromium", "/usr/bin/chromium-browser", "/usr/bin/google-chrome",
                   r"C:\Program Files\Google\Chrome\Application\chrome.exe",
                   "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"]
    for c in candidates:
        if c and os.path.exists(c):
            return c
    return None


class QuietHandler(SimpleHTTPRequestHandler):
    """Serves the repo root (viewer + three.js) and the pack being rendered at /pack.glb."""
    pack = None

    def log_message(self, *args):
        pass

    def do_GET(self):
        if self.path.split("?")[0] == "/pack.glb" and self.pack is not None:
            data = Path(self.pack).read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", "model/gltf-binary")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return
        super().do_GET()


def rel(path):
    path = Path(path).resolve()
    return path.relative_to(ROOT) if path.is_relative_to(ROOT) else path


def render_all(jobs, glb_path, workers=4):
    browser = find_browser()
    if not browser:
        print("  ! no Chrome/Chromium found (set CHROME_PATH) - skipping renders")
        return False
    if not (HERE / "node_modules" / "three" / "build" / "three.module.js").exists():
        print("  ! three.js missing - run `npm install` in tools/world - skipping renders")
        return False
    handler = type("PackHandler", (QuietHandler,), {"pack": str(glb_path)})
    server = ThreadingHTTPServer(("127.0.0.1", 0), partial(handler, directory=str(ROOT)))
    threading.Thread(target=server.serve_forever, daemon=True).start()
    port = server.server_address[1]
    glb_url = "/pack.glb"

    def one(job):
        prop_id, target, view, size = job
        target.parent.mkdir(parents=True, exist_ok=True)
        url = f"http://127.0.0.1:{port}/tools/world/viewer.html?prop={prop_id}&view={view}&size={size}&glb={glb_url}"
        url += "&pivot=1" if prop_id in PIVOT_PROPS else ""
        command = [browser, "--headless=new", "--no-sandbox", "--use-angle=swiftshader", "--enable-unsafe-swiftshader",
                   "--hide-scrollbars", "--force-device-scale-factor=1", "--default-background-color=00000000",
                   "--virtual-time-budget=20000", f"--window-size={size},{size}", f"--screenshot={target}", url]
        subprocess.run(command, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=180)

    try:
        with ThreadPoolExecutor(max_workers=workers) as pool:
            list(pool.map(one, jobs))
    finally:
        server.shutdown()
    return True


def contact_sheet(built, images, target, title, columns=4, tile=300):
    from PIL import Image, ImageDraw, ImageFilter, ImageFont

    ids = [p for p in built if p in images]
    columns = max(1, min(columns, len(ids)))
    rows = (len(ids) + columns - 1) // columns
    pad, header, label = 22, 96, 54
    width = columns * (tile + pad) + pad
    height = header + rows * (tile + label + pad) + pad
    top, bottom = np.array([120, 205, 255]), np.array([46, 134, 240])
    grad = (top[None, :] + (bottom - top)[None, :] * np.linspace(0, 1, height)[:, None]).astype(np.uint8)
    sheet = Image.fromarray(np.repeat(grad[:, None, :], width, axis=1)).convert("RGBA")
    draw = ImageDraw.Draw(sheet)
    try:
        title_font = ImageFont.truetype(str(FONT), 46)
        name_font = ImageFont.truetype(str(FONT), 24)
        small_font = ImageFont.truetype(str(FONT), 15)
    except OSError:
        title_font = name_font = small_font = ImageFont.load_default()
    draw.text((width / 2, header / 2), title, font=title_font, fill="white", anchor="mm", stroke_width=4,
              stroke_fill=(35, 48, 102))
    for i, prop_id in enumerate(ids):
        row, col = divmod(i, columns)
        x = pad + col * (tile + pad)
        y = header + row * (tile + label + pad)
        b = built[prop_id]
        card = Image.new("RGBA", (tile, tile + label), (0, 0, 0, 0))
        cd = ImageDraw.Draw(card)
        cd.rounded_rectangle((0, 0, tile - 1, tile + label - 1), radius=22, fill=(255, 255, 255, 255),
                             outline=(35, 48, 102, 255), width=3)
        cd.rounded_rectangle((5, 5, tile - 6, tile - 6), radius=18, fill=(234, 243, 255, 255))
        art = Image.open(images[prop_id]).convert("RGBA").resize((tile - 16, tile - 16), Image.LANCZOS)
        card.alpha_composite(art, (8, 6))
        cd = ImageDraw.Draw(card)
        cd.text((tile / 2, tile + 12), prop_id, font=name_font, fill=(35, 48, 102), anchor="mm")
        s = b["size"]
        info = f"{s[0]:.1f} x {s[1]:.1f} x {s[2]:.1f} studs  ·  {b['tris']} tris"
        cd.text((tile / 2, tile + 36), info, font=small_font, fill=(91, 106, 158), anchor="mm")
        shadow = Image.new("RGBA", (tile + 20, tile + label + 20), (0, 0, 0, 0))
        ImageDraw.Draw(shadow).rounded_rectangle((10, 16, tile + 9, tile + label + 15), radius=22, fill=(35, 48, 102, 90))
        sheet.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(5)), (x - 10, y - 10))
        sheet.alpha_composite(card, (x, y))
    target.parent.mkdir(parents=True, exist_ok=True)
    sheet.convert("RGB").save(target)


# ------------------------------------------------------------------------------ main

def print_report(report):
    bad = 0
    for prop_id, b, problems, warnings in report:
        status = "FAIL" if problems else "ok"
        size = np.round(b.get("size", np.zeros(3)), 2).tolist() if b.get("pieces") else "-"
        paints = ", ".join(b["pieces"]) if b.get("pieces") else "-"
        print(f"  {status:<4} {prop_id:<18} {b.get('tris', 0):>5} tris  size {size}  paints {paints}")
        for p in problems:
            print(f"         ! {p}")
        for w in warnings:
            print(f"         ~ {w}")
        bad += bool(problems)
    return bad


def run_check(props, built, report):
    import offline_sketchup

    failures = 0
    print("Sandbox safety of tools/world/sketchup/*.py:")
    for path in sorted((HERE / "sketchup").glob("*.py")):
        problems = offline_sketchup.check_source(path)
        print(f"  {'ok' if not problems else 'FAIL':<4} {path.name}")
        for p in problems:
            print(f"         ! {p}")
        failures += len(problems)
    print("Dry run of the build scripts (offline SketchUp stand-in, sandbox builtins only):")
    try:
        cats = offline_sketchup.category_scripts()
        reports, extraction = offline_sketchup.build_and_extract(cats)
        for r in reports:
            print(f"  {'ok' if not r['warnings'] else 'WARN':<4} {r['id']:<18} {r['tris']:>5} tris  size {r['size']}")
            for w in r["warnings"]:
                print(f"         ~ {w}")
        scripted = {p["id"]: p["category"] for p in extraction["props"]}
        for prop_id, cat in sorted(scripted.items()):
            if prop_id not in props:
                print(f"         ~ {prop_id} ({cat}) is scripted but not imported into assets/source/world yet")
        for prop_id in sorted(props):
            if prop_id not in scripted:
                print(f"         ~ {prop_id} is in assets/source/world but in no build script")
    except Exception as e:  # noqa: BLE001 - report any script failure
        print(f"  FAIL {type(e).__name__}: {e}")
        failures += 1
    print("Sources (assets/source/world/*.json):")
    failures += print_report(report)
    print("Generated files:")
    for path, fresh in ((GLB, glb_bytes(built)), (LUAU, luau_text(built).encode("utf-8"))):
        current = path.read_bytes() if path.exists() else None
        state = "ok" if current == fresh else ("MISSING" if current is None else "STALE")
        print(f"  {state:<7} {path.relative_to(ROOT)}")
        failures += state != "ok"
    print("check passed" if not failures else f"check FAILED ({failures} problem(s))")
    return failures


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true", help="validate only, write nothing")
    parser.add_argument("--no-render", action="store_true", help="skip the preview renders")
    parser.add_argument("--views", action="store_true", help="also front/side/back/top renders")
    parser.add_argument("--props", default="", help="comma-separated prop ids to render (default all)")
    parser.add_argument("--source", default=str(SOURCE), help="source folder (default assets/source/world)")
    args = parser.parse_args()

    source = Path(args.source).resolve()
    preview = source != SOURCE.resolve()
    props = load_sources(source)
    if not props:
        sys.exit(f"no prop sources in {source}")
    built, report = build_all(props)
    if args.check:
        sys.exit(1 if run_check(props, built, report) else 0)

    print(f"Props from {rel(source)}:")
    if print_report(report):
        sys.exit("contract problems - nothing written")
    glb_path = source / "StormWorldProps.glb" if preview else GLB
    out_dir = source if preview else OUT
    glb_path.parent.mkdir(parents=True, exist_ok=True)
    glb_path.write_bytes(glb_bytes(built))
    print(f"wrote {rel(glb_path)} ({glb_path.stat().st_size // 1024} KB, {len(built)} props)")
    if not preview:
        LUAU.write_text(luau_text(built), encoding="utf-8")
        print(f"wrote {LUAU.relative_to(ROOT)}")
    if args.no_render:
        return
    wanted = [p for p in args.props.split(",") if p] or list(built)
    jobs = [(p, out_dir / f"{p}.png", "hero", 512) for p in wanted if p in built]
    if args.views:
        jobs += [(p, out_dir / "views" / f"{p}_{v}.png", v, 512) for p in wanted if p in built
                 for v in ("front", "side", "back", "top")]
    if render_all(jobs, glb_path):
        images = {p: out_dir / f"{p}.png" for p in built if (out_dir / f"{p}.png").exists()}
        contact_sheet(built, images, out_dir / "sheet.png", "Storm World Props")
        print(f"rendered {len(jobs)} views -> {rel(out_dir)}/ (+ sheet.png)")


if __name__ == "__main__":
    main()
