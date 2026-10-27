"""Reusable chibi parts for the Secret Stormlings: faces (eyes, pupils, shines, lashes, blush, mouths),
feathered / membrane / fin wings, halos, crowns, orbit rings and small helpers.

Every builder returns plain mesh objects in the modelling space of kit.py (Z up, pet faces -Y, the pet's
left is +X); the caller files them under a role with Pet.add(role, ...).
"""

import math

import bmesh
import bpy
from mathutils import Matrix, Vector

import kit
from kit import Surface, curve_tube, decal, extrude_outline, subsurf, sweep, torus


def joined(name, *objs, consume=False):
    """A mesh object holding copies of objs (e.g. a single shrinkwrap/raycast target); consume=True removes
    the source objects."""
    bm = bmesh.new()
    for obj in objs:
        tmp = bmesh.new()
        tmp.from_mesh(obj.data)
        tmp.transform(obj.matrix_world)
        mesh = bpy.data.meshes.new("tmp")
        tmp.to_mesh(mesh)
        tmp.free()
        bm.from_mesh(mesh)
        bpy.data.meshes.remove(mesh)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    if consume:
        for obj in objs:
            kit.remove(obj)
    return kit.link(bpy.data.objects.new(name, mesh))


def mirrored(objs):
    return [kit.mirror_copy(o) for o in objs]


# --------------------------------------------------------------------------------------- face

def face(pet, body, eye_x=0.36, eye_z=0.08, eye_rx=0.17, eye_ry=0.22, tilt=0.0, pupil=0.74, lash=True,
         kohl=False, mouth="cat", mouth_z=-0.2, mouth_w=0.1, blush=True, blush_x=None, blush_z=None,
         brows=False, shine_side=-1):
    """Big glossy anime-chibi eyes and a little mouth on `body` (a baked mesh object).

    Eye (role Eye, the pet's neon EyeColor) is a domed oval; the pupil (role Mouth = dark ink) covers its
    upper part so the eye colour reads as a bright crescent at the bottom; Shine adds a big and a small
    highlight; lash draws an ink upper lid with a flick; kohl adds an Egyptian eyeliner tail.
    """
    surf = Surface(body)
    pupils, shines, inks, eyes = [], [], [], []
    for side in (-1, 1):
        x = side * eye_x
        roll = -side * tilt
        eye = decal(f"eye{side}", body, surf.front(x, eye_z), eye_rx, eye_ry, offset=0.004,
                    dome=0.03, roll=roll, rings=5, segments=28)
        eyes.append(eye)
        esurf = Surface(eye)
        pupil_obj = decal(f"pupil{side}", eye, esurf.front(x, eye_z + eye_ry * 0.12), eye_rx * pupil,
                          eye_ry * (pupil + 0.06), offset=0.003, roll=roll, rings=3, segments=24)
        pupils.append(pupil_obj)
        top = joined(f"eyetop{side}", eye, pupil_obj)
        tsurf = Surface(top)
        sx = shine_side
        big = decal(f"shine{side}a", top, tsurf.front(x + sx * eye_rx * 0.3, eye_z + eye_ry * 0.36),
                    eye_rx * 0.3, eye_ry * 0.24, offset=0.003, rings=3, segments=20, roll=0.5 * sx)
        small = decal(f"shine{side}b", top, tsurf.front(x - sx * eye_rx * 0.32, eye_z - eye_ry * 0.22),
                      eye_rx * 0.13, eye_rx * 0.13, offset=0.003, rings=2, segments=14)
        tiny = decal(f"shine{side}c", top, tsurf.front(x + sx * eye_rx * 0.02, eye_z + eye_ry * 0.02),
                     eye_rx * 0.07, eye_rx * 0.07, offset=0.003, rings=2, segments=10)
        shines += [big, small, tiny]
        kit.remove(top)
        if lash:
            pts = []
            for i in range(9):
                a = math.radians(25 + 130 * i / 8)
                # the arc runs from the outer corner to the inner corner
                ca = math.cos(a) * side
                px = x + ca * eye_rx * 1.08
                pz = eye_z + math.sin(a) * eye_ry * 1.06 - (0.0 if i else 0.0)
                pts.append((px, pz))
            path = kit.surface_path(surf, pts, offset=0.012)
            taper = [0.6, 1.0, 1.15, 1.2, 1.15, 1.05, 0.9, 0.7, 0.45]
            inks.append(curve_tube(f"lid{side}", path, 0.016, taper=taper[: len(path)], resolution=2))
            # outer flick
            ox = x + side * eye_rx * 1.0
            flick = kit.surface_path(surf, [(ox, eye_z + eye_ry * 0.45), (ox + side * 0.07, eye_z + eye_ry * 0.62),
                                            (ox + side * 0.12, eye_z + eye_ry * 0.85)], offset=0.012)
            inks.append(curve_tube(f"flick{side}", flick, 0.016, taper=[1.0, 0.75, 0.3][: len(flick)]))
        if kohl:
            kx = x + side * eye_rx * 0.95
            path = kit.surface_path(surf, [(kx, eye_z - eye_ry * 0.1), (kx + side * 0.12, eye_z - eye_ry * 0.2),
                                           (kx + side * 0.24, eye_z - eye_ry * 0.12)], offset=0.012)
            inks.append(curve_tube(f"kohl{side}", path, 0.02, taper=[1.0, 0.8, 0.35][: len(path)]))
        if brows:
            bz = eye_z + eye_ry * 1.55
            path = kit.surface_path(surf, [(x - side * eye_rx * 0.4, bz - 0.01), (x + side * eye_rx * 0.1, bz + 0.03),
                                           (x + side * eye_rx * 0.6, bz + 0.01)], offset=0.012)
            inks.append(curve_tube(f"brow{side}", path, 0.018, taper=[0.6, 1.0, 0.5][: len(path)]))
    pet.add("Eye", *eyes, keep=True)
    pet.add("Mouth", *pupils, *inks, keep=True)
    pet.add("Shine", *shines, keep=True)
    if mouth:
        pet.add("Mouth", *mouth_shape(surf, mouth, mouth_z, mouth_w), keep=True)
    if blush:
        bx = blush_x if blush_x is not None else eye_x + eye_rx * 0.55
        bz = blush_z if blush_z is not None else eye_z - eye_ry - 0.06
        for side in (-1, 1):
            pet.add("Blush", decal(f"blush{side}", body, surf.front(side * bx, bz), 0.12, 0.065, offset=0.004,
                                   rings=3, segments=20))
    return surf


def mouth_shape(surf, style, z, w):
    out = []
    if style == "cat":  # a soft "w"
        for side in (-1, 1):
            pts = [(0.0, z + 0.015), (side * w * 0.25, z - 0.035), (side * w * 0.6, z - 0.03), (side * w, z + 0.02)]
            path = kit.surface_path(surf, pts, offset=0.008)
            out.append(curve_tube(f"mouth{side}", path, 0.016, taper=[0.8, 1.0, 1.0, 0.7]))
    elif style == "smile":
        pts = [(-w, z + 0.03), (-w * 0.5, z - 0.025), (0, z - 0.04), (w * 0.5, z - 0.025), (w, z + 0.03)]
        path = kit.surface_path(surf, pts, offset=0.008)
        out.append(curve_tube("mouth", path, 0.017, taper=[0.6, 1.0, 1.0, 1.0, 0.6]))
    elif style == "fang":
        pts = [(-w, z + 0.02), (-w * 0.45, z - 0.02), (0, z - 0.03), (w * 0.45, z - 0.02), (w, z + 0.02)]
        path = kit.surface_path(surf, pts, offset=0.008)
        out.append(curve_tube("mouth", path, 0.016, taper=[0.6, 1.0, 1.0, 1.0, 0.6]))
    return out


def open_mouth(pet, body, z, w=0.09, h=0.07):
    """A little open "D" mouth sticker (use with face(..., mouth=None))."""
    surf = Surface(body)

    def shape(a):
        return 1.0 if math.sin(a) < 0 else 0.3

    pet.add("Mouth", decal("mouth", body, surf.front(0, z), w, h, offset=0.004, rings=3,
                           segments=22, shape=shape))


def belly(body, z, rx, ry, ridges=3, offset=0.012, dome=0.035, ridge_radius=0.02):
    """A smooth belly patch (an inlaid oval sticker) with raised horizontal ridges across it, like the
    plated belly of a dragon. Returns the objects (file them under one role)."""
    surf = Surface(body)
    patch = decal("belly", body, surf.front(0.0, z), rx, ry, offset=offset, dome=dome, rings=6, segments=36)
    psurf = Surface(patch)
    out = [patch]
    for k in range(1, ridges + 1):
        zk = z + ry * (0.75 - 1.5 * k / (ridges + 1))
        half = rx * math.sqrt(max(0.0, 1.0 - ((zk - z) / ry) ** 2)) * 0.82
        pts = [(-half + 2 * half * t / 8, zk + 0.025 * math.sin(math.pi * t / 8)) for t in range(9)]
        path = kit.surface_path(psurf, pts, offset=0.0)
        if len(path) > 2:
            out.append(curve_tube(f"ridge{k}", path, ridge_radius, taper=[0.3, 0.8, 1, 1, 1, 1, 1, 0.8, 0.3][: len(path)],
                                  resolution=2))
    return out


def fangs(body, z, x=0.05, size=0.04):
    """Two small rounded fang cones hanging under the mouth line (role Shine/Color_FFFFFF)."""
    surf = Surface(body)
    out = []
    for side in (-1, 1):
        loc, n = surf.front(side * x, z)
        tip = loc + Vector((0, -0.01, -size * 1.4))
        out.append(sweep(f"fang{side}", [loc - n * 0.02, loc + n * 0.01 + Vector((0, 0, -size * 0.5)), tip],
                         [size * 0.55, size * 0.45, 0.0], sides=8))
    return out


# --------------------------------------------------------------------------------------- wings

def feather(name, root, direction, length, width, thickness=0.05, curl=0.15, bend_axis=(0, 1, 0), sides=8,
            tip=0.0, smooth=1):
    """One plump, rounded feather (a paddle): narrow at the quill, widest past the middle, with a round
    end (tip > 0 makes it pointier). A flat elliptical sweep that curls about bend_axis, then smoothed by
    a subdivision surface."""
    d = Vector(direction).normalized()
    b = Vector(bend_axis).normalized()
    side = d.cross(b).normalized()
    ts = [0.0, 0.12, 0.3, 0.5, 0.66, 0.78, 0.87, 0.94, 0.985, 1.0]
    pts, radii = [], []
    for t in ts:
        bend = side * (curl * length * t * t)
        pts.append(Vector(root) + d * (length * t) + bend)
        if t <= 0.55:
            w = width * (0.45 + 0.55 * math.sin(math.pi / 2 * t / 0.55))
        else:
            u = (t - 0.55) / 0.45
            w = width * math.sqrt(max(0.0, 1.0 - u ** (2.0 - tip)))
        th = thickness * (0.7 + 0.3 * (w / width))
        radii.append((max(w, 0.0), max(th * min(1.0, w / width * 3), 0.0)))
    obj = sweep(name, pts, radii, sides=sides, up=tuple(b))
    if smooth:
        obj = subsurf(obj, smooth)
    return obj


def feather_wing(name, shoulder, span=1.0, count=5, base_angle=-20.0, fan=95.0, width=0.2, thickness=0.07,
                 sweep_back=0.3, curl=0.2, coverts=3, arm=True, tilt=0.0, tip=0.0):
    """A cute layered wing on the pet's +X side: a fan of plump primaries (longest at the top), a row of
    short coverts over their roots and a rounded arm along the leading edge. The wing lies in a plane
    swept back by `sweep_back` (radians about Z) and tilted by `tilt` (about the wing's own axis)."""
    sh = Vector(shoulder)
    rot = Matrix.Rotation(-sweep_back, 3, "Z") @ Matrix.Rotation(tilt, 3, "X")
    normal = rot @ Vector((0.0, 1.0, 0.0))
    objs = []
    for i in range(count):
        f = i / max(1, count - 1)
        ang = math.radians(base_angle + fan * f)
        d = rot @ Vector((math.cos(ang), 0.0, math.sin(ang)))
        length = span * (0.55 + 0.45 * math.sin(math.pi * (0.2 + 0.62 * f)))
        root = sh + rot @ Vector((0.0, 0.025 * (count - i), 0.0))
        objs.append(feather(f"{name}_p{i}", root, d, length, width * (0.9 + 0.15 * f), thickness, curl=curl,
                            bend_axis=normal, tip=tip))
    for i in range(coverts):
        f = (i + 0.5) / max(1, coverts)
        ang = math.radians(base_angle + 10 + (fan - 10) * f)
        d = rot @ Vector((math.cos(ang), 0.0, math.sin(ang)))
        root = sh + rot @ Vector((0.0, -0.05, 0.0))
        objs.append(feather(f"{name}_c{i}", root, d, span * 0.5, width * 1.2, thickness * 1.3, curl=0.12,
                            bend_axis=normal, tip=tip * 0.5))
    if arm:
        top = math.radians(base_angle + fan * 0.9)
        d = rot @ Vector((math.cos(top), 0.0, math.sin(top)))
        pts = [sh - d * 0.06, sh + d * span * 0.32, sh + d * span * 0.62, sh + d * span * 0.7]
        objs.append(subsurf(sweep(f"{name}_arm", pts, [(0.12, 0.09), (0.11, 0.08), (0.07, 0.06), (0.0, 0.0)],
                                  sides=8, up=tuple(normal)), 1))
    return objs


def membrane_wing(name, shoulder, span=1.0, height=0.9, sweep_back=0.3, bone=0.045, thickness=0.04,
                  billow=0.06):
    """Bat/dragon wing on the +X side: an arm bone up to the wrist, three finger bones fanning out from it
    (a little claw on the wrist) and a membrane between them with scalloped (concave) trailing edges.
    Returns (bones, membrane)."""
    place = Matrix.Translation(Vector(shoulder)) @ Matrix.Rotation(-sweep_back, 4, "Z")

    def at(u, v, w=0.0):  # wing plane: u out, v up, w back
        return place @ Vector((u, w, v))

    wrist2 = (span * 0.4, height * 0.62)
    tips2 = [(span * 0.98, height * 0.92), (span * 1.08, height * 0.32), (span * 0.74, -height * 0.18)]
    anchor2 = (span * 0.08, -height * 0.2)
    # membrane outline (2D): wrist -> tip0 -> scallop -> tip1 -> scallop -> tip2 -> scallop -> anchor -> shoulder
    chain = tips2 + [anchor2]
    outline = [wrist2, tips2[0]]
    for (ax, ay), (bx, by) in zip(chain[:-1], chain[1:]):
        length = math.hypot(bx - ax, by - ay)
        for k in range(1, 7):
            t = k / 6
            px, py = ax + (bx - ax) * t, ay + (by - ay) * t
            dx, dy = wrist2[0] - px, wrist2[1] - py
            dl = math.hypot(dx, dy) or 1.0
            pull = 0.2 * length * math.sin(math.pi * t)
            outline.append((px + dx / dl * pull, py + dy / dl * pull))
    outline += [(0.0, 0.0), (span * 0.2, height * 0.31)]
    centre = (wrist2[0] * 0.55 + tips2[1][0] * 0.25 + anchor2[0] * 0.2,
              wrist2[1] * 0.55 + tips2[1][1] * 0.25 + anchor2[1] * 0.2)
    bm = bmesh.new()
    c = bm.verts.new(at(*centre))
    ring = [bm.verts.new(at(u, v)) for u, v in outline]
    for i in range(len(ring)):
        bm.faces.new((c, ring[i], ring[(i + 1) % len(ring)]))
    bmesh.ops.subdivide_edges(bm, edges=list(bm.edges), cuts=2, use_grid_fill=True)
    mesh = bpy.data.meshes.new(name + "_mem")
    bm.to_mesh(mesh)
    bm.free()
    mem = kit.link(bpy.data.objects.new(name + "_mem", mesh))
    wrist3 = at(*wrist2)
    back = place.to_3x3() @ Vector((0, 1, 0))
    for v in mem.data.vertices:
        d = (v.co - wrist3).length / span
        v.co += back * billow * math.sin(min(d, 1.0) * math.pi)
    mem.data.update()
    kit.fix_normals_outward(mem, Vector((0, -1, 0)))
    kit.modifier(mem, "SOLIDIFY", thickness=thickness, offset=0.0, use_rim=True, use_even_offset=True)
    mem = kit.bake(mem)
    mem = kit.subsurf(mem, 1)
    # bones
    bones = [sweep(f"{name}_arm", [at(-0.05, -0.02), at(wrist2[0] * 0.5, wrist2[1] * 0.5 + 0.06), wrist3],
                   [bone * 1.7, bone * 1.4, bone * 1.25], sides=10)]
    bones.append(kit.uv_sphere(f"{name}_wrist", bone * 1.6, 14, 8, loc=tuple(wrist3)))
    for i, (u, v) in enumerate(tips2):
        tip = at(u * 1.02, v * 1.02 if v > 0 else v * 1.06)
        mid = wrist3.lerp(tip, 0.5) + back * 0.02
        bones.append(sweep(f"{name}_f{i}", [wrist3, mid, tip], [bone * 1.05, bone * 0.8, 0.0], sides=8))
    claw_base = wrist3 + Vector((0, 0, bone))
    bones.append(sweep(f"{name}_claw", [claw_base, claw_base + Vector((-0.02, -0.02, 0.09)),
                                        claw_base + Vector((-0.07, -0.03, 0.14))], [bone * 0.9, bone * 0.6, 0.0],
                       sides=8))
    bones = [kit.subsurf(b, 1) if len(b.data.polygons) < 400 else b for b in bones]
    return bones, [mem]


def fin_wing(name, shoulder, span=0.9, rays=5, height=0.8, sweep_back=0.35, thickness=0.04):
    """Webbed fish fin on the +X side: a rounded fan with raised rays. Returns (web, rays)."""
    sh = Vector(shoulder)
    back = Matrix.Rotation(-sweep_back, 3, "Z")
    web_pts = []
    ray_objs = []
    n = 28
    for i in range(n + 1):
        f = i / n
        ang = math.radians(-35 + 115 * f)
        r = span * (0.7 + 0.3 * math.sin(math.pi * f)) * (1.0 - 0.12 * math.cos(f * math.pi * rays * 2) ** 2)
        web_pts.append(sh + back @ Vector((math.cos(ang) * r, 0.0, math.sin(ang) * r * height / span)))
    bm = bmesh.new()
    c = bm.verts.new(sh)
    vs = [bm.verts.new(p) for p in web_pts]
    for a, b in zip(vs[:-1], vs[1:]):
        bm.faces.new((c, a, b))
    bmesh.ops.subdivide_edges(bm, edges=list(bm.edges), cuts=2, use_grid_fill=True)
    mesh = bpy.data.meshes.new(name + "_web")
    bm.to_mesh(mesh)
    bm.free()
    web = kit.link(bpy.data.objects.new(name + "_web", mesh))
    for v in web.data.vertices:
        d = (v.co - sh).length
        v.co.y += 0.08 * (d / span) ** 2
    web.data.update()
    kit.fix_normals_outward(web, Vector((0, -1, 0)))
    kit.modifier(web, "SOLIDIFY", thickness=thickness, offset=0.0, use_rim=True, use_even_offset=True)
    web = kit.bake(web)
    kit.modifier(web, "SUBSURF", levels=1, render_levels=1)
    web = kit.set_smooth(kit.bake(web))
    for i in range(rays):
        f = (i + 0.5) / rays
        ang = math.radians(-35 + 115 * f)
        r = span * (0.7 + 0.3 * math.sin(math.pi * f)) * 0.95
        tip = sh + back @ Vector((math.cos(ang) * r, 0.0, math.sin(ang) * r * height / span))
        mid = sh.lerp(tip, 0.5) + Vector((0, 0.08 * 0.25 - 0.012, 0))
        ray_objs.append(sweep(f"{name}_ray{i}", [sh, mid, tip], [0.035, 0.03, 0.0], sides=7, flat=0.8))
    return [web], ray_objs


# --------------------------------------------------------------------------------------- head gear

def halo(name, z, radius=0.42, tube=0.045, tilt=0.0, sides=12, segments=48):
    obj = torus(name, radius, tube, segments, sides, minor_z=tube * 0.8)
    kit.transform(obj, loc=(0, 0, z), rot=(tilt, 0, 0))
    return obj


def crown(name, z, radius=0.32, height=0.24, points=5, band=0.08, base_y=0.0, flare=1.12, tilt=0.0):
    """A chunky rounded crown: a bevelled band (lathe) with ball-tipped points. Returns (gold, tips) where
    tips are the ball positions (for gems)."""
    profile = [(radius * 0.92, -band * 0.5), (radius, -band * 0.5), (radius * 1.04, 0.0),
               (radius * flare, band * 0.6), (radius * flare * 0.95, band * 0.7), (radius * 0.88, band * 0.2),
               (radius * 0.86, -band * 0.45)]
    ring = kit.lathe(name + "_band", profile, segments=40)
    kit.modifier(ring, "SUBSURF", levels=1, render_levels=1)
    ring = kit.bake(ring)
    objs = [ring]
    tips = []
    for i in range(points):
        a = 2 * math.pi * i / points - math.pi / 2  # first point at the front (-Y)
        base = Vector((math.cos(a) * radius * flare * 0.97, math.sin(a) * radius * flare * 0.97, band * 0.5))
        top = Vector((math.cos(a) * radius * flare * 1.08, math.sin(a) * radius * flare * 1.08, height))
        objs.append(sweep(f"{name}_pt{i}", [base, base.lerp(top, 0.55), top], [0.07, 0.045, 0.02], sides=8))
        ball = kit.uv_sphere(f"{name}_ball{i}", 0.045, 12, 8, loc=tuple(top + Vector((0, 0, 0.02))))
        objs.append(ball)
        tips.append(top + Vector((0, 0, 0.02)))
    for o in objs:
        kit.transform(o, rot=(tilt, 0, 0))
        kit.transform(o, loc=(0, base_y, z))
    tips = [Matrix.Translation((0, base_y, z)) @ (Matrix.Rotation(tilt, 4, "X") @ t) for t in tips]
    return objs, tips


def gem(name, at, size=0.06, facets=6, flat_top=True):
    """A small faceted gem (flat shaded; put its role in pet.flat_roles)."""
    profile = [(0.0, -size * 1.1), (size, 0.0), (size * 0.62, size * 0.55), (0.0, size * 0.62)]
    obj = kit.lathe(name, profile, segments=facets, smooth=False)
    kit.transform(obj, loc=tuple(at))
    return obj


def star_outline(points=5, outer=1.0, inner=0.45, round_k=0.0):
    out = []
    for i in range(points * 2):
        a = math.pi / 2 + math.pi * i / points
        r = outer if i % 2 == 0 else inner
        out.append((math.cos(a) * r, math.sin(a) * r))
    return out


def bolt_outline(scale=1.0):
    pts = [(0.10, 1.0), (-0.32, 0.05), (-0.04, 0.05), (-0.18, -1.0), (0.34, 0.12), (0.05, 0.12), (0.28, 1.0)]
    return [(x * scale, z * scale) for x, z in pts]


def bolt(name, at, scale=0.2, depth=0.07, rot=(0, 0, 0), bevel=0.018):
    obj = extrude_outline(name, bolt_outline(scale), depth, bevel=bevel, bevel_segments=2)
    kit.set_smooth(obj, True)
    kit.transform(obj, rot=rot)
    kit.transform(obj, loc=tuple(at))
    return obj


def star(name, at, size=0.12, depth=0.05, rot=(0, 0, 0), bevel=0.015, points=5, inner=0.48):
    obj = extrude_outline(name, star_outline(points, size, size * inner), depth, bevel=bevel, bevel_segments=2)
    kit.set_smooth(obj, True)
    kit.transform(obj, rot=rot)
    kit.transform(obj, loc=tuple(at))
    return obj


def smooth_outline(points, per_segment=6):
    """Closed Catmull-Rom spline through 2D points -> a smooth outline polygon."""
    n = len(points)
    out = []
    for i in range(n):
        p0, p1, p2, p3 = (Vector(points[(i + k) % n]) for k in (-1, 0, 1, 2))
        for s in range(per_segment):
            t = s / per_segment
            t2, t3 = t * t, t * t * t
            p = 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)
            out.append((p.x, p.y))
    return out


def lobe_wing(name, shoulder, lobes, thickness=0.05, sweep_back=0.35, lift=0.15, veins=True):
    """Butterfly-style wing on the +X side: each lobe is a smooth outline [(out, up), ...] (spline points,
    in wing space: out = away from the body, up = +Z), extruded thin with rounded (bevelled) edges, plus
    raised veins from the root. The wing plane is swept back by `sweep_back` and tilted up by `lift`."""
    objs = []
    place = Matrix.Translation(Vector(shoulder)) @ Matrix.Rotation(-sweep_back, 4, "Z") @ Matrix.Rotation(-lift, 4, "Y")
    for i, lobe in enumerate(lobes):
        outline = smooth_outline(lobe, 6)
        obj = extrude_outline(f"{name}_lobe{i}", outline, thickness, bevel=thickness * 0.45, bevel_segments=2,
                              smooth=True)
        obj.data.transform(Matrix.Translation((0, 0.012 * i, 0)))
        obj.data.transform(place)
        obj.data.update()
        objs.append(obj)
        if veins:  # three raised veins from the root toward the outer rim
            mid =[(p[0] * 0.75, p[1] * 0.75) for p in lobe if (p[0] * p[0] + p[1] * p[1]) > 0.1]
            for j, end in enumerate(mid[:: max(1, len(mid) // 3)][:3]):
                pts = [Vector((0.05, -thickness * 0.6, 0.0)), Vector((end[0] * 0.5, -thickness * 0.6, end[1] * 0.5)),
                       Vector((end[0], -thickness * 0.6, end[1]))]
                pts = [place @ p for p in pts]
                objs.append(curve_tube(f"{name}_vein{i}{j}", pts, thickness * 0.35, taper=[1.0, 0.8, 0.3],
                                       resolution=3))
    return objs


def spiral_points(turns=1.6, r0=0.02, r1=0.2, n=40, phase=0.0, cx=0.0, cz=0.0, direction=1):
    pts = []
    for i in range(n):
        t = i / (n - 1)
        a = phase + direction * 2 * math.pi * turns * t
        r = r0 + (r1 - r0) * t
        pts.append((cx + math.cos(a) * r, cz + math.sin(a) * r))
    return pts


def ring_of(name, count, radius, z, make, tilt=0.0, phase=0.0):
    """count copies of make(name, angle) -> object placed around the Z axis at radius (for SpinY pieces)."""
    objs = []
    for i in range(count):
        a = phase + 2 * math.pi * i / count
        obj = make(f"{name}{i}", a)
        kit.transform(obj, loc=(math.cos(a) * radius, math.sin(a) * radius, 0))
        kit.transform(obj, rot=(tilt, 0, 0))
        kit.transform(obj, loc=(0, 0, z))
        objs.append(obj)
    return objs


def orbit_ring(name, radius, z, tube=0.018, tilt=0.25, segments=64):
    obj = torus(name, radius, tube, segments, 8)
    kit.transform(obj, rot=(tilt, 0, 0))
    kit.transform(obj, loc=(0, 0, z))
    return obj
