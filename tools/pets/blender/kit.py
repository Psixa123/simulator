"""Shared Blender helpers for the Secret Stormling models (tools/pets/blender/).

Run with Blender's Python module (`pip install bpy`), see build_secret_pets.py. Everything here works
headless (no operators that need a UI context): meshes are built with bmesh / from_pydata, modifiers
(Subdivision Surface, Shrinkwrap, Solidify, Skin, Bevel, Remesh, Decimate, ...) are evaluated through the
depsgraph and baked into plain meshes, and curves / metaballs are converted the same way.

Modelling space (Blender): metres = studs, Z up, the pet faces -Y, origin = pet centre, the pet's own
left side is +X. `export_pet` turns the result 180 degrees about Z, so the glTF (Y up) has the pet facing
-Z exactly like the rest of the pack (assets/models/StormlingPets.glb), with WingL on the pack's -X side.
"""

import math
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

ROOT = Path(__file__).resolve().parents[3]
GEOMETRY = ROOT / "tools" / "pets" / "pet_geometry.py"

FACE_ROLES = ("Eye", "Shine", "Blush", "Mouth")


# --------------------------------------------------------------------------------------- pet table

def load_geometry():
    """pet_geometry.py namespace (pet table + role colours), loaded the way build_pets.py does."""
    namespace = {"math": math}
    exec(compile(GEOMETRY.read_text(encoding="utf-8"), str(GEOMETRY), "exec"), namespace)
    return namespace


GEO = load_geometry()


def look(pet_id):
    return GEO["PETS"][pet_id]


def role_info(role, pet_look):
    return GEO["role_color"](role, pet_look)


# --------------------------------------------------------------------------------------- scene basics

def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def link(obj):
    bpy.context.scene.collection.objects.link(obj)
    return obj


def mesh_object(name, verts, faces, smooth=True):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([tuple(v) for v in verts], [], [tuple(f) for f in faces])
    mesh.validate(clean_customdata=False)
    mesh.update()
    obj = link(bpy.data.objects.new(name, mesh))
    set_smooth(obj, smooth)
    return obj


def set_smooth(obj, smooth=True):
    if obj.type == "MESH" and len(obj.data.polygons):
        obj.data.polygons.foreach_set("use_smooth", [bool(smooth)] * len(obj.data.polygons))
        obj.data.update()
    return obj


def remove(obj):
    data = obj.data
    bpy.data.objects.remove(obj, do_unlink=True)
    if data is not None and data.users == 0:
        if isinstance(data, bpy.types.Mesh):
            bpy.data.meshes.remove(data)
        elif isinstance(data, bpy.types.Curve):
            bpy.data.curves.remove(data)
        elif isinstance(data, bpy.types.MetaBall):
            bpy.data.metaballs.remove(data)


def bake(obj, keep_smooth=None):
    """Evaluates the object's modifiers (or curve/metaball geometry) into a plain mesh object with the
    transform applied. Returns the new mesh object (the original is removed)."""
    depsgraph = bpy.context.evaluated_depsgraph_get()
    depsgraph.update()
    evaluated = obj.evaluated_get(depsgraph)
    mesh = bpy.data.meshes.new_from_object(evaluated, preserve_all_data_layers=False, depsgraph=depsgraph)
    mesh.transform(obj.matrix_world)
    name = obj.name
    remove(obj)
    new = link(bpy.data.objects.new(name, mesh))
    if keep_smooth is not None:
        set_smooth(new, keep_smooth)
    return new


def modifier(obj, kind, **settings):
    mod = obj.modifiers.new(kind.lower(), kind)
    for key, value in settings.items():
        setattr(mod, key, value)
    return mod


def subsurf(obj, levels=2, apply=True):
    modifier(obj, "SUBSURF", levels=levels, render_levels=levels, quality=3)
    return bake(obj) if apply else obj


def transform(obj, loc=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1)):
    """Applies loc/rot(euler XYZ radians)/scale to the mesh data."""
    from mathutils import Euler

    m = Matrix.Translation(Vector(loc)) @ Euler(rot, "XYZ").to_matrix().to_4x4() @ Matrix.Diagonal((*scale, 1.0))
    obj.data.transform(m)
    obj.data.update()
    return obj


def deform(obj, fn):
    """fn(Vector) -> Vector for every vertex."""
    for v in obj.data.vertices:
        v.co = fn(v.co.copy())
    obj.data.update()
    return obj


def mirror_copy(obj, name=None):
    """A copy mirrored in X (faces flipped back to point outward)."""
    mesh = obj.data.copy()
    mesh.transform(Matrix.Diagonal((-1.0, 1.0, 1.0, 1.0)))
    mesh.flip_normals()
    new = link(bpy.data.objects.new(name or obj.name + "_m", mesh))
    return new


def duplicate(obj, name=None):
    new = link(bpy.data.objects.new(name or obj.name + "_d", obj.data.copy()))
    return new


def triangulate(obj):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.triangulate(bm, faces=bm.faces, quad_method="BEAUTY", ngon_method="BEAUTY")
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
    return obj


def signed_volume(obj):
    """Signed volume of the mesh (positive when the faces point outward; for an open sticker facing away from
    the origin it is the positive volume of the cone it spans)."""
    mesh = obj.data
    mw = obj.matrix_world
    co = [mw @ v.co for v in mesh.vertices]
    total = 0.0
    for p in mesh.polygons:
        idx = list(p.vertices)
        a = co[idx[0]]
        for i in range(1, len(idx) - 1):
            total += a.dot(co[idx[i]].cross(co[idx[i + 1]]))
    return total / 6.0


def tri_count(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


# --------------------------------------------------------------------------------------- primitives

def quad_sphere(name, radius=1.0, level=3, loc=(0, 0, 0), scale=(1, 1, 1)):
    """A sphere with clean quad edge flow (a subdivided cube pushed onto the sphere)."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=2.0)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = link(bpy.data.objects.new(name, mesh))
    modifier(obj, "SUBSURF", levels=level, render_levels=level, quality=3)
    obj = bake(obj)
    deform(obj, lambda co: co.normalized() * radius)
    transform(obj, loc=loc, scale=scale)
    return set_smooth(obj)


def uv_sphere(name, radius=1.0, segments=24, rings=12, loc=(0, 0, 0), scale=(1, 1, 1)):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segments, v_segments=rings, radius=radius)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = link(bpy.data.objects.new(name, mesh))
    transform(obj, loc=loc, scale=scale)
    return set_smooth(obj)


def frames_along(points, up_hint=(0, 0, 1)):
    """Rotation-minimising frames (tangent, normal, binormal) along a polyline."""
    pts = [Vector(p) for p in points]
    n = len(pts)
    tangents = []
    for i in range(n):
        a = pts[max(i - 1, 0)]
        b = pts[min(i + 1, n - 1)]
        t = b - a
        tangents.append(t.normalized() if t.length > 1e-9 else Vector((0, 0, 1)))
    up = Vector(up_hint)
    normal = up - tangents[0] * up.dot(tangents[0])
    if normal.length < 1e-6:
        normal = Vector((1, 0, 0)) - tangents[0] * tangents[0].x
    normal.normalize()
    frames = []
    for i in range(n):
        if i > 0:
            # double reflection would be nicer; projection is plenty for our short, smooth paths
            normal = normal - tangents[i] * normal.dot(tangents[i])
            if normal.length < 1e-6:
                normal = frames[-1][1]
            normal.normalize()
        binormal = tangents[i].cross(normal).normalized()
        frames.append((tangents[i], normal, binormal))
    return frames


def sweep(name, points, radii, sides=10, flat=1.0, up=(0, 0, 1), cap_start=True, cap_end=True, twist=0.0,
          smooth=True):
    """A tube along `points` with elliptical cross-sections.

    radii: one radius per point (or (rx, ry) pairs; ry runs along the frame normal, which starts at `up`).
    flat scales the normal-direction radius (flat < 1 gives ribbons/feathers). Radius 0 at an end makes a
    point. Ends are closed with a pole vertex, so the result is a closed (watertight) shell.
    """
    pts = [Vector(p) for p in points]
    frames = frames_along(pts, up)
    verts, faces = [], []
    rings = []
    for i, (p, (t, nrm, bin_)) in enumerate(zip(pts, frames)):
        r = radii[i]
        rx, ry = (r, r * flat) if not isinstance(r, (tuple, list)) else r
        ring = []
        for s in range(sides):
            a = 2 * math.pi * s / sides + twist * i
            offset = bin_ * (math.cos(a) * rx) + nrm * (math.sin(a) * ry)
            ring.append(len(verts))
            verts.append(p + offset)
        rings.append(ring)
    for i in range(len(rings) - 1):
        for s in range(sides):
            a, b = rings[i][s], rings[i][(s + 1) % sides]
            c, d = rings[i + 1][(s + 1) % sides], rings[i + 1][s]
            faces.append((a, d, c, b))
    if cap_start:
        verts.append(pts[0] - frames[0][0] * 1e-4)
        c = len(verts) - 1
        for s in range(sides):
            faces.append((c, rings[0][s], rings[0][(s + 1) % sides]))
    if cap_end:
        verts.append(pts[-1] + frames[-1][0] * 1e-4)
        c = len(verts) - 1
        for s in range(sides):
            faces.append((c, rings[-1][(s + 1) % sides], rings[-1][s]))
    obj = mesh_object(name, verts, faces, smooth)
    fix_normals(obj)
    return obj


def fix_normals(obj):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
    return obj


def lathe(name, profile, segments=24, smooth=True):
    """Revolves [(radius, z), ...] around Z (first/last radius 0 closes the ends)."""
    verts, faces = [], []
    rings = []
    for r, z in profile:
        if r < 1e-6:
            rings.append([len(verts)] * segments)
            verts.append((0.0, 0.0, z))
            continue
        ring = []
        for s in range(segments):
            a = 2 * math.pi * s / segments
            ring.append(len(verts))
            verts.append((r * math.cos(a), r * math.sin(a), z))
        rings.append(ring)
    for i in range(len(rings) - 1):
        for s in range(segments):
            a, b = rings[i][s], rings[i][(s + 1) % segments]
            c, d = rings[i + 1][(s + 1) % segments], rings[i + 1][s]
            quad = [a, b, c, d]
            uniq = []
            for q in quad:
                if q not in uniq:
                    uniq.append(q)
            if len(uniq) >= 3:
                faces.append(tuple(uniq))
    obj = mesh_object(name, verts, faces, smooth)
    fix_normals(obj)
    return obj


def torus(name, major, minor, segments=48, sides=12, minor_z=None):
    """A ring around Z at the origin (minor_z flattens/stretches the tube vertically)."""
    minor_z = minor if minor_z is None else minor_z
    verts, faces = [], []
    for i in range(segments):
        a = 2 * math.pi * i / segments
        for j in range(sides):
            b = 2 * math.pi * j / sides
            r = major + minor * math.cos(b)
            verts.append((r * math.cos(a), r * math.sin(a), minor_z * math.sin(b)))
    for i in range(segments):
        for j in range(sides):
            a = i * sides + j
            b = ((i + 1) % segments) * sides + j
            c = ((i + 1) % segments) * sides + (j + 1) % sides
            d = i * sides + (j + 1) % sides
            faces.append((a, b, c, d))
    obj = mesh_object(name, verts, faces)
    fix_normals(obj)
    return obj


def extrude_outline(name, outline, depth, bevel=0.0, bevel_segments=2, smooth=False):
    """A 2D outline [(x, z), ...] (counter-clockwise seen from -Y) extruded along Y, centred on y=0,
    with optional rounded (bevelled) edges. Good for bolts, stars, crown points and shards."""
    bm = bmesh.new()
    front = [bm.verts.new((x, -depth / 2, z)) for x, z in outline]
    face = bm.faces.new(front)
    bmesh.ops.recalc_face_normals(bm, faces=[face])
    if face.normal.y > 0:
        face.normal_flip()
    result = bmesh.ops.extrude_face_region(bm, geom=[face])
    moved = [e for e in result["geom"] if isinstance(e, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, verts=moved, vec=(0, depth, 0))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4], quad_method="BEAUTY",
                          ngon_method="BEAUTY")
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = link(bpy.data.objects.new(name, mesh))
    if bevel > 0:
        modifier(obj, "BEVEL", width=bevel, segments=bevel_segments, limit_method="ANGLE",
                 angle_limit=math.radians(30), harden_normals=False)
        obj = bake(obj)
    set_smooth(obj, smooth)
    return obj


def metaball_mesh(name, balls, resolution=0.06, threshold=0.6, smooth_iterations=8, remesh=None):
    """Organic blob from metaballs: balls = [(center, radius) or (center, radius, (sx, sy, sz))].
    Converted to a mesh, optionally voxel-remeshed (even quads) and relaxed."""
    data = bpy.data.metaballs.new("mb_" + name.replace(".", "_"))
    data.resolution = resolution
    data.render_resolution = resolution
    data.threshold = threshold
    for ball in balls:
        el = data.elements.new()
        el.co = Vector(ball[0])
        el.radius = ball[1]
        if len(ball) > 2:
            el.type = "ELLIPSOID"
            el.size_x, el.size_y, el.size_z = ball[2]
        el.stiffness = 2.0
    obj = link(bpy.data.objects.new("mb_" + name.replace(".", "_"), data))
    obj = bake(obj)
    obj.name = name
    if remesh:
        modifier(obj, "REMESH", mode="VOXEL", voxel_size=remesh, use_smooth_shade=True)
        obj = bake(obj)
    if smooth_iterations:
        modifier(obj, "SMOOTH", factor=0.5, iterations=smooth_iterations)
        obj = bake(obj)
    return set_smooth(obj)


def blob_union(name, blobs, voxel=0.03, smooth=6, smooth_factor=0.5):
    """Union of ellipsoids [(center, (rx, ry, rz)), ...] via a voxel remesh (even quad topology), then
    relaxed so the creases between the puffs stay soft but readable (cloud puffs, paws, cheeks)."""
    bm = bmesh.new()
    for center, radii in blobs:
        tmp = bmesh.new()
        bmesh.ops.create_icosphere(tmp, subdivisions=4, radius=1.0)
        bmesh.ops.scale(tmp, vec=Vector(radii), verts=tmp.verts)
        bmesh.ops.translate(tmp, vec=Vector(center), verts=tmp.verts)
        mesh = bpy.data.meshes.new("tmp")
        tmp.to_mesh(mesh)
        tmp.free()
        bm.from_mesh(mesh)
        bpy.data.meshes.remove(mesh)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = link(bpy.data.objects.new(name, mesh))
    modifier(obj, "REMESH", mode="VOXEL", voxel_size=voxel, use_smooth_shade=True)
    obj = bake(obj)
    if smooth:
        modifier(obj, "SMOOTH", factor=smooth_factor, iterations=smooth)
        obj = bake(obj)
    return set_smooth(obj)


def skin_tree(name, verts, edges, radii, subdiv=2, root=0):
    """Organic limbs/horns/antlers: a vertex skeleton with the Skin modifier + subdivision surface.
    radii: one radius (or (rx, ry)) per skeleton vertex."""
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([tuple(v) for v in verts], [tuple(e) for e in edges], [])
    mesh.update()
    obj = link(bpy.data.objects.new(name, mesh))
    modifier(obj, "SKIN", use_smooth_shade=True)
    skin = mesh.skin_vertices[0].data
    for i, r in enumerate(radii):
        rx, ry = r if isinstance(r, (tuple, list)) else (r, r)
        skin[i].radius = (rx, ry)
        skin[i].use_root = i == root
    modifier(obj, "SUBSURF", levels=subdiv, render_levels=subdiv, quality=3)
    return set_smooth(bake(obj))


def curve_tube(name, points, radius, taper=None, resolution=3, bevel_resolution=1, closed=False):
    """A smooth bevelled curve through points (NURBS-like smoothness from a Bezier with auto handles).
    taper: optional list of per-point radius multipliers."""
    data = bpy.data.curves.new(name, "CURVE")
    data.dimensions = "3D"
    data.resolution_u = resolution
    data.bevel_depth = radius
    data.bevel_resolution = bevel_resolution
    data.use_fill_caps = True
    spline = data.splines.new("BEZIER")
    spline.bezier_points.add(len(points) - 1)
    for i, p in enumerate(points):
        bp = spline.bezier_points[i]
        bp.co = Vector(p)
        bp.handle_left_type = bp.handle_right_type = "AUTO"
        if taper:
            bp.radius = taper[i]
    spline.use_cyclic_u = closed
    obj = link(bpy.data.objects.new(name, data))
    return set_smooth(bake(obj))


# --------------------------------------------------------------------------------------- surfaces

class Surface:
    """Ray casts against a (baked) mesh object, e.g. the body, to seat decals and details on it."""

    def __init__(self, *objects):
        bm = bmesh.new()
        for obj in objects:
            tmp = bmesh.new()
            tmp.from_mesh(obj.data)
            tmp.transform(obj.matrix_world)
            mesh = bpy.data.meshes.new("tmp")
            tmp.to_mesh(mesh)
            tmp.free()
            bm.from_mesh(mesh)
            bpy.data.meshes.remove(mesh)
        self.tree = BVHTree.FromBMesh(bm)
        self.bm = bm

    def hit(self, origin, direction):
        loc, normal, _, _ = self.tree.ray_cast(Vector(origin), Vector(direction).normalized())
        return loc, normal

    def toward(self, point, center=(0, 0, 0)):
        """Surface point along the ray from far outside through `point` toward `center`."""
        p = Vector(point)
        c = Vector(center)
        d = (p - c).normalized()
        return self.hit(c + d * 10.0, -d)

    def front(self, x, z, y_from=-10.0):
        """Surface point hit by a ray travelling +Y (from the front) at (x, z)."""
        return self.hit((x, y_from, z), (0, 1, 0))

    def nearest(self, point):
        loc, normal, _, _ = self.tree.find_nearest(Vector(point))
        return loc, normal


def disc(name, rx, ry, rings=6, segments=28, shape=None):
    """A flat filled ellipse in the XY plane (normal +Z), polar grid. shape(angle) scales the rim."""
    verts = [(0.0, 0.0, 0.0)]
    faces = []
    for r in range(1, rings + 1):
        f = r / rings
        for s in range(segments):
            a = 2 * math.pi * s / segments
            k = shape(a) if shape else 1.0
            verts.append((math.cos(a) * rx * f * k, math.sin(a) * ry * f * k, 0.0))
    for s in range(segments):
        faces.append((0, 1 + s, 1 + (s + 1) % segments))
    for r in range(1, rings):
        base0 = 1 + (r - 1) * segments
        base1 = 1 + r * segments
        for s in range(segments):
            faces.append((base0 + s, base1 + s, base1 + (s + 1) % segments, base0 + (s + 1) % segments))
    return mesh_object(name, verts, faces)


def orient_matrix(origin, normal, up=(0, 0, 1), roll=0.0):
    """Matrix placing local +Z along `normal`, local +Y toward `up`, at origin."""
    z = Vector(normal).normalized()
    u = Vector(up)
    x = u.cross(z)
    if x.length < 1e-6:
        x = Vector((1, 0, 0))
    x.normalize()
    y = z.cross(x).normalized()
    if roll:
        c, s = math.cos(roll), math.sin(roll)
        x, y = x * c + y * s, y * c - x * s
    m = Matrix((x, y, z)).transposed().to_4x4()
    m.translation = Vector(origin)
    return m


def decal(name, target, at, rx, ry, offset=0.01, dome=0.0, sink=0.012, roll=0.0, rings=5, segments=28,
          shape=None, direction=None, up=(0, 0, 1)):
    """A sticker that hugs the target surface (eyes, pupils, blush, markings): a polar ellipse disc placed
    at the surface point `at` (from Surface.front/toward), Shrinkwrap-projected onto the target at `offset`,
    domed outward by `dome` at its centre, with its rim sunk `sink` below the surface so it reads as
    inlaid with no visible edge. (An open shell facing outward: the target closes it.)"""
    loc, normal = at
    facing = Vector(direction).normalized() if direction else normal
    obj = disc(name, rx, ry, rings, segments, shape)
    ell = []
    for v in obj.data.vertices:
        a = math.atan2(v.co.y / max(ry, 1e-6), v.co.x / max(rx, 1e-6))
        k = shape(a) if shape else 1.0
        ell.append(min(1.0, math.hypot(v.co.x / (rx * k), v.co.y / (ry * k))))
    obj.matrix_world = orient_matrix(loc + facing * 0.3, facing, up, roll)
    obj = bake(obj)
    modifier(obj, "SHRINKWRAP", target=target, wrap_method="PROJECT", wrap_mode="ON_SURFACE", offset=0.0,
             use_negative_direction=True, use_positive_direction=True)
    obj = bake(obj)
    surf = Surface(target)
    for v, e in zip(obj.data.vertices, ell):
        _, n = surf.nearest(v.co)
        if n is None:
            continue
        lift = offset + dome * (1.0 - e * e)
        if e > 0.999:
            lift = -sink
        v.co = v.co + n * lift
    obj.data.update()
    fix_normals_outward(obj, facing)
    obj["keep"] = True
    return set_smooth(obj)


def fix_normals_outward(obj, facing):
    """Flip a sheet so its faces point along `facing`."""
    mesh = obj.data
    total = Vector((0, 0, 0))
    for p in mesh.polygons:
        total += p.normal * p.area
    if total.dot(Vector(facing)) < 0:
        mesh.flip_normals()
        mesh.update()
    return obj


def surface_path(surface, points2d, offset=0.0):
    """Projects (x, z) points onto the surface from the front and lifts them by `offset`."""
    out = []
    for x, z in points2d:
        loc, normal = surface.front(x, z)
        if loc is None:
            continue
        out.append(loc + normal * offset)
    return out


# --------------------------------------------------------------------------------------- materials

def srgb_to_linear(c):
    c = c / 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def role_material(pet_id, role, pet_look):
    """Preview material for a role (the game recolours by role, see PetModels.luau)."""
    name = f"{pet_id}.{role}"
    mat = bpy.data.materials.get(name)
    if mat:
        return mat
    info = role_info(role, pet_look)
    rgb = [srgb_to_linear(c) for c in info["rgb"]]
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    bsdf = nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.42
    base = role.split("@")[0]
    if info["material"] == "Neon" or base == "Shine":
        bsdf.inputs["Emission Color"].default_value = (*rgb, 1.0)
        bsdf.inputs["Emission Strength"].default_value = 1.6 if base != "Eye" else 1.1
    if base == "Eye":
        bsdf.inputs["Roughness"].default_value = 0.12
    if info["material"] == "Ice":
        bsdf.inputs["Roughness"].default_value = 0.08
        bsdf.inputs["Transmission Weight"].default_value = 0.35
    bsdf.inputs["Coat Weight"].default_value = 0.6 if base in ("Body", "Accent", "Eye") else 0.25
    bsdf.inputs["Coat Roughness"].default_value = 0.08
    if info["transparency"] > 0 and info["visible"]:
        bsdf.inputs["Alpha"].default_value = 1.0 - info["transparency"]
    mat.diffuse_color = (*rgb, 1.0)
    return mat


# --------------------------------------------------------------------------------------- the pet

class Pet:
    """Collects parts by role, then merges, triangulates, fits the budget, adds Root/Pivot markers and
    exports. Roles follow the pack contract (tools/pets/README.md): Body, Accent, Eye, Shine, Blush, Mouth,
    Color_RRGGBB, Neon_RRGGBB, Ice_RRGGBB, each optionally @WingL/@WingR/@Wag/@SpinY/@SpinZ."""

    def __init__(self, pet_id):
        self.pet_id = pet_id
        self.look = look(pet_id)
        self.parts = {}  # role -> [objects]
        self.pivots = {}  # anim -> (x, y, z)
        self.flat_roles = set()  # roles shaded flat (crystals)
        self.final = {}  # role -> merged object
        self.raw = {}  # role -> triangles before fitting the budget

    def add(self, role, *objs, keep=False):
        """Files objects under a role. keep=True (or obj["keep"], set by decal/curve_tube) protects a part
        from decimation (thin stickers and face lines would lose their outline)."""
        for obj in objs:
            if obj is None:
                continue
            triangulate(obj)
            if signed_volume(obj) < 0:  # a shell wound inside out (thin pieces can confuse recalc_face_normals)
                obj.data.flip_normals()
                obj.data.update()
            self.parts.setdefault(role, []).append(obj)
            if keep:
                obj["keep"] = True
        return objs[0] if objs else None

    def pivot(self, anim, at):
        self.pivots[anim] = tuple(at)

    def all_parts(self):
        return [(role, obj) for role, objs in self.parts.items() for obj in objs]

    def tris(self):
        if self.final:
            return sum(tri_count(o) for o in self.final.values())
        return sum(tri_count(o) for _, o in self.all_parts())

    def fit_budget(self, budget, floor_tris=80, role_weights=None):
        """Collapse-decimates parts until the pet fits `budget` triangles. What the protected parts (keep
        parts: the face, stickers) leave is shared by "water filling": a part keeps min(its triangles,
        max(floor, cap * sqrt(area))), so big surfaces get more triangles but small curvy parts (horns,
        feathers, bolts) keep proportionally more of theirs. Parts near the X=0 plane are decimated
        symmetrically."""
        for role, obj in self.all_parts():
            self.raw[role] = self.raw.get(role, 0) + tri_count(obj)
        for attempt in range(6):
            parts = self.all_parts()
            total = sum(tri_count(o) for _, o in parts)
            if total <= budget:
                break
            flex = [(r, o) for r, o in parts if not o.get("keep")]
            fixed = total - sum(tri_count(o) for _, o in flex)
            if not flex:
                break
            avail = (budget - fixed) * (0.99 - 0.02 * attempt)
            info = []
            for role, obj in flex:
                count = tri_count(obj)
                area = sum(p.area for p in obj.data.polygons)
                boost = (role_weights or {}).get(role, 2.0 if role == "Body" else 1.0)
                info.append((role, obj, count, min(count, floor_tris), boost * max(area, 0.01) ** 0.5))
            lo, hi = 0.0, float(max(c for _, _, c, _, _ in info)) * 100
            for _ in range(60):
                cap = (lo + hi) / 2
                if sum(min(c, max(f, cap * w)) for _, _, c, f, w in info) > avail:
                    hi = cap
                else:
                    lo = cap
            for role, obj, count, floor, w in info:
                target = min(count, max(floor, lo * w))
                if target >= count * 0.995:
                    continue
                centre_x = sum(v.co.x for v in obj.data.vertices) / max(1, len(obj.data.vertices))
                modifier(obj, "DECIMATE", decimate_type="COLLAPSE", ratio=max(0.01, target / count),
                         use_symmetry=abs(centre_x) < 0.05, symmetry_axis="X", use_collapse_triangulate=True)
                new = bake(obj)
                objs = self.parts[role]
                objs[objs.index(obj)] = new
        return self.tris()

    def merge(self):
        for role, objs in self.parts.items():
            bm = bmesh.new()
            for obj in objs:
                tmp = bmesh.new()
                tmp.from_mesh(obj.data)
                tmp.transform(obj.matrix_world)
                m = bpy.data.meshes.new("tmp")
                tmp.to_mesh(m)
                tmp.free()
                bm.from_mesh(m)
                bpy.data.meshes.remove(m)
            for obj in objs:
                remove(obj)
            bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
            bmesh.ops.triangulate(bm, faces=bm.faces, quad_method="BEAUTY", ngon_method="BEAUTY")
            # drop degenerate slivers (zero-area triangles) left by decimation
            bad = [f for f in bm.faces if f.calc_area() < 1e-10]
            if bad:
                bmesh.ops.delete(bm, geom=bad, context="FACES")
            name = f"{self.pet_id}.{role}"
            mesh = bpy.data.meshes.new(name)
            bm.to_mesh(mesh)
            bm.free()
            obj = link(bpy.data.objects.new(name, mesh))
            obj.name = name
            set_smooth(obj, role not in self.flat_roles)
            self.final[role] = obj
        self.parts = {}

    def finish(self, budget):
        self.fit_budget(budget)
        self.merge()
        # anything else left in the scene is a leftover helper: drop it (and say so)
        keep = set(self.final.values())
        for obj in list(bpy.context.scene.objects):
            if obj.type in ("MESH", "CURVE", "META") and obj not in keep:
                print(f"  ! {self.pet_id}: removing stray object {obj.name!r}")
                remove(obj)
        total = self.tris()
        for role, obj in self.final.items():
            obj.data.name = obj.name
            obj.data.materials.clear()
            obj.data.materials.append(role_material(self.pet_id, role, self.look))
        # markers: Root (0.2 cube on the origin) and one 0.1 cube per hinge
        self.markers = {}
        self.markers["Root"] = self._cube("Root", (0, 0, 0), 0.2)
        for anim, at in self.pivots.items():
            self.markers[f"Pivot@{anim}"] = self._cube(f"Pivot@{anim}", at, 0.1)
        return total

    def _cube(self, role, at, size):
        h = size / 2
        verts = [(at[0] + sx * h, at[1] + sy * h, at[2] + sz * h) for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)]
        faces = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
        obj = mesh_object(f"{self.pet_id}.{role}", verts, faces, smooth=False)
        fix_normals(obj)
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        bmesh.ops.triangulate(bm, faces=bm.faces)
        bm.to_mesh(obj.data)
        bm.free()
        mat = bpy.data.materials.get("Marker") or bpy.data.materials.new("Marker")
        obj.data.materials.append(mat)
        obj.hide_render = True
        return obj

    def objects(self, include_markers=True):
        objs = list(self.final.values())
        if include_markers:
            objs += list(self.markers.values())
        return objs

    def report(self):
        lines = []
        for role, obj in self.final.items():
            lines.append(f"    {role:22s} {tri_count(obj):5d} tris  (built {self.raw.get(role, 0)})")
        lines.append(f"    total {self.tris()} tris, {len(self.final)} visible meshes")
        return "\n".join(lines)


def export_pet(pet, path):
    """Writes <path> (GLB): a "<PetId>" node with one "<PetId>.<Role>" child per mesh (Root and Pivot
    markers included). The meshes are turned 180 degrees about Z for the export, so the glTF (+Y up) faces
    -Z like the pack. build_pets.py merges these per-pet files into assets/models/StormlingPets.glb."""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    turn = Matrix.Rotation(math.pi, 4, "Z")
    parent = link(bpy.data.objects.new(pet.pet_id, None))
    objs = pet.objects()
    for obj in objs:
        obj.data.transform(turn)
        obj.parent = parent
    try:
        bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB", export_yup=True, export_apply=True,
                                  export_normals=True, export_texcoords=False, export_materials="EXPORT",
                                  export_cameras=False, export_lights=False, export_animations=False,
                                  export_extras=False)
    finally:
        for obj in objs:
            obj.parent = None
            obj.data.transform(turn.inverted())
        bpy.data.objects.remove(parent, do_unlink=True)
    return path
