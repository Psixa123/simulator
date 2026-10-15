# Storm Catcher Simulator - SketchUp prop extraction (tools/world/sketchup/extract.py)
#
# Sent to the Trimble SketchUp MCP sandbox (build_model) as ONE call after the props are built. It
# returns every top-level group named "Prop_<PropId>" as raw polygons in prop-local coordinates
# (inches, Z up, the prop group's own placement removed), one entry per leaf group ("piece"):
#
#   result = {"storm_world_extract": 1, "units": "inch", "props": [
#       {"id": "TreeRound", "category": "common", "solid": true, "slot": [x, y, z],
#        "paints": {"Primary": "5CC94F", ...},           # defaults from the prop's attributes
#        "pieces": [{"paint": "Primary", "rgb": "5CC94F", "alpha": 255, "collide": null, "crease": 40,
#                    "v": [x0, y0, z0, x1, ...],          # vertex table, rounded to 0.01 in
#                    "f": [[[0, 1, 2, 3], [hole...]], ...]}, ...]}, ...]}  # face = outer loop + holes
#
# Faces are wound counter-clockwise around their front (outward) normal. Nested groups and component
# instances are walked; a leaf takes its paint from the nearest group/instance named by a paint
# (Primary, Secondary, Tertiary, Color_RRGGBB, Neon_RRGGBB, Glass_RRGGBB; a "#1" suffix is ignored).
# Hidden groups are skipped. Then run tools/world/import_sketchup.py on the saved tool result.
#
# Edit ONLY to extract a subset (prop ids); empty = every prop in the model.
ONLY = []
DIGITS = 2
TINTS = {"primary": "Primary", "secondary": "Secondary", "tertiary": "Tertiary"}
FIXED = {"color_": "Color_", "neon_": "Neon_", "glass_": "Glass_"}
HEX = "0123456789ABCDEF"
IDENTITY = [1.0, 0, 0, 0, 0, 1.0, 0, 0, 0, 0, 1.0, 0, 0, 0, 0, 1.0]


def paint_of(name):
    """Normalised paint name, or None when the name is not a paint."""
    base = (name or "").split("#")[0].strip()
    low = base.lower()
    if low in TINTS:
        return TINTS[low]
    for pre in FIXED:
        code = base[len(pre):].upper()
        if low.startswith(pre) and len(code) == 6 and len([c for c in code if c in HEX]) == 6:
            return FIXED[pre] + code
    return None


def mat_mul(a, b):
    """Column-major 4x4 product a * b."""
    out = [0.0] * 16
    for c in range(4):
        for r in range(4):
            out[c * 4 + r] = a[r] * b[c * 4] + a[4 + r] * b[c * 4 + 1] + a[8 + r] * b[c * 4 + 2] + a[12 + r] * b[c * 4 + 3]
    return out


def apply(m, p):
    return [m[0] * p.x + m[4] * p.y + m[8] * p.z + m[12],
            m[1] * p.x + m[5] * p.y + m[9] * p.z + m[13],
            m[2] * p.x + m[6] * p.y + m[10] * p.z + m[14]]


def det3(m):
    return (m[0] * (m[5] * m[10] - m[9] * m[6]) - m[4] * (m[1] * m[10] - m[9] * m[2])
            + m[8] * (m[1] * m[6] - m[5] * m[2]))


def attrs(entity, name):
    out = {}
    try:
        d = entity.get_attribute_dictionary(name)
        for k in list(d.keys()):
            out[k] = d[k].python_value
    except Exception:
        pass
    return out


def color_of(mat):
    if mat is None:
        return None, 255
    c = mat.get_color()
    code = ""
    for x in (c.red, c.green, c.blue):
        code += HEX[int(x) // 16] + HEX[int(x) % 16]
    return code, int(c.alpha)


def leaf_piece(ents, xf, paint, mat, meta):
    """Polygons of the faces directly in `ents`, in prop-local coordinates."""
    flip = det3(xf) < 0
    index, verts, faces = {}, [], []
    rgb, alpha = None, 255
    for face in ents.get_faces():
        if rgb is None:
            front = face.get_front_material()
            rgb, alpha = color_of(front if front is not None else mat)
        loops = []
        for lp in [face.get_outer_loop()] + list(face.get_inner_loops()):
            ids = []
            for v in lp.get_vertices():
                p = apply(xf, v.get_position())
                key = (round(p[0], DIGITS), round(p[1], DIGITS), round(p[2], DIGITS))
                if key not in index:
                    index[key] = len(verts) // 3
                    verts.extend([key[0], key[1], key[2]])
                ids.append(index[key])
            loops.append(list(reversed(ids)) if flip else ids)
        faces.append(loops)
    if rgb is None:
        rgb, alpha = color_of(mat)
    return {"paint": paint or "Unpainted", "rgb": rgb, "alpha": alpha, "collide": meta.get("collide"),
            "crease": meta.get("crease"), "v": verts, "f": faces}


def walk(ents, xf, paint, mat, meta, out):
    if len(ents.get_faces()) > 0:
        out.append(leaf_piece(ents, xf, paint, mat, meta))
    for g in ents.get_groups():
        if g.get_hidden():
            continue
        own_meta = dict(meta)
        own_meta.update(attrs(g, "storm_piece"))
        own = g.get_material()
        walk(g.get_entities(), mat_mul(xf, list(g.get_transform().values)), paint_of(g.get_name()) or paint,
             own if own is not None else mat, own_meta, out)
    for inst in ents.get_instances():
        if inst.get_hidden():
            continue
        d = inst.get_definition()
        name = inst.get_name() or d.get_name()
        own = inst.get_material()
        walk(d.get_entities(), mat_mul(xf, list(inst.get_transform().values)), paint_of(name) or paint,
             own if own is not None else mat, meta, out)


props, skipped = [], []
for g in model.get_entities().get_groups():
    name = g.get_name() or ""
    if not name.startswith("Prop_"):
        continue
    info = attrs(g, "storm_prop")
    prop_id = info.get("id") or name[5:]
    if ONLY and prop_id not in ONLY:
        skipped.append(prop_id)
        continue
    pieces = []
    walk(g.get_entities(), IDENTITY, None, None, {}, pieces)
    t = list(g.get_transform().values)
    paints = {}
    for k in info:
        if k.startswith("paint_"):
            paints[k[6:]] = info[k]
    props.append({"id": prop_id, "category": info.get("category") or "misc", "solid": bool(info.get("solid")),
                  "slot": [round(t[12], DIGITS), round(t[13], DIGITS), round(t[14], DIGITS)],
                  "paints": paints, "pieces": pieces})

result = {"storm_world_extract": 1, "units": "inch", "props": props, "skipped": skipped,
          "summary": [[p["id"], len(p["pieces"]), sum([len(x["f"]) for x in p["pieces"]])] for p in props]}
