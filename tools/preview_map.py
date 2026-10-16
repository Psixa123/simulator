#!/usr/bin/env python3
"""Renders the real game world without Roblox, so map changes can be checked visually.

Runs the real src/server/Services/MapService.luau (Init, then Start) inside a mock Roblox runtime
(tools/preview/MapMock.luau) under the `luau` command line, dumps the world it builds to JSON (every
BasePart, Terrain fills, Lighting/Atmosphere/Sky/Clouds settings, SurfaceGui/BillboardGui text), then
draws it with three.js in headless Chromium (tools/preview/viewer.js) and saves PNGs. ~25 s for everything.

Usage (from the repo root):
    python3 tools/preview_map.py                          overview + hub + zones 1..6, aerial and eye shots
    python3 tools/preview_map.py --region hub             one region (hub, 1..6); several: --region hub,3
    python3 tools/preview_map.py --region 3 --views eye   only the eye-level shot of zone 3
    python3 tools/preview_map.py --region all --out build/preview
    python3 tools/preview_map.py --shot "tower target=-112,10,0 az=60 el=25 dist=140"
    python3 tools/preview_map.py --showcase               every pack prop placed with WorldProps.Place
    python3 tools/preview_map.py --script /tmp/MapService.luau   preview an edited copy of MapService
    python3 tools/preview_map.py --dump-only              only write world.json (no browser)

Options:
    --region R        hub | 1..6 | all | overview | fit | none, comma-separated (default all: overview + 7
                      regions). fit = one aerial framing everything visible.
    --views V         aerial | eye | aerial,eye (default): which shots each region gets
    --shot SPEC       an extra camera (repeatable). SPEC = "NAME key=value ..." (spaces or ';'). With --shot
                      (or --showcase), --region defaults to none: add --region all for the usual shots too.
                        pos=X,Y,Z look=X,Y,Z         camera at pos looking at look (or dir=X,Y,Z;
                                                     neither = along +X)
                        target=X,Y,Z az=A el=E dist=D  orbit: D studs from target, azimuth A, elevation E
                        box=X0,Y0,Z0,X1,Y1,Z1 [az= el=] frame a box (aerial); region=hub|1..6 frames a
                                                     region; fit frames everything visible
                      azimuth (az): 0 = camera on the +Z side, 90 = on the -X side (looking along +X),
                      180 = -Z side, 270 = +X side. Elevation (el): degrees above the horizon.
                      Extras: fov=DEG (vertical), size=WxH, light=world|hub|1..6 (whose Lighting preset;
                      default: the region under the target), fog=NEAR,FAR (studs)
                      e.g. --shot "gate pos=-20,8,-30 look=10,6,0 fov=60"
    --cameras         print every shot's camera as a --shot option, to tweak a view and render it again
    --size WxH        image size (default 1600x900; the overview is 1.5x wider)
    --out DIR         output folder (default build/preview)
    --script FILE     run this ModuleScript instead of MapService (Init/Start like a service). It goes next
                      to MapService under its file name (MapService.luau replaces MapService), so it can
                      require its siblings (script.Parent.WorldProps) and the shared modules
    --showcase        run tools/preview/PropShowcase.luau: every prop of the pack placed with
                      WorldProps.Place (default paints, a biome tint, scaled) and render it
    --no-pack         no prop pack (WorldProps finds nothing, so the map's part-built fallbacks show)
    --pack-at PATH    where the pack goes in the DataModel (default ServerStorage/WorldProps; repeatable;
                      none = only InsertService:LoadAsset, used when GameConfig.WorldPropsAssetId > 0)
    --no-start        run MapService.Init only;  --sim-seconds N: simulated seconds of tasks (default 5)
    --keep-going      render even if the map code raised errors or hit a mock gap
    --no-shadows      faster, flatter renders;   --terrain-res N: terrain mesh spacing (default 2 studs)
    --dump-only       stop after world.json;     --luau PATH, --timeout SECONDS (browser, default 300)

Shots (in --out):
    overview.png              the whole world from above (hub Lighting)
    <region>_aerial.png       a region from above, south-west side (region = hub, 1_meadows, 2_thunder, ...)
    <region>_eye.png          a region from 10 studs behind its spawn, 7.5 above the ground, looking along
                              +X like Roblox's default camera (FieldOfView 70)
    <name>.png                --shot / fit / showcase shots
    contact_sheet.png         all shots on one page (when Pillow is installed)
    world.json                the raw dump: Parts [{Class, Name, Path, Shape, Size, CFrame (x y z + 9
                              rotation numbers), Color, Material, Transparency, CastShadow, MeshId}],
                              Terrain.Fills, Lighting {Properties, Effects, Clouds}, Guis, Beams, Lights,
                              Layout (regions), Warnings, Prints, Errors, Gaps
    scene.json, meshes.bin, terrain.bin, preview_bundle.luau   renderer input and the luau bundle
Each region shot uses that zone's Lighting preset (Config/Zones, applied by ZoneController in game).

How things are drawn: flat toon shading, soft sun shadows, sky gradient with the zone's Clouds, Atmosphere
as distance fog, Neon glows (bloom), Glass and transparent parts see-through, ForceField faint, Terrain as a
smoothed height field, gui text with the real fonts. MeshParts named "<PropId>.<Paint>" (or with the pack's
mock MeshId) are drawn with that piece's mesh from assets/models/StormWorldProps.glb, placed by CFrame and
stretched to their Size; other MeshParts, unions and trusses are drawn as boxes (a warning lists them).
Particles, decals, textures, point lights and animation are not drawn; tweens stay at their start.

The prop pack: preview_map.py reads the GLB and the mock builds ServerStorage.WorldProps from it (a Model
per prop with MeshParts "<PropId>.<Paint>" and a 1-stud "<PropId>.Root" cube), so WorldProps.Load/Place
(src/server/Services/WorldProps.luau, with Config/WorldPropsData) work as in a place with the pack
imported. InsertService:LoadAsset returns the same pack.

When the map code uses something the mock doesn't know (class, property, method, enum, service), the run
stops with a message naming it and the game line that used it - even when the game code wrapped it in a
pcall (reported as MOCK GAP). Add it to tools/preview/MapMock.luau (CLASSES and the method tables) and
run again. Game warn()/print() output is shown as warn:/print: lines.

Requirements:
    luau        the Luau command line (https://github.com/luau-lang/luau/releases): on PATH, or LUAU=path
    Chromium    Playwright's headless shell (PLAYWRIGHT_BROWSERS_PATH or ~/.cache/ms-playwright), a system
                Chrome/Chromium, or CHROME_PATH=path
    three.js    `npm install` in tools/preview (tools/world or tools/pets node_modules also work)
    Python 3.9+ with numpy; Pillow is optional (contact sheet)
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
    def mesh_nodes(index, matrix):
        """(node, transform relative to the prop) of every mesh node under a prop node, at any depth."""
        for child_index in nodes[index].get("children", []):
            child = nodes[child_index]
            local = matrix @ node_matrix(child)
            if "mesh" in child:
                yield child, local
            yield from mesh_nodes(child_index, local)

    props = []
    for prop_index in prop_indices:
        prop_node = nodes[prop_index]
        prop_id = prop_node.get("name", f"Prop{prop_index}")
        prop_matrix = node_matrix(prop_node)
        pieces = []
        for child, local in mesh_nodes(prop_index, np.eye(4)):
            name = child.get("name", "")
            if name.lower().startswith(prop_id.lower() + "."):
                paint = name[len(prop_id) + 1:]
            else:  # a bare "<Paint>" piece inside the prop's node
                paint = name.split(".", 1)[1] if "." in name else name
            name = f"{prop_id}.{paint}"
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
                "Mesh": child["mesh"], "Matrix": local.tolist(),
            })
        props.append({"Id": prop_id, "Slot": [round(float(v), 4) for v in prop_matrix[:3, 3]], "Pieces": pieces})
    return props


SKIP_SOURCES = ("StarterPlayer/", "StarterGui/")  # client code: never required by the server map code


def script_module_path(args):
    """Where --script's module goes: next to MapService (replacing a module with the same name)."""
    stem, kind = script_kind(Path(args.script).name)
    if kind != "ModuleScript":
        sys.exit(f"--script must be a ModuleScript file (Name.luau), got {args.script}")
    return SERVICE.rsplit("/", 1)[0] + "/" + stem


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
            if path.startswith(SKIP_SOURCES):
                chunks.append(f"__mock.Node({json.dumps(path)}, \"ModuleScript\")")
                continue
            chunk = payload.relative_to(ROOT).as_posix()
            source = payload.read_text(encoding="utf-8")
            chunks.append(f"__mock.Module({json.dumps(path)}, {json.dumps(chunk)}, {long_string(source)})")
        elif kind == "props":
            props = {k: v for k, v in payload.items() if isinstance(v, (bool, int, float, str, list))}
            chunks.append(f"__mock.SetProps({json.dumps(path)}, {lua_value(props)})")
        elif kind == "binary" and "worldprop" in path.lower().replace("_", ""):
            pack_paths.append(path)
    service = args.service
    if args.script:
        script = Path(args.script).resolve()
        if not script.is_file():
            sys.exit(f"--script: no such file {args.script}")
        service = script_module_path(args)
        chunk = script.relative_to(ROOT).as_posix() if ROOT in script.parents else str(script)
        chunks.append(f"__mock.Module({json.dumps(service)}, {json.dumps(chunk)}, "
                      f"{long_string(script.read_text(encoding='utf-8'))})")
    if pack is not None:
        mock_pack = [{"Id": p["Id"], "Slot": p["Slot"], "Pieces": [
            {k: v for k, v in piece.items() if k not in ("Mesh", "Matrix")} for piece in p["Pieces"]]} for p in pack]
        chunks.append(f"__mock.SetPack({lua_value(mock_pack)})")
        targets = pack_paths + [p for p in (args.pack_at or [DEFAULT_PACK_AT]) if p.lower() != "none"]
        for path in dict.fromkeys(targets):
            chunks.append(f"__mock.PlacePack({json.dumps(path)})")
    config = {"Service": service, "Start": not args.no_start, "SimSeconds": args.sim_seconds,
              "Layout": "ReplicatedStorage/Shared/Config/MapLayout", "Zones": "ReplicatedStorage/Shared/Config/Zones"}
    chunks.append(f"__mock.Run({lua_value(config)})  -- preview_map.py reads the errors from the dump")
    return "\n".join(chunks) + "\n"


def run_mock(args, out_dir, pack):
    luau = find_luau(args.luau)
    if not luau:
        sys.exit("luau not found: install it (https://github.com/luau-lang/luau/releases) or set LUAU=path/to/luau")
    bundle_path = out_dir / "preview_bundle.luau"
    bundle_path.write_text(build_bundle(args, pack), encoding="utf-8")
    started = time.time()
    try:
        result = subprocess.run([luau, str(bundle_path)], capture_output=True, text=True, encoding="utf-8",
                                errors="replace", timeout=args.mock_timeout)
    except subprocess.TimeoutExpired:
        sys.exit(f"the mock run took longer than {args.mock_timeout}s (an endless loop in the map code? "
                 f"--sim-seconds is {args.sim_seconds}); bundle: {bundle_path}")
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
    for message in world.get("Prints", []):
        print("  print:", message)
    for message in world.get("Warnings", []):
        print("  warn:", message)
    errors = world.get("Errors", [])
    for message in errors:
        print("  ERROR:", message.replace("\n", "\n         "))
    # mock gaps the game code caught with pcall (they never reached Errors)
    hidden = [g for g in world.get("Gaps", []) if not any(g["Message"] in e for e in errors)]
    gaps = [g for g in hidden if not g.get("Maybe")]
    for gap in hidden:
        where = f" (at {gap['Where']})" if gap.get("Where") else ""
        if gap.get("Maybe"):
            print(f"  warn: {gap['Message']}{where} - caught by a pcall in the game code; a missing child, "
                  "or a real Roblox member the mock lacks?")
        else:
            print(f"  MOCK GAP: {gap['Message']}{where} - caught by a pcall in the game code, so the game "
                  "carried on, but the preview may differ from Roblox")
    counts = world.get("Counts", {})
    print(f"  mock: {len(world['Parts'])} parts ({counts.get('MeshPart', 0)} MeshParts), "
          f"{len(world['Terrain']['Fills'])} terrain fills, {len(world['Guis'])} guis in {time.time() - started:.1f}s")
    if (errors or gaps) and not args.keep_going:
        what = "raised errors in the mock" if errors else "used something the mock doesn't support"
        sys.exit(f"the map code {what} (see above; fix it, or pass --keep-going to render anyway)")
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


def export_meshes(pack, names, path):
    """Writes the pack meshes used in the world (piece names), in prop space and normalised to a unit box
    around their centre (a MeshPart stretches its mesh to its Size), to `path`."""
    import numpy as np
    gltf, blob = read_glb(GLB)
    pieces = {piece["Name"]: piece for prop in pack for piece in prop["Pieces"]}
    items, chunks, offset = {}, [], 0
    for name in sorted(names):
        piece = pieces.get(name)
        if piece is None:
            continue
        positions, normals, indices = [], [], []
        base = 0
        local = np.array(piece["Matrix"], dtype=float)
        for prim in gltf["meshes"][piece["Mesh"]]["primitives"]:
            if prim.get("mode", 4) != 4:
                continue  # only triangle lists
            pos = read_accessor(gltf, blob, prim["attributes"]["POSITION"]).astype(np.float64)
            idx = read_accessor(gltf, blob, prim["indices"]).reshape(-1).astype(np.uint32) \
                if "indices" in prim else np.arange(len(pos), dtype=np.uint32)
            if "NORMAL" in prim["attributes"]:
                nrm = read_accessor(gltf, blob, prim["attributes"]["NORMAL"]).astype(np.float64)
            else:  # smooth normals from the faces
                tri = idx.reshape(-1, 3)
                face = np.cross(pos[tri[:, 1]] - pos[tri[:, 0]], pos[tri[:, 2]] - pos[tri[:, 0]])
                nrm = np.zeros_like(pos)
                for corner in range(3):
                    np.add.at(nrm, tri[:, corner], face)
            pos = (local[:3, :3] @ pos.T).T + local[:3, 3]
            nrm = (np.linalg.inv(local[:3, :3]).T @ nrm.T).T
            positions.append(pos)
            normals.append(nrm)
            indices.append(idx + base)
            base += len(pos)
        if not positions:
            continue
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


def mesh_key(name):
    """Pack piece names compared the way WorldProps reads them: "TreeRound.Neon_fff3b0" == "treeround.neon_FFF3B0"."""
    return str(name).strip().lower()


def find_mesh(part, mesh_names):
    """The pack mesh a MeshPart shows: by the mock MeshId the pack carries ("rbxassetid://mock/<piece>"),
    else by its "<PropId>.<Paint>" name. None if it isn't a pack piece."""
    mesh_id = str(part.get("MeshId") or "")
    if mesh_id.startswith("rbxassetid://mock/"):
        found = mesh_names.get(mesh_key(mesh_id[len("rbxassetid://mock/"):]))
        if found:
            return found
    return mesh_names.get(mesh_key(part["Name"]))


def part_records(world, mesh_names):
    """Visible parts as [shape, kind, opacity, castShadow, x, y, z, r00..r22, sx, sy, sz, colour].
    mesh_names: {mesh_key(piece name): GLB node name} of the prop pack."""
    records, used_meshes, unknown_meshes, odd_classes = [], set(), {}, {}
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
        elif cls in ("UnionOperation", "NegateOperation", "PartOperation", "TrussPart"):
            odd_classes[cls] = odd_classes.get(cls, 0) + 1
        elif cls == "MeshPart":
            mesh = find_mesh(p, mesh_names)
            if mesh:
                shape = "mesh:" + mesh
                used_meshes.add(mesh)
            else:
                unknown_meshes[p["Name"]] = unknown_meshes.get(p["Name"], 0) + 1
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
    if odd_classes:
        print("  warn: drawn as their bounding boxes: " + ", ".join(f"{c} x{n}" for c, n in sorted(odd_classes.items())))
    if unknown_meshes:
        names = ", ".join(f"{n} x{c}" for n, c in sorted(unknown_meshes.items())[:12])
        print(f"  warn: {sum(unknown_meshes.values())} MeshParts aren't pack pieces (no mesh in "
              f"{GLB.relative_to(ROOT)}), drawn as boxes: {names}")
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
    # Clouds (Terrain.Clouds; ZoneController applies the zone preset's Clouds): cover, density and colour
    clouds = None
    cloud_props = preset.get("Clouds") if preset and isinstance(preset.get("Clouds"), dict) else world["Lighting"].get("Clouds")
    if cloud_props and cloud_props.get("Enabled", True) is not False:
        base = hex_rgb(cloud_props.get("Color", "FFFFFF"))
        light = mix([0.2, 0.22, 0.4], mix(sun_color, white, 0.6), 0.3 + 0.7 * day)
        lit = [base[i] * light[i] for i in range(3)]
        clouds = {"cover": round(max(0.0, min(1.0, float(cloud_props.get("Cover", 0.5)))), 3),
                  "density": round(0.55 + 0.45 * max(0.0, min(1.0, float(cloud_props.get("Density", 0.7)))), 3),
                  "color": to_hex(lit), "shade": to_hex(mix([c * 0.8 for c in lit], zenith, 0.3))}
    # Atmosphere density (and haze) -> how far you can see at eye level
    visibility = max(250.0, min(2600.0, 1500.0 * (0.3 / max(density, 0.05)) ** 0.9 / (1 + 0.15 * max(haze_amount - 1, 0))))
    return {
        "clouds": clouds,
        "sky": {"zenith": to_hex(zenith), "horizon": to_hex(horizon), "below": to_hex(below), "stars": round(1 - day, 3),
                "sun": round(day, 3),
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

EYE_BACK = 10.0     # studs the eye camera sits behind the spawn (Roblox's default camera is ~12 behind the head)
EYE_HEIGHT = 7.5    # studs above the ground under the spawn
EYE_FOV = 70        # Roblox's default Camera.FieldOfView (vertical)


def region_slug(region):
    return "hub" if region["Id"] == 0 else f"{region['Id']}_{region['Key'].lower()}"


def region_key(region):
    return "hub" if region["Id"] == 0 else str(region["Id"])


def world_regions(world):
    layout = world.get("Layout") or {}
    if layout.get("Error"):
        print(f"  warn: couldn't read MapLayout/Zones ({layout['Error']}); using the default region layout")
    return layout.get("Regions") or DEFAULT_REGIONS, layout.get("HalfWidth", 120)


def region_at(regions, x):
    for region in regions:
        if region["X0"] <= x < region["X1"]:
            return region
    return min(regions, key=lambda r: min(abs(x - r["X0"]), abs(x - r["X1"]))) if regions else None


def part_box(part):
    """Axis-aligned bounds (min xyz, max xyz) of a dumped part."""
    cf, size = part["CFrame"], part["Size"]
    rot = [cf[3:6], cf[6:9], cf[9:12]]
    ext = [sum(abs(rot[i][j]) * size[j] for j in range(3)) / 2 for i in range(3)]
    return [cf[i] - ext[i] for i in range(3)], [cf[i] + ext[i] for i in range(3)]


def visible_bounds(world, x_range=None):
    """Bounds [x0, y0, z0, x1, y1, z1] of the visible parts (optionally only those centred in an x range),
    ignoring giant ones (baseplates, sky domes) so the shot frames the content."""
    lo, hi = [math.inf] * 3, [-math.inf] * 3
    for part in world["Parts"]:
        if part.get("Transparency", 0) >= 0.98 or max(part["Size"]) > 1500:
            continue
        if x_range and not (x_range[0] <= part["CFrame"][0] <= x_range[1]):
            continue
        a, b = part_box(part)
        lo = [min(lo[i], a[i]) for i in range(3)]
        hi = [max(hi[i], b[i]) for i in range(3)]
    if lo[0] == math.inf:
        return None
    return lo + hi


def ground_height(world, x, z, below):
    """Height of the highest solid surface (part top or terrain) under (x, z) that is below `below`."""
    best = -math.inf
    for part in world["Parts"]:
        if part.get("Transparency", 0) >= 0.9:
            continue
        cf, size = part["CFrame"], part["Size"]
        if abs(cf[0] - x) > max(size) or abs(cf[2] - z) > max(size):
            continue
        # vertical line (x, t, z) in the part's space: local = R^T (p - c)
        r = [cf[3:6], cf[6:9], cf[9:12]]  # rows of R
        d = [x - cf[0], -cf[1], z - cf[2]]
        a = [r[0][i] * d[0] + r[1][i] * d[1] + r[2][i] * d[2] for i in range(3)]  # local at t = 0
        b = [r[1][i] for i in range(3)]  # d(local)/dt
        t0, t1 = -math.inf, math.inf
        for i in range(3):
            h = size[i] / 2
            if abs(b[i]) < 1e-9:
                if abs(a[i]) > h:
                    t0, t1 = math.inf, -math.inf
                    break
            else:
                u, v = (-h - a[i]) / b[i], (h - a[i]) / b[i]
                t0, t1 = max(t0, min(u, v)), min(t1, max(u, v))
        if t0 <= t1 and t1 <= below + 0.01 and t1 > best:
            best = t1
    for fill in (world.get("Terrain") or {}).get("Fills", []):
        if fill.get("Material") == "Air":
            continue
        try:
            import numpy as np
            top, _, inside = fill_columns(fill, np.array([x]), np.array([z]))
            if inside[0] and top[0] <= below + 0.01:
                best = max(best, float(top[0]))
        except (KeyError, ValueError):
            pass
    return best if best > -math.inf else None


def region_box(region, half, ground):
    """What a region's aerial shot frames: its x range, the playable width plus a margin, ground level."""
    return [region["X0"], ground, -half - 16, region["X1"], ground + 16, half + 16]


def look_direction(azimuth, elevation):
    """Unit vector from the target to the camera. azimuth 0 = camera on the +Z (south) side, 90 = on the
    -X side (looking along +X), 180 = -Z side, 270 = +X side; elevation in degrees above the horizon."""
    a, e = math.radians(azimuth), math.radians(elevation)
    return [-math.sin(a) * math.cos(e), math.sin(e), math.cos(a) * math.cos(e)]


def aerial_shot(name, box, lighting, azimuth=24, elevation=40, fov=38, margin=1.0, size=None):
    pad = max(box[3] - box[0], box[5] - box[2]) * 0.6 + 60
    shot = {"name": name, "kind": "aerial", "fov": fov, "dir": look_direction(azimuth, elevation),
            "focus": [round(v, 2) for v in box], "margin": margin, "lighting": lighting,
            "shadow": [box[0] - pad * 0.4, box[1] - 40, box[2] - pad * 0.4, box[3] + pad * 0.4, box[4] + 60, box[5] + pad * 0.4]}
    if size:
        shot["size"] = size
    return shot


def eye_shot(name, position, look, lighting, fov=EYE_FOV, fog=None, size=None):
    """A camera at `position` looking at `look`. Fog and the sun's shadow box follow how far away the
    look point is, so the same kind of shot works at eye level and from high up."""
    dist = math.dist(position, look)
    if dist > 150:  # high or far camera: shadows around what it looks at
        centre, reach = [look[0], look[2]], max(150.0, dist * 0.7)
    else:  # eye level: shadows ahead of the camera
        fx, fz = look[0] - position[0], look[2] - position[2]
        norm = math.hypot(fx, fz) or 1
        centre, reach = [position[0] + fx / norm * 120, position[2] + fz / norm * 120], 150.0
    low = min(position[1], look[1])
    shot = {"name": name, "kind": "eye", "fov": fov, "position": [round(v, 3) for v in position],
            "look": [round(v, 3) for v in look], "lighting": lighting,
            "shadow": [centre[0] - reach, low - 80, centre[1] - reach, centre[0] + reach, low + 120, centre[1] + reach]}
    visibility = lighting["fog"]["visibility"]
    shot["fog"] = fog or [round(max(visibility * 0.12, dist * 1.1)), round(max(visibility, dist * 4))]
    if size:
        shot["size"] = size
    return shot


def parse_size(text):
    try:
        w, h = (int(v) for v in str(text).lower().split("x"))
        if w < 16 or h < 16 or w > 8192 or h > 8192:
            raise ValueError
        return [w, h]
    except ValueError:
        raise ValueError(f"size must look like 1600x900, got {text!r}")


def parse_numbers(text, count, key):
    try:
        values = [float(v) for v in str(text).split(",")]
    except ValueError:
        values = []
    if len(values) != count:
        raise ValueError(f"{key}= needs {count} comma-separated numbers, got {text!r}")
    return values


def parse_region_list(text):
    """--region value -> ordered list of keys: overview, hub, 1..6, fit."""
    keys = []
    for item in re.split(r"[,\s]+", text.strip().lower()):
        if not item:
            continue
        if item == "all":
            keys += ["overview"] + REGION_KEYS
        elif item in ("0", "hub"):
            keys.append("hub")
        elif item in REGION_KEYS or item in ("overview", "fit", "none"):
            keys.append(item)
        else:
            raise ValueError(f"--region: unknown {item!r} (use hub, 1..6, all, overview, fit or none; "
                             "several with commas: hub,3)")
    return [k for k in dict.fromkeys(keys) if k != "none"]


SHOT_KEYS = {"pos", "look", "dir", "target", "az", "el", "dist", "box", "region", "fit", "fov", "size", "light", "fog"}


def custom_shot(spec, world, regions, half, presets):
    """--shot "NAME key=value ..." (or ';'-separated) -> a shot. See the module docstring for the keys."""
    try:
        return parse_shot(spec, world, regions, half, presets)
    except ValueError as error:
        message = str(error)
        raise ValueError(message if message.startswith("--shot") else f"--shot {spec.split()[0]!r}: {message}")


def parse_shot(spec, world, regions, half, presets):
    tokens = [t for t in re.split(r"[;\s]+", spec.strip()) if t]
    if not tokens or "=" in tokens[0]:
        raise ValueError(f"--shot {spec!r}: start with a name, e.g. --shot \"gate pos=-10,8,0 look=40,4,0\"")
    name = re.sub(r"[^A-Za-z0-9_.-]", "_", tokens[0])
    opts = {}
    for token in tokens[1:]:
        key, eq, value = token.partition("=")
        key = key.lower()
        if not eq and key == "fit":
            value = "all"
        elif not eq or key not in SHOT_KEYS:
            raise ValueError(f"--shot {name}: unknown option {token!r} (keys: {', '.join(sorted(SHOT_KEYS))})")
        opts[key] = value
    fov = float(opts["fov"]) if "fov" in opts else None
    size = parse_size(opts["size"]) if "size" in opts else None

    def lighting_for(x):
        light = opts.get("light")
        if light in (None, ""):
            region = region_at(regions, x)
            return presets(region)
        if light == "world":
            return presets(None)
        wanted = "hub" if light in ("0", "hub") else light
        for region in regions:
            if region_key(region) == wanted:
                return presets(region)
        raise ValueError(f"--shot {name}: light= must be world, hub or 1..6, got {light!r}")

    if "pos" in opts:
        pos = parse_numbers(opts["pos"], 3, "pos")
        if "look" in opts:
            look = parse_numbers(opts["look"], 3, "look")
        elif "dir" in opts:
            d = parse_numbers(opts["dir"], 3, "dir")
            look = [pos[i] + d[i] * 100 for i in range(3)]
        else:
            look = [pos[0] + 100, pos[1] - 4, pos[2]]
        fog = parse_numbers(opts["fog"], 2, "fog") if "fog" in opts else None
        return eye_shot(name, pos, look, lighting_for(look[0]), fov or EYE_FOV, fog, size)

    az = float(opts.get("az", 24))
    el = float(opts.get("el", 40))
    if "target" in opts:
        target = parse_numbers(opts["target"], 3, "target")
        dist = float(opts.get("dist", 150))
        d = look_direction(az, el)
        pos = [target[i] + d[i] * dist for i in range(3)]
        fog = parse_numbers(opts["fog"], 2, "fog") if "fog" in opts else None
        return eye_shot(name, pos, target, lighting_for(target[0]), fov or 45, fog, size)
    if "box" in opts:
        box = parse_numbers(opts["box"], 6, "box")
        box = [min(box[0], box[3]), min(box[1], box[4]), min(box[2], box[5]),
               max(box[0], box[3]), max(box[1], box[4]), max(box[2], box[5])]
    elif "region" in opts:
        wanted = "hub" if opts["region"] in ("0", "hub") else opts["region"]
        region = next((r for r in regions if region_key(r) == wanted), None)
        if not region:
            raise ValueError(f"--shot {name}: region= must be hub or 1..6")
        spawn = region["Spawn"][:3]
        ground = ground_height(world, spawn[0], spawn[2], spawn[1] + 2)
        box = region_box(region, half, spawn[1] - 4 if ground is None else ground)
    elif "fit" in opts:
        box = visible_bounds(world)
        if not box:
            raise ValueError(f"--shot {name}: fit: the world has no visible parts")
    else:
        raise ValueError(f"--shot {name}: give pos= (+ look=/dir=), target= (+ az/el/dist), box=, region= or fit")
    light = lighting_for((box[0] + box[3]) / 2) if opts.get("light") or "fit" not in opts else presets(None)
    return aerial_shot(name, box, light, az, el, fov or 38, 1.0, size)


def make_shots(world, args, width):
    """The shots to render: --region / --views shots, --showcase shots, then --shot ones."""
    regions, half = world_regions(world)
    keys = parse_region_list(args.region)
    views = {v for v in re.split(r"[,\s]+", args.views.lower()) if v}
    if not views <= {"aerial", "eye"}:
        raise ValueError("--views takes aerial, eye or aerial,eye")
    cache = {}

    def presets(region):
        key = region_key(region) if region else "world"
        if key not in cache:
            cache[key] = lighting_settings(world, region.get("Lighting") if region else None)
        return cache[key]

    shots = []
    if "overview" in keys and regions:
        wx0 = min(r["X0"] for r in regions)
        wx1 = max(r["X1"] for r in regions)
        shots.append(aerial_shot("overview", [wx0 - 10, 0, -half - 50, wx1 + 10, 30, half + 50], presets(regions[0]),
                                 azimuth=6, elevation=50, fov=26, size=[round(width * 1.5), round(width * 1.5 / 2.8)]))
    for region in regions:
        if region_key(region) not in keys:
            continue
        slug = region_slug(region)
        lighting = presets(region)
        spawn = region["Spawn"][:3]
        ground = ground_height(world, spawn[0] - EYE_BACK, spawn[2], spawn[1] + 2)
        ground = spawn[1] - 4 if ground is None else ground  # MapLayout spawns are 4 studs up
        if "aerial" in views:
            shots.append(aerial_shot(f"{slug}_aerial", region_box(region, half, ground), lighting))
        if "eye" in views:
            eye = [spawn[0] - EYE_BACK, ground + EYE_HEIGHT, spawn[2]]
            shots.append(eye_shot(f"{slug}_eye", eye, [eye[0] + 120, ground + 2, eye[2]], lighting))
    if "fit" in keys:
        box = visible_bounds(world)
        if box:
            shots.append(aerial_shot("fit", box, presets(None)))
    if args.showcase:
        box = visible_bounds(world)
        if box:
            shots.append(aerial_shot("showcase", box, presets(None), azimuth=205, elevation=38, fov=30))
            cx = (box[0] + box[3]) / 2
            front = [cx, 14, box[2] - 30]
            shots.append(eye_shot("showcase_front", front, [cx, 4, box[2] + 18], presets(None), fov=50,
                                  fog=[400, 3000]))
    for spec in args.shot or []:
        shots.append(custom_shot(spec, world, regions, half, presets))
    names = [shot["name"] for shot in shots]
    duplicates = {n for n in names if names.count(n) > 1}
    if duplicates:
        raise ValueError(f"two shots are called {', '.join(sorted(duplicates))}: give --shot a different name")
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
        self.cameras = []
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
        elif path == "/__cameras":
            self.server.cameras = json.loads(body.decode("utf-8", "replace"))
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
    return written, server.cameras


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

def parse_args(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--region", default=None,
                        help="hub, 1..6, all, overview, fit or none; several with commas, e.g. hub,3 "
                             "(default all; none with --shot or --showcase)")
    parser.add_argument("--views", default="aerial,eye", help="per-region shots: aerial, eye or aerial,eye (default)")
    parser.add_argument("--shot", action="append", metavar="SPEC",
                        help='extra camera, e.g. "gate pos=-10,8,0 look=40,4,0" (repeatable; see above)')
    parser.add_argument("--out", default="build/preview", help="output folder (default build/preview)")
    parser.add_argument("--size", default="1600x900", help="image size WxH (default 1600x900)")
    parser.add_argument("--script", metavar="FILE",
                        help="run this ModuleScript file instead of MapService (an edited copy, a test map); it is "
                             "placed next to MapService under its own name, replacing a module of that name")
    parser.add_argument("--showcase", action="store_true",
                        help="place every prop of the pack with WorldProps.Place (tools/preview/PropShowcase.luau) "
                             "instead of running MapService, and render it")
    parser.add_argument("--dump-only", action="store_true", help="only run the map code and write world.json")
    parser.add_argument("--no-start", action="store_true", help="run MapService.Init only, not Start")
    parser.add_argument("--sim-seconds", type=float, default=5.0, help="simulated seconds to run tasks for (default 5)")
    parser.add_argument("--keep-going", action="store_true", help="render even if the map code raised errors")
    parser.add_argument("--no-pack", action="store_true",
                        help="ignore assets/models/StormWorldProps.glb (no prop pack: the part-built fallback props)")
    parser.add_argument("--pack-at", action="append", metavar="PATH",
                        help=f"DataModel path for the GLB prop pack (default {DEFAULT_PACK_AT}; 'none' = only via "
                             "InsertService:LoadAsset; repeatable)")
    parser.add_argument("--no-shadows", action="store_true", help="faster, flatter renders")
    parser.add_argument("--cameras", action="store_true",
                        help="print each shot's camera as a --shot option (to tweak a view)")
    parser.add_argument("--terrain-res", type=float, default=2.0, help="terrain mesh spacing in studs (default 2)")
    parser.add_argument("--luau", help="path to the luau command line (default: $LUAU or luau on PATH)")
    parser.add_argument("--timeout", type=float, default=300, help="seconds to wait for the browser (default 300)")
    parser.add_argument("--mock-timeout", type=float, default=120, help=argparse.SUPPRESS)
    parser.add_argument("--service", default=SERVICE, help=argparse.SUPPRESS)
    args = parser.parse_args(argv)
    if args.showcase and args.script:
        parser.error("--showcase and --script both pick the code to run: use one")
    if args.showcase:
        args.script = str(HERE / "PropShowcase.luau")
        if args.no_pack:
            parser.error("--showcase needs the prop pack (drop --no-pack)")
    if args.region is None:
        args.region = "none" if args.showcase or args.shot else "all"
    return parser, args


def main(argv=None):
    parser, args = parse_args(argv)
    out_dir = (ROOT / args.out) if not os.path.isabs(args.out) else Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)
    try:
        width, height = parse_size(args.size)
        parse_region_list(args.region)
    except ValueError as error:
        parser.error(str(error))

    started = time.time()
    pack = None
    if GLB.exists() and not args.no_pack:
        pack = pack_from_glb(GLB)
        print(f"  pack: {len(pack)} props from {GLB.relative_to(ROOT)}: {', '.join(p['Id'] for p in pack)}")
    elif not args.no_pack:
        print(f"  pack: {GLB.relative_to(ROOT)} not found, so WorldProps has no pack (part-built props)")
    what = Path(args.script).name if args.script else "MapService"
    print(f"Running {what} in the mock Roblox runtime...")
    world = run_mock(args, out_dir, pack)
    (out_dir / "world.json").write_text(json.dumps(world, separators=(",", ":")), encoding="utf-8")
    if args.dump_only:
        print(f"Wrote {out_dir / 'world.json'} in {time.time() - started:.1f}s")
        return

    try:
        shots = make_shots(world, args, width)
    except ValueError as error:
        parser.error(str(error))
    if not shots:
        sys.exit("nothing to render: --region none and no --shot")
    mesh_names = {mesh_key(piece["Name"]): piece["Name"] for prop in (pack or []) for piece in prop["Pieces"]}
    parts, used_meshes = part_records(world, mesh_names)
    scene = {"size": [width, height], "parts": parts, "lighting": lighting_settings(world),
             "shots": shots, "guis": [], "beams": [], "settings": {"shadows": not args.no_shadows}}
    for name in ("terrain.bin", "meshes.bin"):
        (out_dir / name).unlink(missing_ok=True)
    if used_meshes:
        items = export_meshes(pack, used_meshes, out_dir / "meshes.bin")
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
          f"{scene.get('terrain', {}).get('indices', 0) // 3} terrain triangles, {len(shots)} shots ({prep:.1f}s)")

    print("Rendering with three.js in headless Chromium...")
    written, cameras = render(out_dir, (width, height), args.timeout)
    if args.cameras:
        print("  cameras (reuse with --shot):")
        for cam in cameras:
            print(f'    --shot "{cam["name"]} pos={cam["pos"]} look={cam["look"]} fov={cam["fov"]}"')
    order = {shot["name"]: i for i, shot in enumerate(shots)}
    written.sort(key=lambda p: order.get(p.stem, 999))
    if len(written) > 2:
        sheet = contact_sheet(written, out_dir / "contact_sheet.png")
        if sheet:
            written.append(sheet)
    for path in written:
        print(f"  wrote {path.relative_to(ROOT) if ROOT in path.parents else path}")
    print(f"Done in {time.time() - started:.1f}s")


if __name__ == "__main__":
    main()
