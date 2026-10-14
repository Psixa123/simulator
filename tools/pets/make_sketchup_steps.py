"""Prepares the Stormling pets for Trimble SketchUp (the SketchUp MCP / build_model sandbox).

The sandbox runs one Python snippet per call, forbids imports, and keeps nothing between calls except
the `session_state` dict. So this script:
  1. strips comments/docstrings from tools/pets/pet_geometry.py and re-indents it (smaller to paste),
  2. rewrites every top-level name to live in session_state["PGLIB"], so functions keep working across calls,
  3. splits it into chunks (paste chunk1..N in order, the first with clean=true),
  4. writes step_verify.py (must report the checksum printed below) and step_build1..K.py (5 pets each,
     building one "Stormlings" group with a group per pet and a sub-group per role mesh).

Usage:  python tools/pets/make_sketchup_steps.py [--chunks 4] [--out build/sketchup]
Then: run the files in order through build_model, style + camera, save_model("StormlingPets.skp").
The steps are checked here by simulating the sandbox (fresh namespace per call, shared session_state).
"""

import argparse
import ast
import math
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCE = ROOT / "tools" / "pets" / "pet_geometry.py"
BATCH_SIZE = 5


def minify(src):
    tree = ast.parse(src)

    class Strip(ast.NodeTransformer):
        def _strip(self, node):
            self.generic_visit(node)
            body = node.body
            if body and isinstance(body[0], ast.Expr) and isinstance(getattr(body[0], "value", None), ast.Constant) and isinstance(body[0].value.value, str):
                node.body = body[1:] or [ast.Pass()]
            return node

        visit_FunctionDef = _strip
        visit_Module = _strip

    return Strip().visit(tree)


def shrink(code):
    out = []
    for line in code.splitlines():
        if not line.strip():
            continue
        n = len(line) - len(line.lstrip(" "))
        out.append(" " * (n // 4) + line.lstrip(" "))
    return "\n".join(out)


def rewrite(tree):
    top = set()
    for node in tree.body:
        if isinstance(node, ast.FunctionDef):
            top.add(node.name)
        elif isinstance(node, ast.Assign):
            for target in node.targets:
                for n in ast.walk(target):
                    if isinstance(n, ast.Name):
                        top.add(n.id)
        else:
            raise SystemExit("unsupported top-level statement at line %d" % node.lineno)
    for n in ast.walk(tree):
        if isinstance(n, (ast.Global, ast.Nonlocal, ast.ClassDef, ast.Lambda)):
            raise SystemExit("unsupported %s at line %d" % (type(n).__name__, n.lineno))

    def bound(fn):
        names = set(a.arg for a in fn.args.args + fn.args.kwonlyargs)
        for extra in (fn.args.vararg, fn.args.kwarg):
            if extra:
                names.add(extra.arg)
        for n in ast.walk(fn):
            if n is fn:
                continue
            if isinstance(n, ast.Name) and isinstance(n.ctx, (ast.Store, ast.Del)):
                names.add(n.id)
            elif isinstance(n, ast.FunctionDef):
                names.add(n.name)
            elif isinstance(n, ast.arg):
                names.add(n.arg)
        return names

    class Rewriter(ast.NodeTransformer):
        scopes = []

        def visit_FunctionDef(self, node):
            node.args.defaults = [self.visit(d) for d in node.args.defaults]
            node.args.kw_defaults = [self.visit(d) if d is not None else None for d in node.args.kw_defaults]
            self.scopes.append(bound(node))
            node.body = [self.visit(s) for s in node.body]
            self.scopes.pop()
            return node

        def visit_Name(self, node):
            if node.id in top and not any(node.id in s for s in self.scopes):
                if self.scopes and isinstance(node.ctx, ast.Store):
                    return node
                ref = ast.Subscript(value=ast.Name(id="PGLIB", ctx=ast.Load()), slice=ast.Constant(value=node.id), ctx=node.ctx)
                return ast.copy_location(ref, node)
            return node

    rw = Rewriter()
    body = []
    for node in tree.body:
        if isinstance(node, ast.FunctionDef):
            body.append(rw.visit(node))
            body.append(ast.parse("PGLIB['%s'] = %s" % (node.name, node.name)).body[0])
        else:
            body.append(rw.visit(node))
    module = ast.Module(body=body, type_ignores=[])
    ast.fix_missing_locations(module)
    return [shrink(ast.unparse(s)) for s in module.body]


def checksum(entries):
    s = 0.0
    t = 0
    for e in entries:
        t += len(e["tris"])
        for i, v in enumerate(e["verts"]):
            s += (v[0] * 1.0 + v[1] * 2.0 + v[2] * 3.0) * ((i % 7) + 1)
        for tr in e["tris"]:
            s += (tr[0] + tr[1] * 2 + tr[2] * 3) * 0.001
    return round(s, 3), t, len(entries)


VERIFY = """PGLIB = session_state['PGLIB']
entries = PGLIB['sketchup_layout'](None, 12.0, False)
s = 0.0
t = 0
for e in entries:
    t += len(e['tris'])
    i = 0
    for v in e['verts']:
        s += (v[0] * 1.0 + v[1] * 2.0 + v[2] * 3.0) * ((i % 7) + 1)
        i += 1
    for tr in e['tris']:
        s += (tr[0] + tr[1] * 2 + tr[2] * 3) * 0.001
result = {'checksum': round(s, 3), 'tris': t, 'entries': len(entries), 'expected': __EXPECTED__}
"""

BUILD = "PGLIB = session_state['PGLIB']\nBATCH = __BATCH__\nentries = PGLIB['sketchup_layout'](BATCH, 12.0, False)\nexisting = {}\nfor m in model.get_materials():\n    existing[m.get_name()] = m\ndef pet_material(rgb, transparency):\n    alpha = int(round(255 * (1.0 - transparency)))\n    name = 'Pet_' + PGLIB['rgb_hex'](rgb)\n    if alpha < 255:\n        name = name + '_A' + str(alpha)\n    mat = existing.get(name)\n    if mat is None:\n        mat = Material()\n        mat.set_name(name)\n        mat.set_color(SUColor(int(rgb[0]), int(rgb[1]), int(rgb[2]), alpha))\n        model.add_materials([mat])\n        existing[name] = mat\n    return mat\nroot = None\nfor g in model.get_entities().get_groups():\n    if g.get_name() == 'Stormlings':\n        root = g\nif root is None:\n    root = Group()\n    model.get_entities().add_group(root)\n    root.set_name('Stormlings')\npet_groups = {}\nbuilt = []\nfor e in entries:\n    pg = pet_groups.get(e['pet'])\n    if pg is None:\n        pg = Group()\n        root.get_entities().add_group(pg)\n        pg.set_name(e['pet'])\n        pet_groups[e['pet']] = pg\n        built.append(e['pet'])\n    g = Group()\n    pg.get_entities().add_group(g)\n    g.set_name(e['role'])\n    geom = GeometryInput()\n    geom.set_vertices([SUPoint3D(v[0], v[1], v[2]) for v in e['verts']])\n    for tri in e['tris']:\n        lp = LoopInput()\n        lp.add_vertex_index(tri[0])\n        lp.add_vertex_index(tri[1])\n        lp.add_vertex_index(tri[2])\n        _, geom = geom.add_face(lp)\n    g.get_entities().fill(geom, weld_vertices=True)\n    mat = pet_material(e['rgb'], e['transparency'])\n    for f in g.get_entities().get_faces():\n        f.set_front_material(mat)\n        f.set_back_material(mat)\n    for ed in g.get_entities().get_edges():\n        if len(ed.get_faces()) == 2:\n            ed.set_soft(True)\n            ed.set_smooth(True)\nresult = {'built': built, 'meshes': len(entries), 'pet_groups_in_root': len(root.get_entities().get_groups())}\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--chunks", type=int, default=4)
    parser.add_argument("--out", default=str(ROOT / "build" / "sketchup"))
    args = parser.parse_args()
    out = pathlib.Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    stmts = rewrite(minify(SOURCE.read_text()))
    header = "PGLIB = session_state.setdefault('PGLIB', {})\n"
    target = sum(len(s) for s in stmts) / args.chunks
    chunks, current, size = [], [], 0
    for s in stmts:
        current.append(s)
        size += len(s)
        if size >= target and len(chunks) < args.chunks - 1 and not s.startswith("def "):
            chunks.append(current)
            current, size = [], 0
    chunks.append(current)
    files = []
    for i, chunk in enumerate(chunks, 1):
        path = out / ("chunk%d.py" % i)
        path.write_text(header + "\n".join(chunk) + "\nresult = {'chunk': %d, 'names': len(PGLIB)}\n" % i)
        files.append(path)

    # Simulate the sandbox: a fresh namespace per call, one shared session_state
    session_state = {}
    for path in files:
        exec(path.read_text(), {"math": math, "session_state": session_state, "Exception": Exception})
    lib = session_state["PGLIB"]
    expected = checksum(lib["sketchup_layout"](None, 12.0, False))
    (out / "step_verify.py").write_text(VERIFY.replace("__EXPECTED__", repr(list(expected))))
    ids = lib["PET_IDS"]
    batches = [ids[i:i + BATCH_SIZE] for i in range(0, len(ids), BATCH_SIZE)]
    for k, batch in enumerate(batches, 1):
        (out / ("step_build%d.py" % k)).write_text(BUILD.replace("__BATCH__", repr(batch)))

    for path in files:
        print("%-14s %6d bytes" % (path.name, path.stat().st_size))
    print("step_verify.py expects checksum=%s tris=%d entries=%d" % expected)
    print("%d build steps of up to %d pets in %s" % (len(batches), BATCH_SIZE, out))


if __name__ == "__main__":
    main()
