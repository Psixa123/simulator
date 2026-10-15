#!/usr/bin/env python3
"""Runs the SketchUp-side prop scripts without SketchUp (a stand-in for the Trimble SketchUp MCP sandbox).

The prop kit is modelled in SketchUp (tools/world/sketchup/*.py, sent with build_model). This module
executes the very same files locally against a small stand-in of the SketchUp API, chunk by chunk
(each "# ===== chunk" block in a fresh namespace with only the sandbox's builtins, sharing
session_state, exactly like build_model), then runs extract.py on the result. Uses:

  * `build_world_pack.py --check` runs every script through it, so a script that would fail in the
    sandbox (import, any()/all(), dunders, a typo) fails here first;
  * quick local previews while designing a prop, before spending SketchUp calls:

        python3 tools/world/offline_sketchup.py common            -> build/world/offline/common.json
        python3 tools/world/build_world_pack.py --source build/world/offline

    (the preview pack and renders go to build/world/offline/; assets/ is not touched).

The real pack is always built from SketchUp extractions (tools/world/import_sketchup.py).
"""

import argparse
import ast
import builtins
import json
import math
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = ROOT / "tools" / "world"
SCRIPTS = HERE / "sketchup"
CHUNK_RE = re.compile(r"^# ===== chunk", re.M)

# Builtins the SketchUp sandbox allows (probed in the sandbox; any()/all() are NOT available)
SANDBOX_BUILTINS = {"range", "len", "min", "max", "abs", "int", "float", "str", "list", "dict", "tuple", "set",
                    "enumerate", "zip", "reversed", "sorted", "sum", "round", "bool", "map", "isinstance", "hasattr",
                    "repr", "divmod", "print", "Exception"}
SKETCHUP_NAMES = {"model", "math", "session_state", "result", "SUPoint2D", "SUPoint3D", "SUVector3D", "SUTransformation",
                  "SUColor", "Face", "Edge", "Material", "Layer", "ArcCurve", "Curve", "Camera", "Scene", "Style",
                  "Texture", "Image", "ImageRep", "GeometryInput", "LoopInput", "Group", "ComponentDefinition",
                  "ComponentInstance", "SUMaterialWorkflow", "SUModelVersion", "RenderingOptionKey", "ShadowInfoKey",
                  "TypedValue", "RenderMode", "EdgeType", "EdgeDisplayMode"}
FORBIDDEN_CALLS = {"eval", "exec", "open", "type", "setattr", "getattr", "__import__", "compile", "globals", "locals",
                   "vars", "input", "any", "all"}


# ------------------------------------------------------------------------------ the SketchUp stand-in

class Point:
    def __init__(self, x, y, z=0.0):
        self.x, self.y, self.z = float(x), float(y), float(z)


class Color:
    def __init__(self, r, g, b, a=255):
        self.red, self.green, self.blue, self.alpha = int(r), int(g), int(b), int(a)


class Material:
    def __init__(self):
        self.name, self.color = "", Color(200, 200, 200)

    def set_name(self, name):
        self.name = name

    def get_name(self):
        return self.name

    def set_color(self, color):
        self.color = color

    def get_color(self):
        return self.color


class Transformation:
    def __init__(self, values):
        self.values = [float(v) for v in values]


class Typed:
    def __init__(self, **kw):
        if len(kw) != 1:
            raise TypeError("TypedValue takes exactly one named value")
        self.python_value = list(kw.values())[0]


class Vertex:
    def __init__(self, p):
        self.p = Point(*p)

    def get_position(self):
        return self.p


class Loop:
    def __init__(self, points):
        self.points = points

    def get_vertices(self):
        return [Vertex(p) for p in self.points]


def newell(points):
    n = [0.0, 0.0, 0.0]
    for i in range(len(points)):
        a, b = points[i], points[(i + 1) % len(points)]
        n[0] += (a[1] - b[1]) * (a[2] + b[2])
        n[1] += (a[2] - b[2]) * (a[0] + b[0])
        n[2] += (a[0] - b[0]) * (a[1] + b[1])
    return n


class Face:
    def __init__(self, outer, inners, front, back):
        self.outer, self.inners, self.front, self.back = outer, inners, front, back

    def get_outer_loop(self):
        return Loop(self.outer)

    def get_inner_loops(self):
        return [Loop(p) for p in self.inners]

    def get_front_material(self):
        return self.front

    def get_normal(self):
        n = newell(self.outer)
        k = math.sqrt(sum(c * c for c in n)) or 1.0
        return Point(n[0] / k, n[1] / k, n[2] / k)


class LoopInput:
    def __init__(self):
        self.ids, self.soft = [], set()

    def add_vertex_index(self, i):
        self.ids.append(int(i))

    def edge_set_soft(self, k, on):
        self.soft.add(k)

    def edge_set_smooth(self, k, on):
        pass


class GeometryInput:
    def __init__(self):
        self.verts, self.faces = [], []

    def set_vertices(self, points):
        self.verts = [(p.x, p.y, p.z) for p in points]

    def add_vertex(self, p):
        self.verts.append((p.x, p.y, p.z))
        return self

    def add_face(self, loop):
        self.faces.append({"outer": list(loop.ids), "inner": [], "front": None, "back": None})
        return len(self.faces) - 1, self

    def face_add_inner_loop(self, idx, loop):
        self.faces[idx]["inner"].append(list(loop.ids))
        return self

    def face_set_front_material(self, idx, uv, mat):
        self.faces[idx]["front"] = mat

    def face_set_back_material(self, idx, uv, mat):
        self.faces[idx]["back"] = mat


class Entities:
    def __init__(self):
        self.groups, self.faces = [], []

    def add_group(self, g):
        self.groups.append(g)

    def get_groups(self):
        return list(self.groups)

    def get_instances(self):
        return []

    def get_faces(self):
        return list(self.faces)

    def erase_entities(self, items):
        self.groups = [g for g in self.groups if g not in items]
        self.faces = [f for f in self.faces if f not in items]

    def fill(self, gi, weld_vertices=True):
        for f in gi.faces:
            pts = [gi.verts[i] for i in f["outer"]]
            n = newell(pts)
            k = math.sqrt(sum(c * c for c in n))
            if k < 1e-9:
                continue
            n = [c / k for c in n]
            # SketchUp refuses non-planar faces
            if max(abs(sum((p[j] - pts[0][j]) * n[j] for j in range(3))) for p in pts) > 1e-3:
                continue
            self.faces.append(Face(pts, [[gi.verts[i] for i in lp] for lp in f["inner"]], f["front"], f["back"]))


class Group:
    def __init__(self):
        self.name, self.ents, self.hidden, self.material = "", Entities(), False, None
        self.xf = Transformation([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1])
        self.dicts = {}

    def set_name(self, name):
        self.name = name

    def get_name(self):
        return self.name

    def set_transform(self, t):
        self.xf = t

    def get_transform(self):
        return self.xf

    def get_entities(self):
        return self.ents

    def get_hidden(self):
        return self.hidden

    def get_material(self):
        return self.material

    def get_attribute_dictionary(self, name):
        return self.dicts.setdefault(name, {})


class Model:
    def __init__(self):
        self.ents, self.materials = Entities(), []

    def get_entities(self):
        return self.ents

    def get_materials(self):
        return list(self.materials)

    def add_materials(self, mats):
        names = {m.get_name() for m in self.materials}
        for m in mats:
            if m.get_name() in names:
                raise RuntimeError("duplicate material " + m.get_name())
            self.materials.append(m)


# ------------------------------------------------------------------------------ running scripts

def chunks(path):
    """The build_model calls a script file is made of: its "# ===== chunk" blocks (or the whole file)."""
    source = Path(path).read_text(encoding="utf-8")
    marks = [m.start() for m in CHUNK_RE.finditer(source)]
    if not marks:
        return [source]
    return [source[a:b] for a, b in zip(marks, marks[1:] + [len(source)])]


def check_source(path):
    """Static check that a script only uses what the SketchUp sandbox allows."""
    path = Path(path)
    problems = []
    for n, chunk in enumerate(chunks(path), 1):
        where = f"{path.name} chunk {n}"
        lines = chunk.count("\n")
        if lines > 230:
            problems.append(f"{where}: {lines} lines (keep build_model calls under ~200 lines)")
        try:
            tree = ast.parse(chunk)
        except SyntaxError as e:
            problems.append(f"{where}: syntax error line {e.lineno}: {e.msg}")
            continue
        bound = set()
        for node in ast.walk(tree):
            if isinstance(node, (ast.Import, ast.ImportFrom)):
                problems.append(f"{where} line {node.lineno}: import statement")
            elif isinstance(node, (ast.ClassDef, ast.Global, ast.Nonlocal, ast.Yield, ast.YieldFrom, ast.Await)):
                problems.append(f"{where} line {node.lineno}: {type(node).__name__} is not allowed")
            elif isinstance(node, ast.Attribute) and node.attr.startswith("__"):
                problems.append(f"{where} line {node.lineno}: dunder attribute {node.attr}")
            elif isinstance(node, ast.Name) and node.id.startswith("__"):
                problems.append(f"{where} line {node.lineno}: dunder name {node.id}")
            elif isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id in FORBIDDEN_CALLS:
                problems.append(f"{where} line {node.lineno}: call to {node.func.id}()")
            if isinstance(node, (ast.FunctionDef, ast.Lambda)):
                if isinstance(node, ast.FunctionDef):
                    bound.add(node.name)
                for a in node.args.args + node.args.kwonlyargs + node.args.posonlyargs:
                    bound.add(a.arg)
            elif isinstance(node, ast.Name) and isinstance(node.ctx, ast.Store):
                bound.add(node.id)
            elif isinstance(node, ast.ExceptHandler) and node.name:
                bound.add(node.name)
        for node in ast.walk(tree):
            if isinstance(node, ast.Name) and isinstance(node.ctx, ast.Load):
                if node.id not in bound and node.id not in SANDBOX_BUILTINS and node.id not in SKETCHUP_NAMES:
                    problems.append(f"{where} line {node.lineno}: unknown name {node.id}")
    return problems


class Session:
    """One stand-in SketchUp session: a model plus session_state, fed build_model calls."""

    def __init__(self):
        self.model = Model()
        self.state = {}
        self.allowed = {name: getattr(builtins, name) for name in SANDBOX_BUILTINS if hasattr(builtins, name)}

    def call(self, code, label="<build_model>"):
        ns = {"__builtins__": self.allowed, "math": math, "model": self.model, "session_state": self.state,
              "SUPoint3D": Point, "SUColor": Color, "SUTransformation": Transformation, "TypedValue": Typed,
              "Material": Material, "Group": Group, "GeometryInput": GeometryInput, "LoopInput": LoopInput,
              "Exception": Exception}
        exec(compile(code, label, "exec"), ns)
        return ns.get("result")

    def run_file(self, path):
        return [self.call(chunk, f"{Path(path).name}#{n}") for n, chunk in enumerate(chunks(path), 1)]


def build_and_extract(categories):
    """lib.py + the category scripts + extract.py in one stand-in session -> (reports, extraction)."""
    session = Session()
    session.run_file(SCRIPTS / "lib.py")
    reports = []
    for cat in categories:
        for res in session.run_file(SCRIPTS / f"{cat}.py"):
            reports.extend((res or {}).get("built", []))
    extraction = session.call((SCRIPTS / "extract.py").read_text(encoding="utf-8"), "extract.py")
    return reports, extraction


def category_scripts():
    return sorted(p.stem for p in SCRIPTS.glob("*.py") if p.stem not in ("lib", "extract"))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("categories", nargs="*", help="category scripts to run (default: all)")
    parser.add_argument("--out", default=str(ROOT / "build" / "world" / "offline"), help="output folder")
    args = parser.parse_args()
    sys.path.insert(0, str(HERE))
    import import_sketchup

    cats = args.categories or category_scripts()
    reports, extraction = build_and_extract(cats)
    for r in reports:
        warn = ("  ! " + "; ".join(r["warnings"])) if r["warnings"] else ""
        print(f"  {r['id']:<16} {r['pieces']:>3} pieces {r['tris']:>5} tris  size {r['size']}{warn}")
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    (out / "extract.json").write_text(json.dumps(extraction, separators=(",", ":")), encoding="utf-8")
    written = import_sketchup.import_extraction(extraction, out, replace=True)
    print("wrote " + ", ".join(str(p.relative_to(ROOT)) for p in written))


if __name__ == "__main__":
    main()
