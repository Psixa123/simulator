#!/usr/bin/env python3
"""Builds the Stormling pet mesh pack (Roblox) and preview renders from tools/pets/pet_geometry.py.

pet_geometry.py is sandbox-safe pure Python (it is also pasted into the Trimble SketchUp MCP
sandbox, which forbids imports). This script loads it by exec'ing its source into a namespace that
already contains `math`, exactly like the sandbox does, then:

  1. checks the pet table against src/shared/Config/Pets.luau and every pet against the mesh pack
     contract (role names, Root/Pivot markers, triangle and mesh budgets, winding),
  2. writes assets/models/StormlingPets.glb   (PetMeshes -> <PetId> -> "<PetId>.<Role>" nodes, smooth normals,
                                                preview material colours; pets laid out on a grid)
            assets/models/StormlingPets.obj/.mtl (flat "<PetId>.<Role>" objects, same grid layout),
  3. renders previews with three.js in headless Chromium (tools/pets/viewer.html):
            build/pets/<PetId>.png (3/4 hero view, transparent background) and build/pets/sheet.png.

Usage (from the repo root):
    python tools/pets/build_pets.py                 export + hero renders + contact sheet
    python tools/pets/build_pets.py --no-render     export only
    python tools/pets/build_pets.py --check         validate only (sandbox safety, Pets.luau, contract)
    python tools/pets/build_pets.py --views         also front/side/back/top renders (build/pets/views/)
    python tools/pets/build_pets.py --tiers         also Golden/Rainbow renders (build/pets/tiers/)
    python tools/pets/build_pets.py --anim 0.1      also a posed render (wings/tail/halo animated)
    python tools/pets/build_pets.py --pets Puffling,VoltBat   only render these pets

Requirements: Python 3.9+, numpy, Pillow; for renders: Chrome/Chromium (CHROME_PATH or Playwright's
headless shell) and three.js (`npm install` in tools/pets, which pins three@0.169.0).
"""

import argparse
import ast
import builtins
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
HERE = ROOT / "tools" / "pets"
GEOMETRY = HERE / "pet_geometry.py"
PETS_LUAU = ROOT / "src" / "shared" / "Config" / "Pets.luau"
MODELS = ROOT / "assets" / "models"
OUT = ROOT / "build" / "pets"
FONT = ROOT / "assets" / "source" / "fonts" / "FredokaOne-Regular.ttf"

MAX_TRIS = 4000
MAX_VISIBLE_MESHES = 12
ANIMS = ("WingL", "WingR", "Wag", "SpinY", "SpinZ")
HINGED = ("WingL", "WingR", "Wag")
ROLE_RE = re.compile(r"^(Body|Accent|Eye|Shine|Blush|Mouth|Color_[0-9A-F]{6}|Neon_[0-9A-F]{6}|Ice_[0-9A-F]{6})(@(WingL|WingR|Wag|SpinY|SpinZ))?$")
PIVOT_RE = re.compile(r"^Pivot@(WingL|WingR|Wag)$")

# Builtins the SketchUp sandbox allows (anything else must be defined in the file itself)
SANDBOX_BUILTINS = {"range", "len", "min", "max", "abs", "int", "float", "str", "list", "dict", "tuple", "enumerate",
                    "isinstance", "sorted", "sum", "math", "True", "False", "None"}
FORBIDDEN_CALLS = {"eval", "exec", "open", "type", "setattr", "getattr", "__import__", "compile", "globals", "locals",
                   "vars", "print", "input"}

RARITY_COLORS = {
    "Common": (196, 204, 218), "Uncommon": (96, 222, 112), "Rare": (72, 164, 255), "Epic": (182, 96, 255),
    "Legendary": (255, 192, 42), "Exclusive": (255, 84, 156), "Secret": (44, 22, 88),
}


# --------------------------------------------------------------------------------------- loading

def load_geometry():
    source = GEOMETRY.read_text(encoding="utf-8")
    namespace = {"math": math}
    exec(compile(source, str(GEOMETRY), "exec"), namespace)  # same as the SketchUp sandbox
    return namespace


def check_sandbox_safety():
    """Static check that pet_geometry.py only uses what the SketchUp sandbox allows."""
    source = GEOMETRY.read_text(encoding="utf-8")
    tree = ast.parse(source)
    problems = []
    bound = set()
    for node in ast.walk(tree):
        if isinstance(node, (ast.Import, ast.ImportFrom)):
            problems.append(f"line {node.lineno}: import statement")
        elif isinstance(node, (ast.ClassDef, ast.Global, ast.Nonlocal, ast.Yield, ast.YieldFrom, ast.Await)):
            problems.append(f"line {node.lineno}: {type(node).__name__} is not allowed")
        elif isinstance(node, ast.Attribute) and node.attr.startswith("__"):
            problems.append(f"line {node.lineno}: dunder attribute {node.attr}")
        elif isinstance(node, ast.Name) and node.id.startswith("__"):
            problems.append(f"line {node.lineno}: dunder name {node.id}")
        elif isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id in FORBIDDEN_CALLS:
            problems.append(f"line {node.lineno}: call to {node.func.id}()")
        elif isinstance(node, ast.FormattedValue) and node.format_spec is not None:
            problems.append(f"line {node.lineno}: f-string format spec")
        if isinstance(node, (ast.FunctionDef, ast.Lambda)):
            if isinstance(node, ast.FunctionDef):
                bound.add(node.name)
            args = node.args
            for a in args.args + args.kwonlyargs + args.posonlyargs:
                bound.add(a.arg)
        elif isinstance(node, ast.Name) and isinstance(node.ctx, ast.Store):
            bound.add(node.id)
    for node in ast.walk(tree):
        if isinstance(node, ast.Name) and isinstance(node.ctx, ast.Load):
            if node.id not in bound and node.id not in SANDBOX_BUILTINS:
                problems.append(f"line {node.lineno}: unknown global/builtin {node.id}")
    return problems


def run_restricted():
    """Exec pet_geometry.py with ONLY the sandbox builtins (and `math`) and build every pet."""
    allowed = {name: getattr(builtins, name) for name in SANDBOX_BUILTINS if hasattr(builtins, name)}
    namespace = {"math": math, "__builtins__": allowed}
    exec(compile(GEOMETRY.read_text(encoding="utf-8"), str(GEOMETRY), "exec"), namespace)
    return namespace["build_all"]()


def parse_pets_luau():
    """Pets.Pets[*].Look from the Luau config -> {id: look}."""
    text = PETS_LUAU.read_text(encoding="utf-8")
    pets = {}
    line_re = re.compile(r'^\s*(\w+)\s*=\s*\{\s*Name\s*=\s*"([^"]+)",\s*Rarity\s*=\s*"(\w+)".*?Look\s*=\s*\{(.*)\}\s*\},?\s*$')
    rgb_re = r"rgb\((\d+),\s*(\d+),\s*(\d+)\)"
    for line in text.splitlines():
        m = line_re.match(line)
        if not m:
            continue
        pet_id, name, rarity, look_src = m.groups()
        look = {"Name": name, "Rarity": rarity}
        body = re.search(r'Body\s*=\s*"(\w+)"', look_src)
        look["Body"] = body.group(1) if body else None
        for key in ("Color", "Accent", "EyeColor"):
            c = re.search(key + r"\s*=\s*" + rgb_re, look_src)
            look[key] = tuple(int(v) for v in c.groups()) if c else None
        feats = re.search(r"Features\s*=\s*\{([^}]*)\}", look_src)
        look["Features"] = re.findall(r'"(\w+)"', feats.group(1)) if feats else []
        effect = re.search(r'Effect\s*=\s*"(\w+)"', look_src)
        look["Effect"] = effect.group(1) if effect else None
        pets[pet_id] = look
    return pets


def check_pet_table(geo):
    problems = []
    luau = parse_pets_luau()
    table = geo["PETS"]
    if set(luau) != set(table):
        problems.append(f"pet ids differ: only in Pets.luau {sorted(set(luau) - set(table))}, "
                        f"only in pet_geometry {sorted(set(table) - set(luau))}")
    if sorted(geo["PET_IDS"]) != sorted(table):
        problems.append("PET_IDS does not list every pet exactly once")
    for pet_id, look in luau.items():
        mine = table.get(pet_id)
        if not mine:
            continue
        for key in ("Name", "Rarity", "Body", "Color", "Accent", "EyeColor", "Effect", "Features"):
            a = look[key]
            b = mine[key]
            if isinstance(b, (list, tuple)) and key != "Features":
                b = tuple(b)
            if key == "Features":
                a, b = list(a), list(b)
            if a != b:
                problems.append(f"{pet_id}.{key}: Pets.luau has {a!r}, pet_geometry has {b!r}")
    return problems


# --------------------------------------------------------------------------------------- validation

def validate_pet(geo, pet_id, meshes):
    problems = []
    names = [m["name"] for m in meshes]
    if len(names) != len(set(names)):
        problems.append("duplicate mesh names")
    if "Root" not in names:
        problems.append("missing Root")
    anims = set()
    pivots = set()
    visible = 0
    tris = 0
    for m in meshes:
        name = m["name"]
        verts = np.asarray(m["verts"], dtype=np.float64)
        faces = np.asarray(m["tris"], dtype=np.int64)
        tris += len(faces)
        if len(faces) == 0 or faces.min() < 0 or faces.max() >= len(verts):
            problems.append(f"{name}: bad triangle indices")
            continue
        if name == "Root":
            lo, hi = verts.min(0), verts.max(0)
            if not (np.allclose(hi - lo, 0.2, atol=1e-6) and np.allclose((lo + hi) / 2, 0, atol=1e-6)):
                problems.append("Root must be a 0.2 cube centred on the origin")
            continue
        pm = PIVOT_RE.match(name)
        if pm:
            pivots.add(pm.group(1))
            lo, hi = verts.min(0), verts.max(0)
            if not np.allclose(hi - lo, 0.1, atol=1e-6):
                problems.append(f"{name} must be a 0.1 cube")
            continue
        rm = ROLE_RE.match(name)
        if not rm:
            problems.append(f"{name}: not a contract role name")
            continue
        visible += 1
        if rm.group(3):
            anims.add(rm.group(3))
        a, b, c = verts[faces[:, 0]], verts[faces[:, 1]], verts[faces[:, 2]]
        area = np.linalg.norm(np.cross(b - a, c - a), axis=1)
        if (area < 1e-12).sum() > len(faces) * 0.02:
            problems.append(f"{name}: {(area < 1e-12).sum()} degenerate triangles")
        # outward winding: the signed volume of the role's (mostly closed) pieces must be positive
        vol = np.einsum("ij,ij->i", a, np.cross(b, c)).sum() / 6.0
        if vol <= 0:
            problems.append(f"{name}: inward winding (signed volume {vol:.4f})")
    for anim in anims:
        if anim in HINGED and anim not in pivots:
            problems.append(f"missing Pivot@{anim}")
    for anim in pivots:
        if anim not in anims:
            problems.append(f"Pivot@{anim} without animated meshes")
    if tris > MAX_TRIS:
        problems.append(f"{tris} triangles > {MAX_TRIS}")
    if visible > MAX_VISIBLE_MESHES:
        problems.append(f"{visible} visible meshes > {MAX_VISIBLE_MESHES}")
    # spinning pieces rotate about the pet origin, so they must be centred on that axis
    for m in meshes:
        anim = geo["role_base"](m["name"])[1]
        if anim in ("SpinY", "SpinZ"):
            centre = np.asarray(m["verts"]).mean(0)
            axis_off = np.hypot(centre[0], centre[2]) if anim == "SpinY" else np.hypot(centre[0], centre[1])
            if axis_off > 0.05:
                problems.append(f"{m['name']} is {axis_off:.2f} studs off its spin axis")
    return problems, tris, visible


# --------------------------------------------------------------------------------------- export

def vertex_normals(verts, tris):
    v = np.asarray(verts, dtype=np.float64)
    f = np.asarray(tris, dtype=np.int64)
    normals = np.zeros_like(v)
    p = [v[f[:, k]] for k in range(3)]
    face_n = np.cross(p[1] - p[0], p[2] - p[0])
    face_n /= np.maximum(np.linalg.norm(face_n, axis=1, keepdims=True), 1e-20)
    for k in range(3):
        e1 = p[(k + 1) % 3] - p[k]
        e2 = p[(k + 2) % 3] - p[k]
        cos = np.einsum("ij,ij->i", e1, e2) / np.maximum(np.linalg.norm(e1, axis=1) * np.linalg.norm(e2, axis=1), 1e-20)
        angle = np.arccos(np.clip(cos, -1, 1))
        np.add.at(normals, f[:, k], face_n * angle[:, None])
    length = np.linalg.norm(normals, axis=1, keepdims=True)
    normals = np.where(length > 1e-12, normals / np.maximum(length, 1e-20), np.array([0.0, 1.0, 0.0]))
    return normals


def srgb_to_linear(c):
    c = c / 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4




def write_glb(path, geo, pack):
    blob = bytearray()
    views, accessors, meshes, materials = [], [], [], []
    nodes = [{"name": "PetMeshes", "children": []}]

    def add_view(data, target):
        while len(blob) % 4:
            blob.append(0)
        views.append({"buffer": 0, "byteOffset": len(blob), "byteLength": len(data), "target": target})
        blob.extend(data)
        return len(views) - 1

    for index, pet_id in enumerate(geo["PET_IDS"]):
        look = geo["PETS"][pet_id]
        pet_node = {"name": pet_id, "translation": list(geo["pack_offset"](index)), "children": [],
                    "extras": {"pet": pet_id, "displayName": look["Name"]}}
        nodes.append(pet_node)
        nodes[0]["children"].append(len(nodes) - 1)
        for m in pack[pet_id]:
            role = m["name"]
            info = geo["role_color"](role, look)
            pos = np.asarray(m["verts"], dtype=np.float32)
            nrm = vertex_normals(m["verts"], m["tris"]).astype(np.float32)
            idx = np.asarray(m["tris"], dtype=np.uint32 if len(pos) > 65535 else np.uint16).reshape(-1)
            pa = add_view(pos.tobytes(), 34962)
            accessors.append({"bufferView": pa, "componentType": 5126, "count": len(pos), "type": "VEC3",
                              "min": pos.min(0).tolist(), "max": pos.max(0).tolist()})
            na = add_view(nrm.tobytes(), 34962)
            accessors.append({"bufferView": na, "componentType": 5126, "count": len(nrm), "type": "VEC3"})
            ia = add_view(idx.tobytes(), 34963)
            accessors.append({"bufferView": ia, "componentType": 5125 if idx.dtype == np.uint32 else 5123,
                              "count": len(idx), "type": "SCALAR"})
            rgb = [srgb_to_linear(c) for c in info["rgb"]]
            alpha = 1.0 - info["transparency"]
            material = {"name": f"{pet_id}.{role}",
                        "pbrMetallicRoughness": {"baseColorFactor": rgb + [alpha], "metallicFactor": 0.0,
                                                 "roughnessFactor": 0.5}}
            if info["material"] == "Neon":
                material["emissiveFactor"] = rgb
            if alpha < 1.0:
                material["alphaMode"] = "BLEND"
            materials.append(material)
            # Every piece is named "<PetId>.<Role>" (node and mesh alike), so the game can tell which pet it
            # belongs to whatever an importer does with the names and the per-pet nodes
            meshes.append({"name": f"{pet_id}.{role}", "primitives": [{"attributes": {"POSITION": len(accessors) - 3,
                                                                        "NORMAL": len(accessors) - 2},
                                                         "indices": len(accessors) - 1,
                                                         "material": len(materials) - 1}]})
            extras = {"pet": pet_id, "role": role, "rgb": list(info["rgb"]), "material": info["material"],
                      "transparency": info["transparency"], "tint": info["tint"], "visible": info["visible"]}
            nodes.append({"name": f"{pet_id}.{role}", "mesh": len(meshes) - 1, "extras": extras})
            pet_node["children"].append(len(nodes) - 1)

    gltf = {
        "asset": {"version": "2.0", "generator": "Storm Catcher Simulator tools/pets/build_pets.py"},
        "scene": 0, "scenes": [{"name": "StormlingPets", "nodes": [0]}],
        "nodes": nodes, "meshes": meshes, "materials": materials, "accessors": accessors,
        "bufferViews": views, "buffers": [{"byteLength": len(blob)}],
    }
    while len(blob) % 4:
        blob.append(0)
    js = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    js += b" " * ((4 - len(js) % 4) % 4)
    out = bytearray()
    out += struct.pack("<4sII", b"glTF", 2, 12 + 8 + len(js) + 8 + len(blob))
    out += struct.pack("<I4s", len(js), b"JSON") + js
    out += struct.pack("<I4s", len(blob), b"BIN\x00") + blob
    path.write_bytes(bytes(out))


def write_obj(path, geo, pack):
    mtl_path = path.with_suffix(".mtl")
    obj = [f"# Stormling pet mesh pack - generated by tools/pets/build_pets.py (do not edit)",
           f"# Roblox studs, Y up, pets face -Z; each pet is laid out on a grid, its origin is its Root object",
           f"mtllib {mtl_path.name}"]
    mtl = ["# Stormling pet materials (preview colours; the game recolours by role)"]
    base = 1
    for index, pet_id in enumerate(geo["PET_IDS"]):
        look = geo["PETS"][pet_id]
        off = np.asarray(geo["pack_offset"](index))
        for m in pack[pet_id]:
            role = m["name"]
            name = f"{pet_id}.{role}"
            info = geo["role_color"](role, look)
            v = np.asarray(m["verts"], dtype=np.float64) + off
            n = vertex_normals(m["verts"], m["tris"])
            obj.append(f"o {name}")
            obj.append(f"usemtl {name}")
            obj.extend(f"v {p[0]:.4f} {p[1]:.4f} {p[2]:.4f}" for p in v)
            obj.extend(f"vn {p[0]:.3f} {p[1]:.3f} {p[2]:.3f}" for p in n)
            obj.append("s 1")
            obj.extend(f"f {a + base}//{a + base} {b + base}//{b + base} {c + base}//{c + base}" for (a, b, c) in m["tris"])
            base += len(v)
            r, g, b = (c / 255.0 for c in info["rgb"])
            mtl += [f"newmtl {name}", f"Kd {r:.4f} {g:.4f} {b:.4f}", "Ka 0 0 0", "Ks 0.25 0.25 0.25", "Ns 60",
                    f"d {1.0 - info['transparency']:.2f}", "illum 2"]
            if info["material"] == "Neon":
                mtl.append(f"Ke {r:.4f} {g:.4f} {b:.4f}")
    path.write_text("\n".join(obj) + "\n", encoding="utf-8")
    mtl_path.write_text("\n".join(mtl) + "\n", encoding="utf-8")


# --------------------------------------------------------------------------------------- rendering

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
    def log_message(self, *args):
        pass


def start_server():
    server = ThreadingHTTPServer(("127.0.0.1", 0), partial(QuietHandler, directory=str(ROOT)))
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server


def render_one(browser, port, pet_id, target, view="hero", tier="Normal", size=512, extra=""):
    target.parent.mkdir(parents=True, exist_ok=True)
    url = f"http://127.0.0.1:{port}/tools/pets/viewer.html?pet={pet_id}&view={view}&tier={tier}&size={size}{extra}"
    command = [browser, "--headless=new", "--no-sandbox", "--use-angle=swiftshader", "--enable-unsafe-swiftshader",
               "--hide-scrollbars", "--force-device-scale-factor=1", "--default-background-color=00000000",
               "--virtual-time-budget=20000", f"--window-size={size},{size}", f"--screenshot={target}", url]
    subprocess.run(command, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=180)
    return target


def render_all(jobs, workers=6):
    browser = find_browser()
    if not browser:
        print("  ! no Chrome/Chromium found (set CHROME_PATH) - skipping renders")
        return False
    if not (HERE / "node_modules" / "three" / "build" / "three.module.js").exists():
        print("  ! three.js missing - run `npm install` in tools/pets - skipping renders")
        return False
    server = start_server()
    port = server.server_address[1]
    try:
        with ThreadPoolExecutor(max_workers=workers) as pool:
            list(pool.map(lambda job: render_one(browser, port, *job), jobs))
    finally:
        server.shutdown()
    return True


def contact_sheet(geo, images, target, title, columns=8, tile=230):
    from PIL import Image, ImageDraw, ImageFilter, ImageFont

    ids = [pet_id for pet_id in geo["PET_IDS"] if pet_id in images]
    rows = (len(ids) + columns - 1) // columns
    pad = 18
    header = 92
    label = 40
    width = columns * (tile + pad) + pad
    height = header + rows * (tile + label + pad) + pad
    sheet = Image.new("RGB", (width, height))
    top, bottom = np.array([120, 205, 255]), np.array([46, 134, 240])
    gradient = (top[None, :] + (bottom - top)[None, :] * np.linspace(0, 1, height)[:, None]).astype(np.uint8)
    sheet.paste(Image.fromarray(np.repeat(gradient[:, None, :], width, axis=1)))
    draw = ImageDraw.Draw(sheet)
    try:
        title_font = ImageFont.truetype(str(FONT), 46)
        name_font = ImageFont.truetype(str(FONT), 21)
    except OSError:
        title_font = name_font = ImageFont.load_default()
    draw.text((width / 2, header / 2), title, font=title_font, fill="white", anchor="mm", stroke_width=4,
              stroke_fill=(27, 31, 59))
    for i, pet_id in enumerate(ids):
        row, col = divmod(i, columns)
        x = pad + col * (tile + pad)
        y = header + row * (tile + label + pad)
        look = geo["PETS"][pet_id]
        rarity = np.array(RARITY_COLORS.get(look["Rarity"], (200, 200, 200)))
        card = Image.new("RGBA", (tile, tile + label), (0, 0, 0, 0))
        cd = ImageDraw.Draw(card)
        cd.rounded_rectangle((0, 0, tile - 1, tile + label - 1), radius=18, fill=(244, 247, 255, 255),
                             outline=(43, 52, 103, 255), width=3)
        glow = Image.new("RGBA", (tile, tile), (0, 0, 0, 0))
        gd = ImageDraw.Draw(glow)
        light = tuple(int(c) for c in (rarity * 0.55 + 255 * 0.45)) + (255,)
        gd.rounded_rectangle((3, 3, tile - 4, tile - 4), radius=16, fill=light)
        card.alpha_composite(glow)
        shadow = Image.new("RGBA", (tile, tile), (0, 0, 0, 0))
        sd = ImageDraw.Draw(shadow)
        sd.ellipse((tile * 0.28, tile * 0.84, tile * 0.72, tile * 0.94), fill=(20, 30, 70, 70))
        card.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(5)))
        pet = Image.open(images[pet_id]).convert("RGBA").resize((tile - 16, tile - 16), Image.LANCZOS)
        card.alpha_composite(pet, (8, 6))
        cd = ImageDraw.Draw(card)
        cd.text((tile / 2, tile + label / 2 - 4), look["Name"], font=name_font, fill=(43, 52, 103), anchor="mm")
        cd.rounded_rectangle((tile - 92, 10, tile - 10, 32), radius=11, fill=tuple(int(c) for c in rarity) + (255,),
                             outline=(43, 52, 103, 255), width=2)
        small = ImageFont.truetype(str(FONT), 14) if FONT.exists() else name_font
        cd.text((tile - 51, 21), look["Rarity"], font=small, fill="white", anchor="mm", stroke_width=2,
                stroke_fill=(43, 52, 103))
        sheet.paste(card, (x, y), card)
    target.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(target)
    return target


def downsample(paths, size):
    from PIL import Image

    for p in paths:
        im = Image.open(p).convert("RGBA")
        if im.size[0] != size:
            im.resize((size, size), Image.LANCZOS).save(p)


# --------------------------------------------------------------------------------------- main

def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--check", action="store_true", help="validate only")
    parser.add_argument("--no-render", action="store_true", help="export the pack without renders")
    parser.add_argument("--views", action="store_true", help="also render front/side/back/top views")
    parser.add_argument("--tiers", action="store_true", help="also render Golden and Rainbow tiers")
    parser.add_argument("--anim", type=float, default=None, help="also render an animated pose at this time")
    parser.add_argument("--pets", default="", help="comma separated pet ids to render")
    parser.add_argument("--size", type=int, default=512, help="render size in pixels")
    parser.add_argument("--no-outline", action="store_true", help="render without the ink outline")
    args = parser.parse_args()

    print("Checking pet_geometry.py sandbox safety...")
    problems = check_sandbox_safety()
    geo = load_geometry()
    problems += check_pet_table(geo)
    print("Building meshes...")
    pack = geo["build_all"]()
    try:
        restricted = run_restricted()
        for pet_id, meshes in pack.items():
            other = restricted.get(pet_id, [])
            if [(m["name"], len(m["tris"])) for m in meshes] != [(m["name"], len(m["tris"])) for m in other]:
                problems.append(f"{pet_id}: different result with sandbox-only builtins")
    except Exception as error:  # noqa: BLE001 - report anything the sandbox would trip over
        problems.append(f"pet_geometry.py fails with sandbox-only builtins: {error!r}")
    report = []
    for pet_id in geo["PET_IDS"]:
        errs, tris, visible = validate_pet(geo, pet_id, pack[pet_id])
        problems += [f"{pet_id}: {e}" for e in errs]
        report.append((pet_id, tris, visible, len(pack[pet_id])))
    total = sum(r[1] for r in report)
    for pet_id, tris, visible, count in report:
        print(f"  {pet_id:16s} {tris:5d} tris  {visible:2d} visible meshes  ({count} incl. markers)")
    print(f"  total {total} triangles, max {max(r[1] for r in report)} per pet")
    if problems:
        print("PROBLEMS:")
        for p in problems:
            print("  -", p)
        sys.exit(1)
    print("All checks passed.")
    if args.check:
        return

    MODELS.mkdir(parents=True, exist_ok=True)
    write_glb(MODELS / "StormlingPets.glb", geo, pack)
    write_obj(MODELS / "StormlingPets.obj", geo, pack)
    for name in ("StormlingPets.glb", "StormlingPets.obj", "StormlingPets.mtl"):
        print(f"  wrote assets/models/{name} ({(MODELS / name).stat().st_size / 1024:.0f} KB)")
    if args.no_render:
        return

    wanted = [p for p in args.pets.split(",") if p] or list(geo["PET_IDS"])
    extra = "&outline=0" if args.no_outline else ""
    render_size = args.size * 2  # supersampled, then downsampled
    jobs = [(pet_id, OUT / f"{pet_id}.png", "hero", "Normal", render_size, extra) for pet_id in wanted]
    if args.views:
        for view in ("front", "side", "back", "top"):
            jobs += [(pet_id, OUT / "views" / f"{pet_id}_{view}.png", view, "Normal", render_size, extra) for pet_id in wanted]
    if args.tiers:
        for tier in ("Golden", "Rainbow"):
            jobs += [(pet_id, OUT / "tiers" / f"{pet_id}_{tier}.png", "hero", tier, render_size, extra) for pet_id in wanted]
    if args.anim is not None:
        jobs += [(pet_id, OUT / "anim" / f"{pet_id}_pose.png", "hero", "Normal", render_size, extra + f"&t={args.anim}")
                 for pet_id in wanted]
    print(f"Rendering {len(jobs)} previews...")
    if not render_all(jobs):
        return
    downsample([job[1] for job in jobs], args.size)
    images = {pet_id: OUT / f"{pet_id}.png" for pet_id in geo["PET_IDS"] if (OUT / f"{pet_id}.png").exists()}
    print("  wrote", contact_sheet(geo, images, OUT / "sheet.png", "STORMLINGS").relative_to(ROOT))
    if args.views:
        for view in ("front", "side", "back", "top"):
            imgs = {p: OUT / "views" / f"{p}_{view}.png" for p in wanted}
            print("  wrote", contact_sheet(geo, imgs, OUT / f"sheet_{view}.png", view.upper()).relative_to(ROOT))
    if args.tiers:
        for tier in ("Golden", "Rainbow"):
            imgs = {p: OUT / "tiers" / f"{p}_{tier}.png" for p in wanted}
            print("  wrote", contact_sheet(geo, imgs, OUT / f"sheet_{tier.lower()}.png", tier.upper()).relative_to(ROOT))
    if args.anim is not None:
        imgs = {p: OUT / "anim" / f"{p}_pose.png" for p in wanted}
        print("  wrote", contact_sheet(geo, imgs, OUT / "sheet_anim.png", "ANIMATED POSE").relative_to(ROOT))


if __name__ == "__main__":
    main()
