#!/usr/bin/env python3
"""Renders the real game world without Roblox, so map changes can be checked visually.

Runs the real src/server/Services/MapService.luau (Init, then Start if it has one) inside a mock Roblox
runtime (tools/preview/MapMock.luau) under the `luau` command line, dumps the world it builds as JSON
(every part, Terrain fills, lighting, sign text), then draws it with three.js in headless Chromium.

Usage (from the repo root):
    python3 tools/preview_map.py                      overview + every region, aerial and eye-level shots
    python3 tools/preview_map.py --region hub         only the Storm Station hub (also: 1..6, all)
    python3 tools/preview_map.py --region 3 --out build/preview
    python3 tools/preview_map.py --dump-only          only write build/preview/world.json (no browser)
    python3 tools/preview_map.py --size 1920x1080     image size (default 1600x900)

Output (build/preview/ by default, ignored by git):
    overview.png                    the whole world from above
    <region>_aerial.png             each region from above   (region = hub, 1_meadows, 2_thunder, ...)
    <region>_eye.png                each region at player eye level from its spawn, looking along +X
    world.json                      the raw dump (parts, terrain fills, lighting, gui text, warnings)
    contact_sheet.png               all shots on one page (when Pillow is installed)

Requirements:
    luau        the Luau command line (https://github.com/luau-lang/luau/releases): on PATH, or LUAU=path
    Chromium    Playwright's headless shell (PLAYWRIGHT_BROWSERS_PATH or ~/.cache/ms-playwright), a system
                Chrome/Chromium, or CHROME_PATH=path
    three.js    `npm install` in tools/preview (tools/world or tools/pets node_modules also work)
    Python 3.9+ with numpy; Pillow is optional (contact sheet)

World prop meshes: MeshParts named "<PropId>.<Paint>" are drawn with the matching mesh from
assets/models/StormWorldProps.glb when it exists. The mock's InsertService:LoadAsset returns that pack
(WorldProps -> <PropId> -> MeshParts) so a MapService that loads the uploaded pack sees it too; pass
--pack-at Service/Path to also put it in the DataModel (e.g. --pack-at ReplicatedStorage/WorldProps).

When MapService uses something the mock doesn't know, the run stops with a message naming the class,
property or method: add it to tools/preview/MapMock.luau (CLASSES / methods) and run again.
"""

import argparse
import glob
import json
import math
import os
import re
import shutil
import struct
import subprocess
import sys
import threading
import time
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HERE = ROOT / "tools" / "preview"
MOCK = HERE / "MapMock.luau"
PROJECT = ROOT / "default.project.json"
GLB = ROOT / "assets" / "models" / "StormWorldProps.glb"
SERVICE = "ServerScriptService/Server/Services/MapService"
DEFAULT_PACK_AT = "ServerStorage/WorldProps"

REGION_KEYS = ["hub", "1", "2", "3", "4", "5", "6"]


# --------------------------------------------------------------------------------------- luau bundle

def find_luau(explicit):
    for candidate in (explicit, os.environ.get("LUAU"), shutil.which("luau")):
        if candidate and os.path.exists(candidate):
            return candidate
    return None


def long_string(text):
    level = 0
    while f"]{'=' * level}]" in text:
        level += 1
    eq = "=" * level
    return f"[{eq}[\n{text}]{eq}]"


def lua_value(value):
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return repr(value)
    if isinstance(value, str):
        return json.dumps(value)  # JSON string escapes are valid Luau string escapes
    if isinstance(value, list):
        return "{" + ", ".join(lua_value(v) for v in value) + "}"
    if isinstance(value, dict):
        return "{" + ", ".join(f"[{json.dumps(k)}] = {lua_value(v)}" for k, v in value.items()) + "}"
    if value is None:
        return "nil"
    raise TypeError(f"can't write {value!r} as Luau")


def script_kind(filename):
    """Rojo file naming: Foo.luau -> ModuleScript, Foo.server.luau -> Script, Foo.client.luau -> LocalScript."""
    for suffix, kind in ((".server.luau", "Script"), (".client.luau", "LocalScript"), (".server.lua", "Script"),
                         (".client.lua", "LocalScript"), (".luau", "ModuleScript"), (".lua", "ModuleScript")):
        if filename.endswith(suffix):
            return filename[: -len(suffix)], kind
    return None, None


def project_nodes(tree, path, out):
    """Walks default.project.json like Rojo does: emits (kind, instance path, payload) entries."""
    for name, node in tree.items():
        if name.startswith("$") or not isinstance(node, dict):
            continue
        child_path = f"{path}/{name}" if path else name
        class_name = node.get("$className")
        source = node.get("$path")
        if isinstance(source, dict):
            source = source.get("optional")
        if source:
            full = ROOT / source
            if full.is_dir():
                out.append(("node", child_path, class_name or "Folder"))
                directory_nodes(full, child_path, out)
            elif full.is_file():
                stem, kind = script_kind(full.name)
                if kind == "ModuleScript":
                    out.append(("module", child_path, full))
                elif full.suffix in (".rbxm", ".rbxmx"):
                    out.append(("binary", child_path, full))
        elif class_name and path:
            out.append(("node", child_path, class_name))
        if node.get("$properties"):
            out.append(("props", child_path, node["$properties"]))
        project_nodes(node, child_path, out)


def directory_nodes(directory, path, out):
    for entry in sorted(directory.iterdir()):
        if entry.is_dir():
            init = next((entry / n for n in ("init.luau", "init.lua") if (entry / n).exists()), None)
            if init:
                out.append(("module", f"{path}/{entry.name}", init))
            else:
                out.append(("node", f"{path}/{entry.name}", "Folder"))
            directory_nodes(entry, f"{path}/{entry.name}", out)
        elif entry.is_file() and not entry.name.startswith("init."):
            stem, kind = script_kind(entry.name)
            if kind == "ModuleScript":
                out.append(("module", f"{path}/{stem}", entry))
            elif kind:
                out.append(("node", f"{path}/{stem}", kind))


def read_glb(path):
    """Returns (gltf json, binary chunk) of a .glb file."""
    data = path.read_bytes()
    magic, version, length = struct.unpack_from("<4sII", data, 0)
    if magic != b"glTF":
        raise ValueError(f"{path} is not a GLB file")
    offset, js, blob = 12, None, b""
    while offset < length:
        chunk_length, chunk_type = struct.unpack_from("<I4s", data, offset)
        chunk = data[offset + 8: offset + 8 + chunk_length]
        if chunk_type == b"JSON":
            js = json.loads(chunk.decode("utf-8"))
        elif chunk_type == b"BIN\x00":
            blob = chunk
        offset += 8 + chunk_length
    return js, blob


def node_matrix(node):
    """4x4 (row-major nested lists) local transform of a glTF node."""
    import numpy as np
    if "matrix" in node:
        return np.array(node["matrix"], dtype=float).reshape(4, 4).T
    t = node.get("translation", [0, 0, 0])
    r = node.get("rotation", [0, 0, 0, 1])
    s = node.get("scale", [1, 1, 1])
    x, y, z, w = r
    rot = np.array([
        [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
        [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
    ])
    m = np.eye(4)
    m[:3, :3] = rot * np.array(s)
    m[:3, 3] = t
    return m


PAINT_RE = re.compile(r"^(Color|Neon|Glass)_([0-9A-Fa-f]{6})$")


def pack_from_glb(path):
    """Describes the prop pack (props, pieces with bounding boxes) for the mock and the renderer."""
    import numpy as np
    gltf, blob = read_glb(path)
    nodes = gltf.get("nodes", [])
    accessors = gltf.get("accessors", [])
    materials = gltf.get("materials", [])

    def mesh_bounds(mesh_index):
        lo, hi = np.full(3, np.inf), np.full(3, -np.inf)
        for prim in gltf["meshes"][mesh_index]["primitives"]:
            acc = accessors[prim["attributes"]["POSITION"]]
            if "min" in acc and "max" in acc:
                lo = np.minimum(lo, acc["min"])
                hi = np.maximum(hi, acc["max"])
            else:
                view = gltf["bufferViews"][acc["bufferView"]]
                start = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
                pts = np.frombuffer(blob, dtype=np.float32, count=acc["count"] * 3, offset=start).reshape(-1, 3)
                lo, hi = np.minimum(lo, pts.min(0)), np.maximum(hi, pts.max(0))
        return lo, hi

    def mesh_color(mesh_index):
        prim = gltf["meshes"][mesh_index]["primitives"][0]
        if "material" not in prim:
            return "CCCCCC", 1.0
        pbr = materials[prim["material"]].get("pbrMetallicRoughness", {})
        r, g, b, a = pbr.get("baseColorFactor", [0.8, 0.8, 0.8, 1])

        def to_srgb(c):
            c = max(0.0, min(1.0, c))
            return 12.92 * c if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055
        return "%02X%02X%02X" % tuple(round(to_srgb(c) * 255) for c in (r, g, b)), a

    root_index = next((i for i, n in enumerate(nodes) if n.get("name") == "WorldProps"), None)
    prop_indices = nodes[root_index].get("children", []) if root_index is not None else [
        i for i, n in enumerate(nodes) if n.get("children") and "." not in n.get("name", "")]
    props = []
    for prop_index in prop_indices:
        prop_node = nodes[prop_index]
        prop_id = prop_node.get("name", f"Prop{prop_index}")
        prop_matrix = node_matrix(prop_node)
        pieces = []
        for child_index in prop_node.get("children", []):
            child = nodes[child_index]
            if "mesh" not in child:
                continue
            name = child.get("name", "")
            paint = name.split(".", 1)[1] if "." in name else name
            local = node_matrix(child)
            lo, hi = mesh_bounds(child["mesh"])
            # pieces are expected to carry no rotation; transform the box corners to be safe
            corners = np.array([[x, y, z, 1] for x in (lo[0], hi[0]) for y in (lo[1], hi[1]) for z in (lo[2], hi[2])])
            moved = (local @ corners.T).T[:, :3]
            plo, phi = moved.min(0), moved.max(0)
            extras = child.get("extras", {})
            kind = extras.get("kind")
            color, alpha = mesh_color(child["mesh"])
            match = PAINT_RE.match(paint)
            if not kind:
                kind = "Root" if paint == "Root" else (match.group(1) if match else "Tint")
            if extras.get("rgb"):
                color = str(extras["rgb"]).lstrip("#").upper()
            elif match:
                color = match.group(2).upper()
            transparency = 0.0
            if paint == "Root":
                kind, transparency = "Root", round(1 - alpha, 3)
            elif kind == "Glass":
                transparency = round(1 - alpha, 3) if alpha < 1 else 0.55
            pieces.append({
                "Name": name, "Paint": paint, "Kind": kind, "Color": color,
                "Center": [round(float(v), 4) for v in (plo + phi) / 2],
                "Size": [round(max(float(v), 0.01), 4) for v in (phi - plo)],
                "Collide": bool(extras.get("collide", False)), "Transparency": transparency,
                "Mesh": child["mesh"],
            })
        props.append({"Id": prop_id, "Slot": [round(float(v), 4) for v in prop_matrix[:3, 3]], "Pieces": pieces})
    return props


def build_bundle(args, pack):
    chunks = ["local __mock = (function()\n" + MOCK.read_text(encoding="utf-8") + "\nend)()"]
    entries = []
    project = json.loads(PROJECT.read_text(encoding="utf-8"))
    project_nodes(project["tree"], "", entries)
    pack_paths = []
    for kind, path, payload in entries:
        if kind == "node":
            chunks.append(f"__mock.Node({json.dumps(path)}, {json.dumps(payload)})")
        elif kind == "module":
            chunk = payload.relative_to(ROOT).as_posix()
            source = payload.read_text(encoding="utf-8")
            chunks.append(f"__mock.Module({json.dumps(path)}, {json.dumps(chunk)}, {long_string(source)})")
        elif kind == "props":
            props = {k: v for k, v in payload.items() if isinstance(v, (bool, int, float, str, list))}
            chunks.append(f"__mock.SetProps({json.dumps(path)}, {lua_value(props)})")
        elif kind == "binary" and "worldprop" in path.lower().replace("_", ""):
            pack_paths.append(path)
    if pack is not None:
        mock_pack = [{"Id": p["Id"], "Slot": p["Slot"], "Pieces": [
            {k: v for k, v in piece.items() if k != "Mesh"} for piece in p["Pieces"]]} for p in pack]
        chunks.append(f"__mock.SetPack({lua_value(mock_pack)})")
        targets = pack_paths + [p for p in (args.pack_at or [DEFAULT_PACK_AT]) if p.lower() != "none"]
        for path in dict.fromkeys(targets):
            chunks.append(f"__mock.PlacePack({json.dumps(path)})")
    config = {"Service": args.service, "Start": not args.no_start, "SimSeconds": args.sim_seconds,
              "Layout": "ReplicatedStorage/Shared/Config/MapLayout", "Zones": "ReplicatedStorage/Shared/Config/Zones"}
    chunks.append(f"if not __mock.Run({lua_value(config)}) then error('MapService raised errors (see above)', 0) end")
    return "\n".join(chunks) + "\n"


def run_mock(args, out_dir, pack):
    luau = find_luau(args.luau)
    if not luau:
        sys.exit("luau not found: install it (https://github.com/luau-lang/luau/releases) or set LUAU=path/to/luau")
    bundle_path = out_dir / "preview_bundle.luau"
    bundle_path.write_text(build_bundle(args, pack), encoding="utf-8")
    started = time.time()
    result = subprocess.run([luau, str(bundle_path)], capture_output=True, text=True, encoding="utf-8")
    world = None
    other = []
    for line in result.stdout.splitlines():
        if line.startswith("@@WORLD@@"):
            world = json.loads(line[len("@@WORLD@@"):])
        elif line.strip():
            other.append(line)
    for line in other:
        print("  luau:", line)
    if result.stderr.strip():
        print(result.stderr.strip())
    if world is None:
        sys.exit(f"the mock run failed before dumping the world (exit code {result.returncode}); bundle: {bundle_path}")
    for message in world.get("Warnings", []):
        print("  warn:", message)
    for message in world.get("Prints", []):
        print("  print:", message)
    errors = world.get("Errors", [])
    for message in errors:
        print("  ERROR:", message.replace("\n", "\n         "))
    print(f"  mock: {len(world['Parts'])} parts, {len(world['Terrain']['Fills'])} terrain fills, "
          f"{len(world['Guis'])} guis in {time.time() - started:.1f}s")
    if errors and not args.keep_going:
        sys.exit("MapService failed in the mock (fix the error above, or pass --keep-going to render anyway)")
    return world




# --------------------------------------------------------------------------------------- terrain

def srgb_to_linear(c):
    import numpy as np
    c = np.asarray(c, dtype=np.float64)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def hex_rgb(hexcode):
    hexcode = str(hexcode).lstrip("#")
    return [int(hexcode[i:i + 2], 16) / 255 for i in (0, 2, 4)]


def fill_footprint(fill):
    """(min x, min z, max x, max z) of a terrain fill."""
    import numpy as np
    if fill["Kind"] == "Ball":
        x, _, z = fill["Center"]
        r = fill["Radius"]
        return x - r, z - r, x + r, z + r
    cf = fill["CFrame"]
    rot = np.array(cf[3:12]).reshape(3, 3)
    if fill["Kind"] == "Cylinder":
        half = np.array([fill["Radius"], fill["Height"] / 2, fill["Radius"]])
    else:
        half = np.array(fill["Size"]) / 2
    ext = np.abs(rot) @ half
    return cf[0] - ext[0], cf[2] - ext[2], cf[0] + ext[0], cf[2] + ext[2]


def fill_columns(fill, X, Z):
    """Top and bottom heights of a fill along vertical lines at (X, Z), and where it covers them."""
    import numpy as np
    if fill["Kind"] == "Ball":
        cx, cy, cz = fill["Center"]
        d2 = fill["Radius"] ** 2 - (X - cx) ** 2 - (Z - cz) ** 2
        inside = d2 >= 0
        root = np.sqrt(np.maximum(d2, 0))
        return cy + root, cy - root, inside
    cf = fill["CFrame"]
    c = np.array(cf[:3])
    rot = np.array(cf[3:12]).reshape(3, 3)
    # local = R^T (p - c), with p = (X, y, Z):  local = a + y * b
    rt = rot.T
    px, pz = X - c[0], Z - c[2]
    a = [rt[i, 0] * px + rt[i, 1] * (-c[1]) + rt[i, 2] * pz for i in range(3)]
    b = rt[:, 1]
    lo = np.full(X.shape, -np.inf)
    hi = np.full(X.shape, np.inf)
    inside = np.ones(X.shape, dtype=bool)

    def slab(i, h):
        nonlocal lo, hi, inside
        if abs(b[i]) < 1e-9:
            inside &= np.abs(a[i]) <= h
        else:
            t0 = (-h - a[i]) / b[i]
            t1 = (h - a[i]) / b[i]
            lo = np.maximum(lo, np.minimum(t0, t1))
            hi = np.minimum(hi, np.maximum(t0, t1))

    if fill["Kind"] == "Cylinder":
        slab(1, fill["Height"] / 2)
        r = fill["Radius"]
        qa = b[0] ** 2 + b[2] ** 2
        qb = 2 * (a[0] * b[0] + a[2] * b[2])
        qc = a[0] ** 2 + a[2] ** 2 - r * r
        if qa < 1e-9:
            inside &= qc <= 0
        else:
            disc = qb * qb - 4 * qa * qc
            inside &= disc >= 0
            root = np.sqrt(np.maximum(disc, 0))
            lo = np.maximum(lo, (-qb - root) / (2 * qa))
            hi = np.minimum(hi, (-qb + root) / (2 * qa))
    else:  # Block, Wedge (drawn as its block)
        size = fill["Size"]
        for i in range(3):
            slab(i, size[i] / 2)
    inside &= lo <= hi
    return hi, lo, inside


def terrain_mesh(terrain, res=2.0):
    """Height-field mesh of the Terrain fills: positions, linear colours and triangle indices (numpy)."""
    import numpy as np
    fills = terrain.get("Fills") or []
    if not fills:
        return None
    colors = terrain.get("MaterialColors", {})
    prints = [fill_footprint(f) for f in fills]
    x0 = math.floor(min(p[0] for p in prints) / res) * res - res
    z0 = math.floor(min(p[1] for p in prints) / res) * res - res
    x1 = math.ceil(max(p[2] for p in prints) / res) * res + res
    z1 = math.ceil(max(p[3] for p in prints) / res) * res + res
    nx, nz = int(round((x1 - x0) / res)) + 1, int(round((z1 - z0) / res)) + 1
    height = np.full((nz, nx), -np.inf)
    bottom = np.full((nz, nx), np.inf)
    mat = np.full((nz, nx), -1, dtype=np.int32)
    names = []
    for fill, (fx0, fz0, fx1, fz1) in zip(fills, prints):
        i0, i1 = max(0, int((fx0 - x0) / res) - 1), min(nx, int((fx1 - x0) / res) + 2)
        j0, j1 = max(0, int((fz0 - z0) / res) - 1), min(nz, int((fz1 - z0) / res) + 2)
        if i0 >= i1 or j0 >= j1:
            continue
        X, Z = np.meshgrid(x0 + np.arange(i0, i1) * res, z0 + np.arange(j0, j1) * res)
        top, low, inside = fill_columns(fill, X, Z)
        H = height[j0:j1, i0:i1]
        if fill["Material"] == "Air":
            carve = inside & (top >= H - 0.01) & (low < H)
            H[carve] = low[carve]
            continue
        if fill["Material"] not in names:
            names.append(fill["Material"])
        index = names.index(fill["Material"])
        update = inside & (top >= H - 0.05)
        H[update] = np.maximum(H[update], top[update])
        mat[j0:j1, i0:i1][update] = index
        B = bottom[j0:j1, i0:i1]
        B[inside] = np.minimum(B[inside], low[inside])

    valid = np.isfinite(height) & (mat >= 0)
    if not valid.any():
        return None
    # soften: a few 3x3 blur passes where all neighbours are solid (smooth terrain rounds its edges)
    for _ in range(3):
        padded = np.pad(np.where(valid, height, np.nan), 1, constant_values=np.nan)
        stack = np.stack([padded[1 + dj: nz + 1 + dj, 1 + di: nx + 1 + di] for dj in (-1, 0, 1) for di in (-1, 0, 1)])
        full = ~np.isnan(stack).any(axis=0)
        mean = np.where(full, np.nan_to_num(stack).sum(axis=0) / 9.0, height)
        height = np.where(valid, mean, height)

    # cliff skirt: empty points next to solid ones drop to the neighbours' bottom
    vpad = np.pad(valid, 1)
    neighbour = np.zeros_like(valid)
    low_pad = np.pad(np.where(valid, bottom, np.inf), 1, constant_values=np.inf)
    skirt_low = np.full((nz, nx), np.inf)
    for dj in (-1, 0, 1):
        for di in (-1, 0, 1):
            neighbour |= vpad[1 + dj: nz + 1 + dj, 1 + di: nx + 1 + di]
            skirt_low = np.minimum(skirt_low, low_pad[1 + dj: nz + 1 + dj, 1 + di: nx + 1 + di])
    skirt = neighbour & ~valid
    floor = float(np.nanmin(np.where(np.isfinite(bottom), bottom, np.nan)))
    skirt_low = np.where(np.isfinite(skirt_low), skirt_low, floor)
    heights = np.where(valid, height, np.where(skirt, skirt_low, 0.0))
    used = valid | skirt

    # colours: material colour, darker on steep slopes and on the cliff skirt, a little per-vertex noise
    palette = np.array([hex_rgb(colors.get(n, "808080")) for n in names] or [[0.5, 0.5, 0.5]])
    mat_filled = mat.copy()
    for dj in (-1, 0, 1):  # skirt points take a neighbour's material
        for di in (-1, 0, 1):
            shifted = np.pad(mat, 1, constant_values=-1)[1 + dj: nz + 1 + dj, 1 + di: nx + 1 + di]
            mat_filled = np.where((mat_filled < 0) & (shifted >= 0), shifted, mat_filled)
    rgb = palette[np.clip(mat_filled, 0, len(palette) - 1)]
    gz, gx = np.gradient(np.where(used, heights, 0.0), res)
    steep = 1 / np.sqrt(1 + gx * gx + gz * gz)
    shade = 0.78 + 0.22 * steep
    shade = np.where(skirt, 0.62, shade)
    rng = np.random.default_rng(7)
    noise = 1 + (rng.random((nz, nx)) - 0.5) * 0.05 * steep ** 4
    rgb = rgb * (shade * noise)[..., None]
    linear = srgb_to_linear(np.clip(rgb, 0, 1))

    # vertices for used points; two triangles per quad with at least one solid corner
    index_of = np.full((nz, nx), -1, dtype=np.int64)
    flat = np.flatnonzero(used.ravel())
    index_of.ravel()[flat] = np.arange(len(flat))
    jj, ii = np.unravel_index(flat, (nz, nx))
    positions = np.stack([x0 + ii * res, heights[jj, ii], z0 + jj * res], axis=1).astype(np.float32)
    vertex_colors = linear[jj, ii].astype(np.float32)
    a = index_of[:-1, :-1]
    b = index_of[:-1, 1:]
    c = index_of[1:, :-1]
    d = index_of[1:, 1:]
    solid_quad = valid[:-1, :-1] | valid[:-1, 1:] | valid[1:, :-1] | valid[1:, 1:]
    quad = (a >= 0) & (b >= 0) & (c >= 0) & (d >= 0) & solid_quad
    a, b, c, d = a[quad], b[quad], c[quad], d[quad]
    # counter-clockwise seen from above (+Y): a(x,z) b(x+1,z) c(x,z+1) d(x+1,z+1)
    tris = np.concatenate([np.stack([a, c, b], 1), np.stack([b, c, d], 1)]).astype(np.uint32)
    return positions, vertex_colors, tris


# --------------------------------------------------------------------------------------- prop meshes

def read_accessor(gltf, blob, index):
    import numpy as np
    acc = gltf["accessors"][index]
    view = gltf["bufferViews"][acc["bufferView"]]
    dtype = {5126: np.float32, 5125: np.uint32, 5123: np.uint16, 5121: np.uint8}[acc["componentType"]]
    width = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[acc["type"]]
    start = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
    item = np.dtype(dtype).itemsize * width
    stride = view.get("byteStride", item)
    raw = np.frombuffer(blob, dtype=np.uint8, count=stride * (acc["count"] - 1) + item, offset=start)
    rows = np.lib.stride_tricks.as_strided(raw, shape=(acc["count"], item), strides=(stride, 1))
    return np.ascontiguousarray(rows).view(dtype).reshape(acc["count"], width)


def export_meshes(names, path):
    """Writes the pack meshes used in the world, normalised to a unit box around their centre, to `path`."""
    import numpy as np
    gltf, blob = read_glb(GLB)
    by_name = {n.get("name"): n for n in gltf.get("nodes", []) if "mesh" in n}
    items, chunks, offset = {}, [], 0
    for name in sorted(names):
        node = by_name.get(name)
        if node is None:
            continue
        positions, normals, indices = [], [], []
        base = 0
        local = node_matrix(node)
        for prim in gltf["meshes"][node["mesh"]]["primitives"]:
            pos = read_accessor(gltf, blob, prim["attributes"]["POSITION"]).astype(np.float64)
            nrm = read_accessor(gltf, blob, prim["attributes"]["NORMAL"]).astype(np.float64) \
                if "NORMAL" in prim["attributes"] else np.zeros_like(pos)
            idx = read_accessor(gltf, blob, prim["indices"]).reshape(-1).astype(np.uint32) \
                if "indices" in prim else np.arange(len(pos), dtype=np.uint32)
            pos = (local[:3, :3] @ pos.T).T + local[:3, 3]
            nrm = (np.linalg.inv(local[:3, :3]).T @ nrm.T).T
            positions.append(pos)
            normals.append(nrm)
            indices.append(idx + base)
            base += len(pos)
        pos = np.concatenate(positions)
        nrm = np.concatenate(normals)
        idx = np.concatenate(indices)
        lo, hi = pos.min(0), pos.max(0)
        size = np.maximum(hi - lo, 1e-4)
        pos = (pos - (lo + hi) / 2) / size
        nrm = nrm * size
        nrm /= np.maximum(np.linalg.norm(nrm, axis=1, keepdims=True), 1e-9)
        entry = {"vertices": len(pos), "indices": len(idx)}
        for key, array in (("position", pos.astype(np.float32)), ("normal", nrm.astype(np.float32)),
                           ("index", idx.astype(np.uint32))):
            entry[key] = offset
            data = array.tobytes()
            chunks.append(data)
            offset += len(data)
        items[name] = entry
    path.write_bytes(b"".join(chunks))
    return items


# --------------------------------------------------------------------------------------- scene

def mix(a, b, t):
    return [a[i] + (b[i] - a[i]) * t for i in range(3)]


def to_hex(rgb):
    return "%02X%02X%02X" % tuple(max(0, min(255, round(c * 255))) for c in rgb)


def part_records(world, mesh_names):
    """Visible parts as [shape, kind, opacity, castShadow, x, y, z, r00..r22, sx, sy, sz, colour]."""
    records, used_meshes = [], set()
    for p in world["Parts"]:
        transparency = p.get("Transparency", 0)
        if transparency >= 0.98:
            continue
        cls, size = p["Class"], list(p["Size"])
        cf = p["CFrame"]
        pos, rot = list(cf[:3]), cf[3:12]
        shape, scale = "box", size
        part_shape = p.get("Shape", "Block")
        if cls == "WedgePart" or part_shape == "Wedge":
            shape = "wedge"
        elif cls == "CornerWedgePart" or part_shape == "CornerWedge":
            shape = "cornerwedge"
        elif cls == "MeshPart":
            if p["Name"] in mesh_names:
                shape = "mesh:" + p["Name"]
                used_meshes.add(p["Name"])
        elif part_shape == "Ball":
            d = min(size)
            shape, scale = "ball", [d, d, d]
        elif part_shape == "Cylinder":
            d = min(size[1], size[2])
            shape, scale = "cylinder", [size[0], d, d]
        mesh = p.get("Mesh")
        if mesh and cls != "MeshPart":
            kind_name, ms, mo = mesh["Type"], mesh["Scale"], mesh["Offset"]
            if kind_name in ("Sphere", "Head"):
                shape, scale = "ball", [size[i] * ms[i] for i in range(3)]
            elif kind_name == "Brick":
                shape, scale = "box", [size[i] * ms[i] for i in range(3)]
            elif kind_name == "Cylinder":
                shape, scale = "ycylinder", [size[i] * ms[i] for i in range(3)]
            elif kind_name == "Wedge":
                shape, scale = "wedge", [size[i] * ms[i] for i in range(3)]
            if any(mo):
                pos = [pos[i] + rot[i * 3] * mo[0] + rot[i * 3 + 1] * mo[1] + rot[i * 3 + 2] * mo[2] for i in range(3)]
        material = p.get("Material", "SmoothPlastic")
        opacity = 1.0 - transparency
        if material == "Neon":
            kind = "neon"
            opacity = 1.0 if transparency < 0.5 else round(opacity, 1)
            if opacity < 1:
                kind = "glass"
        elif material == "ForceField":
            kind, opacity = "force", round(max(0.05, 0.16 * opacity), 2)
        elif material == "Glass":
            kind, opacity = "glass", round(min(0.85, max(0.2, opacity * 0.7)), 2)
        else:
            kind = "solid" if transparency < 0.02 else "glass"
            opacity = round(opacity, 1) if kind == "glass" else 1.0
        cast = 1 if p.get("CastShadow", True) and kind in ("solid", "neon") else 0
        records.append([shape, kind, opacity, cast] + [round(v, 3) for v in pos] + [round(v, 5) for v in rot]
                       + [round(v, 3) for v in scale] + [p["Color"]])
    return records, used_meshes


def lighting_settings(world, preset=None):
    """Renderer lighting from the Lighting service as MapService left it, with a zone's Lighting preset
    (Config/Zones, applied by ZoneController when a player enters the zone) on top."""
    props = dict(world["Lighting"]["Properties"])
    effects = {e["Class"]: dict(e["Properties"]) for e in world["Lighting"]["Effects"]}
    if preset:
        for key in ("ClockTime", "Brightness", "ExposureCompensation", "Ambient", "OutdoorAmbient"):
            if key in preset:
                props[key] = preset[key]
        for name, cls in (("Atmosphere", "Atmosphere"), ("ColorCorrection", "ColorCorrectionEffect"), ("Bloom", "BloomEffect")):
            if isinstance(preset.get(name), dict):
                effects.setdefault(cls, {}).update(preset[name])
    atmosphere = effects.get("Atmosphere", {})
    grade = effects.get("ColorCorrectionEffect", {})
    bloom = effects.get("BloomEffect", {"Intensity": 0.4, "Size": 24, "Threshold": 2})
    white = [1, 1, 1]
    haze = hex_rgb(atmosphere.get("Color", "C7DEFF"))
    density = float(atmosphere.get("Density", 0.3))
    haze_amount = float(atmosphere.get("Haze", 1))
    clock = float(props.get("ClockTime", 14)) % 24
    from_noon = abs(clock - 12)
    # 1 by day, 0 at night (sun below the horizon), blended around dawn and dusk
    day = max(0.0, min(1.0, (6.6 - from_noon) / 1.6))
    late = max(0.0, min(1.0, (from_noon - 2.5) / 3.5))
    horizon_day = mix(haze, white, 0.3)
    zenith_day = mix([0.24, 0.6, 0.95], haze, 0.18)  # Sky blue (STYLE_GUIDE "Sky") tinted by the haze
    horizon_night = mix(haze, [0.1, 0.1, 0.25], 0.45)
    zenith_night = mix([0.07, 0.07, 0.22], haze, 0.22)
    horizon = mix(horizon_night, horizon_day, day)
    zenith = mix(zenith_night, zenith_day, day)
    below = mix(horizon, [0.93, 0.95, 1.0], 0.6 * day + 0.1)
    if day > 0:
        elevation = math.radians(max(18, min(68, 90 - from_noon * 13)))
        side = -1 if clock >= 12 else 1  # afternoon sun from -X, morning from +X
    else:  # moonlight
        elevation, side = math.radians(42), 1
    horizontal = [0.42 * side, -0.9]
    norm = math.hypot(*horizontal)
    direction = [math.cos(elevation) * horizontal[0] / norm, math.sin(elevation), math.cos(elevation) * horizontal[1] / norm]
    sun_color = mix([0.72, 0.78, 1.0], mix([1.0, 0.96, 0.89], [1.0, 0.76, 0.52], late), day)
    outdoor = hex_rgb(props.get("OutdoorAmbient", "9696A5"))
    ambient = hex_rgb(props.get("Ambient", "646878"))
    brightness = float(props.get("Brightness", 2))
    tint = hex_rgb(grade.get("TintColor", "FFFFFF"))
    # Atmosphere density (and haze) -> how far you can see at eye level
    visibility = max(250.0, min(2600.0, 1500.0 * (0.3 / max(density, 0.05)) ** 0.9 / (1 + 0.15 * max(haze_amount - 1, 0))))
    return {
        "sky": {"zenith": to_hex(zenith), "horizon": to_hex(horizon), "below": to_hex(below), "stars": round(1 - day, 3),
                "screenTop": to_hex(mix(mix([0.12, 0.12, 0.32], haze, 0.25), mix([0.36, 0.7, 1.0], haze, 0.12), day)),
                "screenBottom": to_hex(mix(horizon, white, 0.45 * day + 0.12))},
        "hemi": {"sky": to_hex(mix(outdoor, [0.88, 0.94, 1.0], 0.6 * day + 0.25)), "ground": to_hex(mix(ambient, [0.78, 0.72, 0.86], 0.55)),
                 "intensity": round(1.2 + 0.25 * sum(outdoor) / 3 * 2, 3)},
        "sun": {"color": to_hex(sun_color), "intensity": round((0.9 + 0.55 * brightness) * (0.45 + 0.55 * day), 3), "direction": direction},
        "exposure": round(2 ** float(props.get("ExposureCompensation", 0)) ** 0.5, 3),
        "fog": {"color": to_hex(mix(horizon, haze, 0.25)), "visibility": round(visibility)},
        "bloom": {"strength": round(0.2 + 0.4 * float(bloom.get("Intensity", 0.4)), 3),
                  "radius": round(min(0.8, 0.2 + float(bloom.get("Size", 24)) / 80), 3), "threshold": 0.92},
        "grade": {"saturation": round(float(grade.get("Saturation", 0)), 3), "contrast": round(float(grade.get("Contrast", 0)) * 0.8, 3),
                  "brightness": round(float(grade.get("Brightness", 0)) * 0.5, 3), "tint": tint},
    }


DEFAULT_REGIONS = [{"Id": 0, "Key": "Hub", "X0": -220, "X1": 0, "Spawn": [-196, 4, 0]}] + [
    {"Id": i, "Key": f"Zone{i}", "X0": (i - 1) * 320, "X1": i * 320, "Spawn": [(i - 1) * 320 + 26, 4, 0]} for i in range(1, 7)]


def region_slug(region):
    return "hub" if region["Id"] == 0 else f"{region['Id']}_{region['Key'].lower()}"


def make_shots(world, region_arg, width):
    layout = world.get("Layout") or {}
    regions = layout.get("Regions") or DEFAULT_REGIONS
    half = layout.get("HalfWidth", 120)
    shots = []
    wx0 = min(r["X0"] for r in regions)
    wx1 = max(r["X1"] for r in regions)
    deg = math.radians

    def direction(azimuth, elevation):
        # azimuth 0 = camera south of the target (+Z), positive turns toward -X
        return [-math.sin(deg(azimuth)) * math.cos(deg(elevation)), math.sin(deg(elevation)),
                math.cos(deg(azimuth)) * math.cos(deg(elevation))]

    if region_arg == "all":
        shots.append({"name": "overview", "kind": "aerial", "fov": 30, "dir": direction(4, 52),
                      "focus": [wx0 - 20, 0, -half - 70, wx1 + 20, 30, half + 70], "margin": 1.0,
                      "size": [round(width * 1.5), round(width * 1.5 / 2.4)],
                      "shadow": [wx0 - 80, -40, -half - 150, wx1 + 80, 120, half + 150],
                      "lighting": lighting_settings(world, (regions[0] if regions else {}).get("Lighting"))})
    for region in regions:
        key = "hub" if region["Id"] == 0 else str(region["Id"])
        if region_arg not in ("all", key):
            continue
        slug = region_slug(region)
        x0, x1 = region["X0"], region["X1"]
        lighting = lighting_settings(world, region.get("Lighting"))
        visibility = lighting["fog"]["visibility"]
        shots.append({"name": f"{slug}_aerial", "kind": "aerial", "fov": 40, "dir": direction(28, 42),
                      "focus": [x0 - 6, 0, -half - 40, x1 + 6, 20, half + 40], "lighting": lighting,
                      "shadow": [x0 - 120, -40, -half - 160, x1 + 120, 120, half + 160]})
        spawn = region["Spawn"][:3]
        eye = [spawn[0] - 4, spawn[1] + 1.8, spawn[2]]
        shots.append({"name": f"{slug}_eye", "kind": "eye", "fov": 70, "position": eye,
                      "look": [eye[0] + 100, eye[1] - 4, eye[2]], "lighting": lighting,
                      "fog": [round(visibility * 0.12), visibility],
                      "shadow": [eye[0] - 20, -40, -half - 80, eye[0] + 300, 120, half + 80]})
    return shots


# --------------------------------------------------------------------------------------- browser

def find_browser():
    candidates = [os.environ.get("CHROME_PATH", "")]
    for base in (os.environ.get("PLAYWRIGHT_BROWSERS_PATH", ""), "/opt/pw-browsers", os.path.expanduser("~/.cache/ms-playwright")):
        if base:
            candidates += sorted(glob.glob(os.path.join(base, "chromium_headless_shell-*/chrome-linux/headless_shell")), reverse=True)
            candidates += sorted(glob.glob(os.path.join(base, "chromium-*/chrome-linux/chrome")), reverse=True)
    candidates += ["/usr/bin/chromium", "/usr/bin/chromium-browser", "/usr/bin/google-chrome",
                   r"C:\Program Files\Google\Chrome\Application\chrome.exe",
                   "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"]
    for candidate in candidates:
        if candidate and os.path.exists(candidate):
            return candidate
    return None


def find_three():
    for folder in ("tools/preview", "tools/world", "tools/pets"):
        path = ROOT / folder / "node_modules" / "three"
        if (path / "build" / "three.module.js").exists():
            return path
    return None


class PreviewServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, out_dir, three_dir):
        self.routes = {"/__data/": out_dir, "/__three/": three_dir, "/__fonts/": ROOT / "assets" / "source" / "fonts"}
        self.shots = {}
        self.logs = []
        self.done = threading.Event()
        self.error = None
        super().__init__(("127.0.0.1", 0), partial(PreviewHandler, directory=str(HERE)))


class PreviewHandler(SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def translate_path(self, path):
        clean = path.split("?", 1)[0].split("#", 1)[0]
        for prefix, folder in self.server.routes.items():
            if clean.startswith(prefix):
                rel = clean[len(prefix):]
                target = (Path(folder) / rel).resolve()
                if Path(folder).resolve() in target.parents or target == Path(folder).resolve():
                    return str(target)
                return str(HERE / "__forbidden__")
        return super().translate_path(path)

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length)
        path, _, query = self.path.partition("?")
        if path == "/__shot":
            name = re.sub(r"[^A-Za-z0-9_.-]", "_", query.split("name=", 1)[-1])
            self.server.shots[name] = body
        elif path == "/__log":
            self.server.logs.append(body.decode("utf-8", "replace"))
        elif path == "/__done":
            if "error" in query:
                self.server.error = body.decode("utf-8", "replace")
            self.server.done.set()
        self.send_response(200)
        self.send_header("Content-Length", "2")
        self.end_headers()
        self.wfile.write(b"ok")


def render(out_dir, size, timeout=240):
    browser = find_browser()
    if not browser:
        sys.exit("no Chrome/Chromium found: install Playwright's chromium (npx playwright install chromium-headless-shell) "
                 "or set CHROME_PATH")
    three_dir = find_three()
    if not three_dir:
        sys.exit("three.js missing: run `npm install` in tools/preview")
    server = PreviewServer(out_dir, three_dir)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    url = f"http://127.0.0.1:{server.server_address[1]}/viewer.html"
    command = [browser, "--headless=new", "--no-sandbox", "--use-angle=swiftshader", "--enable-unsafe-swiftshader",
               "--ignore-gpu-blocklist", "--hide-scrollbars", "--force-device-scale-factor=1", "--mute-audio",
               "--disable-background-timer-throttling", "--disable-renderer-backgrounding",
               f"--window-size={size[0]},{size[1]}", url]
    process = subprocess.Popen(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        finished = server.done.wait(timeout)
    finally:
        process.kill()
        process.wait()
        server.shutdown()
    for line in server.logs:
        print("  viewer:", line)
    if server.error:
        sys.exit("the renderer failed: " + server.error)
    if not finished:
        sys.exit(f"the renderer timed out after {timeout}s ({len(server.shots)} shots done)")
    written = []
    for name, data in server.shots.items():
        path = out_dir / f"{name}.png"
        path.write_bytes(data)
        written.append(path)
    return written


def contact_sheet(paths, target, columns=3, tile=520):
    try:
        from PIL import Image, ImageDraw, ImageFont
    except ImportError:
        return None
    images = [Image.open(p).convert("RGB") for p in paths]
    if not images:
        return None
    ratio = max(image.height / image.width for image in images)
    th = int(tile * ratio)
    label = 34
    rows = math.ceil(len(images) / columns)
    sheet = Image.new("RGB", (columns * tile + (columns + 1) * 12, rows * (th + label) + (rows + 1) * 12), (234, 243, 255))
    draw = ImageDraw.Draw(sheet)
    font_path = ROOT / "assets" / "source" / "fonts" / "FredokaOne-Regular.ttf"
    try:
        font = ImageFont.truetype(str(font_path), 22)
    except OSError:
        font = ImageFont.load_default()
    for index, (path, image) in enumerate(zip(paths, images)):
        col, row = index % columns, index // columns
        x = 12 + col * (tile + 12)
        y = 12 + row * (th + label + 12)
        fit = min(tile / image.width, th / image.height)
        small = image.resize((round(image.width * fit), round(image.height * fit)), Image.LANCZOS)
        sheet.paste(small, (x + (tile - small.width) // 2, y + label + (th - small.height) // 2))
        draw.text((x + 4, y + 4), path.stem, fill=(35, 48, 102), font=font)
    sheet.save(target)
    return target


# --------------------------------------------------------------------------------------- main

def parse_args():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--region", default="all", help="hub, 1..6 or all (default)")
    parser.add_argument("--out", default="build/preview", help="output folder (default build/preview)")
    parser.add_argument("--size", default="1600x900", help="image size WxH (default 1600x900)")
    parser.add_argument("--dump-only", action="store_true", help="only run MapService and write world.json")
    parser.add_argument("--no-start", action="store_true", help="run MapService.Init only, not Start")
    parser.add_argument("--sim-seconds", type=float, default=5.0, help="simulated seconds to run tasks for (default 5)")
    parser.add_argument("--keep-going", action="store_true", help="render even if MapService raised errors")
    parser.add_argument("--luau", help="path to the luau command line (default: $LUAU or luau on PATH)")
    parser.add_argument("--service", default=SERVICE, help=argparse.SUPPRESS)
    parser.add_argument("--pack-at", action="append",
                        help=f"DataModel path for the GLB prop pack (default {DEFAULT_PACK_AT}; 'none' = only via LoadAsset)")
    parser.add_argument("--no-pack", action="store_true", help="ignore assets/models/StormWorldProps.glb")
    parser.add_argument("--terrain-res", type=float, default=2.0, help="terrain mesh spacing in studs (default 2)")
    return parser.parse_args()


def main():
    args = parse_args()
    out_dir = (ROOT / args.out) if not os.path.isabs(args.out) else Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)
    region = args.region.lower()
    if region != "all" and region not in REGION_KEYS:
        sys.exit(f"--region must be one of hub, 1..6, all (got {args.region})")
    try:
        width, height = (int(v) for v in args.size.lower().split("x"))
    except ValueError:
        sys.exit("--size must look like 1600x900")

    started = time.time()
    pack = None
    if GLB.exists() and not args.no_pack:
        pack = pack_from_glb(GLB)
        print(f"  pack: {len(pack)} props from {GLB.relative_to(ROOT)}")
    print("Running MapService in the mock runtime...")
    world = run_mock(args, out_dir, pack)
    (out_dir / "world.json").write_text(json.dumps(world, separators=(",", ":")), encoding="utf-8")
    if args.dump_only:
        print(f"Wrote {out_dir / 'world.json'} in {time.time() - started:.1f}s")
        return

    import numpy as np
    mesh_names = {piece["Name"] for prop in (pack or []) for piece in prop["Pieces"]}
    parts, used_meshes = part_records(world, mesh_names)
    scene = {"size": [width, height], "parts": parts, "lighting": lighting_settings(world),
             "shots": make_shots(world, region, width), "guis": [], "beams": []}
    for name in ("terrain.bin", "meshes.bin"):
        (out_dir / name).unlink(missing_ok=True)
    if used_meshes:
        items = export_meshes(used_meshes, out_dir / "meshes.bin")
        scene["meshes"] = {"url": "/__data/meshes.bin", "items": items}
    mesh = terrain_mesh(world["Terrain"], args.terrain_res)
    if mesh:
        positions, colors, tris = mesh
        blob = positions.tobytes() + colors.tobytes() + tris.tobytes()
        (out_dir / "terrain.bin").write_bytes(blob)
        scene["terrain"] = {"url": "/__data/terrain.bin", "vertices": len(positions), "indices": tris.size,
                            "position": 0, "color": positions.nbytes, "index": positions.nbytes + colors.nbytes}
    parts_by_index = world["Parts"]
    for gui in world["Guis"]:
        entry = dict(gui)
        index = gui.get("Part")
        if index:
            p = parts_by_index[index - 1]
            entry["part"] = {"size": p["Size"], "cframe": p["CFrame"]}
        scene["guis"].append(entry)
    for beam in world.get("Beams", []):
        colors_seq = beam["Color"]
        transparency = beam["Transparency"]
        scene["beams"].append({"a": beam["A0"], "b": beam["A1"], "w0": beam["Width0"], "w1": beam["Width1"],
                               "color": colors_seq[0][1], "opacity": round(1 - sum(v for _, v in transparency) / len(transparency), 2),
                               "additive": beam.get("LightEmission", 0) > 0.5})
    (out_dir / "scene.json").write_text(json.dumps(scene, separators=(",", ":")), encoding="utf-8")
    prep = time.time() - started
    print(f"  scene: {len(parts)} visible parts, {len(used_meshes)} prop meshes, "
          f"{scene.get('terrain', {}).get('indices', 0) // 3} terrain triangles, {len(scene['shots'])} shots ({prep:.1f}s)")

    print("Rendering with three.js in headless Chromium...")
    written = render(out_dir, (width, height))
    order = {shot["name"]: i for i, shot in enumerate(scene["shots"])}
    written.sort(key=lambda p: order.get(p.stem, 999))
    if len(written) > 1:
        sheet = contact_sheet(written, out_dir / "contact_sheet.png")
        if sheet:
            written.append(sheet)
    for path in written:
        print(f"  wrote {path.relative_to(ROOT) if ROOT in path.parents else path}")
    print(f"Done in {time.time() - started:.1f}s")


if __name__ == "__main__":
    main()
