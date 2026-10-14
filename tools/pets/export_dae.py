"""Exports the Stormling pets as a COLLADA (.dae) file that SketchUp can import.

Same meshes and grid as the Roblox pack (tools/pets/pet_geometry.py), converted to SketchUp's
convention: inches, Z up, pets facing -Y. One node per pet (named by pet id) with one child node per
role mesh, each with its solid colour, so the SketchUp Outliner mirrors the Roblox MeshParts.

Usage:  python tools/pets/export_dae.py [--out assets/models/StormlingPets.dae]
Then in SketchUp: File > Import > COLLADA (*.dae).
"""

import argparse
import math
import pathlib
from xml.sax.saxutils import escape

ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCE = ROOT / "tools" / "pets" / "pet_geometry.py"


def load_library():
    namespace = {"math": math}
    exec(compile(SOURCE.read_text(), str(SOURCE), "exec"), namespace)
    return namespace


def ident(text):
    return "".join(c if c.isalnum() or c in "_-" else "_" for c in text)


def vertex_normals(verts, tris):
    normals = [[0.0, 0.0, 0.0] for _ in verts]
    for a, b, c in tris:
        p, q, r = verts[a], verts[b], verts[c]
        ux, uy, uz = q[0] - p[0], q[1] - p[1], q[2] - p[2]
        vx, vy, vz = r[0] - p[0], r[1] - p[1], r[2] - p[2]
        n = (uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx)
        for i in (a, b, c):
            normals[i][0] += n[0]
            normals[i][1] += n[1]
            normals[i][2] += n[2]
    out = []
    for n in normals:
        length = math.sqrt(n[0] * n[0] + n[1] * n[1] + n[2] * n[2]) or 1.0
        out.append((n[0] / length, n[1] / length, n[2] / length))
    return out


def floats(values):
    return " ".join("%.5f" % v for v in values)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--out", default=str(ROOT / "assets" / "models" / "StormlingPets.dae"))
    args = parser.parse_args()

    lib = load_library()
    entries = lib["sketchup_layout"](None, 12.0, False)

    materials = {}  # (rgb, alpha) -> id
    for e in entries:
        alpha = round(1.0 - e["transparency"], 3)
        key = (tuple(int(v) for v in e["rgb"]), alpha)
        if key not in materials:
            name = "Pet_" + lib["rgb_hex"](key[0]) + ("" if alpha >= 1 else "_A%d" % int(alpha * 100))
            materials[key] = name

    effects, mats, geoms, nodes = [], [], [], {}
    for (rgb, alpha), name in materials.items():
        r, g, b = (c / 255.0 for c in rgb)
        effects.append(
            '<effect id="%s-fx"><profile_COMMON><technique sid="common"><lambert>'
            '<diffuse><color>%.4f %.4f %.4f %.3f</color></diffuse>'
            '<transparent opaque="A_ONE"><color>0 0 0 %.3f</color></transparent><transparency><float>1</float></transparency>'
            "</lambert></technique></profile_COMMON></effect>" % (name, r, g, b, alpha, alpha)
        )
        mats.append('<material id="%s" name="%s"><instance_effect url="#%s-fx"/></material>' % (name, name, name))

    for index, e in enumerate(entries):
        gid = "g%d_%s" % (index, ident(e["name"]))
        verts, tris = e["verts"], e["tris"]
        normals = vertex_normals(verts, tris)
        mat = materials[(tuple(int(v) for v in e["rgb"]), round(1.0 - e["transparency"], 3))]
        geoms.append(
            '<geometry id="%s" name="%s"><mesh>'
            '<source id="%s-pos"><float_array id="%s-pos-a" count="%d">%s</float_array>'
            '<technique_common><accessor source="#%s-pos-a" count="%d" stride="3"><param name="X" type="float"/><param name="Y" type="float"/><param name="Z" type="float"/></accessor></technique_common></source>'
            '<source id="%s-nrm"><float_array id="%s-nrm-a" count="%d">%s</float_array>'
            '<technique_common><accessor source="#%s-nrm-a" count="%d" stride="3"><param name="X" type="float"/><param name="Y" type="float"/><param name="Z" type="float"/></accessor></technique_common></source>'
            '<vertices id="%s-vtx"><input semantic="POSITION" source="#%s-pos"/><input semantic="NORMAL" source="#%s-nrm"/></vertices>'
            '<triangles material="mat" count="%d"><input semantic="VERTEX" source="#%s-vtx" offset="0"/><p>%s</p></triangles>'
            "</mesh></geometry>"
            % (
                gid, escape(e["name"]),
                gid, gid, len(verts) * 3, floats(c for v in verts for c in v), gid, len(verts),
                gid, gid, len(normals) * 3, floats(c for n in normals for c in n), gid, len(normals),
                gid, gid, gid,
                len(tris), gid, " ".join("%d %d %d" % t for t in tris),
            )
        )
        node = (
            '<node id="n%d" name="%s"><instance_geometry url="#%s"><bind_material><technique_common>'
            '<instance_material symbol="mat" target="#%s"/></technique_common></bind_material></instance_geometry></node>'
            % (index, escape(e["role"]), gid, mat)
        )
        nodes.setdefault(e["pet"], []).append(node)

    pet_nodes = "".join(
        '<node id="pet_%s" name="%s">%s</node>' % (ident(pet), escape(pet), "".join(children))
        for pet, children in nodes.items()
    )
    document = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<COLLADA xmlns="http://www.collada.org/2005/11/COLLADASchema" version="1.4.1">'
        "<asset><contributor><authoring_tool>Storm Catcher Simulator tools/pets/export_dae.py</authoring_tool></contributor>"
        '<unit name="inch" meter="0.0254"/><up_axis>Z_UP</up_axis></asset>'
        "<library_effects>%s</library_effects><library_materials>%s</library_materials>"
        "<library_geometries>%s</library_geometries>"
        '<library_visual_scenes><visual_scene id="scene" name="Stormlings"><node id="Stormlings" name="Stormlings">%s</node></visual_scene></library_visual_scenes>'
        '<scene><instance_visual_scene url="#scene"/></scene></COLLADA>\n'
        % ("".join(effects), "".join(mats), "".join(geoms), pet_nodes)
    )
    out = pathlib.Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(document)
    print("%s: %d pets, %d meshes, %d triangles, %d materials, %.1f MB" % (
        out.name, len(nodes), len(entries), sum(len(e["tris"]) for e in entries), len(materials), out.stat().st_size / 1e6))


if __name__ == "__main__":
    main()
